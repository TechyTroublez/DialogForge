import AppKit
import DialogForgeCore
import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case settings
    case parameters
    case step(UUID)
}

/// Holds the open flow and everything the window needs to know about it.
@MainActor
final class AppModel: ObservableObject {
    @Published var project: FlowProject {
        didSet {
            if project != oldValue { isDirty = true }
        }
    }
    @Published var selection: SidebarSelection?
    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var alertMessage: String?
    @Published var showingImport = false
    @Published var showingJamfUpload = false

    static let fileExtension = "dialogforge"

    init() {
        let project = Templates.blank()
        self.project = project
        self.selection = project.steps.first.map { .step($0.id) }
    }

    var windowTitle: String {
        let name = fileURL?.deletingPathExtension().lastPathComponent ?? project.name
        return isDirty ? name + " — Edited" : name
    }

    var selectedStepID: UUID? {
        if case .step(let id) = selection { return id }
        return nil
    }

    var selectedStep: FlowStep? {
        guard let id = selectedStepID else { return nil }
        return project.steps.first { $0.id == id }
    }

    /// A binding that stays valid when steps are reordered or removed.
    func binding(forStep id: UUID) -> Binding<FlowStep>? {
        guard let step = project.steps.first(where: { $0.id == id }) else { return nil }
        return Binding<FlowStep>(
            get: { [weak self] in
                self?.project.steps.first(where: { $0.id == id }) ?? step
            },
            set: { [weak self] newValue in
                guard let self = self, let index = self.project.steps.firstIndex(where: { $0.id == id }) else { return }
                self.project.steps[index] = newValue
            })
    }

    // MARK: Steps

    func addStep(_ kind: StepKind) {
        var step = FlowStep(name: defaultName(for: kind), kind: kind)
        switch kind {
        case .dialog:
            step.dialog = DialogSpec(options: ["title": "Title", "message": "Message", "icon": "SF=info.circle.fill,colour=accent"])
        case .progress:
            step.dialog = DialogSpec(options: ["title": "Working…", "message": "Please wait.", "icon": "SF=gearshape.2.fill,colour=accent"])
            step.tasks = [ProgressTask(title: "First task", action: .policyEvent, value: "customEvent")]
        case .notification:
            step.dialog = DialogSpec(options: ["notification": "", "title": "Title", "message": "Message"])
        case .jamf, .script:
            break
        }
        let insertAt: Int
        if let id = selectedStepID, let index = project.steps.firstIndex(where: { $0.id == id }) {
            insertAt = index + 1
        } else {
            insertAt = project.steps.count
        }
        project.steps.insert(step, at: insertAt)
        selection = .step(step.id)
    }

    private func defaultName(for kind: StepKind) -> String {
        let base = kind.label
        let existing = Set(project.steps.map { $0.name })
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    func duplicateStep(_ id: UUID) {
        guard let index = project.steps.firstIndex(where: { $0.id == id }) else { return }
        var copy = project.steps[index]
        copy.id = UUID()
        copy.name += " copy"
        copy.outcomes = copy.outcomes.map { outcome in
            var fresh = outcome
            fresh.id = UUID()
            return fresh
        }
        copy.tasks = copy.tasks.map { task in
            var fresh = task
            fresh.id = UUID()
            return fresh
        }
        project.steps.insert(copy, at: index + 1)
        selection = .step(copy.id)
    }

    func deleteStep(_ id: UUID) {
        guard let index = project.steps.firstIndex(where: { $0.id == id }) else { return }
        project.steps.remove(at: index)
        if selectedStepID == id {
            let neighbour = project.steps.indices.contains(index) ? index : index - 1
            selection = project.steps.indices.contains(neighbour) ? .step(project.steps[neighbour].id) : .settings
        }
    }

    func moveSteps(from source: IndexSet, to destination: Int) {
        project.steps.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Documents

    func newProject(from template: FlowTemplate) {
        guard confirmDiscardingChanges() else { return }
        load(template.make(), from: nil)
    }

    private func load(_ newProject: FlowProject, from url: URL?) {
        project = newProject
        fileURL = url
        isDirty = false
        selection = newProject.steps.first.map { .step($0.id) } ?? .settings
    }

    private func confirmDiscardingChanges() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes to “\(project.name)” will be lost."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func open() {
        guard confirmDiscardingChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: AppModel.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            load(try FlowProject.decode(try Data(contentsOf: url)), from: url)
        } catch {
            alertMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func save() {
        if let url = fileURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: AppModel.fileExtension) ?? .json]
        panel.nameFieldStringValue = project.name + "." + AppModel.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try project.encoded().write(to: url, options: .atomic)
            fileURL = url
            isDirty = false
        } catch {
            alertMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    func exportScript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zsh") ?? .plainText]
        panel.nameFieldStringValue = project.name + ".zsh"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ScriptGenerator.script(for: project).write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            alertMessage = "Could not export: \(error.localizedDescription)"
        }
    }

    /// Replaces the selected step's dialog with one read from a command line or JSON config.
    func importDialog(from text: String) {
        do {
            let spec = try DialogImporter.importText(text)
            if let id = selectedStepID, let index = project.steps.firstIndex(where: { $0.id == id }),
               project.steps[index].usesDialog {
                project.steps[index].dialog = spec
            } else {
                let kind: StepKind = spec.isNotification ? .notification : .dialog
                let step = FlowStep(name: defaultName(for: kind), kind: kind, dialog: spec)
                project.steps.append(step)
                selection = .step(step.id)
            }
        } catch {
            alertMessage = "Could not import: \(error.localizedDescription)"
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
