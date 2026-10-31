import Foundation
import CloudKit

@MainActor final class CloudSocialDatabase: SocialDatabase {
    private lazy var container = CKContainer(identifier: "iCloud.com.nujoomdigital.wishwell")
    private var database: CKDatabase { container.publicCloudDatabase }
    /// Looking up the signed-in account is a round trip, so it's done once and forgotten when the account changes.
    private var cachedUser: String?
    private var accountObserver: NSObjectProtocol?
    init() {
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cachedUser = nil }
        }
    }
    func userID() async throws -> String {
        if let cachedUser { return cachedUser }
        let user = try await container.userRecordID().recordName
        cachedUser = user; return user
    }

    private func decode(_ record: CKRecord) async throws -> SocialRow {
        guard let kind = SocialKind(rawValue: record.recordType), let creator = record.creatorUserRecordID?.recordName,
              let payload = record["payload"] as? Data else { throw WishwellError("This shared item has an unsupported format.") }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver); archiver.finishEncoding()
        let author = creator == CKCurrentUserDefaultName ? try await userID() : creator
        return SocialRow(id: record.recordID.recordName, kind: kind, creator: author,
            parent: (record["parent"] as? CKRecord.Reference)?.recordID.recordName,
            sourceID: record["sourceID"] as? String, searchTokens: record["searchTokens"] as? [String] ?? [],
            payload: payload, createdAt: record.creationDate ?? Date(), modifiedAt: record.modificationDate ?? record.creationDate ?? Date(),
            systemFields: archiver.encodedData)
    }
    func record(_ id: String) async throws -> SocialRow? {
        do { return try await decode(database.record(for: CKRecord.ID(recordName: id))) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    func query(_ query: SocialQuery) async throws -> [SocialRow] {
        var filters: [NSPredicate] = []
        if let creator = query.creator { filters.append(NSPredicate(format: "creatorUserRecordID == %@", CKRecord.ID(recordName: creator))) }
        if let parent = query.parent { filters.append(NSPredicate(format: "parent == %@", CKRecord.Reference(recordID: CKRecord.ID(recordName: parent), action: .none))) }
        if let source = query.sourceID { filters.append(NSPredicate(format: "sourceID == %@", source)) }
        if let search = query.searchToken { filters.append(NSPredicate(format: "searchTokens CONTAINS %@", search)) }
        let predicate = filters.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(andPredicateWithSubpredicates: filters)
        let ckQuery = CKQuery(recordType: query.kind.rawValue, predicate: predicate)
        var page = try await database.records(matching: ckQuery, resultsLimit: 100)
        var rows: [SocialRow] = []
        while true {
            for (_, result) in page.matchResults { rows.append(try await decode(result.get())) }
            guard let cursor = page.queryCursor else { break }
            guard rows.count < 2_000 else { throw WishwellError("There are too many results. Please narrow your search.") }
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
        }
        return rows
    }
    func save(_ row: SocialRow) async throws -> SocialRow {
        let record: CKRecord
        if let fields = row.systemFields {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: fields)
            unarchiver.requiresSecureCoding = true
            guard let restored = CKRecord(coder: unarchiver) else { throw WishwellError("This shared item couldn’t be updated. Refresh and try again.") }
            unarchiver.finishDecoding(); record = restored
        } else { record = CKRecord(recordType: row.kind.rawValue, recordID: CKRecord.ID(recordName: row.id)) }
        record["payload"] = row.payload as CKRecordValue
        record["sourceID"] = row.sourceID as CKRecordValue?
        record["searchTokens"] = row.searchTokens.isEmpty ? nil : row.searchTokens as CKRecordValue
        record["parent"] = row.parent.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .deleteSelf) }
        // Restored system fields carry the change tag, so a stale device can't overwrite or recreate a deleted record.
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = result.saveResults[record.recordID] else { throw WishwellError("This shared item couldn’t be saved. Refresh and try again.") }
        return try await decode(saved.get())
    }
    func alertSubscriptionIDs() async throws -> Set<String> {
        Set(try await database.allSubscriptions().map(\.subscriptionID))
    }
    func subscribeAlert(_ alert: SocialAlert) async throws {
        let parent = CKRecord.Reference(recordID: CKRecord.ID(recordName: alert.parent), action: .none)
        let subscription = CKQuerySubscription(recordType: alert.kind.rawValue, predicate: NSPredicate(format: "parent == %@", parent),
                                               // Undoing a gift claim updates its record, so the owner hears about that too.
                                               subscriptionID: alert.id, options: alert.kind == .claim ? [.firesOnRecordCreation, .firesOnRecordUpdate] : .firesOnRecordCreation)
        // Public records live in the default zone.
        subscription.zoneID = CKRecordZone.default().zoneID
        let info = CKSubscription.NotificationInfo()
        info.alertBody = alert.message; info.soundName = "default"; info.shouldBadge = false
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }
    func unsubscribeAlert(_ id: String) async throws {
        do { _ = try await database.deleteSubscription(withID: id) }
        catch let error as CKError where error.code == .unknownItem { }
    }
    func delete(_ row: SocialRow) async throws {
        // The server's Creator role enforces ownership independently of this client.
        _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: row.id))
    }
}
