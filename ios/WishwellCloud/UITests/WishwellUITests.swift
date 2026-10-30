import XCTest

final class WishwellUITests: XCTestCase {
    @MainActor func testOfflineWishPersistsWithThreeOptionsAndFulfillment() throws {
        try createWish(local: true)
    }

    @MainActor func testSocialPreviewGettingAWishFromYourCircle() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--social-preview"]; app.launch()
        let circle = app.buttons["Circle"]
        if circle.waitForExistence(timeout: 10) { circle.tap() }
        else { app.staticTexts["Circle"].firstMatch.tap() }
        let person = app.buttons.matching(identifier: "circle.person").matching(NSPredicate(format: "label CONTAINS %@", "Tomas")).firstMatch
        guard person.waitForExistence(timeout: 10) else {
            let failure = XCTAttachment(screenshot: app.screenshot()); failure.lifetime = .keepAlways; add(failure)
            XCTFail("Circle grid missing: \(app.debugDescription)"); return
        }
        person.tap()
        XCTAssertTrue(app.descendants(matching: .any)["social.inCircle"].waitForExistence(timeout: 10))
        tapLabel(app, "A cozy corner", timeout: 10)
        tapLabel(app, "Reading chair", timeout: 10)
        let get = app.buttons["claim.get"]; XCTAssertTrue(get.waitForExistence(timeout: 10)); get.tap()
        let undo = app.buttons["claim.undo"]; XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertTrue(labelled(app, "You’re getting this").exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Getting a wish"; proof.lifetime = .keepAlways; add(proof)
        undo.tap()
        XCTAssertTrue(get.waitForExistence(timeout: 10))
        // Someone else's claim shows as taken, with their name.
        for _ in 0..<3 { app.navigationBars.buttons.firstMatch.tap() }
        tapLabel(app, "Layla Haddad", timeout: 10)
        tapLabel(app, "Birthday", timeout: 10)
        XCTAssertTrue(labelled(app, "Omar Saleh is getting this").waitForExistence(timeout: 10))
        let circleShot = XCTAttachment(screenshot: app.screenshot()); circleShot.name = "Someone else is getting it"; circleShot.lifetime = .keepAlways; add(circleShot)
    }

