import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import StoreKit
import Observation

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(CloudStore.self) private var cloud
    @Environment(\.modelContext) private var context
    @Query(sort: \LocalProfile.createdAt) private var profiles: [LocalProfile]
    @Query(sort: \WishList.createdAt) private var lists: [WishList]
    @Query private var hidden: [HiddenPerson]
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var export = false
    @State private var importing = false
    @State private var migration = false
    @State private var document = BackupDocument()
    @State private var message: String?
    @State private var publicProfile = false
    @State private var removingProfile = false
    var body: some View {
        Form {
            Section("Your profile") {
                HStack(spacing: 16) {
                    if let data = profiles.first?.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                    } else { Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.green) }
                    TextField("Your name", text: $name)
                }
                Button("Save profile") { saveProfile() }
                PhotosPicker("Choose profile photo", selection: $photo, matching: .images)
                Text("These details stay private until you choose to publish a public profile below.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Your library") {
                Label(cloud.localOnly ? "On this device" : "Private iCloud library", systemImage: cloud.localOnly ? "iphone" : "icloud")
                Text(cloud.syncMessage).font(.caption).foregroundStyle(.secondary)
                if let error = cloud.error { Text(error).font(.caption).foregroundStyle(.red) }
                if cloud.localOnly {
                    Button("Open iCloud library") { Task { await cloud.open() } }
                    Text("Back up your on-device library first, then import the backup into iCloud. Libraries are never merged automatically.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Export backup") {
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        document = BackupDocument(data: try encoder.encode(WishwellArchive(lists: lists))); export = true
                    } catch { message = error.localizedDescription }
                }
                Button("Import backup") { importing = true }
                Button("Import website wishes") { migration = true }
            }
            Section {
                NavigationLink { SupportView() } label: { Label("Support Wishwell", systemImage: "heart") }
            } footer: { Text("Wishwell is free. No subscriptions. No locked features.") }
            Section("Your circle") {
                if social.enabled {
                    Button(social.me == nil ? "Set up public profile" : "Edit public profile") { publicProfile = true }
                    if social.me != nil {
                        Button("Remove public profile", role: .destructive) { removingProfile = true }.disabled(social.busy).accessibilityIdentifier("social.profile.remove")
                    }
                } else { Text("Social sharing is awaiting CloudKit permission setup.").font(.footnote).foregroundStyle(.secondary) }
            }
            if !hidden.isEmpty {
                Section("Blocked people") {
                    ForEach(hidden) { person in
                        Button("Unblock member") {
                            let owner = person.ownerID
                            for row in hidden where row.ownerID == owner { context.delete(row) }
                            do { try context.save(); social.hidden.remove(owner) } catch { context.rollback(); message = error.localizedDescription }
                        }.accessibilityIdentifier("social.unblock")
                    }
                }
            }
            Section("About this preview") {
                Text("Personal wishes are stored on your device and, when connected, in your private iCloud database. Only profiles and wishlists you explicitly publish enter the public social database.").font(.footnote)
            }
            Section("Help") {
                Link(destination: URL(string: "mailto:contact@nujoomdigital.com?subject=Wishwell%20feedback")!) { Label("Send feedback", systemImage: "envelope") }
                Link(destination: URL(string: "https://nujoomdigital.com/support#wishwell")!) { Label("Wishwell support", systemImage: "questionmark.circle") }
                Link(destination: URL(string: "https://nujoomdigital.com/privacy#wishwell")!) { Label("Privacy policy", systemImage: "hand.raised") }
            }
        }.navigationTitle("Settings")
            .onAppear { name = profiles.first?.displayName ?? "" }
            .onChange(of: profiles.first?.displayName) { _, value in name = value ?? "" }
            .onChange(of: photo) { _, item in
                Task { @MainActor in
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        let ratio = min(1, 800 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        let thumbnail = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                        let profile = profileForEditing(); profile.photo = thumbnail.jpegData(compressionQuality: 0.8)
                        try context.save()
                    } catch { context.rollback(); message = error.localizedDescription }
                    photo = nil
                }
            }
            .fileExporter(isPresented: $export, document: document, contentType: .json, defaultFilename: "Wishwell-backup") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 20_000_000 else { throw WishwellError("This backup is too large to import.") }
                    let archive = try JSONDecoder().decode(WishwellArchive.self, from: data)
                    let count = try archive.restore(into: context)
                    message = "Imported \(count) new wishlists. Existing lists were kept unchanged."
                } catch { message = error.localizedDescription }
            }
            .sheet(isPresented: $migration) { LegacyImportView() }
            .sheet(isPresented: $publicProfile) { PublicProfileEditor() }
            .confirmationDialog("Remove your public profile?", isPresented: $removingProfile, titleVisibility: .visible) {
                Button("Remove public profile", role: .destructive) { Task { await social.perform {
                    try await social.removeProfile()
                    for list in lists { list.publicRecordName = nil }
                    do { try context.save() } catch { context.rollback(); throw error }
                } } }.accessibilityIdentifier("social.profile.confirmRemove")
            } message: { Text("This removes your public profile, published lists, and the interactions you authored. Your personal wishlists stay private and intact.") }
            .alert("Wishwell", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
    private func profileForEditing() -> LocalProfile {
        if let profile = profiles.first { return profile }
        let profile = LocalProfile(); context.insert(profile); return profile
    }
    private func saveProfile() {
        profileForEditing().displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try context.save(); message = "Profile saved." } catch { context.rollback(); message = error.localizedDescription }
    }
}

