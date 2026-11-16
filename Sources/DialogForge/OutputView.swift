import AppKit
import DialogForgeCore
import SwiftUI

/// The right-hand pane: what the selected step looks like and what the builder generates.
@MainActor
struct OutputView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case command = "Command"
        case json = "JSON"
        case script = "Script"
        case issues = "Issues"

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var tab: Tab = .preview
    @State private var isRunning = false
    @State private var runSummary = ""

    var body: some View {
        let issues = Validator.issues(for: model.project)
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item == .issues && !issues.isEmpty ? "Issues (\(issues.count))" : item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            switch tab {
            case .preview: preview
            case .command: CodeView(text: commandText, emptyMessage: "Select a dialog, progress or notification step.")
            case .json: CodeView(text: jsonText, emptyMessage: "Select a dialog, progress or notification step.")
            case .script: scriptView
            case .issues: IssuesView(issues: issues)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Derived output

    private var dialogStep: FlowStep? {
        guard let step = model.selectedStep, step.usesDialog else { return nil }
        return step
    }

    private var commandText: String {
        guard let step = dialogStep else { return "" }
        let spec = ScriptGenerator.effectiveSpec(for: step, commandFile: CommandFile.defaultPath)
        return DialogBuilder.renderCommand(binary: model.project.settings.dialogPath,
                                           groups: DialogBuilder.argumentGroups(for: spec))
    }

    private var jsonText: String {
        guard let step = dialogStep else { return "" }
        let spec = ScriptGenerator.effectiveSpec(for: step, commandFile: CommandFile.defaultPath)
        let config = DialogBuilder.jsonConfig(for: spec)
        var text = config.json.serialized(pretty: true)
        if !config.extraArguments.isEmpty {
            let extra = config.extraArguments.map { $0.map { Shell.quote($0) }.joined(separator: " ") }.joined(separator: " ")
            text += "\n\n// Also pass on the command line (not expressible in JSON):\n// " + extra
        }
        return text
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let step = dialogStep {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    DialogPreview(spec: ScriptGenerator.effectiveSpec(for: step, commandFile: ""),
                                  variables: model.project.previewVariables)
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Button {
                        run(step)
                    } label: {
                        Label(isRunning ? "Running…" : "Run in swiftDialog", systemImage: "play.fill")
                    }
                    .disabled(isRunning)
                    .help("Launches the real swiftDialog with this step's options. Progress steps are simulated.")
                    Text(runSummary.isEmpty ? "The sketch above is approximate. Run it to see the real thing." : runSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Spacer()
                }
                .padding(10)
            }
        } else {
            Text("This step has no dialog to preview.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func run(_ step: FlowStep) {
        guard let binary = DialogRunner.locate(preferred: model.project.settings.dialogPath) else {
            runSummary = "swiftDialog was not found at \(model.project.settings.dialogPath). Install it from swiftdialog.app to run previews."
            return
        }
        let commandFile = NSTemporaryDirectory() + "dialogforge-preview-\(UUID().uuidString).log"
        let spec = ScriptGenerator.effectiveSpec(for: step, commandFile: commandFile)
        var arguments = DialogBuilder.resolve(DialogBuilder.arguments(for: spec), variables: model.project.previewVariables)
        if !DialogBuilder.captures(for: spec).isEmpty && !spec.has("json") { arguments.append("--json") }

        isRunning = true
        runSummary = "Running…"
        Task { @MainActor in
            var simulation: Task<Void, Never>?
            if step.kind == .progress {
                FileManager.default.createFile(atPath: commandFile, contents: nil)
                simulation = Task.detached { await DialogRunner.simulate(step: step, commandFile: commandFile) }
            }
            do {
                let result = try await DialogRunner.run(binary: binary, arguments: arguments)
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                runSummary = "Exit code \(ExitOutcome.describe(code: Int(result.exitCode)))" + (output.isEmpty ? "" : "\n" + output)
            } catch {
                runSummary = "Could not run swiftDialog: \(error.localizedDescription)"
            }
            simulation?.cancel()
            try? FileManager.default.removeItem(atPath: commandFile)
            isRunning = false
        }
    }

    // MARK: Script

    private var scriptView: some View {
        let script = ScriptGenerator.script(for: model.project)
        return VStack(spacing: 0) {
            CodeView(text: script, emptyMessage: "")
            Divider()
            HStack {
                Button("Export…") { model.exportScript() }
                Button("Upload to Jamf Pro…") { model.showingJamfUpload = true }
                Spacer()
                Text("\(script.split(separator: "\n", omittingEmptySubsequences: false).count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

/// Read-only monospaced text with a copy button.
@MainActor
struct CodeView: View {
    let text: String
    let emptyMessage: String

    var body: some View {
        if text.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topTrailing) {
                Button {
                    Clipboard.copy(text)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .padding(8)
            }
        }
    }
}

@MainActor
struct IssuesView: View {
    @EnvironmentObject private var model: AppModel
    let issues: [ValidationIssue]

    var body: some View {
        if issues.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("No issues found")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(issues) { issue in
                Button {
                    if let id = issue.stepID { model.selection = .step(id) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: symbol(for: issue.severity))
                            .foregroundStyle(color(for: issue.severity))
                        Text(issue.message)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func symbol(for severity: ValidationIssue.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: ValidationIssue.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
