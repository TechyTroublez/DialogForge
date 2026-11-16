import DialogForgeCore
import Foundation
import Security

/// Minimal Jamf Pro API client: authenticate, then create or update one script.
struct JamfClient {
    enum Credentials {
        /// An API client from Settings › API roles and clients (needs Create/Read/Update Scripts).
        case apiClient(id: String, secret: String)
        case user(name: String, password: String)
    }

    enum ClientError: LocalizedError {
        case invalidURL
        case http(status: Int, body: String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The Jamf Pro server address is not valid."
            case .http(let status, let body):
                let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let hint: String
                switch status {
                case 401: hint = " Check the credentials."
                case 403: hint = " The account needs the Create, Read and Update Scripts privileges."
                default: hint = ""
                }
                return "Jamf Pro returned HTTP \(status).\(hint)" + (detail.isEmpty ? "" : "\n" + String(detail.prefix(300)))
            case .unexpectedResponse:
                return "Jamf Pro returned a response this app did not understand."
            }
        }
    }

    let baseURL: URL
    var session: URLSession = .shared

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ClientError.invalidURL }
        return url
    }

    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(status) else { throw ClientError.http(status: status, body: body) }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .null }
        guard let json = try? JSONValue.parse(body) else { throw ClientError.unexpectedResponse }
        return json
    }

    func token(for credentials: Credentials) async throws -> String {
        switch credentials {
        case .apiClient(let id, let secret):
            var request = URLRequest(url: try url("/api/oauth/token"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let fields = ["client_id": id, "client_secret": secret, "grant_type": "client_credentials"]
            request.httpBody = Data(fields.map { key, value in
                key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            }.joined(separator: "&").utf8)
            guard let token = try await send(request)["access_token"]?.stringValue else { throw ClientError.unexpectedResponse }
            return token
        case .user(let name, let password):
            var request = URLRequest(url: try url("/api/v1/auth/token"))
            request.httpMethod = "POST"
            let basic = Data((name + ":" + password).utf8).base64EncodedString()
            request.setValue("Basic " + basic, forHTTPHeaderField: "Authorization")
            guard let token = try await send(request)["token"]?.stringValue else { throw ClientError.unexpectedResponse }
            return token
        }
    }

    /// Creates the script, or updates the existing script with the same name.
    /// Returns the script ID and whether it was newly created.
    func upsertScript(named name: String, payload: JSONValue, token: String) async throws -> (id: String, created: Bool) {
        var search = URLRequest(url: try url(JamfAPI.scriptSearchPath(name: name)))
        search.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        search.setValue("application/json", forHTTPHeaderField: "Accept")
        let existingID = JamfAPI.firstScriptID(in: try await send(search))

        var request = URLRequest(url: try url(existingID.map { "/api/v1/scripts/" + $0 } ?? "/api/v1/scripts"))
        request.httpMethod = existingID == nil ? "POST" : "PUT"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(payload.serialized(pretty: false).utf8)
        let response = try await send(request)
        if let id = existingID { return (id, false) }
        guard let id = response["id"]?.stringValue else { throw ClientError.unexpectedResponse }
        return (id, true)
    }
}

/// Stores the Jamf secret in the login keychain, keyed by server and account.
enum Keychain {
    private static let service = "DialogForge Jamf Pro"

    private static func query(server: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account + "@" + server
        ]
    }

    static func save(secret: String, server: String, account: String) {
        let base = query(server: server, account: account)
        SecItemDelete(base as CFDictionary)
        guard !secret.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(secret.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func secret(server: String, account: String) -> String? {
        var lookup = query(server: server, account: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
