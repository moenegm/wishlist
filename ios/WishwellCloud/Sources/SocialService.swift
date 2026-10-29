import Foundation
import Observation

@MainActor @Observable final class SocialStore {
    let database: any SocialDatabase
    var enabled: Bool
    var isDemo = false
    private(set) var actorID: String?
    private(set) var me: PublicProfile?
    var hidden: Set<String> = []
    var error: String?
    var busy = false
    var publicationMessage: String?
    var activityRows: [SocialActivity] = []
    var refreshRevision = 0
    private var epoch = UUID()
    init(database: (any SocialDatabase)? = nil, enabled: Bool = Bundle.main.object(forInfoDictionaryKey: "WishwellSocialEnabled") as? Bool ?? false) {
        self.database = database ?? CloudSocialDatabase(); self.enabled = enabled
    }
    func connect() async throws {
        guard enabled else { throw WishwellError("Social sharing is awaiting CloudKit permission setup. Your private library is ready to use.") }
        let attempt = epoch
        let user = try await database.userID()
        guard attempt == epoch else { throw CancellationError() }
        actorID = user
        me = try await profile(owner: user)
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
    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private func profileValue(_ row: SocialRow) throws -> PublicProfile {
        guard row.kind == .profile else { throw WishwellError("This profile is unavailable.") }
        var profile: PublicProfile = try row.decode()
        profile.id = row.id; profile.ownerID = row.creator
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.count <= 80 else { throw WishwellError("This profile is unavailable.") }
        return profile
    }
    func profile(owner: String) async throws -> PublicProfile? {
        guard !hidden.contains(owner) else { return nil }
        let rows = try await database.query(SocialQuery(kind: .profile, creator: owner))
        let ordered = rows.filter { $0.creator == owner }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        return ordered.compactMap { try? profileValue($0) }.first
    }
    func saveProfile(name: String, photo: Data?) async throws {
        let user = try await actor()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, (photo?.count ?? 0) < 400_000 else { throw WishwellError("Use a name up to 80 characters and a smaller profile photo.") }
        var row: SocialRow
        if let existing = try await profile(owner: user), let stored = try await database.record(existing.id) { row = stored }
        else { row = SocialRow(kind: .profile, payload: Data()) }
        guard row.creator.isEmpty || row.creator == user else { throw WishwellError("You can only edit your own profile.") }
        row.payload = try encode(PublicProfile(id: row.id, ownerID: user, name: trimmed, photo: photo))
        row.searchTokens = PublicProfile.tokens(for: trimmed)
        try await ensureActor(user)
        me = try profileValue(await database.save(row))
    }
    func search(_ text: String) async throws -> [PublicProfile] {
        _ = try await actor()
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard !token.isEmpty else { return [] }
        let rows = try await database.query(SocialQuery(kind: .profile, searchToken: token))
        var owners: Set<String> = []
        return rows.sorted { $0.createdAt < $1.createdAt }.compactMap { row in
            guard !hidden.contains(row.creator), let profile = try? profileValue(row), owners.insert(row.creator).inserted else { return nil }
            return profile
        }
    }
    func publicList(_ id: String) async throws -> PublicList? {
        guard let row = try await database.record(id), row.kind == .list, !hidden.contains(row.creator),
              let parent = row.parent, let profileRow = try await database.record(parent), profileRow.kind == .profile,
              profileRow.creator == row.creator else { return nil }
        guard var list: PublicList = try? row.decode(), list.profileID == parent,
              row.sourceID == list.sourceID.uuidString, Set(list.wishes.map(\.id)).count == list.wishes.count else { return nil }
        list.id = row.id; list.ownerID = row.creator
        for wish in list.wishes { guard (try? ShoppingOption.validated(wish.options)) != nil else { return nil } }
        return list
    }
    func lists(owner: String) async throws -> [PublicList] {
        guard !hidden.contains(owner) else { return [] }
        let rows = try await database.query(SocialQuery(kind: .list, creator: owner))
        var lists: [PublicList] = []
        for row in rows where row.creator == owner { if let list = try await publicList(row.id) { lists.append(list) } }
        return lists.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func publish(_ snapshot: PublicList, existingID: String?) async throws -> String {
        let user = try await actor()
        guard let me, me.ownerID == user, snapshot.ownerID == user, snapshot.profileID == me.id else { throw WishwellError("Publish your own profile before sharing a wishlist.") }
        let payload = try encode(snapshot)
        guard payload.count < 750_000 else { throw WishwellError("This wishlist is too large to publish as one shared list.") }
        var row: SocialRow
        if let existingID {
            guard let existing = try await database.record(existingID) else { throw WishwellError("This wishlist was unpublished on another device. Refresh its sharing status before publishing it again.") }
            guard existing.creator == user, existing.kind == .list else { throw WishwellError("You can only publish your own wishlist.") }
            row = existing
        } else { row = SocialRow(id: snapshot.id, kind: .list, payload: payload) }
        row.parent = me.id; row.sourceID = snapshot.sourceID.uuidString
        var updated = snapshot; updated.id = row.id
        row.payload = try encode(updated)
        try await ensureActor(user)
        return try await database.save(row).id
    }
    func unpublish(_ id: String) async throws {
        let user = try await actor()
        guard let row = try await database.record(id) else { return }
        guard row.kind == .list, row.creator == user else { throw WishwellError("You can only unpublish your own wishlist.") }
        try await ensureActor(user); try await database.delete(row)
    }
    func following() async throws -> [PublicProfile] {
        let user = try await actor()
        let rows = try await database.query(SocialQuery(kind: .follow, creator: user))
        var result: [PublicProfile] = []; var seen: Set<String> = []
        for row in rows where row.creator == user {
            if let parent = row.parent, let target = try await database.record(parent), target.kind == .profile,
               !hidden.contains(target.creator), seen.insert(target.creator).inserted { result.append(try profileValue(target)) }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func followers(of person: PublicProfile) async throws -> [PublicProfile] {
        guard let target = try await database.record(person.id), target.kind == .profile, target.creator == person.ownerID else { return [] }
        var result: [PublicProfile] = []; var seen: Set<String> = []
        for profileRow in try await database.query(SocialQuery(kind: .profile, creator: person.ownerID)) where profileRow.creator == person.ownerID {
            for row in try await database.query(SocialQuery(kind: .follow, parent: profileRow.id)) where row.parent == profileRow.id {
                if seen.insert(row.creator).inserted, let profile = try await profile(owner: row.creator) { result.append(profile) }
            }
        }
        return result
    }
    func follow(_ person: PublicProfile, enabled: Bool) async throws {
        let user = try await actor()
        guard user != person.ownerID, !hidden.contains(person.ownerID),
              let target = try await database.record(person.id), target.kind == .profile, target.creator == person.ownerID else { throw WishwellError("This person is unavailable.") }
        var existing: [SocialRow] = []
        for row in try await database.query(SocialQuery(kind: .follow, creator: user)) where row.creator == user {
            if let parent = row.parent, let target = try await database.record(parent), target.kind == .profile, target.creator == person.ownerID { existing.append(row) }
        }
        try await ensureActor(user)
        if enabled {
            guard me != nil else { throw WishwellError("Publish your profile before following people.") }
            if existing.isEmpty { _ = try await database.save(SocialRow(kind: .follow, parent: person.id, payload: encode(SocialAction()))) }
        } else { for row in existing { try await database.delete(row) } }
    }
    func thread(listID: String, wishID: UUID?) async throws -> SocialThread {
        let user = try await actor()
        guard let list = try await publicList(listID), list.contains(wishID) else { throw WishwellError("This shared wish is no longer available.") }
        let likes = try await database.query(SocialQuery(kind: .like, parent: listID))
        let comments = try await database.query(SocialQuery(kind: .comment, parent: listID))
        let validLikes = likes.filter {
            guard $0.parent == listID, !hidden.contains($0.creator) else { return false }
            guard let action = try? $0.decode(SocialAction.self) else { return false }
            return action.wishID == wishID
        }
        var thread = SocialThread(liked: validLikes.contains { $0.creator == user }, likeCount: Set(validLikes.map(\.creator)).count)
        for row in comments where row.parent == listID && !hidden.contains(row.creator) {
            guard let action: SocialAction = try? row.decode() else { continue }
            if action.wishID == wishID, !action.text.isEmpty, action.text.count <= 500, let author = try await profile(owner: row.creator) {
                thread.comments.append(SocialComment(id: row.id, author: author, text: action.text, createdAt: row.createdAt))
            }
        }
        thread.comments.sort { $0.createdAt < $1.createdAt }
        // Revalidate the parent after queries so an unpublished list isn't displayed from stale results.
        guard try await publicList(listID) != nil else { throw WishwellError("This wishlist is no longer public.") }
        return thread
    }
    func setLike(listID: String, wishID: UUID?, liked: Bool) async throws {
        let user = try await actor()
        guard me != nil, let list = try await publicList(listID), list.contains(wishID) else { throw WishwellError("Publish a profile and open an available public wish first.") }
        let rows = try await database.query(SocialQuery(kind: .like, creator: user, parent: listID))
        let own = rows.filter {
            guard $0.creator == user, $0.parent == listID else { return false }
            guard let action = try? $0.decode(SocialAction.self) else { return false }
            return action.wishID == wishID
        }
        try await ensureActor(user)
        if liked {
            if own.isEmpty { _ = try await database.save(SocialRow(kind: .like, parent: listID, payload: encode(SocialAction(wishID: wishID)))) }
        } else { for row in own { try await database.delete(row) } }
    }
    func comment(listID: String, wishID: UUID?, text: String) async throws {
        let user = try await actor(); let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw WishwellError("Comments must have 1–500 characters.") }
        guard me != nil, let list = try await publicList(listID), list.contains(wishID) else { throw WishwellError("This shared wish is no longer available.") }
        try await ensureActor(user)
        _ = try await database.save(SocialRow(kind: .comment, parent: listID, payload: encode(SocialAction(wishID: wishID, text: text))))
    }
    func deleteComment(_ id: String) async throws {
        let user = try await actor()
        guard let row = try await database.record(id) else { return }
        guard row.kind == .comment, row.creator == user else { throw WishwellError("You can only delete your own comments.") }
        try await ensureActor(user); try await database.delete(row)
    }
    func report(_ id: String, reason: String) async throws {
        let user = try await actor()
        guard let target = try await database.record(id), target.kind != .report else { throw WishwellError("This content is unavailable.") }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 1000 else { throw WishwellError("Please enter a reason up to 1,000 characters.") }
        let payload = try encode(["target": target.id, "kind": target.kind.rawValue, "reason": reason])
        try await ensureActor(user)
        _ = try await database.save(SocialRow(kind: .report, payload: payload))
    }
    func removeProfile() async throws {
        let user = try await actor()
        let profiles = try await database.query(SocialQuery(kind: .profile, creator: user))
        for kind in [SocialKind.like, .comment, .follow] {
            let rows = try await database.query(SocialQuery(kind: kind, creator: user))
            for row in rows where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        }
        let lists = try await database.query(SocialQuery(kind: .list, creator: user))
        for row in lists where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        for row in profiles where row.creator == user { try await ensureActor(user); try await database.delete(row) }
        me = nil
    }
    func activity() async throws -> [SocialActivity] {
        let user = try await actor()
        var activity: [SocialActivity] = []
        var seen: Set<String> = []
        let profiles = try await database.query(SocialQuery(kind: .profile, creator: user))
        for own in profiles where own.creator == user {
            for row in try await database.query(SocialQuery(kind: .follow, parent: own.id)) where row.parent == own.id && row.creator != user {
                if seen.insert("follow-\(row.creator)").inserted, let author = try await profile(owner: row.creator) {
                    activity.append(SocialActivity(id: row.id, actor: author, message: "\(author.name) followed you", date: row.createdAt, icon: "person.badge.plus"))
                }
            }
        }
        for own in try await database.query(SocialQuery(kind: .list, creator: user)) where own.creator == user {
            for kind in [SocialKind.like, .comment] {
                let rows = try await database.query(SocialQuery(kind: kind, parent: own.id))
                guard let current = try await publicList(own.id) else { continue }
                for row in rows where row.parent == own.id && row.creator != user && !hidden.contains(row.creator) {
                    guard let action: SocialAction = try? row.decode() else { continue }
                    guard current.contains(action.wishID), let author = try await profile(owner: row.creator) else { continue }
                    let target = action.wishID.flatMap { id in current.wishes.first { $0.id == id }?.title } ?? current.title
                    let key = kind == .like ? "like-\(row.creator)-\(own.id)-\(action.wishID?.uuidString ?? "list")" : row.id
                    guard seen.insert(key).inserted else { continue }
                    activity.append(SocialActivity(id: row.id, actor: author, message: "\(author.name) \(kind == .like ? "liked" : "commented on") \(target)", list: current, date: row.createdAt, icon: kind == .like ? "heart.fill" : "bubble.left"))
                }
            }
        }
        let follows = try await database.query(SocialQuery(kind: .follow, creator: user))
        for follow in follows where follow.creator == user {
            guard let parent = follow.parent, let row = try await database.record(parent), row.kind == .profile,
                  !hidden.contains(row.creator), let author = try await profile(owner: row.creator) else { continue }
            for list in try await lists(owner: row.creator) {
                for wish in list.wishes where wish.createdAt >= follow.createdAt {
                    let key = "wish-\(list.id)-\(wish.id)"
                    guard seen.insert(key).inserted else { continue }
                    activity.append(SocialActivity(id: key, actor: author, message: "\(author.name) added \(wish.title)", list: list, date: wish.createdAt, icon: "sparkles"))
                }
            }
        }
        return Array(activity.sorted { $0.date > $1.date }.prefix(100))
    }
}
