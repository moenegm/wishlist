import XCTest

final class WishwellUITests: XCTestCase {
    @MainActor func testSharedWishAndFulfillment() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(withDescription: "Optional password saving") { alert in
            if alert.buttons["Not Now"].exists { alert.buttons["Not Now"].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launchEnvironment["WISHWELL_API_URL"] = "http://localhost:3000"
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        email.tap(); email.typeText("ios-qa@example.test")
        let password = app.secureTextFields["Password"]
        password.tap(); password.typeText("LocalPreview123!")
        app.buttons["Sign in"].tap()
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 5) {
            for _ in 0..<3 {
                guard notNow.exists else { break }
                notNow.tap()
                if notNow.waitForNonExistence(timeout: 2) { break }
            }
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 5))
        }
        let list = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Native QA")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        list.tap()
        let addWish = app.buttons["Add a wish"]
        XCTAssertTrue(addWish.waitForExistence(timeout: 15)); addWish.tap()
        let title = app.textFields["wish.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10)); title.tap()
        title.typeText("Native chair \(UUID().uuidString.prefix(6))")
        let location = app.textFields["Store or link, option 1"]
        location.tap(); location.typeText("https://example.com/chair")
        let price = app.textFields["Price, option 1"]
        price.tap(); price.typeText("89.95")
        if app.buttons["wish.keyboardDone"].exists { app.buttons["wish.keyboardDone"].tap() }
        else if UIDevice.current.userInterfaceIdiom == .pad { price.typeText("\n") }
        app.buttons["Add an option"].tap()
        XCTAssertTrue(app.textFields["Store or link, option 2"].waitForExistence(timeout: 5))
        app.textFields["Store or link, option 2"].tap()
        app.textFields["Store or link, option 2"].typeText("Second store")
        app.textFields["Price, option 2"].tap()
        app.textFields["Price, option 2"].typeText("110")
        if app.buttons["wish.keyboardDone"].exists { app.buttons["wish.keyboardDone"].tap() }
        else if UIDevice.current.userInterfaceIdiom == .pad { app.textFields["Price, option 2"].typeText("\n") }
        app.buttons["Add an option"].tap()
        XCTAssertTrue(app.textFields["Store or link, option 3"].waitForExistence(timeout: 5))
        app.textFields["Store or link, option 3"].tap()
        app.textFields["Store or link, option 3"].typeText("Third store")
        app.textFields["Price, option 3"].tap()
        app.textFields["Price, option 3"].typeText("125")
        XCTAssertFalse(app.buttons["Add an option"].exists)
        app.buttons["wish.save"].tap()
        let wish = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Native chair")).firstMatch
        XCTAssertTrue(wish.waitForExistence(timeout: 15)); wish.tap()
        let fulfill = app.buttons["Mark fulfilled"]
        XCTAssertTrue(fulfill.waitForExistence(timeout: 15)); fulfill.tap()
        XCTAssertTrue(app.buttons["Fulfilled"].waitForExistence(timeout: 15))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = UIDevice.current.userInterfaceIdiom == .pad ? "iPad wish detail" : "iPhone wish detail"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        // Relaunch without the test reset to verify Keychain restoration.
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        XCTAssertFalse(app.textFields["Email"].exists)
    }
}
