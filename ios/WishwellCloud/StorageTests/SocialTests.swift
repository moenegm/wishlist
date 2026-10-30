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
        row.modifiedAt = Date(); row.systemFields = Data(UUID().uuidString.utf8); rows[row.id] = row; writes += 1
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

    @MainActor func testOldICloudAlertSubscriptionsAreRemovedButOthersKept() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let me = try unwrap(owner.me)
        database.alerts["owner"] = [SocialAlert(kind: .follow, parent: me.id).id, "someone-elses-subscription"]
        _ = try await owner.publish(snapshot, existingID: nil)
        expectEqual(database.alerts["owner"], ["someone-elses-subscription"])
    }

    @MainActor func testTheWebsiteIsToldAboutEachFollowAndClaimJustSaved() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        var reported: [(String, String?)] = []
        friend.didSave = { record, profile in reported.append((record, profile)) }
        try await friend.follow(try unwrap(owner.me), enabled: true)
        try await friend.follow(try unwrap(owner.me), enabled: true)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        try await friend.setClaim(listID: id, wishID: wishID, on: false)
        expectEqual(reported.count, 3)
        let follow = try unwrap(database.rows.values.first { $0.kind == .follow })
        let claim = try unwrap(database.rows.values.first { $0.kind == .claim })
        expectEqual(reported.map(\.0), [follow.id, claim.id, claim.id])
        expectEqual(reported.first?.1, friend.me?.id)
        expectNil(reported.last?.1)
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
        XCTAssertEqual(activity.count, 1); XCTAssertEqual(activity.first?.message, "Tomas added you to their circle")
        XCTAssertEqual(database.writes, before)
        database.user = "friend"; try await friend.follow(me, enabled: false)
        expectTrue(try await friend.following().isEmpty)
    }

    @MainActor private func cousin(_ database: TestSocialDatabase) async throws -> SocialStore {
        database.user = "cousin"
        let cousin = SocialStore(database: database, enabled: true)
        try await cousin.saveProfile(name: "Laila", photo: nil)
        return cousin
    }

    @MainActor func testGiversSeeWhoIsGettingAWishButTheOwnerOnlyLearnsSomeoneIs() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        expectEqual(try await friend.claims(listID: id)[wishID], .mine)
        let laila = try await cousin(database)
        expectEqual(try await laila.claims(listID: id)[wishID], .other("Tomas"))
        await rejects { try await laila.setClaim(listID: id, wishID: wishID, on: true) }
        await rejects { try await laila.setClaim(listID: id, wishID: UUID(), on: true) }
        database.user = "owner"
        expectEqual(try await owner.claims(listID: id)[wishID], .someone)
        await rejects { try await owner.setClaim(listID: id, wishID: wishID, on: true) }
        database.user = "friend"
        try await friend.setClaim(listID: id, wishID: wishID, on: false)
        database.user = "cousin"
        expectNil(try await laila.claims(listID: id)[wishID])
        try await laila.setClaim(listID: id, wishID: wishID, on: true)
        expectEqual(try await laila.claims(listID: id)[wishID], .mine)
    }

    @MainActor func testAClaimJustMadeSurvivesARefreshAndTappingAgainSavesNothing() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        var reports = 0
        friend.didSave = { _, _ in reports += 1 }
        // iCloud's search hasn't caught up with the claim yet.
        database.laggingIndex = database.rows
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        expectEqual(try await friend.claims(listID: id)[wishID], .mine)
        let writes = database.writes
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        expectEqual(database.writes, writes)
        expectEqual(reports, 1)
        // Undoing while the search still shows nothing works too, and is reported once.
        try await friend.setClaim(listID: id, wishID: wishID, on: false)
        expectNil(try await friend.claims(listID: id)[wishID])
        expectEqual(reports, 2)
        database.laggingIndex = nil
        expectNil(try await friend.claims(listID: id)[wishID])
    }

    @MainActor func testOnlyOwnerCanPublishAndUndoingOnlyAffectsYourOwnClaim() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        await rejects { _ = try await friend.publish(snapshot, existingID: id) }
        await rejects { try await friend.unpublish(id) }
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        let laila = try await cousin(database)
        try await laila.setClaim(listID: id, wishID: wishID, on: false)
        expectEqual(try await laila.claims(listID: id)[wishID], .other("Tomas"))
    }

    @MainActor func testUnpublishHidesOrphanedInteractionsAndRejectsStaleRepublishing() async throws {
        let (database, owner, privateList, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let stale = try XCTUnwrap(database.rows[id])
        let friend = try await member(database)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        database.user = "owner"; database.keepOrphans = true
        try await owner.unpublish(id)
        XCTAssertTrue(database.rows.values.contains { $0.kind == .claim })
        XCTAssertEqual(privateList.wishes?.count, 1)
        await rejects { _ = try await owner.publish(snapshot, existingID: id) }
        await rejects { _ = try await database.save(stale) }
        XCTAssertNil(database.rows[id])
        expectTrue(try await owner.activity().isEmpty)
        database.user = "friend"
        expectNil(try await friend.publicList(id))
        await rejects { try await friend.setClaim(listID: id, wishID: wishID, on: true) }
    }

    @MainActor func testMakingAListPrivateKeepsWhoIsGettingWhatForWhenItIsSharedAgain() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        database.user = "owner"
        try await owner.pause(id)
        // Nothing of the list itself stays public, and nobody can claim from it.
        let paused = try unwrap(database.rows[id])
        XCTAssertFalse(String(decoding: paused.payload, as: UTF8.self).contains("Private room"))
        expectTrue(try await owner.lists(owner: "owner").isEmpty)
        database.user = "friend"
        expectNil(try await friend.publicList(id))
        await rejects { try await friend.setClaim(listID: id, wishID: wishID, on: false) }
        // Sharing it again reuses the same record, so the claim is still there.
        database.user = "owner"
        expectEqual(try await owner.publish(snapshot, existingID: nil), id)
        expectEqual(try await owner.claims(listID: id)[wishID], .someone)
        expectEqual(try await owner.lists(owner: "owner").map(\.id), [id])
    }

    @MainActor func testOwnerHearsWhenSomeoneMightBeGettingAWishAndWhenItIsOpenAgain() async throws {
        let (database, owner, privateList, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(privateList.wishes?.first?.id)
        let friend = try await member(database)
        try await friend.follow(try unwrap(try await friend.profile(owner: "owner")), enabled: true)
        expectEqual(friend.followingOwners, nil)
        _ = try await friend.following()
        expectEqual(friend.followingOwners, ["owner"])
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        database.user = "owner"
        let getting = try unwrap(try await owner.activity().first { $0.message.contains("getting") })
        expectEqual(getting.message, "Someone might be getting your wish Chair")
        expectNil(getting.actor)
        expectEqual(getting.wishID, wishID)
        database.user = "friend"
        try await friend.setClaim(listID: id, wishID: wishID, on: false)
        database.user = "owner"
        let open = try unwrap(try await owner.activity().first { $0.message.contains("open again") })
        expectEqual(open.message, "Chair is open again")
        XCTAssertNotEqual(open.id, getting.id)
        expectEqual(owner.claimCache[id]?[wishID], nil)
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

    @MainActor func testWishesAddedAfterYouAddSomeoneShowAsNew() async throws {
        let (database, owner, _, _) = try await fixture()
        let friend = try await member(database)
        database.user = "owner"
        try await owner.follow(try unwrap(try await owner.profile(owner: "friend")), enabled: true)
        database.user = "friend"
        let list = WishList(title: "Birthday", category: "")
        list.wishes = [try Wish(title: "Kite", options: [], list: list)]
        _ = try await friend.publish(PublicList(list: list, profile: try unwrap(friend.me)), existingID: nil)
        database.user = "owner"
        let activity = try await owner.activity()
        expectEqual(activity.map(\.message), ["Tomas added Kite"])
        // A second load at the same time shares the first instead of starting over.
        async let first = owner.activity()
        async let second = owner.activity()
        let (a, b) = try await (first, second)
        expectEqual(a.map(\.id), b.map(\.id))
    }

    @MainActor func testBlockedPeopleAreHiddenFromDiscoveryClaimsAndActivity() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        database.user = "owner"; owner.hidden.insert("friend")
        expectTrue(try await owner.search("to").isEmpty)
        expectTrue(try await owner.claims(listID: id).isEmpty)
        expectTrue(try await owner.activity().isEmpty)
    }

    @MainActor func testAccountSwitchDuringOperationCannotWriteAsNewAccount() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let friend = try await member(database)
        database.afterQuery = { database.user = "unrelated" }
        let before = database.writes
        await rejects { try await friend.setClaim(listID: id, wishID: try XCTUnwrap(snapshot.wishes.first?.id), on: true) }
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
    @MainActor func testDuplicateClaimsShowOnceAndUndoingClearsEveryCopy() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        let wishID = try unwrap(snapshot.wishes.first?.id)
        let friend = try await member(database)
        for _ in 0..<2 {
            _ = try await database.save(SocialRow(kind: .claim, parent: id, payload: JSONEncoder().encode(GiftClaim(wishID: wishID, active: true))))
        }
        expectEqual(try await friend.claims(listID: id)[wishID], .mine)
        try await friend.setClaim(listID: id, wishID: wishID, on: false)
        expectNil(try await friend.claims(listID: id)[wishID])
    }
    @MainActor func testOldLikesAreNotMistakenForClaims() async throws {
        let (database, owner, _, snapshot) = try await fixture()
        let id = try await owner.publish(snapshot, existingID: nil)
        _ = try await member(database)
        _ = try await database.save(SocialRow(kind: .claim, parent: id, payload: JSONEncoder().encode(SocialAction(wishID: snapshot.wishes.first?.id))))
        database.user = "owner"
        expectTrue(try await owner.claims(listID: id).isEmpty)
        expectTrue(try await owner.activity().isEmpty)
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
    @MainActor func testRemovedWishTitlesDisappearFromActivityAndClaims() async throws {
        let (database, owner, _, original) = try await fixture()
        let id = try await owner.publish(original, existingID: nil)
        let friend = try await member(database)
        let wishID = try XCTUnwrap(original.wishes.first?.id)
        try await friend.setClaim(listID: id, wishID: wishID, on: true)
        database.user = "owner"
        expectTrue(try await owner.activity().contains { $0.message.contains("Chair") })
        var updated = original; updated.wishes = []
        _ = try await owner.publish(updated, existingID: id)
        expectTrue(try await owner.activity().isEmpty)
        database.user = "friend"
        await rejects { try await friend.setClaim(listID: id, wishID: wishID, on: false) }
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
