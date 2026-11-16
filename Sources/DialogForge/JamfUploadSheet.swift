import DialogForgeCore
import SwiftUI

@MainActor
struct JamfUploadSheet: View {
    enum AuthMode: String, CaseIterable, Identifiable {
        case apiClient = "API client"
        case user = "User account"

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("jamfServer") private var server = ""
    @AppStorage("jamfAccount") private var account = ""
    @AppStorage("jamfAuthMode") private var authMode = AuthMode.apiClient.rawValue
    @AppStorage("jamfRememberSecret") private var rememberSecret = false
    @State private var secret = ""
    @State private var scriptName = ""
    @State private var priority = JamfAPI.Priority.after
    @State private var isUploading = false
    @State private var status = ""
    @State private var failed = false

    private var mode: AuthMode { AuthMode(rawValue: authMode) ?? .apiClient }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Jamf Pro") {
                    TextField("Server", text: $server, prompt: Text("yourcompany.jamfcloud.com"))
                    Picker("Sign in with", selection: $authMode) {
                        ForEach(AuthMode.allCases) { item in
                            Text(item.rawValue).tag(item.rawValue)
                        }
                    }
                    TextField(mode == .apiClient ? "Client ID" : "Username", text: $account)
                    SecureField(mode == .apiClient ? "Client secret" : "Password", text: $secret)
                    Toggle("Remember in my keychain", isOn: $rememberSecret)
                    Text("An API client needs a role with the Create, Read and Update Scripts privileges (Settings › System › API roles and clients).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Script") {
                    TextField("Name", text: $scriptName)
                    Picker("Priority", selection: $priority) {
                        ForEach(JamfAPI.Priority.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Text("A script with this name is updated in place; otherwise a new one is created. Parameter labels 4–11 are set from the flow's Jamf parameters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if !blockingIssues.isEmpty {
                Label("Fix \(blockingIssues.count) error(s) on the Issues tab before uploading.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }
            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }
            HStack {
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                Button(isUploading ? "Uploading…" : "Upload") { upload() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isUploading || !canUpload)
            }
            .padding(20)
        }
        .frame(width: 520)
        .onAppear {
            if scriptName.isEmpty { scriptName = model.project.name }
            loadSecret()
        }
        .onChange(of: server) { _ in loadSecret() }
        .onChange(of: account) { _ in loadSecret() }
    }

    private var blockingIssues: [ValidationIssue] {
        Validator.issues(for: model.project).filter { $0.severity == .error }
    }

    private var canUpload: Bool {
        JamfAPI.baseURL(from: server) != nil && !account.isEmpty && !secret.isEmpty
            && !scriptName.trimmingCharacters(in: .whitespaces).isEmpty && blockingIssues.isEmpty
    }

    private func loadSecret() {
        guard rememberSecret, secret.isEmpty, !server.isEmpty, !account.isEmpty else { return }
        if let stored = Keychain.secret(server: server, account: account) { secret = stored }
    }

    private func upload() {
        guard let baseURL = JamfAPI.baseURL(from: server) else { return }
        let name = scriptName.trimmingCharacters(in: .whitespaces)
        let payload = JamfAPI.scriptPayload(project: model.project, name: name, priority: priority)
        let credentials: JamfClient.Credentials = mode == .apiClient
            ? .apiClient(id: account, secret: secret)
            : .user(name: account, password: secret)
        if rememberSecret {
            Keychain.save(secret: secret, server: server, account: account)
        }
        isUploading = true
        failed = false
        status = "Signing in…"
        Task { @MainActor in
            do {
                let client = JamfClient(baseURL: baseURL)
                let token = try await client.token(for: credentials)
                status = "Uploading script…"
                let result = try await client.upsertScript(named: name, payload: payload, token: token)
                status = (result.created ? "Created" : "Updated") + " script “\(name)” (ID \(result.id)) on \(baseURL.host ?? server)."
            } catch {
                failed = true
                status = error.localizedDescription
            }
            isUploading = false
        }
    }
}
