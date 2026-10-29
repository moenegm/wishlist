import XCTest

final class WishwellUITests: XCTestCase {
    @MainActor func testOfflineWishPersistsWithThreeOptionsAndFulfillment() throws {
        try createWish(local: true)
    }

    @MainActor func testSocialPreviewLikeAndComment() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--social-preview"]; app.launch()
        let circle = app.buttons["Circle"]
        if circle.waitForExistence(timeout: 10) { circle.tap() }
        else { app.staticTexts["Circle"].firstMatch.tap() }
        let shared = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A cozy corner")).firstMatch
        guard shared.waitForExistence(timeout: 10) else {
            let failure = XCTAttachment(screenshot: app.screenshot()); failure.lifetime = .keepAlways; add(failure)
            XCTFail("Shared feed missing: \(app.debugDescription)"); return
        }; shared.tap()
        let like = app.buttons["social.like"]
        if !like.isHittable { app.swipeUp() }
        XCTAssertTrue(like.waitForExistence(timeout: 5)); like.tap()
        XCTAssertEqual(like.label, "1 like")
        let field = app.textFields["social.comment.text"]
        let editor = field.exists ? field : app.textViews["social.comment.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("A lovely place to read")
        if app.buttons["social.keyboard.done"].exists { app.buttons["social.keyboard.done"].tap() }
        app.buttons["social.comment.post"].tap()
        XCTAssertTrue(app.staticTexts["A lovely place to read"].waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Social preview like and comment"; proof.lifetime = .keepAlways; add(proof)
    }

    @MainActor func testPrivateListPublishAndUnpublishInSocialPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--social-preview"]; app.launch()
        let add = app.buttons["list.add"]; XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        let title = app.textFields["list.title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        let name = "Sharing check \(UUID().uuidString.prefix(5))"; title.typeText(name); app.buttons["list.save"].tap()
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5)); list.tap()
        app.buttons["list.menu"].tap(); app.buttons["Wishlist sharing"].tap()
        let publish = app.buttons["social.list.publish"]; XCTAssertTrue(publish.waitForExistence(timeout: 5)); publish.tap()
        app.buttons["social.list.confirmPublish"].firstMatch.tap()
        let makePrivate = app.buttons["social.list.private"]; XCTAssertTrue(makePrivate.waitForExistence(timeout: 5)); makePrivate.tap()
        app.buttons["social.list.confirmPrivate"].firstMatch.tap()
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private wishlist"].exists)
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
