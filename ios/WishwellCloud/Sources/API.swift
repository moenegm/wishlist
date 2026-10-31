import CloudKit
import CoreData
import SwiftData
import Observation
import CryptoKit

@MainActor @Observable final class CloudStore {
    nonisolated static let containerID = "iCloud.com.nujoomdigital.wishwell"
    var container: ModelContainer?
    var loading = false
    var error: String?
    var localOnly = false
    var syncMessage = "Checking iCloud…"
    private var accountObserver: NSObjectProtocol?
    private var identityObserver: NSObjectProtocol?
    private var syncObserver: NSObjectProtocol?
    private var generation = UUID()
    init() {
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.invalidateAccount()
            }
        }
        identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.invalidateAccount() }
        }
        syncObserver = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let finished = event.endDate != nil
            let failure = event.error?.localizedDescription
            let succeeded = event.succeeded
            Task { @MainActor in
                guard let self, !self.localOnly else { return }
                if let failure { self.syncMessage = "iCloud needs attention: \(failure)" }
                else if finished && succeeded { self.syncMessage = "Last iCloud activity completed. Changes may take a moment to appear on other devices." }
                else { self.syncMessage = "Syncing with iCloud…" }
            }
        }
    }
    private func invalidateAccount() {
        guard !localOnly else { return }
        generation = UUID(); container = nil
        error = "Your iCloud account changed. Reconnect to open the matching library."
        syncMessage = "Reconnect iCloud"
    }
    private func tokenFingerprint() -> String? {
        guard let token = FileManager.default.ubiquityIdentityToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// `library` names a separate on-device store; only debug test launches pass one.
    func open(local: Bool = false, library: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        let attempt = UUID(); generation = attempt
        defer { loading = false }
        do {
            var identity = local ? (library ?? "on-device") : "on-device"
            if !local {
                let cloud = CKContainer(identifier: Self.containerID)
                guard try await cloud.accountStatus() == .available else {
                    throw WishwellError("Sign into iCloud in Settings and enable iCloud Drive to sync Wishwell. You can also use a separate on-device library.")
                }
                let token = tokenFingerprint()
                do {
                    let record = try await cloud.userRecordID()
                    identity = SHA256.hash(data: Data(record.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
                    guard generation == attempt else { return }
                    if let token {
                        UserDefaults.standard.set(["token": token, "library": identity], forKey: "WishwellAccountCache")
                    }
                } catch {
                    // An offline reopen is allowed only when the device's iCloud identity still matches.
                    guard let ck = error as? CKError, [.networkFailure, .networkUnavailable].contains(ck.code),
                          let token, let cached = UserDefaults.standard.dictionary(forKey: "WishwellAccountCache") as? [String: String],
                          cached["token"] == token, let library = cached["library"],
                          library.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw error }
                    identity = library
                }
            }
            guard generation == attempt else { return }
            let root = URL.applicationSupportDirectory.appending(path: "WishwellLibraries", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let schema = Schema([WishList.self, Wish.self, LocalProfile.self, SocialReadState.self, HiddenPerson.self])
            let configuration = ModelConfiguration("Wishwell", schema: schema,
                url: root.appending(path: "\(identity).store"),
                cloudKitDatabase: local ? .none : .private(Self.containerID))
            let opened = try ModelContainer(for: schema, configurations: [configuration])
            opened.mainContext.autosaveEnabled = false
            localOnly = local
            syncMessage = local ? "Saved on this device only" : "iCloud enabled. Waiting for sync activity…"
            container = opened
        } catch { self.error = error.localizedDescription; syncMessage = "Library unavailable" }
    }
}

#if DEBUG
extension CloudStore {
    /// Development only: creates every record type and field for the SwiftData models in the private database.
    /// Uses a throwaway store, so the personal library is never opened.
    /// Runs off the main thread: the setup waits on CloudKit replies that are delivered there.
    static func initializeCloudKitSchema() async throws {
        try await Task.detached(priority: .userInitiated) { try createSchema() }.value
    }
    private nonisolated static func createSchema() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Wishwell.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.shouldAddStoreAsynchronously = false
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [WishList.self, Wish.self, LocalProfile.self, SocialReadState.self, HiddenPerson.self]) else {
            throw WishwellError("The data model couldn't be read.")
        }
        let container = NSPersistentCloudKitContainer(name: "Wishwell", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        // Detach the store before its files go, whether or not the setup worked.
        defer {
            for store in container.persistentStoreCoordinator.persistentStores { try? container.persistentStoreCoordinator.remove(store) }
            try? FileManager.default.removeItem(at: folder)
        }
        try container.initializeCloudKitSchema()
    }

    /// Deletes the placeholder records schema setup leaves in the sync zone when it fails part way.
    /// Only names starting with CD_FAKE_ are touched. Returns how many were removed.
    static func removeSchemaPlaceholders() async throws -> Int {
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")
        var placeholders: [CKRecord.ID] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token)
            placeholders += changes.modificationResultsByID.keys.filter { $0.recordName.hasPrefix("CD_FAKE_") }
            token = changes.changeToken
            more = changes.moreComing
        }
        for batch in stride(from: 0, to: placeholders.count, by: 200) {
            _ = try await database.modifyRecords(saving: [], deleting: Array(placeholders[batch..<min(batch + 200, placeholders.count)]))
        }
        return placeholders.count
    }
}
#endif
