import Foundation
import SwiftData

@Model final class WishList {
    var id: UUID = UUID()
    var title: String = ""
    var category: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var legacyID: Int?
    var publicRecordName: String?
    @Relationship(deleteRule: .cascade, inverse: \Wish.list) var wishes: [Wish]?
    init(title: String, category: String = "") { self.title = title; self.category = category; wishes = [] }
    var sortedWishes: [Wish] {
        (wishes ?? []).sorted {
            if $0.fulfilled != $1.fulfilled { return !$0.fulfilled }
            return $0.createdAt > $1.createdAt
        }
    }
}

@Model final class Wish {
    var id: UUID = UUID()
    var title: String = ""
    var fulfilled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var optionsData: Data = Data()
    var legacyID: Int?
    var list: WishList?
    init(title: String, options: [ShoppingOption], list: WishList) throws {
        self.title = title; self.optionsData = try JSONEncoder().encode(options); self.list = list
    }
    var options: [ShoppingOption] { (try? JSONDecoder().decode([ShoppingOption].self, from: optionsData)) ?? [] }
}

struct ShoppingOption: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var location: String = ""
    var price: String = ""
    var currency: String = "USD"
    var link: URL? {
        guard let url = URL(string: location), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    var formattedPrice: String? {
        guard let value = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")), !price.isEmpty else { return nil }
        return value.formatted(.currency(code: currency))
    }
    static func validated(_ options: [Self]) throws -> [Self] {
        guard options.count <= 3 else { throw WishwellError("A wish can have up to three shopping options.") }
        return try options.compactMap { option in
            var row = option
            row.location = row.location.trimmingCharacters(in: .whitespacesAndNewlines)
            row.price = row.price.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.location.isEmpty && row.price.isEmpty { return nil }
            if !row.price.isEmpty {
                guard let value = Decimal(string: row.price, locale: Locale(identifier: "en_US_POSIX")), value >= 0,
                      row.price.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else {
                    throw WishwellError("Enter a nonnegative price with up to two decimal places, such as 49.99.")
                }
            }
            return row
        }
    }
}

@Model final class LocalProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var photo: Data?
    var createdAt: Date = Date()
    init(displayName: String = "") { self.displayName = displayName }
}

struct WishwellError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct WishwellArchive: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var lists: [ListEntry]
    struct ListEntry: Codable { var id: UUID; var title: String; var category: String; var wishes: [WishEntry] }
    struct WishEntry: Codable { var id: UUID; var title: String; var fulfilled: Bool; var options: [ShoppingOption] }
    @MainActor init(lists: [WishList]) {
        self.lists = lists.map { list in
            ListEntry(id: list.id, title: list.title, category: list.category, wishes: list.sortedWishes.map {
                WishEntry(id: $0.id, title: $0.title, fulfilled: $0.fulfilled, options: $0.options)
            })
        }
    }
    @MainActor func restore(into context: ModelContext) throws -> Int {
        guard version == 1 else { throw WishwellError("This backup uses an unsupported version.") }
        let existing = try context.fetch(FetchDescriptor<WishList>())
        let existingWishes = try context.fetch(FetchDescriptor<Wish>())
        var listIDs = Set(existing.map(\.id))
        var wishIDs = Set(existingWishes.map(\.id))
        var count = 0
        for list in lists {
            guard !list.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WishwellError("A list in this backup has no title.") }
            for wish in list.wishes {
                guard !wish.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WishwellError("A wish in this backup has no title.") }
                _ = try ShoppingOption.validated(wish.options)
            }
        }
        for entry in lists where !listIDs.contains(entry.id) {
            let list = WishList(title: entry.title, category: entry.category); list.id = entry.id
            context.insert(list); listIDs.insert(entry.id)
            for row in entry.wishes where !wishIDs.contains(row.id) {
                let wish = try Wish(title: row.title, options: ShoppingOption.validated(row.options), list: list)
                wish.id = row.id; wish.fulfilled = row.fulfilled
                context.insert(wish); wishIDs.insert(row.id)
            }
            count += 1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return count
    }
}
