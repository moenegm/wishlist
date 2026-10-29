import CloudKit
import CoreData
import SwiftData
import Observation
import CryptoKit

@MainActor @Observable final class CloudStore {
    static let containerID = "iCloud.com.nujoomdigital.wishwell"
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
    func open(local: Bool = false) async {
        guard !loading else { return }
        loading = true; error = nil
        let attempt = UUID(); generation = attempt
        defer { loading = false }
        do {
            var identity = "on-device"
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
            let schema = Schema([WishList.self, Wish.self, LocalProfile.self])
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
