import DialogForgeCore
import Foundation

struct RunResult {
    let exitCode: Int32
    let output: String
}

/// Launches the real swiftDialog binary so a step can be tried exactly as it will appear.
enum DialogRunner {
    static let fallbackPaths = [
        "/usr/local/bin/dialog",
        "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
    ]

    static func locate(preferred: String) -> String? {
        ([preferred] + fallbackPaths).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(binary: String, arguments: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RunResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(decoding: data, as: UTF8.self)
                    continuation.resume(returning: RunResult(exitCode: process.terminationStatus, output: output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Plays a progress step's tasks into the command file with short delays, standing in
    /// for the Jamf policies that would run on a managed Mac.
    static func simulate(step: FlowStep, commandFile: String) async {
        func send(_ line: String) {
            guard let handle = FileHandle(forWritingAtPath: commandFile) else { return }
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        }
        func pause(_ seconds: Double) async -> Bool {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return true
            } catch {
                return false
            }
        }

        guard await pause(1.2) else { return }
        for (index, task) in step.tasks.enumerated() {
            send("progresstext: " + (task.progressText.isEmpty ? task.title : task.progressText))
            send("listitem: index: \(index), status: wait, statustext: Working…")
            guard await pause(1.4) else { return }
            send("listitem: index: \(index), status: success, statustext: Done")
            send("progress: increment 1")
        }
        send("progress: complete")
        send("progresstext: " + step.completionText)
        switch step.completion {
        case .waitForButton:
            if !step.completionButtonText.isEmpty { send("button1text: " + step.completionButtonText) }
            send("button1: enable")
        case .autoClose:
            guard await pause(Double(max(step.autoCloseDelay, 0))) else { return }
            send("quit:")
        }
    }
}
