import Foundation
import SwiftData

enum SocialKind: String, Codable, CaseIterable {
    case profile = "WWProfile", list = "WWList", follow = "WWFollow", like = "WWLike", comment = "WWComment", report = "WWReport"
}

struct SocialRow: Identifiable {
    var id: String = UUID().uuidString
    var kind: SocialKind
    var creator: String = ""
    var parent: String?
    var sourceID: String?
    var searchTokens: [String] = []
    var payload: Data
    var createdAt: Date = Date()
    var systemFields: Data?
    func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T { try JSONDecoder().decode(type, from: payload) }
}

struct SocialQuery: Equatable {
    var kind: SocialKind
    var creator: String?
    var parent: String?
    var sourceID: String?
    var searchToken: String?
}

@MainActor protocol SocialDatabase {
    func userID() async throws -> String
    func record(_ id: String) async throws -> SocialRow?
    func query(_ query: SocialQuery) async throws -> [SocialRow]
    func save(_ row: SocialRow) async throws -> SocialRow
    func delete(_ row: SocialRow) async throws
}

struct PublicProfile: Codable, Identifiable, Hashable {
    var id: String
    var ownerID: String
    var name: String
    var photo: Data?
    static func tokens(for name: String) -> [String] {
        let words = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return Array(Set(words.flatMap { word in (1...max(1, min(40, word.count))).map { String(word.prefix($0)) } })).sorted()
    }
}

struct PublicWish: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var fulfilled: Bool
    var options: [ShoppingOption]
    var createdAt: Date
}

struct PublicList: Codable, Identifiable, Hashable {
    var id: String
    var ownerID: String
    var profileID: String
    var sourceID: UUID
    var title: String
    var category: String
    var wishes: [PublicWish]
    @MainActor init(list: WishList, profile: PublicProfile, id: String = UUID().uuidString) {
        self.id = id; ownerID = profile.ownerID; profileID = profile.id; sourceID = list.id
        title = list.title; category = list.category
        wishes = list.sortedWishes.map { PublicWish(id: $0.id, title: $0.title, fulfilled: $0.fulfilled, options: $0.options, createdAt: $0.createdAt) }
    }
    func contains(_ wishID: UUID?) -> Bool { wishID == nil || wishes.contains { $0.id == wishID } }
}

struct SocialAction: Codable {
    var wishID: UUID?
    var text: String = ""
}
struct SocialComment: Identifiable {
    var id: String
    var author: PublicProfile
    var text: String
    var createdAt: Date
}
struct SocialThread {
    var liked = false
    var likeCount = 0
    var comments: [SocialComment] = []
}
struct SocialActivity: Identifiable {
    var id: String
    var actor: PublicProfile
    var message: String
    var list: PublicList?
    var date: Date
    var icon: String
}

@Model final class SocialReadState {
    var id: String = ""
    var readAt: Date = Date()
    init(id: String) { self.id = id }
}
@Model final class HiddenPerson {
    var ownerID: String = ""
    var createdAt: Date = Date()
    init(ownerID: String) { self.ownerID = ownerID }
}