    @MainActor func testPrivateListPublishAndUnpublishInSocialPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--social-preview"]; app.launch()
        let add = app.buttons["list.add"]; XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        let title = app.textFields["list.title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        let name = "Sharing check \(UUID().uuidString.prefix(5))"; title.typeText(name); app.buttons["list.save"].tap()
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5)); list.tap()
        let sharing = app.switches["list.public"]; XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertEqual(sharing.value as? String, "0")
        flip(sharing); XCTAssertTrue(waitFor(sharing, value: "1", timeout: 10), "The list did not become public")
        flip(sharing); XCTAssertTrue(waitFor(sharing, value: "0", timeout: 10), "The list did not become private")
        // A list with wishes in it can be deleted, after saying how many go with it.
        app.buttons["wish.add"].tap()
        let wish = app.textFields["wish.title"]; XCTAssertTrue(wish.waitForExistence(timeout: 5)); wish.tap(); wish.typeText("Goes with the list")
        app.buttons["wish.save"].tap()
        app.buttons["list.menu"].tap(); app.buttons["list.delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete “\(name)” and its 1 wish?"].waitForExistence(timeout: 5))
        app.buttons["list.confirmDelete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["list.add"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists)
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

    // MARK: Live two-account social UI checks
    // Run in order 1–4, alternating between two signed devices with different Apple accounts:
    // TEST_RUNNER_WISHWELL_LIVE_SOCIAL=1 xcodebuild test ... -only-testing:WishwellUITests/WishwellUITests/testLiveSocial1OwnerPublishes
    // They use development CloudKit and a separate synthetic library, and remove their public profiles at the end.

    private let ownerName = "Wishwell Owner Check", peerName = "Wishwell Peer Check", liveList = "Live check list"

    @MainActor func testLiveSocial1OwnerPublishes() throws {
        let app = try launchLiveSocial()
        try ensurePublicProfile(app, name: ownerName)
        publishLiveList(app)
        attach(app, "Owner published list")
    }

    @MainActor func testLiveSocial2PeerInteractsReportsAndBlocks() throws {
        let app = try launchLiveSocial()
        try ensurePublicProfile(app, name: peerName)
        unblockEveryone(app)
        followAndGetWish(app)
        app.navigationBars.buttons.firstMatch.tap()
        let report = app.buttons["social.list.report"]; XCTAssertTrue(report.waitForExistence(timeout: 10)); report.tap()
        let reason = app.textFields["social.report.reason"].exists ? app.textFields["social.report.reason"] : app.textViews["social.report.reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5)); reason.tap(); reason.typeText("Live UI check. No moderation action needed.")
        app.buttons["social.report.submit"].tap()
        XCTAssertTrue(app.staticTexts["Your report has been submitted for review. Thank you."].waitForExistence(timeout: 20))
        app.buttons["social.report.done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let menu = app.buttons["social.person.menu"]; XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        app.buttons["Block this person"].tap(); app.buttons["social.person.confirmBlock"].firstMatch.tap()
        search(app, "Wishwell Owner")
        XCTAssertTrue(app.staticTexts["No one by that name yet."].waitForExistence(timeout: 20), "Blocked person still appears in search")
        openArea(app, "Settings")
        let unblock = app.buttons["social.unblock"]; scrollTo(app, unblock)
        XCTAssertTrue(unblock.waitForExistence(timeout: 10), "Blocked person missing from Settings"); unblock.tap()
        openArea(app, "Circle")
        search(app, "Wishwell Owner")
        XCTAssertTrue(labelled(app, ownerName).waitForExistence(timeout: 30), "Unblocked person did not return to search")
        attach(app, "Peer added owner, got a wish, reported, blocked and unblocked")
    }

    @MainActor func testLiveSocial3OwnerSeesActivityThenRemovesEverything() throws {
        let app = try launchLiveSocial()
        openArea(app, "Notifications")
        for text in ["\(peerName) added you to their circle", "Someone might be getting your wish Live check wish"] {
            XCTAssertTrue(labelled(app, text).waitForExistence(timeout: 30), "Missing activity: \(text)")
        }
        app.buttons["social.activity.markRead"].tap()
        attach(app, "Owner activity marked read")
        openArea(app, "My Lists")
        tapLabel(app, liveList)
        let sharing = app.switches["list.public"]; XCTAssertTrue(sharing.waitForExistence(timeout: 15))
        flip(sharing); XCTAssertTrue(waitFor(sharing, value: "0", timeout: 30), "Making the list private did not finish")
        try removePublicProfile(app)
    }

    @MainActor func testLiveSocial4PeerSeesRemovalThenRemovesProfile() throws {
        let app = try launchLiveSocial()
        openArea(app, "Circle")
        search(app, "Wishwell Owner")
        XCTAssertTrue(app.staticTexts["No one by that name yet."].waitForExistence(timeout: 30), "Removed profile still appears in search")
        try removePublicProfile(app)
    }

    // MARK: Read markers across two devices on the same Apple account
    // Owner iPhone (1, 3), peer iPhone (2, 5), owner iPad (4). Steps 1, 3 and 4 open the owner's
    // personal iCloud library with live social for that launch; nothing in it is published.

    @MainActor func testLiveReadSync1OwnerProfile() throws {
        let app = try launchLiveSocial(personalLibrary: true)
        try ensurePublicProfile(app, name: ownerName)
    }

    @MainActor func testLiveReadSync2PeerFollows() throws {
        let app = try launchLiveSocial()
        try ensurePublicProfile(app, name: peerName)
        unblockEveryone(app)
        openArea(app, "Circle")
        search(app, "Wishwell Owner")
        tapLabel(app, ownerName, timeout: 30)
        addToCircle(app)
    }

    @MainActor func testLiveReadSync3OwnerMarksRead() throws {
        let app = try launchLiveSocial(personalLibrary: true)
        openArea(app, "Notifications")
        let row = labelled(app, "\(peerName) added you to their circle")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Follow notification missing")
        app.buttons["social.activity.markRead"].tap()
        XCTAssertTrue(waitForValue(row, equalTo: "Read", timeout: 10))
        // Keep the app open so private sync can upload the read marker.
        sleep(30)
        attach(app, "Owner iPhone marked follow as read")
    }

    @MainActor func testLiveReadSync4SecondDeviceSeesReadThenRemovesProfile() throws {
        let app = try launchLiveSocial(personalLibrary: true)
        openArea(app, "Notifications")
        let row = labelled(app, "\(peerName) added you to their circle")
        XCTAssertTrue(row.waitForExistence(timeout: 60), "Follow notification missing on second device")
        XCTAssertTrue(waitForValue(row, equalTo: "Read", timeout: 240), "Read marker did not sync from the other device")
        attach(app, "Second device shows synced read marker")
        openArea(app, "Circle")
        XCTAssertTrue(app.navigationBars["Your circle"].waitForExistence(timeout: 30), "Circle did not load on the second device")
        attach(app, "Circle on second device")
        try removePublicProfile(app)
    }

    @MainActor func testLiveReadSync5PeerRemovesProfile() throws {
        let app = try launchLiveSocial()
        try removePublicProfile(app)
    }

    @MainActor private func publishLiveList(_ app: XCUIApplication) {
        openArea(app, "My Lists")
        let add = app.buttons["list.add"]; XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        let title = app.textFields["list.title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(liveList)
        app.buttons["list.save"].tap()
        tapLabel(app, liveList)
        let addWish = app.buttons["wish.add"]; XCTAssertTrue(addWish.waitForExistence(timeout: 5)); addWish.tap()
        let wish = app.textFields["wish.title"]; XCTAssertTrue(wish.waitForExistence(timeout: 5)); wish.tap(); wish.typeText("Live check wish")
        let location = app.textFields["option.location.0"]; location.tap(); location.typeText("Test shop")
        let price = app.textFields["option.price.0"]; price.tap(); price.typeText("10")
        if app.buttons["keyboard.done"].exists { app.buttons["keyboard.done"].tap() }
        app.buttons["wish.save"].tap()
        let sharing = app.switches["list.public"]; XCTAssertTrue(sharing.waitForExistence(timeout: 10))
        flip(sharing); XCTAssertTrue(waitFor(sharing, value: "1", timeout: 30), "Publishing to development CloudKit did not finish")
    }

    /// Safe to rerun: only adds the owner and gets the wish when that hasn't happened yet. Ends on the wish.
    @MainActor private func followAndGetWish(_ app: XCUIApplication) {
        openArea(app, "Circle")
        search(app, "Wishwell Owner")
        tapLabel(app, ownerName, timeout: 30)
        addToCircle(app)
        tapLabel(app, liveList, timeout: 20)
        tapLabel(app, "Live check wish", timeout: 20)
        let get = app.buttons["claim.get"], undo = app.buttons["claim.undo"]
        if !undo.waitForExistence(timeout: 10) { XCTAssertTrue(get.waitForExistence(timeout: 10)); get.tap() }
        XCTAssertTrue(undo.waitForExistence(timeout: 20), "Getting the wish did not finish")
    }
    @MainActor private func addToCircle(_ app: XCUIApplication) {
        let inCircle = app.descendants(matching: .any)["social.inCircle"]
        if !inCircle.waitForExistence(timeout: 5) {
            let add = app.buttons["social.follow"]; XCTAssertTrue(add.waitForExistence(timeout: 15)); add.tap()
        }
        XCTAssertTrue(inCircle.waitForExistence(timeout: 20), "Adding to the circle did not finish")
    }

    @MainActor private func launchLiveSocial(personalLibrary: Bool = false, extra: [String] = []) throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live social checks need signed devices with distinct iCloud accounts.")
        #else
        guard ProcessInfo.processInfo.environment["WISHWELL_LIVE_SOCIAL"] == "1" else { throw XCTSkip("Set TEST_RUNNER_WISHWELL_LIVE_SOCIAL=1 to run live social checks.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = [personalLibrary ? "--social-live-cloud" : "--social-live-ui"] + extra; app.launch()
        XCTAssertTrue(app.buttons["list.add"].waitForExistence(timeout: 60))
        return app
        #endif
    }
    @MainActor private func openArea(_ app: XCUIApplication, _ name: String) {
        // An active search keeps the keyboard up and swallows the tab tap.
        if app.keyboards.count > 0, let label = ["Close", "Cancel"].first(where: { app.buttons[$0].exists }) {
            let button = app.buttons[label].firstMatch
            if button.isHittable { button.tap() }
        }
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }
    @MainActor private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func tapLabel(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 10) {
        let element = labelled(app, text); XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(text)"); element.tap()
    }
    @MainActor private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor private func waitForValue(_ element: XCUIElement, equalTo value: String? = nil, notEqualTo other: String? = nil, timeout: TimeInterval) -> Bool {
        let predicate = value.map { NSPredicate(format: "value == %@", $0) } ?? NSPredicate(format: "value != %@", other ?? "")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
    @MainActor private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.searchFields.firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        if let value = field.value as? String, !value.isEmpty, value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }
    @MainActor private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }
    @MainActor private func ensurePublicProfile(_ app: XCUIApplication, name: String) throws {
        openArea(app, "Settings")
        let account = app.switches["profile.public"]
        XCTAssertTrue(account.waitForExistence(timeout: 15), "Social is not enabled in this build")
        let field = app.textFields["profile.name"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        if (field.value as? String) != name {
            field.tap()
            if let value = field.value as? String, !value.isEmpty, value != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            field.typeText(name + "\n")
        }
        if account.value as? String == "1" { return }
        flip(account)
        XCTAssertTrue(waitFor(account, value: "1", timeout: 30), "Turning on the public account did not finish")
    }
    @MainActor private func unblockEveryone(_ app: XCUIApplication) {
        openArea(app, "Settings")
        let unblock = app.buttons["social.unblock"]
        scrollTo(app, unblock)
        while unblock.exists { unblock.tap(); _ = unblock.waitForNonExistence(timeout: 2) }
    }
    @MainActor private func removePublicProfile(_ app: XCUIApplication) throws {
        openArea(app, "Settings")
        let account = app.switches["profile.public"]
        XCTAssertTrue(account.waitForExistence(timeout: 10)); flip(account)
        app.buttons["profile.confirmPrivate"].firstMatch.tap()
        XCTAssertTrue(waitFor(account, value: "0", timeout: 60), "Profile removal did not finish")
        attach(app, "Public profile removed")
    }
    /// Taps the switch itself; tapping the middle of a labelled switch can land on its label.
    @MainActor private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
    @MainActor private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
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
