import XCTest
import SwiftData
@testable import WishwellStorage

final class StorageTests: XCTestCase {
    @MainActor private func makeContainer() throws -> ModelContainer {
        let schema = Schema([WishList.self, Wish.self, LocalProfile.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    func testOptionValidationAndSafeLinks() throws {
        XCTAssertThrowsError(try ShoppingOption.validated(Array(repeating: ShoppingOption(location: "shop"), count: 4)))
        for price in ["-1", "1.234", "12oops", "1e3", "1,99"] {
            XCTAssertThrowsError(try ShoppingOption.validated([ShoppingOption(price: price)]), price)
        }
        let valid = try ShoppingOption.validated([ShoppingOption(location: " shop ", price: "0.00"), ShoppingOption()])
        XCTAssertEqual(valid.count, 1); XCTAssertEqual(valid.first?.location, "shop")
        XCTAssertNil(ShoppingOption(location: "javascript:alert(1)").link)
        XCTAssertNil(ShoppingOption(location: "file:///private/data").link)
        XCTAssertEqual(ShoppingOption(location: "https://example.com/chair").link?.host, "example.com")
    }

    @MainActor func testArchiveRoundTripAndDuplicateImport() throws {
        let source = try makeContainer(); let context = source.mainContext
        let list = WishList(title: "Home", category: "Furniture"); context.insert(list)
        let wish = try Wish(title: "Chair", options: [ShoppingOption(location: "Store", price: "99.50")], list: list)
        wish.fulfilled = true; context.insert(wish); try context.save()
        let encoded = try JSONEncoder().encode(WishwellArchive(lists: [list]))
        let archive = try JSONDecoder().decode(WishwellArchive.self, from: encoded)
        let target = try makeContainer(); let destination = target.mainContext
        XCTAssertEqual(try archive.restore(into: destination), 1)
        XCTAssertEqual(try archive.restore(into: destination), 0)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Wish>()).first)
        XCTAssertTrue(restored.fulfilled); XCTAssertEqual(restored.options.first?.price, "99.50")
        XCTAssertEqual(restored.list?.category, "Furniture")
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WishList>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Wish>()), 1)
    }

    @MainActor func testInvalidArchiveMakesNoPartialChanges() throws {
        let container = try makeContainer(); let context = container.mainContext
        let list = WishList(title: "Untouched"); context.insert(list); try context.save()
        var archive = WishwellArchive(lists: [])
        archive.lists = [
            .init(id: UUID(), title: "Valid first", category: "", wishes: []),
            .init(id: UUID(), title: "Invalid second", category: "", wishes: [
                .init(id: UUID(), title: "Chair", fulfilled: false, options: [ShoppingOption(price: "-20")])
            ])
        ]
        XCTAssertThrowsError(try archive.restore(into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WishList>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Wish>()), 0)
        archive.version = 99
        XCTAssertThrowsError(try archive.restore(into: context))
    }

    @MainActor func testMoveWishKeepsInverseRelationshipsAndFulfilledSorting() throws {
        let container = try makeContainer(); let context = container.mainContext
        let first = WishList(title: "Home"), second = WishList(title: "Office")
        context.insert(first); context.insert(second)
        let completed = try Wish(title: "Desk", options: [], list: first); completed.fulfilled = true
        let active = try Wish(title: "Chair", options: [], list: first)
        context.insert(completed); context.insert(active); try context.save()
        XCTAssertEqual(first.sortedWishes.map(\.title), ["Chair", "Desk"])
        active.list = second; try context.save()
        XCTAssertEqual(first.wishes?.count, 1); XCTAssertEqual(second.wishes?.first?.id, active.id)
        context.delete(completed); try context.save()
        XCTAssertTrue(first.wishes?.isEmpty == true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Wish>()), 1)
    }
}
