import Foundation
import Security
import Observation

struct SessionKeychain {
    static let service = "com.wishwell.mobile.session"
    static func query(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: host]
    }
    static func read(_ host: String) -> String? {
        var q = query(host); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, host: String) throws {
        remove(host)
        var q = query(host)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIError(message: "Your session could not be stored securely. Please try again.") }
    }
    static func remove(_ host: String) { SecItemDelete(query(host) as CFDictionary) }
}

@MainActor @Observable final class AppStore {
    var user: Person?
    var lists: [WishlistRecord] = []
    var unreadCount = 0
    var error: String?
    var restoring = true
    var busy = false
    private var token: String?
    let baseURL: URL
    let session: URLSession
    let decoder: JSONDecoder

    init() {
        #if DEBUG
        let embedded = Bundle.main.object(forInfoDictionaryKey: "WishwellDevelopmentAPIURL") as? String
        let configured = embedded.flatMap { $0.isEmpty ? nil : $0 }
        let address = ProcessInfo.processInfo.environment["WISHWELL_API_URL"] ?? configured ?? "http://localhost:3000"
        #else
        let address = "https://wishwell-22rh.onrender.com"
        #endif
        baseURL = URL(string: address)!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
        decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        token = SessionKeychain.read(address)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ["localhost", "127.0.0.1"].contains(baseURL.host ?? "") { token = nil }
        #endif
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, data: Data? = nil, contentType: String? = nil) async throws -> Data {
        guard let url = URL(string: "/api/v1/" + path, relativeTo: baseURL) else { throw APIError(message: "Invalid request.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let data {
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "No response from Wishwell.") }
        if response.statusCode == 401 && path != "session" { clearSession() }
        guard (200...299).contains(response.statusCode) else {
            let message = (try? decoder.decode(ServerError.self, from: data))?.error
            throw APIError(message: message ?? (response.statusCode == 429 ? "Please wait a moment and try again." : "Wishwell couldn’t complete that request (\(response.statusCode))."))
        }
        return data
    }

    func fetch<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try decoder.decode(T.self, from: await request(path))
    }
    func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() } catch { self.error = error.localizedDescription }
    }
    func restore() async {
        defer { restoring = false }
        guard token != nil else { return }
        do { user = try await fetch("me"); try await reload() }
        catch { self.error = error.localizedDescription }
    }
    func authenticate(email: String, password: String, first: String = "", last: String = "", register: Bool = false) async throws {
        let data = try await request(register ? "register" : "session", method: "POST", body: ["email": email, "password": password, "password_confirmation": password, "first_name": first, "last_name": last])
        let result = try decoder.decode(LoginResponse.self, from: data)
        try SessionKeychain.save(result.token, host: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        token = result.token; user = result.user
        try await reload()
    }
    func updateCredentials(email: String, currentPassword: String, password: String, confirmation: String) async throws {
        let data = try await request("me/credentials", method: "PATCH", body: ["email": email, "current_password": currentPassword, "password": password, "password_confirmation": confirmation])
        let result = try decoder.decode(LoginResponse.self, from: data)
        try SessionKeychain.save(result.token, host: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        token = result.token; user = result.user
    }

    func reload() async throws {
        let loaded: [WishlistRecord] = try await fetch("wlists")
        lists = loaded
        let activity: ActivityResponse = try await fetch("notifications")
        unreadCount = activity.unreadCount
    }
    func clearSession() {
        SessionKeychain.remove(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        token = nil; user = nil; lists = []; unreadCount = 0
    }
    func signOut() async throws {
        defer { clearSession() }
        _ = try await request("session", method: "DELETE")
    }
    func uploadAvatar(_ data: Data) async throws {
        let boundary = UUID().uuidString
        var payload = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        payload.append(data); payload.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let result = try await request("me/avatar", method: "POST", data: payload, contentType: "multipart/form-data; boundary=\(boundary)")
        user = try decoder.decode(Person.self, from: result)
    }
}
