import XCTest

final class WishwellUITests: XCTestCase {
    @MainActor func testOfflineWishPersistsWithThreeOptionsAndFulfillment() throws {
        try createWish(local: true)
    }

    @MainActor func testCreateCloudSyncFixture() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Cloud sync requires signed devices with iCloud accounts.")
        #else
        try createWish(local: false)
        #endif
    }

    @MainActor func testReadCloudSyncFixture() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Cloud sync requires signed devices with iCloud accounts.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sync check 2026-10-29")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 120)); list.tap()
        let wish = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Cloud chair 2026-10-29")).firstMatch
        XCTAssertTrue(wish.waitForExistence(timeout: 20)); wish.tap()
        XCTAssertTrue(app.buttons["wish.fulfilled"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["wish.fulfilled"].label, "Fulfilled")
        XCTAssertTrue(app.staticTexts["Store 3"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Cloud wish received on second device"; proof.lifetime = .keepAlways; add(proof)
        #endif
    }

    @MainActor private func createWish(local: Bool) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = local ? ["--local-preview"] : []
        app.launch()
        let listTitle = local ? "Home \(UUID().uuidString.prefix(6))" : "Sync check 2026-10-29"
        let wishTitle = local ? "Reading chair \(UUID().uuidString.prefix(6))" : "Cloud chair 2026-10-29"
        let addList = app.buttons["list.add"]
        XCTAssertTrue(addList.waitForExistence(timeout: 20)); addList.tap()
        let listField = app.textFields["list.title"]
        XCTAssertTrue(listField.waitForExistence(timeout: 5)); listField.tap(); listField.typeText(listTitle)
        app.buttons["list.save"].tap()
        let list = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", listTitle)).firstMatch
        let link = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", listTitle)).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        if list.exists { list.tap() } else { link.tap() }
        let addWish = app.buttons["wish.add"]
        XCTAssertTrue(addWish.waitForExistence(timeout: 5)); addWish.tap()
        let title = app.textFields["wish.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(wishTitle)
        for index in 0..<3 {
            if index > 0 {
                if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
                app.buttons["option.add"].tap()
            }
            let location = app.textFields["option.location.\(index)"]
            XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap(); location.typeText("Store \(index + 1)")
            let price = app.textFields["option.price.\(index)"]
            price.tap(); price.typeText("\(80 + index).99")
        }
        XCTAssertFalse(app.buttons["option.add"].exists)
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        app.buttons["wish.save"].tap()
        let wish = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", wishTitle)).firstMatch
        XCTAssertTrue(wish.waitForExistence(timeout: 5)); wish.tap()
        let fulfilled = app.buttons["wish.fulfilled"]
        XCTAssertTrue(fulfilled.waitForExistence(timeout: 5)); fulfilled.tap()
        XCTAssertEqual(fulfilled.label, "Fulfilled")
        app.terminate(); app.launch()
        let savedList = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", listTitle)).firstMatch
        XCTAssertTrue(savedList.waitForExistence(timeout: 10)); savedList.tap()
        let savedWish = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", wishTitle)).firstMatch
        XCTAssertTrue(savedWish.waitForExistence(timeout: 5)); savedWish.tap()
        XCTAssertTrue(app.buttons["wish.fulfilled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["wish.fulfilled"].label, "Fulfilled")
        XCTAssertTrue(app.staticTexts["Store 3"].exists)
        XCTAssertFalse(app.buttons["Sign in"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Fulfilled wish with three options"; image.lifetime = .keepAlways; add(image)
    }
}
