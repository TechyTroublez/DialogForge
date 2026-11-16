import DialogForgeCore
import SwiftUI

/// Script-wide settings: how swiftDialog is found, installed and launched.
@MainActor
struct SettingsEditor: View {
    @Binding var project: FlowProject

    var body: some View {
        Form {
            Section("Flow") {
                TextField("Name", text: $project.name)
                TextField("Organisation", text: $project.settings.organisation, prompt: Text("Shown in the script header"))
                TextField("Notes", text: $project.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section("swiftDialog") {
                TextField("Binary path", text: $project.settings.dialogPath)
                    .font(.system(.body, design: .monospaced))
                TextField("Minimum version", text: $project.settings.minimumVersion, prompt: Text("e.g. 2.5.0 – leave empty to accept any"))
                Picker("If missing or too old", selection: $project.settings.installMethod) {
                    ForEach(InstallMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                if project.settings.installMethod == .jamfPolicy {
                    TextField("Install policy custom event", text: $project.settings.installPolicyEvent)
                }
                if project.settings.installMethod == .github {
                    Text("The script downloads the latest release package from the swiftDialog GitHub repository and installs it only when its signature matches the developer's Team ID. Managed Macs need to be able to reach github.com.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Running") {
                Toggle("Wait for a user to be logged in", isOn: $project.settings.waitForUser)
                Toggle("Run swiftDialog as the logged-in user", isOn: $project.settings.runAsUser)
                Text("Jamf Pro runs scripts as root. swiftDialog windows work as root; system notifications and anything that should respect the user's own settings need the user's context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Keep the Mac awake while the script runs", isOn: $project.settings.caffeinate)
                TextField("Log file", text: $project.settings.logFile)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
    }
}

/// Jamf Pro script parameters 4 – 11, exposed to the flow as named variables.
@MainActor
struct ParametersEditor: View {
    @Binding var parameters: [JamfParameter]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Jamf Pro passes parameters 4 to 11 to a script, set per policy. Give each one a variable name, then use it anywhere in the flow as ${variable} — in titles, messages, policy events or shell. The default is used when the policy leaves the parameter empty, and for previews here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        columnHeader("#")
                        columnHeader("Label in Jamf Pro")
                        columnHeader("Variable")
                        columnHeader("Default")
                        columnHeader("")
                    }

                    ForEach($parameters) { $parameter in
                        GridRow {
                            Picker("", selection: $parameter.index) {
                                ForEach(4...11, id: \.self) { index in
                                    Text("\(index)").tag(index)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 64)
                            TextField("Organisation name", text: $parameter.label)
                                .textFieldStyle(.roundedBorder)
                            TextField("orgName", text: $parameter.variable)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Shell.isValidVariableName(parameter.variable) ? Color.primary : Color.red)
                            TextField("Optional", text: $parameter.defaultValue)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                parameters.removeAll { $0.id == parameter.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    parameters.append(JamfParameter(index: nextIndex, label: "", variable: "parameter\(nextIndex)"))
                } label: {
                    Label("Add Parameter", systemImage: "plus")
                }
                .disabled(parameters.count >= 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var nextIndex: Int {
        let used = Set(parameters.map { $0.index })
        return (4...11).first { !used.contains($0) } ?? 11
    }
}
