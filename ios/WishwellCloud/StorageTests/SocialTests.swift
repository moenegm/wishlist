import XCTest
@testable import WishwellStorage

@MainActor final class TestSocialDatabase: SocialDatabase {
    var user = "owner"
    var rows: [String: SocialRow] = [:]
    var writes = 0
    var keepOrphans = false
    var afterQuery: (() -> Void)?
    var alerts: [String: Set<String>] = [:]
    /// When set, queries read this snapshot instead of the live rows, like CloudKit's lagging query index.
    var laggingIndex: [String: SocialRow]?
    func alertSubscriptionIDs() async throws -> Set<String> { alerts[user] ?? [] }
    func subscribeAlert(_ alert: SocialAlert) async throws { alerts[user, default: []].insert(alert.id) }
    func unsubscribeAlert(_ id: String) async throws { alerts[user]?.remove(id) }
    func userID() async throws -> String { user }
    func record(_ id: String) async throws -> SocialRow? {
        guard let row = rows[id] else { return nil }
        if row.kind == .report && row.creator != user { throw WishwellError("Not permitted") }
        return row
    }
    func query(_ query: SocialQuery) async throws -> [SocialRow] {
        let result = (laggingIndex ?? rows).values.filter {
            $0.kind == query.kind && (query.creator == nil || $0.creator == query.creator) &&
            (query.parent == nil || $0.parent == query.parent) &&
            (query.sourceID == nil || $0.sourceID == query.sourceID) &&
            (query.searchToken == nil || $0.searchTokens.contains(query.searchToken!)) &&
            ($0.kind != .report || $0.creator == user)
        }
        let callback = afterQuery; afterQuery = nil; callback?()
        return result
    }
    func save(_ value: SocialRow) async throws -> SocialRow {
        var row = value
        if let old = rows[row.id] {
            guard old.creator == user, old.systemFields == row.systemFields else { throw WishwellError("Not permitted or stale version") }
            row.creator = old.creator; row.createdAt = old.createdAt
        } else {
            guard row.systemFields == nil else { throw WishwellError("Deleted records cannot be recreated from a stale version") }
            row.creator = user
        }
        if let parent = row.parent, rows[parent] == nil { throw WishwellError("Missing parent") }
        row.systemFields = Data(UUID().uuidString.utf8); rows[row.id] = row; writes += 1
        return row
    }
    func delete(_ row: SocialRow) async throws {
        guard let old = rows[row.id] else { return }
        guard old.creator == user else { throw WishwellError("Not permitted") }
        rows[row.id] = nil; writes += 1
        if !keepOrphans {
            var removed = Set([row.id])
            while true {
                let children = rows.values.filter { $0.parent.map(removed.contains) ?? false }
                guard !children.isEmpty else { break }
                for child in children { rows[child.id] = nil; removed.insert(child.id) }
            }
        }
    }
}

