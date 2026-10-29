import SwiftUI
import SwiftData

struct CircleSetupView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Your circle is coming along", systemImage: "person.2")
        } description: {
            Text("Following, likes, comments, and notifications are being rebuilt for iCloud. Your personal lists stay private in this preview. You can already share a text copy from a wishlist’s menu.")
        }.navigationTitle("Your circle")
    }
}

private struct LegacyLogin: Decodable { let token: String }
private struct LegacyOption: Decodable {
    var location: String?
    var price: String?
    enum CodingKeys: String, CodingKey { case location, price }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        if let value = try? c.decode(String.self, forKey: .price) { price = value }
        else if let value = try? c.decode(Decimal.self, forKey: .price) { price = NSDecimalNumber(decimal: value).stringValue }
        else { price = nil }
    }
}
private struct LegacyWish: Decodable { let id: Int; let title: String; let fulfilled: Bool; let purchaseOptions: [LegacyOption] }
private struct LegacyList: Decodable { let id: Int; let title: String; let category: String; let wishes: [LegacyWish]? }

@MainActor private enum LegacyImporter {
    static func download(email: String, password: String) async throws -> [LegacyList] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 90
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let base = URL(string: "https://wishwell-22rh.onrender.com/api/v1/")!
        var login = URLRequest(url: base.appending(path: "session")); login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await session.data(for: login)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WishwellError("Couldn’t sign into the old website. Check your details and try again.") }
        let token = try decoder.decode(LegacyLogin.self, from: data).token
        func fetch(_ path: String) async throws -> Data {
            var request = URLRequest(url: URL(string: path, relativeTo: base)!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw WishwellError("The website import was interrupted. No wishes have been changed.") }
            return data
        }
        do {
            var rows: [LegacyList] = []; var page = 1
            while true {
                let chunk = try decoder.decode([LegacyList].self, from: await fetch("wlists?page=\(page)"))
                for row in chunk { rows.append(try decoder.decode(LegacyList.self, from: await fetch("wlists/\(row.id)"))) }
                if chunk.count < 40 { break }; page += 1
            }
            var logout = URLRequest(url: base.appending(path: "session")); logout.httpMethod = "DELETE"
            logout.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: logout)
            return rows
        } catch {
            var logout = URLRequest(url: base.appending(path: "session")); logout.httpMethod = "DELETE"
            logout.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: logout)
            throw error
        }
    }
    static func insert(_ rows: [LegacyList], into context: ModelContext) throws -> Int {
        let lists = try context.fetch(FetchDescriptor<WishList>())
        var known = Set(lists.compactMap(\.legacyID))
        var added = 0
        // Prepare and validate before changing the local store.
        let prepared = try rows.map { row in
            (row, try (row.wishes ?? []).map { wish in
                (wish, try ShoppingOption.validated(wish.purchaseOptions.map { ShoppingOption(location: $0.location ?? "", price: $0.price ?? "") }))
            })
        }
        for (row, wishes) in prepared where !known.contains(row.id) {
            let list = WishList(title: row.title, category: row.category); list.legacyID = row.id
            context.insert(list); known.insert(row.id)
            for (old, options) in wishes {
                let wish = try Wish(title: old.title, options: options, list: list)
                wish.fulfilled = old.fulfilled; wish.legacyID = old.id; context.insert(wish)
            }
            added += 1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return added
    }
}

struct LegacyImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var running = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Copy your own wishlists, shopping options, and fulfilled status into this library. The website stays unchanged. Imported lists are private; profiles and social history are not imported.")
                    Text("Your credentials are sent only to the existing Wishwell website for this import and aren’t saved. Signing out revokes the temporary session when the server is reachable.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Existing website account") {
                    TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                }
                Button("Copy my wishes") { Task { await migrate() } }.disabled(running || email.isEmpty || password.isEmpty)
                if running { ProgressView("Copying wishes…") }
                if let message { Text(message) }
            }.navigationTitle("Import website wishes").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { password = ""; dismiss() }.disabled(running) }.interactiveDismissDisabled(running)
        }
    }
    private func migrate() async {
        running = true; message = nil
        defer { password = ""; running = false }
        do {
            let downloaded = try await LegacyImporter.download(email: email, password: password)
            let count = try LegacyImporter.insert(downloaded, into: context)
            message = "Copied \(count) new wishlists. Lists already imported were left unchanged."
        } catch { message = error.localizedDescription }
    }
}
