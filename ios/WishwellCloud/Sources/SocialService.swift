import Foundation
import Observation

@MainActor @Observable final class SocialStore {
    let database: any SocialDatabase
    var enabled: Bool
    var isDemo = false
    /// Debug-only: real development CloudKit social records with an isolated synthetic library.
    var isLiveTest = false
    private(set) var actorID: String?
    private(set) var me: PublicProfile?
    var hidden: Set<String> = []
    var error: String?
    var busy = false
    var publicationMessage: String?
    /// Told about each follow or gift claim just saved, so the website can notify the person it's for.
    var didSave: ((_ record: String, _ profile: String?) async -> Void)?
    var activityRows: [SocialActivity] = []
    var refreshRevision = 0
    /// Lists made private on this device, by personal list ID. Reading a record by name is immediate,
    /// while the query index can lag, so a quick private-then-public switch still finds the old record.
    private var pausedRecords: [String: String] = [:]
    /// Last-known results, shown straight away while a fresh copy loads, so screens don't start empty.
    var followingOwners: Set<String>?
    var claimCache: [String: [UUID: ClaimState]] = [:]
    /// This person's own claims from the last few minutes. iCloud's search can take several seconds to include
    /// a new or changed claim, so a refresh in that window would otherwise undo what they just tapped.
    private var recentClaims: [String: (on: Bool, at: Date)] = [:]
    private var ownClaimRecords: [String: String] = [:]
    var listCache: [String: PublicList] = [:]
    var ownerListCache: [String: [PublicList]] = [:]
    var circleCache: [String: [PublicProfile]] = [:]
    /// Personal lists being made public right now, so their switch shows the change before iCloud confirms it.
    var publishing: Set<UUID> = []
    /// How long a looked-up profile is reused before it's fetched again.
    var profileLifetime: TimeInterval = 60
    private var profileCache: [String: (profile: PublicProfile?, fetched: Date)] = [:]
    private var profileRows: [String: (row: SocialRow, fetched: Date)] = [:]
    private var listsFetched: [String: Date] = [:]
    /// When this person added each member of their circle; only wishes added after that count as new.
    private var followedAt: [String: Date] = [:]
    /// Work already under way. Opening the app used to start the same downloads two or three times over,
    /// and they queued behind each other for about ten seconds.
    private var warming: Task<Void, Never>?
    private var loadingActivity: Task<[SocialActivity], Error>?
    /// Notifications that have arrived as banners, shown at once until the full details load from iCloud.
    /// Some, like "no longer on the list", only ever exist as a banner, so they're kept on the phone for 30 days.
    var deliveredRows: [SocialActivity] = []
    static let bannerLifetime: TimeInterval = 30 * 86_400
    /// Adds banners that just arrived to the ones already kept, leaving out any iCloud has since given full details for.
    func keepBanners(_ fresh: [SocialActivity]) {
        let known = Set(activityRows.map(\.message))
        var seen: Set<String> = []
        deliveredRows = (fresh + deliveredRows).filter {
            seen.insert($0.id).inserted && !known.contains($0.message) && Date().timeIntervalSince($0.date) < Self.bannerLifetime
        }
        saveSnapshot()
    }
    private var epoch = UUID()
    init(database: (any SocialDatabase)? = nil, enabled: Bool = Bundle.main.object(forInfoDictionaryKey: "WishwellSocialEnabled") as? Bool ?? false) {
        self.database = database ?? CloudSocialDatabase(); self.enabled = enabled
        // The app opens with the circle it saw last time; tests start empty.
        if database == nil && enabled { restoreSnapshot() }
    }

