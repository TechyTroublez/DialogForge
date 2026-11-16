import DialogForgeCore
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            HSplitView {
                editor
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                OutputView()
                    .frame(minWidth: 380, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.windowTitle)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(Templates.all) { template in
                        Button {
                            model.newProject(from: template)
                        } label: {
                            Label(template.name, systemImage: template.symbol)
                        }
                        .help(template.summary)
                    }
                } label: {
                    Label("Templates", systemImage: "square.grid.2x2")
                }
                .help("Start a new flow from a template")

                Button {
                    model.showingImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import an existing dialog command or JSON config")

                Button {
                    model.exportScript()
                } label: {
                    Label("Export Script", systemImage: "square.and.arrow.up")
                }
                .help("Save the generated zsh script")

                Button {
                    model.showingJamfUpload = true
                } label: {
                    Label("Upload to Jamf Pro", systemImage: "icloud.and.arrow.up")
                }
                .help("Create or update the script in Jamf Pro")
            }
        }
        .sheet(isPresented: $model.showingImport) {
            ImportSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showingJamfUpload) {
            JamfUploadSheet()
                .environmentObject(model)
        }
        .alert("DialogForge", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding<Bool>(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
    }

    @ViewBuilder
    private var editor: some View {
        switch model.selection {
        case .settings:
            SettingsEditor(project: $model.project)
        case .parameters:
            ParametersEditor(parameters: $model.project.parameters)
        case .step(let id):
            if let step = model.binding(forStep: id) {
                StepEditor(step: step)
                    .id(id)
            } else {
                placeholder
            }
        case .none:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Select or add a step")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Project") {
                Label("Script Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
                Label("Jamf Parameters", systemImage: "list.number")
                    .badge(model.project.parameters.count)
                    .tag(SidebarSelection.parameters)
            }
            Section("Steps") {
                ForEach(model.project.steps) { step in
                    StepRow(step: step, number: number(of: step))
                        .tag(SidebarSelection.step(step.id))
                        .contextMenu {
                            Button("Duplicate") { model.duplicateStep(step.id) }
                            Button("Delete", role: .destructive) { model.deleteStep(step.id) }
                        }
                }
                .onMove { source, destination in
                    model.moveSteps(from: source, to: destination)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    ForEach(StepKind.allCases) { kind in
                        Button {
                            model.addStep(kind)
                        } label: {
                            Label(kind.label, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(10)
        }
    }

    /// Position among enabled steps, matching the step_N function names in the script.
    private func number(of step: FlowStep) -> Int? {
        guard step.enabled else { return nil }
        let enabled = model.project.steps.filter { $0.enabled }
        return enabled.firstIndex(where: { $0.id == step.id }).map { $0 + 1 }
    }
}

@MainActor
struct StepRow: View {
    let step: FlowStep
    let number: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: step.kind.symbol)
                .frame(width: 18)
                .foregroundStyle(step.enabled ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name.isEmpty ? step.kind.label : step.name)
                    .foregroundStyle(step.enabled ? Color.primary : Color.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var text = step.kind.label
        if let number = number {
            text = "\(number) · " + text
        } else {
            text += " · disabled"
        }
        if !step.condition.isEmpty { text += " · conditional" }
        return text
    }
}

@MainActor
struct ImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import a dialog")
                .font(.headline)
            Text("Paste a swiftDialog command line from an existing script, or a JSON config. It replaces the selected step's dialog, or adds a new step.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 560, minHeight: 260)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Import") {
                    model.importDialog(from: text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
