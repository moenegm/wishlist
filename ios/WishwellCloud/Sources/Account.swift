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
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var framing: FramingImage?
    @State private var export = false
    @State private var importing = false
    @State private var migration = false
    @State private var document = BackupDocument()
    @State private var message: String?
    @State private var turningOff = false
    @FocusState private var editingName: Bool
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let data = profiles.first?.photo, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                            } else { Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.green) }
                            Image(systemName: "camera.circle.fill").font(.title3).foregroundStyle(.white, Theme.green)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Choose profile photo").accessibilityIdentifier("profile.photo")
                    TextField("Your name", text: $name).focused($editingName).submitLabel(.done).onSubmit { saveProfile() }
                        .accessibilityIdentifier("profile.name")
                    if nameChanged { Button("Save") { saveProfile() }.buttonStyle(.borderedProminent).accessibilityIdentifier("profile.save") }
                }
                if social.enabled {
                    Toggle(isOn: Binding(get: { social.me != nil }, set: { setPublic($0) })) {
                        Label("Public account", systemImage: "person.2")
                    }.tint(Theme.green).disabled(social.busy).accessibilityIdentifier("profile.public")
                }
            } header: { Text("Your profile") } footer: {
                if social.me != nil { Text("People using Wishwell can find you by your name and photo, so you can add people to your circle and share wishlists. Each wishlist stays private until you make it public.") }
                else { Text("Turn on a public account to add people to your circle and share wishlists. Your name and photo are only shown to others when it’s on.") }
            }
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.appearance")
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
            Section("About your data") {
                Text("Your wishes are stored on your device and, when connected, in your private iCloud database. Only your public account and the wishlists you make public are shared with other people.").font(.footnote)
            }
            Section("Help") {
                Link(destination: URL(string: "mailto:contact@nujoomdigital.com?subject=Wishwell%20feedback")!) { Label("Send feedback", systemImage: "envelope") }
                Link(destination: URL(string: "https://nujoomdigital.com/support#wishwell")!) { Label("Wishwell support", systemImage: "questionmark.circle") }
                Link(destination: URL(string: "https://nujoomdigital.com/privacy#wishwell")!) { Label("Privacy policy", systemImage: "hand.raised") }
            }
        }.navigationTitle("Settings").scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingName = false } } }
            .onAppear { name = profiles.first?.displayName ?? "" }
            .onChange(of: profiles.first?.displayName) { _, value in if !editingName { name = value ?? "" } }
            .onChange(of: photo) { _, item in
                Task { @MainActor in
                    defer { photo = nil }
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        framing = FramingImage(image: image)
                    } catch { message = error.localizedDescription }
                }
            }
            .sheet(item: $framing) { item in PhotoFramer(image: item.image) { savePhoto($0) } }
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
            .confirmationDialog("Turn off your public account?", isPresented: $turningOff, titleVisibility: .visible) {
                Button("Turn off", role: .destructive) { Task { await social.perform {
                    try await social.removeProfile()
                    for list in lists { list.publicRecordName = nil }
                    do { try context.save() } catch { context.rollback(); throw error }
                } } }.accessibilityIdentifier("profile.confirmPrivate")
            } message: { Text("This removes your public profile, makes your public wishlists private, and deletes the follows, likes, and comments you made. Your wishlists stay intact on your devices.") }
            .alert("Wishwell", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameChanged: Bool { trimmedName != (profiles.first?.displayName ?? "") }
    private func profileForEditing() -> LocalProfile {
        if let profile = profiles.first { return profile }
        let profile = LocalProfile(); context.insert(profile); return profile
    }
    private func saveProfile() {
        editingName = false
        guard nameChanged else { return }
        profileForEditing().displayName = trimmedName
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription; return }
        updatePublicProfile()
    }
    private func savePhoto(_ image: UIImage) {
        profileForEditing().photo = image.jpegData(compressionQuality: 0.8)
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription; return }
        updatePublicProfile()
    }
    /// Keeps the public profile in step with the personal one while the account is public.
    private func updatePublicProfile() {
        guard social.me != nil, let profile = profiles.first, !profile.displayName.isEmpty else { return }
        Task { await social.perform { try await social.saveProfile(name: profile.displayName, photo: profile.photo) } }
    }
    private func setPublic(_ on: Bool) {
        editingName = false
        guard on else { turningOff = true; return }
        if nameChanged { saveProfile() }
        guard let profile = profiles.first, !profile.displayName.isEmpty else { message = "Add your name first, so people know who you are."; return }
        Task { await social.perform {
            try await social.saveProfile(name: profile.displayName, photo: profile.photo)
            if AlertPermission.allowed(for: social) { await AlertPermission.request() }
        } }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    static let key = "appearance"
    var id: String { rawValue }
    var label: String { switch self { case .light: "Light"; case .dark: "Dark"; case .system: "Match phone" } }
    var scheme: ColorScheme? { switch self { case .light: .light; case .dark: .dark; case .system: nil } }
}

struct FramingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Lets a person move and zoom a photo inside the profile circle before it's saved.
struct PhotoFramer: View {
    let image: UIImage
    var onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    private let side: CGFloat = 280
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("Drag to move. Pinch or use the slider to zoom.").font(.subheadline).foregroundStyle(.secondary)
                Image(uiImage: image).resizable().frame(width: drawn.width, height: drawn.height).offset(offset)
                    .frame(width: side, height: side).clipShape(Circle()).contentShape(Circle())
                    .overlay(Circle().stroke(Theme.green, lineWidth: 2))
                    .gesture(DragGesture()
                        .onChanged { value in offset = clamped(CGSize(width: settledOffset.width + value.translation.width, height: settledOffset.height + value.translation.height)) }
                        .onEnded { _ in settledOffset = offset })
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { value in zoom(to: settledScale * value.magnification) }
                        .onEnded { _ in settledScale = scale; settledOffset = offset })
                    .accessibilityLabel("Profile photo preview")
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: Binding(get: { scale }, set: { zoom(to: $0); settledScale = scale; settledOffset = offset }), in: 1...4)
                    Image(systemName: "plus.magnifyingglass")
                }.foregroundStyle(.secondary).frame(maxWidth: side + 40)
                Spacer()
            }.padding(24).frame(maxWidth: .infinity).background(Theme.background)
                .navigationTitle("Frame your photo").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(rendered()); dismiss() }.accessibilityIdentifier("photo.save") }
                }
        }
    }
    /// The photo's on-screen size: it always covers the circle, then grows with the zoom.
    private var drawn: CGSize {
        let fill = side / max(1, min(image.size.width, image.size.height))
        return CGSize(width: image.size.width * fill * scale, height: image.size.height * fill * scale)
    }
    private func zoom(to value: CGFloat) {
        scale = min(4, max(1, value)); offset = clamped(offset)
    }
    private func clamped(_ value: CGSize) -> CGSize {
        let x = max(0, (drawn.width - side) / 2), y = max(0, (drawn.height - side) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    /// Draws exactly what's inside the circle into a 600-point square.
    private func rendered() -> UIImage {
        let output: CGFloat = 600, factor = output / side
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format).image { _ in
            let size = CGSize(width: drawn.width * factor, height: drawn.height * factor)
            image.draw(in: CGRect(x: (output - size.width) / 2 + offset.width * factor, y: (output - size.height) / 2 + offset.height * factor, width: size.width, height: size.height))
        }
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