final class SocialTests: XCTestCase {
    private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value, file: file, line: line) }
    private func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { XCTAssertNil(value, file: file, line: line) }
    private func expectEqual<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(value, expected, file: file, line: line) }
    private func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T { try XCTUnwrap(value, file: file, line: line) }

    @MainActor private func fixture() async throws -> (TestSocialDatabase, SocialStore, WishList, PublicList) {
        let database = TestSocialDatabase()
        let owner = SocialStore(database: database, enabled: true)
        try await owner.saveProfile(name: "Moe", photo: nil)
        let privateList = WishList(title: "Private room", category: "Home")
        let wish = try Wish(title: "Chair", options: [ShoppingOption(location: "Shop", price: "99")], list: privateList)
        privateList.wishes = [wish]
        let snapshot = PublicList(list: privateList, profile: try XCTUnwrap(owner.me))
        return (database, owner, privateList, snapshot)
    }
    @MainActor private func member(_ database: TestSocialDatabase) async throws -> SocialStore {
        database.user = "friend"
        let member = SocialStore(database: database, enabled: true)
        try await member.saveProfile(name: "Tomas", photo: nil)
        return member
    }
    @MainActor private func rejects(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected operation to be rejected", file: file, line: line) } catch {}
    }

    @MainActor func testDiagnosticFixturesNeverAppearInNormalSocialReads() async throws {
        let (database, owner, privateList, _) = try await fixture()
        // An older synthetic profile must not replace the real one.
        let fixtureProfile = PublicProfile(id: "wishwell-check-1-profile", ownerID: "owner", name: "Wishwell permission test", photo: nil)
        database.rows[fixtureProfile.id] = SocialRow(id: fixtureProfile.id, kind: .profile, creator: "owner", searchTokens: PublicProfile.tokens(for: fixtureProfile.name), payload: try JSONEncoder().encode(fixtureProfile), createdAt: .distantPast)
        let fixtureList = PublicList(list: privateList, profile: fixtureProfile, id: "wishwell-check-1-list")
        database.rows[fixtureList.id] = SocialRow(id: fixtureList.id, kind: .list, creator: "owner", parent: fixtureProfile.id, sourceID: privateList.id.uuidString, payload: try JSONEncoder().encode(fixtureList))
        let profile = try await owner.profile(owner: "owner"); expectEqual(profile?.name, "Moe")
        let found = try await owner.search("wishwell"); expectEqual(found.count, 0)
        let list = try await owner.publicList(fixtureList.id); expectNil(list)
        let lists = try await owner.lists(owner: "owner"); expectEqual(lists.count, 0)
    }

    @MainActor func testAlertsFollowProfileAndPublishedListsOnly() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        try await owner.syncAlerts()
        let me = try unwrap(owner.me)
        expectEqual(database.alerts["owner"], [SocialAlert(kind: .follow, parent: me.id).id])
        let listID = try await owner.publish(snapshot, existingID: nil)
        try await owner.syncAlerts()
        expectEqual(database.alerts["owner"], Set([SocialAlert(kind: .follow, parent: me.id).id, SocialAlert(kind: .like, parent: listID).id, SocialAlert(kind: .comment, parent: listID).id]))
        database.alerts["owner"]?.insert("someone-elses-subscription")
        try await owner.unpublish(listID)
        try await owner.syncAlerts()
        expectEqual(database.alerts["owner"], [SocialAlert(kind: .follow, parent: me.id).id, "someone-elses-subscription"])
        try await owner.removeProfile()
        try await owner.syncAlerts()
        expectEqual(database.alerts["owner"], ["someone-elses-subscription"])
    }

    @MainActor func testAlertsCoverAListTheQueryIndexHasNotCaughtUpWith() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let me = try unwrap(owner.me)
        database.laggingIndex = database.rows
        let listID = try await owner.publish(snapshot, existingID: nil)
        expectEqual(database.alerts["owner"], Set([SocialAlert(kind: .follow, parent: me.id).id, SocialAlert(kind: .like, parent: listID).id, SocialAlert(kind: .comment, parent: listID).id]))
        database.laggingIndex = database.rows
        try await owner.unpublish(listID)
        expectEqual(database.alerts["owner"], [SocialAlert(kind: .follow, parent: me.id).id])
    }

    @MainActor func testSearchMatchesEveryTypedWord() async throws {
        let (database, owner, _, _) = try await fixture()
        database.user = "friend"
        let friend = SocialStore(database: database, enabled: true)
        try await friend.saveProfile(name: "Tomas Ålund", photo: nil)
        database.user = "owner"
        let full = try await owner.search("tomas alund"); expectEqual(full.map(\.name), ["Tomas Ålund"])
        let prefixes = try await owner.search("  Tom   Ål "); expectEqual(prefixes.map(\.name), ["Tomas Ålund"])
        let mismatch = try await owner.search("tomas smith"); expectTrue(mismatch.isEmpty)
    }

    @MainActor func testPrivateContentIsNotPublishedByCreatingOrEditingIt() async throws {
        let (database, _, privateList, _) = try await fixture()
        privateList.title = "Still private"; privateList.wishes?.first?.fulfilled = true
        XCTAssertEqual(database.rows.values.filter { $0.kind == .list }.count, 0)
        XCTAssertNil(privateList.publicRecordName)
        XCTAssertFalse(database.rows.values.contains { String(data: $0.payload, encoding: .utf8)?.contains("Still private") == true })
    }

    @MainActor func testDisabledSocialGateCannotWrite() async throws {
        let database = TestSocialDatabase()
        let service = SocialStore(database: database, enabled: false)
        await rejects { try await service.saveProfile(name: "Moe", photo: nil) }
        XCTAssertEqual(database.writes, 0)
        XCTAssertNil(service.me)
    }

    @MainActor func testSearchAndIdentityComeFromServerCreator() async throws {
        let (database, owner, _, _) = try await fixture()
        database.user = "attacker"
        let spoof = PublicProfile(id: "forged", ownerID: "owner", name: "Moe impersonation", photo: nil)
        _ = try await database.save(SocialRow(id: "forged", kind: .profile, searchTokens: PublicProfile.tokens(for: spoof.name), payload: JSONEncoder().encode(spoof)))
        let attacker = SocialStore(database: database, enabled: true)
        let profile = try unwrap(try await attacker.profile(owner: "attacker"))
        XCTAssertEqual(profile.ownerID, "attacker")
        XCTAssertEqual(profile.id, "forged")
        database.user = "owner"
        let matches = try await owner.search("mo")
        XCTAssertEqual(Set(matches.map(\.ownerID)), Set(["owner", "attacker"]))
        XCTAssertEqual(PublicProfile.tokens(for: "Élodie Smith").contains("elo"), true)
    }

    @MainActor func testFollowDeduplicatesAndActivityDoesNotMarkAnythingRead() async throws {
        let (database, owner, _, _) = try await fixture()
        let me = try XCTUnwrap(owner.me), friend = try await member(database)
        try await friend.follow(me, enabled: true); try await friend.follow(me, enabled: true)
        expectEqual(try await friend.following().count, 1)
        database.user = "owner"
        let before = database.writes
        let activity = try await owner.activity()
        XCTAssertEqual(activity.count, 1); XCTAssertTrue(activity.first?.message.contains("Tomas followed") == true)
        XCTAssertEqual(database.writes, before)
        database.user = "friend"; try await friend.follow(me, enabled: false)
        expectTrue(try await friend.following().isEmpty)
    }

    @MainActor func testLikesAndCommentsRespectListAndWishTargets() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        try await friend.setLike(listID: id, wishID: nil, liked: true)
        try await friend.setLike(listID: id, wishID: nil, liked: true)
        let wishID = try XCTUnwrap(snapshot.wishes.first?.id)
        try await friend.comment(listID: id, wishID: wishID, text: " Lovely chair ")
        let listThread = try await friend.thread(listID: id, wishID: nil)
        let wishThread = try await friend.thread(listID: id, wishID: wishID)
        XCTAssertEqual(listThread.likeCount, 1); XCTAssertTrue(listThread.liked); XCTAssertTrue(listThread.comments.isEmpty)
        XCTAssertEqual(wishThread.comments.first?.text, "Lovely chair"); XCTAssertEqual(wishThread.likeCount, 0)
        await rejects { try await friend.comment(listID: id, wishID: UUID(), text: "Unknown wish") }
        await rejects { try await friend.comment(listID: id, wishID: nil, text: String(repeating: "a", count: 501)) }
        try await friend.setLike(listID: id, wishID: nil, liked: false)
        expectEqual(try await friend.thread(listID: id, wishID: nil).likeCount, 0)
    }

    @MainActor func testOnlyOwnerCanPublishAndOnlyAuthorCanDeleteComment() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        await rejects { _ = try await friend.publish(snapshot, existingID: id) }
        await rejects { try await friend.unpublish(id) }
        try await friend.comment(listID: id, wishID: nil, text: "A comment")
        let comment = try unwrap(try await friend.thread(listID: id, wishID: nil).comments.first)
        database.user = "owner"
        await rejects { try await owner.deleteComment(comment.id) }
        database.user = "friend"; try await friend.deleteComment(comment.id)
        expectTrue(try await friend.thread(listID: id, wishID: nil).comments.isEmpty)
    }

    @MainActor func testUnpublishHidesOrphanedInteractionsAndRejectsStaleRepublishing() async throws {
        let (database, owner, privateList, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let stale = try XCTUnwrap(database.rows[id])
        let friend = try await member(database)
        try await friend.comment(listID: id, wishID: nil, text: "Old public comment")
        database.user = "owner"; database.keepOrphans = true
        try await owner.unpublish(id)
        XCTAssertTrue(database.rows.values.contains { $0.kind == .comment })
        XCTAssertEqual(privateList.wishes?.count, 1)
        await rejects { _ = try await owner.publish(snapshot, existingID: id) }
        await rejects { _ = try await database.save(stale) }
        XCTAssertNil(database.rows[id])
        expectTrue(try await owner.activity().isEmpty)
        database.user = "friend"
        expectNil(try await friend.publicList(id))
        await rejects { _ = try await friend.thread(listID: id, wishID: nil) }
        await rejects { try await friend.comment(listID: id, wishID: nil, text: "Too late") }
    }

    @MainActor func testMakingAListPrivateKeepsItsLikesAndCommentsForTheOwner() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        try await friend.comment(listID: id, wishID: nil, text: "Lovely list")
        try await friend.setLike(listID: id, wishID: nil, liked: true)
        database.user = "owner"
        try await owner.pause(id)
        // Nothing of the list itself stays public.
        let paused = try unwrap(database.rows[id])
        XCTAssertFalse(String(decoding: paused.payload, as: UTF8.self).contains("Private room"))
        expectTrue(try await owner.lists(owner: "owner").isEmpty)
        // The owner still reads what was said, but nobody can add to it.
        let ownerView = try await owner.thread(listID: id, wishID: nil)
        expectTrue(ownerView.paused)
        expectEqual(ownerView.comments.map(\.text), ["Lovely list"])
        expectEqual(ownerView.likeCount, 1)
        await rejects { try await owner.comment(listID: id, wishID: nil, text: "My own note") }
        database.user = "friend"
        expectNil(try await friend.publicList(id))
        await rejects { _ = try await friend.thread(listID: id, wishID: nil) }
        await rejects { try await friend.comment(listID: id, wishID: nil, text: "Still here?") }
        await rejects { try await friend.setLike(listID: id, wishID: nil, liked: false) }
        // Sharing it again reuses the same record, so everything comes back.
        database.user = "owner"
        expectEqual(try await owner.publish(snapshot, existingID: nil), id)
        let restored = try await owner.thread(listID: id, wishID: nil)
        XCTAssertFalse(restored.paused)
        expectEqual(restored.comments.map(\.text), ["Lovely list"])
        expectEqual(try await owner.lists(owner: "owner").map(\.id), [id])
    }

    @MainActor func testWishActivityPointsAtTheWishAndScreensCanShowLastKnownResults() async throws {
        let (database, owner, privateList, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(privateList.wishes?.first?.id)
        let friend = try await member(database)
        try await friend.follow(try unwrap(try await friend.profile(owner: "owner")), enabled: true)
        expectEqual(friend.followingOwners, nil)
        _ = try await friend.following()
        expectEqual(friend.followingOwners, ["owner"])
        try await friend.comment(listID: id, wishID: wishID, text: "This one!")
        database.user = "owner"
        let comment = try unwrap(try await owner.activity().first { $0.message.contains("commented") })
        expectEqual(comment.wishID, wishID)
        _ = try await owner.thread(listID: id, wishID: wishID)
        expectEqual(owner.cachedThread(listID: id, wishID: wishID)?.comments.map(\.text), ["This one!"])
        XCTAssertNotNil(owner.listCache[id])
        try await owner.pause(id)
        XCTAssertNil(owner.listCache[id])
    }

    @MainActor func testAQuickPrivateThenPublicSwitchFindsTheRecordBeforeTheIndexCatchesUp() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        database.laggingIndex = [:]
        let id = try await owner.publish(snapshot, existingID: nil)
        try await owner.pause(id)
        expectEqual(try await owner.publish(snapshot, existingID: nil), id)
        expectEqual(database.rows.values.filter { $0.kind == .list }.count, 1)
    }

    @MainActor func testBlockedAuthorsAreHiddenFromDiscoveryThreadsAndActivity() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        try await friend.comment(listID: id, wishID: nil, text: "Hello")
        try await friend.setLike(listID: id, wishID: nil, liked: true)
        database.user = "owner"; owner.hidden.insert("friend")
        expectTrue(try await owner.search("to").isEmpty)
        let thread = try await owner.thread(listID: id, wishID: nil)
        XCTAssertEqual(thread.likeCount, 0); XCTAssertTrue(thread.comments.isEmpty)
        expectTrue(try await owner.activity().isEmpty)
    }

    @MainActor func testAccountSwitchDuringOperationCannotWriteAsNewAccount() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        database.afterQuery = { database.user = "unrelated" }
        let before = database.writes
        await rejects { try await friend.setLike(listID: id, wishID: nil, liked: true) }
        XCTAssertEqual(database.writes, before)
        XCTAssertNil(friend.me)
    }

    @MainActor func testRemovePublicProfilePreservesPrivateOriginals() async throws {
        let (database, owner, privateList, snapshot) = try await fixture()
        _ = try await owner.publish(snapshot, existingID: nil)
        try await owner.removeProfile()
        XCTAssertNil(owner.me)
        XCTAssertFalse(database.rows.values.contains { $0.creator == "owner" })
        XCTAssertEqual(privateList.title, "Private room"); XCTAssertEqual(privateList.wishes?.first?.title, "Chair")
    }

    @MainActor func testReportsAreNotReadableByAnotherMember() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        try await friend.report(id, reason: "Test report")
        let reportID = try XCTUnwrap(database.rows.values.first { $0.kind == .report }?.id)
        database.user = "owner"
        await rejects { _ = try await database.record(reportID) }
        expectTrue(try await database.query(SocialQuery(kind: .report)).isEmpty)
    }
    @MainActor func testDuplicateLikesCountOnceAndUnlikingRemovesAllOwnCopies() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        for _ in 0..<2 {
            _ = try await database.save(SocialRow(kind: .like, parent: id, payload: JSONEncoder().encode(SocialAction())))
        }
        expectEqual(try await friend.thread(listID: id, wishID: nil).likeCount, 1)
        try await friend.setLike(listID: id, wishID: nil, liked: false)
        expectEqual(try await friend.thread(listID: id, wishID: nil).likeCount, 0)
    }
    @MainActor func testFollowersAndUnfollowAcrossDuplicateProfileRecords() async throws {
        let (database, owner, _, _) = try await fixture()
        let canonical = try XCTUnwrap(owner.me)
        let duplicate = PublicProfile(id: "another-profile", ownerID: "owner", name: "Moe", photo: nil)
        _ = try await database.save(SocialRow(id: duplicate.id, kind: .profile, payload: JSONEncoder().encode(duplicate)))
        let friend = try await member(database)
        try await friend.follow(duplicate, enabled: true)
        database.user = "owner"
        expectEqual(try await owner.followers(of: canonical).count, 1)
        database.user = "friend"
        try await friend.follow(canonical, enabled: false)
        expectTrue(try await friend.following().isEmpty)
    }
    @MainActor func testRemovedWishTitlesDisappearFromActivityAndThreads() async throws {
        let (database, owner, _, original) = try await fixture()
        let id = try await owner.publish(original, existingID: nil)
        let friend = try await member(database)
        let wishID = try XCTUnwrap(original.wishes.first?.id)
        try await friend.setLike(listID: id, wishID: wishID, liked: true)
        database.user = "owner"
        expectTrue(try await owner.activity().contains { $0.message.contains("Chair") })
        var updated = original; updated.wishes = []
        _ = try await owner.publish(updated, existingID: id)
        expectTrue(try await owner.activity().isEmpty)
        database.user = "friend"
        await rejects { _ = try await friend.thread(listID: id, wishID: wishID) }
    }
    @MainActor func testForeignProfileParentCannotImpersonateOwner() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        database.user = "attacker"
        _ = try await database.save(SocialRow(id: snapshot.id, kind: .list, parent: try XCTUnwrap(owner.me).id, sourceID: snapshot.sourceID.uuidString, payload: JSONEncoder().encode(snapshot)))
        database.user = "owner"
        expectNil(try await owner.publicList(snapshot.id))
    }
    func testReportSchemaDoesNotGrantWorldReadOrAuthenticatedWrite() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("CloudKit/social.ckdb")
        let schema = try String(contentsOf: url, encoding: .utf8)
        let report = try XCTUnwrap(schema.components(separatedBy: "RECORD TYPE WWReport (").last)
        XCTAssertFalse(report.contains("TO \"_world\""))
        XCTAssertFalse(schema.contains("GRANT WRITE TO \"_icloud\""))
        XCTAssertFalse(schema.contains("GRANT WRITE TO \"_world\""))
        XCTAssertTrue(report.contains("GRANT READ, WRITE TO Moderator"))
        XCTAssertTrue(report.contains("GRANT READ, WRITE TO \"_creator\""))
        XCTAssertFalse(report.contains("GRANT READ TO \"_icloud\""))
    }
}
