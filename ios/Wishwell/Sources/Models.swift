import Foundation

struct Person: Codable, Identifiable, Hashable {
    let id: Int
    var firstName: String
    var lastName: String
    var avatarUrl: String?
    var following: Bool
    var followersCount: Int
    var followingCount: Int
    var email: String?
    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ").isEmpty ? "Wishwell member" : [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var initials: String { String(firstName.prefix(1) + lastName.prefix(1)).uppercased() }
}

struct PurchaseOption: Codable, Hashable {
    var location: String?
    var price: String?
    init(location: String? = nil, price: String? = nil) { self.location = location; self.price = price }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        if let text = try? c.decodeIfPresent(String.self, forKey: .price) { price = text }
        else if let amount = try? c.decodeIfPresent(Decimal.self, forKey: .price) { price = NSDecimalNumber(decimal: amount).stringValue }
    }
    var formattedPrice: String? {
        guard let price, let amount = Decimal(string: price) else { return nil }
        return amount.formatted(.currency(code: "USD"))
    }
    var link: URL? {
        guard let location, let url = URL(string: location), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

struct WishRecord: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var userId: Int
    var wlistId: Int
    var fulfilled: Bool
    var purchaseOptions: [PurchaseOption]
    var likesCount: Int
    var liked: Bool
    var commentsCount: Int
}

struct WishlistRecord: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var userId: Int
    var category: String
    var isPublic: Bool
    var wishesCount: Int
    var owner: Person
    var likesCount: Int
    var liked: Bool
    var commentsCount: Int
    var wishes: [WishRecord]?
}

struct CommentRecord: Codable, Identifiable {
    let id: Int
    let body: String
    let user: Person
    let createdAt: String
}
struct ActivityRecord: Codable, Identifiable {
    let id: Int
    let message: String
    let eventType: String
    let actorId: Int
    let wlistId: Int?
    var read: Bool
    let createdAt: String
    var icon: String { eventType == "followed" ? "person.badge.plus" : eventType == "added_wish" ? "sparkles" : eventType.hasPrefix("liked") ? "heart.fill" : "bubble.left" }
}
struct ActivityResponse: Codable { let unreadCount: Int; let notifications: [ActivityRecord] }
struct ProfileResponse: Codable { let user: Person; let wlists: [WishlistRecord] }
struct LoginResponse: Codable { let token: String; let user: Person }
struct ServerError: Codable { let error: String? }

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