@MainActor @Observable final class TipStore {
    private(set) var products: [Product] = []
    private(set) var loading = false
    private(set) var purchasing = false
    var message: String?
    static let productIDs = ["com.nujoomdigital.wishwell.tip.small", "com.nujoomdigital.wishwell.tip.medium", "com.nujoomdigital.wishwell.tip.large"]
    @ObservationIgnored nonisolated(unsafe) private var updates: Task<Void, Never>?
    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.finish(result)
            }
        }
    }
    deinit { updates?.cancel() }
    func load() async {
        loading = true; defer { loading = false }
        for await transaction in StoreKit.Transaction.unfinished { await finish(transaction) }
        do { products = try await Product.products(for: Self.productIDs).filter { $0.type == .consumable }.sorted { $0.price < $1.price } }
        catch { message = error.localizedDescription }
    }
    func purchase(_ product: Product) async {
        guard !purchasing else { return }
        purchasing = true; defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result): await finish(result)
            case .pending: message = "Your tip is awaiting approval. Thank you!"
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }
    private func finish(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { message = "Apple couldn’t verify this purchase."; return }
        guard Self.productIDs.contains(transaction.productID) else { return }
        await transaction.finish()
        message = "Thank you for supporting Wishwell!"
    }
}

struct SupportView: View {
    @State private var tips = TipStore()
    var body: some View {
        List {
            Section {
                Image(systemName: "heart.fill").font(.system(size: 38)).foregroundStyle(Theme.green).padding(.vertical)
                Text("A little kindness goes a long way.").font(.system(.title2, design: .serif))
                Text("Wishwell is free to use. If it brings you a little joy, you can leave an optional one-time tip.")
                Text("No subscription. No extra features. Just a thank-you.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Support Wishwell") {
                if tips.loading { ProgressView() }
                ForEach(tips.products) { product in
                    Button { Task { await tips.purchase(product) } } label: {
                        HStack { Text(product.displayName); Spacer(); Text(product.displayPrice) }
                    }.disabled(tips.purchasing)
                }
                if !tips.loading && tips.products.isEmpty {
                    Text("Tips aren’t available in this preview yet. Everything in Wishwell remains free.").foregroundStyle(.secondary)
                    Button("Try again") { Task { await tips.load() } }
                }
            }
        }.navigationTitle("Support Wishwell").task { await tips.load() }
            .alert("Support Wishwell", isPresented: Binding(get: { tips.message != nil }, set: { if !$0 { tips.message = nil } })) { Button("OK") { tips.message = nil } } message: { Text(tips.message ?? "") }
    }
}
