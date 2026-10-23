import XCTest

nonisolated final class MobileNavigationTests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor private func launch(fixture: Bool = false, accessible: Bool = false) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-setupCompleted", "YES"]
        if fixture { app.launchArguments.append("--meeting-review-fixture") }
        if accessible {
            app.launchArguments += ["--notes-review-fixture", "--ui-testing-dark",
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
    }

    @MainActor func testRecordingMeetingsNotesAndSettings() {
        launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Record"].firstMatch.waitForExistence(timeout: 15))
        capture("Record")
        open("Meetings")
        XCTAssertTrue(app.buttons["Start Meeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Meeting title (optional)"].exists)
        capture("Meeting setup")
        open("Notes")
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        capture("Notes")
        open("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Settings")
    }

    @MainActor func testLandscapeMeetingSetup() {
        launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        open("Meetings")
        let title = app.textFields["Meeting title (optional)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Planning")
        XCTAssertEqual(title.value as? String, "Planning")
        capture("Landscape meeting setup")
    }

    @MainActor func testMeetingReviewEditsPersist() {
        launch(fixture: true)
        defer { app.terminate() }
        open("Meetings")
        let fixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Planning fixture")).firstMatch
        if !fixture.isHittable {
            let recent = app.buttons["Recent meetings"]
            if recent.exists { recent.tap() }
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.tap()
        XCTAssertTrue(app.staticTexts["Ship Friday."].waitForExistence(timeout: 5))
        app.buttons["Actions"].tap()
        let actions = app.textViews["Meeting action items"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        actions.typeText(" amended")
        let edited = actions.value as? String
        XCTAssertTrue(edited?.contains("amended") == true)
        capture("Meeting actions review")
        app.terminate()
        app.launch()
        open("Meetings")
        if !fixture.isHittable {
            let recent = app.buttons["Recent meetings"]
            if recent.exists { recent.tap() }
        }
        fixture.tap()
        app.buttons["Actions"].tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertEqual(actions.value as? String, edited)
        app.buttons["Transcript"].tap()
        XCTAssertTrue(app.staticTexts["I will send the notes."].exists)
        capture("Meeting transcript review")
    }

    @MainActor func testAccessibleMeetingSetupAndNoteReading() {
        launch(accessible: true)
        defer { app.terminate() }
        open("Meetings")
        let start = app.buttons["Start Meeting"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
        capture("Accessible meeting setup")
        open("Notes")
        let note = app.staticTexts["Tablet note fixture"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.staticTexts["A private tablet note."].waitForExistence(timeout: 5))
        }
        capture("Accessible notes")
    }

    @MainActor private func open(_ title: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists, tab.isHittable { tab.tap(); return }
        let cell = app.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if cell.exists, cell.isHittable { cell.tap(); return }
        let button = app.buttons[title].firstMatch
        if button.exists, button.isHittable { button.tap(); return }
        let sidebar = app.buttons["Show Sidebar"].firstMatch
        if sidebar.exists { sidebar.tap() }
        if cell.exists, cell.isHittable { cell.tap(); return }
        let item = app.buttons[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
