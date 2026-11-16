import AppKit
import DialogForgeCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run` rather than from an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DialogForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Menu("New from Template") {
                    ForEach(Templates.all) { template in
                        Button(template.name) { model.newProject(from: template) }
                    }
                }
                Button("Open…") { model.open() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s")
                Button("Save As…") { model.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Import Dialog Command or JSON…") { model.showingImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Script…") { model.exportScript() }
                    .keyboardShortcut("e")
                Button("Upload Script to Jamf Pro…") { model.showingJamfUpload = true }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandMenu("Flow") {
                ForEach(StepKind.allCases) { kind in
                    Button("Add \(kind.label) Step") { model.addStep(kind) }
                }
                Divider()
                Button("Duplicate Step") {
                    if let id = model.selectedStepID { model.duplicateStep(id) }
                }
                .keyboardShortcut("d")
                .disabled(model.selectedStepID == nil)
                Button("Delete Step") {
                    if let id = model.selectedStepID { model.deleteStep(id) }
                }
                .disabled(model.selectedStepID == nil)
            }
        }
    }
}