    /// What's kept on the phone so the circle and people's lists show instantly, before iCloud answers.
    private struct Snapshot: Codable {
        var actor: String
        var me: PublicProfile?
        var circle: [PublicProfile]
        var lists: [String: [PublicList]]
        var activity: [SocialActivity]?
        var banners: [SocialActivity]?
    }
    private var snapshotActor: String?
    private static var snapshotURL: URL { URL.applicationSupportDirectory.appending(path: "WishwellCircle.json") }
    private func restoreSnapshot() {
        guard let data = try? Data(contentsOf: Self.snapshotURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshotActor = snapshot.actor
        me = snapshot.me
        circleCache["following"] = snapshot.circle
        followingOwners = Set(snapshot.circle.map(\.ownerID))
        ownerListCache = snapshot.lists
        activityRows = snapshot.activity ?? []
        deliveredRows = (snapshot.banners ?? []).filter { Date().timeIntervalSince($0.date) < Self.bannerLifetime }
        for list in snapshot.lists.values.flatMap({ $0 }) { listCache[list.id] = list }
    }
    private func saveSnapshot() {
        guard let actorID else { return }
        let circle = circleCache["following"] ?? []
        let owners = Set(circle.map(\.ownerID))
        let snapshot = Snapshot(actor: actorID, me: me, circle: circle, lists: ownerListCache.filter { owners.contains($0.key) }, activity: activityRows, banners: deliveredRows)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: Self.snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.snapshotURL, options: [.atomic, .completeFileProtection])
    }
    /// Refreshes the circle and everyone's lists in the background, so they're ready before they're opened.
    func warmCircle() async {
        if let warming { return await warming.value }
        let task = Task { @MainActor in
            guard let people = try? await self.following() else { return }
            await withTaskGroup(of: Void.self) { group in
                for person in people { group.addTask { @MainActor in _ = try? await self.lists(owner: person.ownerID) } }
            }
            self.saveSnapshot()
        }
        warming = task
        await task.value
        warming = nil
    }
    func connect() async throws {
        guard enabled else { throw WishwellError("Social sharing is awaiting CloudKit permission setup. Your private library is ready to use.") }
        let attempt = epoch
        let user = try await database.userID()
        guard attempt == epoch else { throw CancellationError() }
        actorID = user
        // A different account never sees the previous one's saved circle.
        if let snapshotActor, snapshotActor != user {
            circleCache = [:]; ownerListCache = [:]; listCache = [:]; followingOwners = nil; me = nil; activityRows = []
            try? FileManager.default.removeItem(at: Self.snapshotURL)
        }
        snapshotActor = user
        me = try await profile(owner: user)
        await refreshAlerts()
    }
    /// Notifications now come from the website. This removes the iCloud alert subscriptions earlier versions made,
    /// which never delivered and would otherwise double up if they started to.
    func syncAlerts(published: String? = nil, unpublished: String? = nil) async throws {
        _ = try await actor()
        let wanted: Set<SocialAlert> = []
        let existing = try await database.alertSubscriptionIDs().filter { $0.hasPrefix(SocialAlert.prefix) }
        for id in existing.subtracting(wanted.map(\.id)) { try await database.unsubscribeAlert(id) }
        for alert in wanted where !existing.contains(alert.id) { try await database.subscribeAlert(alert) }
    }
    /// Alerts are best effort: a failure never blocks the social action that triggered it.
    private func refreshAlerts(published: String? = nil, unpublished: String? = nil) async {
        do { try await syncAlerts(published: published, unpublished: unpublished) } catch { print("Wishwell alerts: \(error)") }
    }
    func reset() { epoch = UUID(); actorID = nil; me = nil; hidden = []; activityRows = [] }
    private func actor() async throws -> String {
        guard enabled else { throw WishwellError("CloudKit social setup is not active yet.") }
        let current = try await database.userID()
        if let actorID, actorID != current { reset(); throw WishwellError("Your iCloud account changed. Reopen Wishwell before sharing.") }
        actorID = current; return current
    }
    private func ensureActor(_ expected: String) async throws {
        try Task.checkCancellation()
        guard try await actor() == expected else { throw WishwellError("Your iCloud account changed. Please try again.") }
    }
    /// Records created by the debug-only live diagnostics never appear in normal social screens.
    nonisolated static func isDiagnosticFixture(_ id: String) -> Bool { id.hasPrefix("wishwell-check-") }
    private func fetch(_ id: String) async throws -> SocialRow? {
        guard !Self.isDiagnosticFixture(id) else { return nil }
        return try await database.record(id)
    }
    private func fetchRows(_ query: SocialQuery) async throws -> [SocialRow] {
        try await database.query(query).filter { !Self.isDiagnosticFixture($0.id) }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    nonisolated static func isPaused(_ row: SocialRow) -> Bool { (try? row.decode(PausedList.self))?.paused == true }
    private func profileValue(_ row: SocialRow) throws -> PublicProfile {
        guard row.kind == .profile else { throw WishwellError("This profile is unavailable.") }
        var profile: PublicProfile = try row.decode()
        profile.id = row.id; profile.ownerID = row.creator
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.count <= 80 else { throw WishwellError("This profile is unavailable.") }
        return profile
    }
    func profile(owner: String) async throws -> PublicProfile? {
        guard !hidden.contains(owner) else { return nil }
        if let cached = profileCache[owner], Date().timeIntervalSince(cached.fetched) < profileLifetime { return cached.profile }
        let rows = try await fetchRows(SocialQuery(kind: .profile, creator: owner))
        let ordered = rows.filter { $0.creator == owner }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        let profile = ordered.compactMap { try? profileValue($0) }.first
        if profile != nil { profileCache[owner] = (profile, Date()) }
        return profile
    }
    /// Looks up several people at once instead of one after another.
    private func profiles(_ owners: Set<String>) async -> [String: PublicProfile] {
        var found: [String: PublicProfile] = [:]
        await withTaskGroup(of: (String, PublicProfile?).self) { group in
            for owner in owners { group.addTask { @MainActor in (owner, try? await self.profile(owner: owner)) } }
            for await (owner, profile) in group { if let profile { found[owner] = profile } }
        }
        return found
    }
    func saveProfile(name: String, photo: Data?) async throws {
        let user = try await actor()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, (photo?.count ?? 0) < 400_000 else { throw WishwellError("Use a name up to 80 characters and a smaller profile photo.") }
        var row: SocialRow
        if let existing = try await profile(owner: user), let stored = try await fetch(existing.id) { row = stored }
        else { row = SocialRow(kind: .profile, payload: Data()) }
        guard row.creator.isEmpty || row.creator == user else { throw WishwellError("You can only edit your own profile.") }
        row.payload = try encode(PublicProfile(id: row.id, ownerID: user, name: trimmed, photo: photo))
        row.searchTokens = PublicProfile.tokens(for: trimmed)
        try await ensureActor(user)
        me = try profileValue(await database.save(row))
        profileCache[user] = (me, Date())
        await refreshAlerts()
    }
    func search(_ text: String) async throws -> [PublicProfile] {
        _ = try await actor()
        // Tokens are per-word prefixes, so query by the first word and require every typed word to match.
        let words = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).map { String($0.prefix(40)) }
        guard let first = words.first else { return [] }
        let rows = try await fetchRows(SocialQuery(kind: .profile, searchToken: first))
        var owners: Set<String> = []
        return rows.sorted { $0.createdAt < $1.createdAt }.compactMap { row in
            guard words.allSatisfy(row.searchTokens.contains), !hidden.contains(row.creator), let profile = try? profileValue(row), owners.insert(row.creator).inserted else { return nil }
            return profile
        }
    }
    func publicList(_ id: String) async throws -> PublicList? {
        guard let row = try await fetch(id) else { return nil }
        return try await list(from: row)
    }
    /// Checks a list record and its owner's profile, then reads the list from it.
    private func list(from row: SocialRow) async throws -> PublicList? {
        guard row.kind == .list, !Self.isPaused(row), !hidden.contains(row.creator),
              let parent = row.parent, let profileRow = try await profileRow(parent), profileRow.kind == .profile,
              profileRow.creator == row.creator else { return nil }
        guard var list: PublicList = try? row.decode(), list.profileID == parent,
              row.sourceID == list.sourceID.uuidString, Set(list.wishes.map(\.id)).count == list.wishes.count else { return nil }
        list.id = row.id; list.ownerID = row.creator
        for wish in list.wishes { guard (try? ShoppingOption.validated(wish.options)) != nil else { return nil } }
        listCache[list.id] = list
        return list
    }
    func lists(owner: String) async throws -> [PublicList] {
        guard !hidden.contains(owner) else { return [] }
        let rows = try await fetchRows(SocialQuery(kind: .list, creator: owner))
        var lists: [PublicList] = []
        try await withThrowingTaskGroup(of: PublicList?.self) { group in
            // The search already returned each list in full, so it isn't fetched a second time.
            for row in rows where row.creator == owner { group.addTask { @MainActor in try await self.list(from: row) } }
            for try await list in group { if let list { lists.append(list) } }
        }
        lists.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        ownerListCache[owner] = lists
        listsFetched[owner] = Date()
        return lists
    }
    /// The current person's public record for a personal list, shared or paused.
    func ownListRecord(source: UUID) async throws -> SocialRow? {
        let user = try await actor()
        return try await fetchRows(SocialQuery(kind: .list, creator: user, sourceID: source.uuidString))
            .filter { $0.creator == user && $0.kind == .list }.sorted { $0.createdAt < $1.createdAt }.first
    }
    func publish(_ snapshot: PublicList, existingID: String?) async throws -> String {
        let user = try await actor()
        guard let me, me.ownerID == user, snapshot.ownerID == user, snapshot.profileID == me.id else { throw WishwellError("Turn on your public account before sharing a wishlist.") }
        let payload = try encode(snapshot)
        guard payload.count < 750_000 else { throw WishwellError("This wishlist is too large to publish as one shared list.") }
        var row: SocialRow
        // A list made private earlier keeps its record, so sharing it again brings back its likes and comments.
        var reused: SocialRow?
        if existingID == nil {
            if let known = pausedRecords[snapshot.sourceID.uuidString], let row = try await fetch(known), row.creator == user, row.kind == .list { reused = row }
            else { reused = try await ownListRecord(source: snapshot.sourceID) }
        }
        if let reused { row = reused }
        else if let existingID {
            guard let existing = try await fetch(existingID) else { throw WishwellError("This wishlist was unpublished on another device. Refresh its sharing status before publishing it again.") }
            guard existing.creator == user, existing.kind == .list else { throw WishwellError("You can only publish your own wishlist.") }
            row = existing
        } else { row = SocialRow(id: snapshot.id, kind: .list, payload: payload) }
        row.parent = me.id; row.sourceID = snapshot.sourceID.uuidString
        var updated = snapshot; updated.id = row.id
        row.payload = try encode(updated)
        try await ensureActor(user)
        let saved = try await database.save(row).id
        pausedRecords[snapshot.sourceID.uuidString] = nil
        // Only a list that just became public needs new subscriptions.
        if existingID == nil { await refreshAlerts(published: saved) }
        return saved
    }
    /// Makes a shared list private without deleting it: its contents leave the public database,
    /// while likes and comments stay attached for the owner and return if the list is shared again.
    func pause(_ id: String, wishIDs: [UUID] = []) async throws {
        let user = try await actor()
        guard var row = try await fetch(id) else { return }
        guard row.kind == .list, row.creator == user else { throw WishwellError("You can only change your own wishlist.") }
        row.payload = try encode(PausedList(paused: true, wishIDs: wishIDs))
        try await ensureActor(user); _ = try await database.save(row)
        listCache[id] = nil; ownerListCache[user] = nil
        if let source = row.sourceID { pausedRecords[source] = id }
        await refreshAlerts(unpublished: id)
    }
    /// Keeps a private list's record in step with which wishes are still on it.
    func updatePaused(_ id: String, wishIDs: [UUID]) async throws {
        let user = try await actor()
        guard var row = try await fetch(id), row.kind == .list, row.creator == user, Self.isPaused(row) else { return }
        row.payload = try encode(PausedList(paused: true, wishIDs: wishIDs))
        try await ensureActor(user); _ = try await database.save(row)
    }
    func unpublish(_ id: String) async throws {
        let user = try await actor()
        guard let row = try await fetch(id) else { return }
        guard row.kind == .list, row.creator == user else { throw WishwellError("You can only unpublish your own wishlist.") }
        try await ensureActor(user); try await database.delete(row)
        listCache[id] = nil; ownerListCache[user] = nil
        await refreshAlerts(unpublished: id)
    }
    func following() async throws -> [PublicProfile] {
        let user = try await actor()
        let rows = try await fetchRows(SocialQuery(kind: .follow, creator: user))
        var targets: [SocialRow] = []
        await withTaskGroup(of: SocialRow?.self) { group in
            for row in rows where row.creator == user {
                guard let parent = row.parent else { continue }
                group.addTask { @MainActor in try? await self.fetch(parent) }
            }
            for await target in group { if let target { targets.append(target) } }
        }
        var result: [PublicProfile] = []; var seen: Set<String> = []
        for target in targets where target.kind == .profile && !hidden.contains(target.creator) && seen.insert(target.creator).inserted {
            result.append(try profileValue(target))
            profileRows[target.id] = (target, Date())
        }
        for row in rows where row.creator == user {
            guard let owner = targets.first(where: { $0.id == row.parent })?.creator else { continue }
            followedAt[owner] = min(followedAt[owner] ?? row.createdAt, row.createdAt)
        }
        followingOwners = seen
        let sorted = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        circleCache["following"] = sorted
        saveSnapshot()
        return sorted
    }
    func followers(of person: PublicProfile) async throws -> [PublicProfile] {
        guard let target = try await fetch(person.id), target.kind == .profile, target.creator == person.ownerID else { return [] }
        var result: [PublicProfile] = []; var seen: Set<String> = []
        for profileRow in try await fetchRows(SocialQuery(kind: .profile, creator: person.ownerID)) where profileRow.creator == person.ownerID {
            for row in try await fetchRows(SocialQuery(kind: .follow, parent: profileRow.id)) where row.parent == profileRow.id {
                if seen.insert(row.creator).inserted, let profile = try await profile(owner: row.creator) { result.append(profile) }
            }
        }
        return result
    }
    func follow(_ person: PublicProfile, enabled: Bool) async throws {
        let user = try await actor()
        guard user != person.ownerID, !hidden.contains(person.ownerID),
              let target = try await fetch(person.id), target.kind == .profile, target.creator == person.ownerID else { throw WishwellError("This person is unavailable.") }
        var existing: [SocialRow] = []
        for row in try await fetchRows(SocialQuery(kind: .follow, creator: user)) where row.creator == user {
            if let parent = row.parent, let target = try await fetch(parent), target.kind == .profile, target.creator == person.ownerID { existing.append(row) }
        }
        try await ensureActor(user)
        if enabled {
            guard me != nil else { throw WishwellError("Turn on your public account before following people.") }
            if existing.isEmpty {
                let saved = try await database.save(SocialRow(kind: .follow, parent: person.id, payload: encode(SocialAction())))
                await didSave?(saved.id, me?.id)
            }
            followingOwners?.insert(person.ownerID)
        } else {
            for row in existing { try await database.delete(row) }
            followingOwners?.remove(person.ownerID)
        }
    }
    /// A quicker check than `publicList` for claims: one read of the list record, without the owner's profile.
    private func sharedList(_ id: String) async throws -> PublicList? {
        guard let row = try await fetch(id), row.kind == .list, !Self.isPaused(row), !hidden.contains(row.creator),
              var list: PublicList = try? row.decode() else { return nil }
        list.id = row.id; list.ownerID = row.creator
        return list
    }
    private func claimRows(_ listID: String) async throws -> [(row: SocialRow, claim: GiftClaim)] {
        try await fetchRows(SocialQuery(kind: .claim, parent: listID)).compactMap { row in
            guard row.parent == listID, let claim = try? row.decode(GiftClaim.self) else { return nil }
            return (row, claim)
        }
    }
    /// Who is getting which wish on a list. The list's owner only learns that someone is, never who.
    func claims(listID: String) async throws -> [UUID: ClaimState] {
        let user = try await actor()
        let rows = try await claimRows(listID)
        let owner = try await fetch(listID)?.creator
        var states: [UUID: ClaimState] = [:]
        let active = rows.filter { $0.claim.active && !hidden.contains($0.row.creator) }
        let names = owner == user ? [:] : await profiles(Set(active.map(\.row.creator)))
        for (row, claim) in active.sorted(by: { $0.row.modifiedAt < $1.row.modifiedAt }) where states[claim.wishID] == nil {
            if row.creator == user { states[claim.wishID] = .mine }
            else if owner == user { states[claim.wishID] = .someone }
            else { states[claim.wishID] = .other(names[row.creator]?.name ?? "Someone") }
        }
        for (key, change) in recentClaims where key.hasPrefix(listID + "|") && Date().timeIntervalSince(change.at) < 180 {
            guard let wishID = UUID(uuidString: String(key.dropFirst(listID.count + 1))) else { continue }
            if change.on { states[wishID] = .mine } else if states[wishID] == .mine { states[wishID] = nil }
        }
        claimCache[listID] = states
        return states
    }
    /// Marks a wish as one this person is getting, or lets it go again.
    func setClaim(listID: String, wishID: UUID, on: Bool) async throws {
        let user = try await actor()
        async let current = sharedList(listID)
        async let existing = claimRows(listID)
        guard me != nil, let list = try await current, list.contains(wishID) else { throw WishwellError("This wish is no longer shared.") }
        guard list.ownerID != user else { throw WishwellError("You can’t get your own wish.") }
        let rows = try await existing.filter { $0.claim.wishID == wishID }
        if on, rows.contains(where: { $0.claim.active && $0.row.creator != user && !hidden.contains($0.row.creator) }) {
            throw WishwellError("Someone is already getting this.")
        }
        try await ensureActor(user)
        // One record per person and wish: undoing keeps it, marked inactive, so the owner can be told it's open again.
        // The search can lag behind recent changes, so this person's own records are read again by name,
        // which is always current. A record saved moments ago may not be in the search at all yet.
        var names = Set(rows.filter { $0.row.creator == user }.map(\.row.id))
        if let known = ownClaimRecords[listID + "|" + wishID.uuidString] { names.insert(known) }
        var own: [SocialRow] = []
        for name in names { if let row = try await fetch(name), row.creator == user { own.append(row) } }
        if let first = own.first { ownClaimRecords[listID + "|" + wishID.uuidString] = first.id }
        let active = own.contains { (try? $0.decode(GiftClaim.self))?.active == true }
        recentClaims[listID + "|" + wishID.uuidString] = (on, Date())
        // Nothing to change, so nothing is saved and nobody is notified twice.
        if on == active { claimCache[listID, default: [:]][wishID] = on ? .mine : nil; return }
        if on, var first = own.first {
            first.payload = try encode(GiftClaim(wishID: wishID, active: true))
            let saved = try await database.save(first)
            await didSave?(saved.id, nil)
        } else if !on {
            for var row in own where (try? row.decode(GiftClaim.self))?.active == true {
                row.payload = try encode(GiftClaim(wishID: wishID, active: false))
                let saved = try await database.save(row)
                await didSave?(saved.id, nil)
            }
        } else {
            let saved = try await database.save(SocialRow(kind: .claim, parent: listID, payload: encode(GiftClaim(wishID: wishID, active: true))))
            ownClaimRecords[listID + "|" + wishID.uuidString] = saved.id
            await didSave?(saved.id, nil)
        }
        var states = claimCache[listID] ?? [:]
        states[wishID] = on ? .mine : nil
        claimCache[listID] = states
    }
    func report(_ id: String, reason: String) async throws {
        let user = try await actor()
        guard let target = try await fetch(id), target.kind != .report else { throw WishwellError("This content is unavailable.") }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 1000 else { throw WishwellError("Please enter a reason up to 1,000 characters.") }
        let payload = try encode(["target": target.id, "kind": target.kind.rawValue, "reason": reason])
        try await ensureActor(user)
        _ = try await database.save(SocialRow(kind: .report, payload: payload))
    }
    func removeProfile() async throws {
        let user = try await actor()
        let profiles = try await fetchRows(SocialQuery(kind: .profile, creator: user))
        for kind in [SocialKind.claim, .follow] {
            let rows = try await fetchRows(SocialQuery(kind: kind, creator: user))
            for row in rows where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        }
        let lists = try await fetchRows(SocialQuery(kind: .list, creator: user))
        for row in lists where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        for row in profiles where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        me = nil
        circleCache = [:]; ownerListCache = [:]; followingOwners = nil
        try? FileManager.default.removeItem(at: Self.snapshotURL)
        await refreshAlerts()
    }
    /// Everything for the Notifications screen. The three kinds load side by side, and so does each list and person,
    /// because one lookup after another took several seconds.
    /// Someone's public profile by its record name, for opening a person from a notification.
    func person(_ id: String) async throws -> PublicProfile? {
        guard let row = try await profileRow(id), row.kind == .profile, !hidden.contains(row.creator) else { return nil }
        return try? profileValue(row)
    }
    /// A list owner's profile record, reused for a minute: every list lookup checks it.
    private func profileRow(_ id: String) async throws -> SocialRow? {
        if let cached = profileRows[id], Date().timeIntervalSince(cached.fetched) < profileLifetime { return cached.row }
        let row = try await fetch(id)
        if let row { profileRows[id] = (row, Date()) }
        return row
    }
    func activity() async throws -> [SocialActivity] {
        if let loadingActivity { return try await loadingActivity.value }
        let task = Task { @MainActor in try await self.loadActivity() }
        loadingActivity = task
        defer { loadingActivity = nil }
        return try await task.value
    }
    private func loadActivity() async throws -> [SocialActivity] {
        let user = try await actor()
        #if DEBUG
        let started = Date()
        defer { print("Wishwell notifications loaded in \(String(format: "%.1f", Date().timeIntervalSince(started)))s") }
        #endif
        async let follows = timed("added you") { try await self.addedYouActivity(user) }
        async let claims = timed("claims") { try await self.claimActivity(user) }
        async let wishes = timed("new wishes") { try await self.newWishActivity(user) }
        var seen: Set<String> = []
        let all = try await follows + claims + wishes
        let rows = Array(all.filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }.prefix(100))
        activityRows = rows
        let messages = Set(rows.map(\.message))
        deliveredRows.removeAll { messages.contains($0.message) }
        saveSnapshot()
        return rows
    }
    private func timed<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        #if DEBUG
        let started = Date()
        defer { print("Wishwell timing \(name): \(String(format: "%.1f", Date().timeIntervalSince(started)))s") }
        #endif
        return try await work()
    }
    /// "Soaed added you to their circle", once per person.
    private func addedYouActivity(_ user: String) async throws -> [SocialActivity] {
        let profiles = try await fetchRows(SocialQuery(kind: .profile, creator: user)).filter { $0.creator == user }
        var follows: [SocialRow] = []
        try await withThrowingTaskGroup(of: [SocialRow].self) { group in
            for own in profiles { group.addTask { @MainActor in try await self.fetchRows(SocialQuery(kind: .follow, parent: own.id)).filter { $0.parent == own.id } } }
            for try await rows in group { follows += rows }
        }
        var first: [String: SocialRow] = [:]
        for row in follows.sorted(by: { $0.createdAt < $1.createdAt }) where row.creator != user && first[row.creator] == nil { first[row.creator] = row }
        let people = await self.profiles(Set(first.keys))
        return first.compactMap { creator, row in
            people[creator].map { SocialActivity(id: row.id, actor: $0, message: "\($0.name) added you to their circle", date: row.createdAt, icon: "person.badge.plus") }
        }
    }
    /// "Someone might be getting your wish …" and "… is open again" on this person's own lists.
    private func claimActivity(_ user: String) async throws -> [SocialActivity] {
        let lists = try await fetchRows(SocialQuery(kind: .list, creator: user)).filter { $0.creator == user && !Self.isPaused($0) }
        var activity: [SocialActivity] = []
        try await withThrowingTaskGroup(of: [SocialActivity].self) { group in
            for own in lists {
                group.addTask { @MainActor in
                    async let shared = self.publicList(own.id)
                    async let claimed = self.claimRows(own.id)
                    guard let current = try await shared else { return [] }
                    return try await claimed.compactMap { row, claim in
                        guard row.creator != user, !self.hidden.contains(row.creator), let wish = current.wishes.first(where: { $0.id == claim.wishID }) else { return nil }
                        // Each change gets its own ID, so "getting" and "open again" both reach the owner.
                        let id = "claim-\(row.id)-\(claim.active ? "on" : "off")-\(Int(row.modifiedAt.timeIntervalSince1970))"
                        return SocialActivity(id: id, actor: nil,
                            message: claim.active ? "Someone might be getting your wish \(wish.title)" : "\(wish.title) is open again",
                            list: current, wishID: wish.id, date: row.modifiedAt, icon: claim.active ? "gift.fill" : "gift")
                    }
                }
            }
            for try await rows in group { activity += rows }
        }
        return activity
    }
    /// "Soaed added …" for wishes added by people in this person's circle since they were added.
    /// Built from the circle refresh's own results, so it adds no trips to iCloud.
    private func newWishActivity(_ user: String) async throws -> [SocialActivity] {
        let people = circleCache["following"] ?? []
        let fresh = !people.isEmpty && people.allSatisfy { person in listsFetched[person.ownerID].map { Date().timeIntervalSince($0) < 120 } ?? false }
        if !fresh { await warmCircle() }
        return (circleCache["following"] ?? []).flatMap { person -> [SocialActivity] in
            guard let since = followedAt[person.ownerID], !hidden.contains(person.ownerID) else { return [] }
            return (ownerListCache[person.ownerID] ?? []).flatMap { list in
                list.wishes.filter { $0.createdAt >= since }.map { wish in
                    SocialActivity(id: "wish-\(list.id)-\(wish.id)", actor: person, message: "\(person.name) added \(wish.title)", list: list, date: wish.createdAt, icon: "sparkles")
                }
            }
        }
    }
}
