import XCTest

nonisolated final class MobileNavigationTests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor private func launch(fixture: Bool = false, accessible: Bool = false, arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-setupCompleted", "YES",
                               "--notes-test-id", UUID().uuidString] + arguments
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
        XCTAssertTrue(app.textFields["meetingTitle"].exists)
        XCTAssertFalse(app.buttons["Start Meeting"].isEnabled)
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
        let title = app.textFields["meetingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Planning\n")
        XCTAssertEqual(title.value as? String, "Planning")
        XCTAssertTrue(app.buttons["Start Meeting"].isHittable)
        capture("Landscape meeting setup")
    }

    @MainActor func testMeetingTitleIsRequired() {
        launch()
        defer { app.terminate() }
        open("Meetings")
        let title = app.textFields["meetingTitle"]
        let start = app.buttons["Start Meeting"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled)
        title.tap()
        title.typeText("   ")
        XCTAssertFalse(start.isEnabled)
        title.typeText("Planning\n")
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(start.isHittable)
        capture("Required meeting title beside start")
    }

    @MainActor func testMeetingReviewEditsPersist() {
        launch(fixture: true)
        defer { app.terminate() }
        open("Meetings")
        let fixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Planning fixture")).firstMatch
        if !fixture.isHittable {
            showMeetingList()
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
            showMeetingList()
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
        for _ in 0..<8 {
            if start.exists && start.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
        XCTAssertTrue(app.textFields["meetingTitle"].isHittable)
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

    @MainActor func testCopiedDeletionRequiresConfirmationAndPersists() {
        launch(arguments: ["--notes-review-fixture"])
        defer { app.terminate() }
        open("Notes")
        actions(for: "Tablet note fixture")
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete Recording"].waitForExistence(timeout: 5))
        cancelConfirmation()
        XCTAssertTrue(app.staticTexts["Tablet note fixture"].exists)
        actions(for: "Tablet note fixture")
        app.buttons["Delete"].tap()
        app.buttons["Delete Recording"].tap()
        XCTAssertTrue(app.staticTexts["Tablet note fixture"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        open("Notes")
        XCTAssertFalse(app.staticTexts["Tablet note fixture"].exists)
        capture("Confirmed copied recording deletion")
    }

    @MainActor func testQueuedSkipResumeAndConfirmedDeletionPersist() {
        launch(arguments: ["--queued-recordings-fixture", "--queue-processing-fixture"])
        defer { app.terminate() }
        open("Notes")
        actions(for: "Queued recording 1")
        XCTAssertFalse(app.buttons["Delete"].isEnabled)
        app.buttons["Skip for Now"].tap()
        actions(for: "Queued recording 1")
        XCTAssertTrue(app.buttons["Resume Writing"].waitForExistence(timeout: 5))
        app.tap() // Dismiss the menu without changing the recording.
        actions(for: "Queued recording 2")
        app.buttons["Resume Writing"].tap()
        actions(for: "Queued recording 2")
        XCTAssertFalse(app.buttons["Delete"].isEnabled)
        app.buttons["Skip for Now"].tap()
        actions(for: "Queued recording 1")
        app.buttons["Delete"].tap()
        cancelConfirmation()
        XCTAssertTrue(app.staticTexts["Queued recording 1"].exists)
        actions(for: "Queued recording 1")
        app.buttons["Delete"].tap()
        app.buttons["Delete Recording"].tap()
        XCTAssertTrue(app.staticTexts["Queued recording 1"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        open("Notes")
        XCTAssertFalse(app.staticTexts["Queued recording 1"].exists)
        XCTAssertTrue(app.staticTexts["Queued recording 2"].exists)
        actions(for: "Queued recording 2")
        XCTAssertTrue(app.buttons["Resume Writing"].exists)
        capture("Skipped queue persists")
    }

    @MainActor func testInterruptedWritingDefersSyncedModelsAndUnlocksAfterSkip() {
        launch(arguments: ["--queued-recordings-fixture", "--queue-processing-fixture", "--deferred-model-fixture"])
        defer { app.terminate() }
        open("Settings")
        openModels()
        let english = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'English'")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertFalse(english.isEnabled)
        XCTAssertTrue(app.staticTexts["Synced model changes will apply when recording and processing finish."].exists)
        capture("Models locked during writing")
        XCUIDevice.shared.press(.home)
        app.activate()
        open("Notes")
        XCTAssertTrue(app.staticTexts["Queued recording 1"].waitForExistence(timeout: 5))
        actions(for: "Queued recording 1")
        app.buttons["Skip for Now"].tap()
        open("Settings")
        if !english.exists { openModels() }
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertTrue(english.isEnabled)
        XCTAssertFalse(app.staticTexts["Synced model changes will apply when recording and processing finish."].exists)
        capture("Models unlocked after writing pauses")
    }

    @MainActor func testRecordingSurvivesRotationAndDiscardCancellation() {
        launch(arguments: ["--recording-fixture"])
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        open("Settings")
        openModels()
        let english = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'English'")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertFalse(english.isEnabled)
        open("Record")
        XCUIDevice.shared.orientation = .landscapeLeft
        if UIDevice.current.userInterfaceIdiom == .pad {
            let landscape = NSPredicate { [app] _, _ in
                guard let app else { return false }
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            }
            expectation(for: landscape, evaluatedWith: app)
            waitForExpectations(timeout: 5)
        }
        XCTAssertTrue(app.staticTexts["Recording fixture transcript."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop and make a note"].isHittable)
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        capture("Active recording after rotation")
        app.buttons["Discard recording"].tap()
        cancelConfirmation()
        XCTAssertTrue(app.staticTexts["Recording fixture transcript."].exists)
        app.buttons["Discard recording"].tap()
        app.buttons["Discard Recording"].tap()
        XCTAssertTrue(app.buttons["Record"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testCompactWidthQueueActionsAtLargeText() {
        launch(accessible: true, arguments: ["--compact-layout-fixture", "--queued-recordings-fixture"])
        defer { app.terminate() }
        open("Notes")
        let actions = app.buttons["Actions for Queued recording 1"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        if !actions.isHittable { app.swipeUp() }
        XCTAssertTrue(actions.isHittable)
        actions.tap()
        XCTAssertTrue(app.buttons["Resume Writing"].isHittable)
        XCTAssertTrue(app.buttons["Delete"].isHittable)
        capture("Compact layout harness at accessibility text size")
    }

    @MainActor private func actions(for title: String) {
        let button = app.buttons["Actions for \(title)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    @MainActor private func cancelConfirmation() {
        let keep = app.buttons["Keep Recording"]
        if keep.exists {
            keep.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.15)).tap()
        }
    }

    @MainActor private func openModels() {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Models'")).firstMatch.tap()
    }

    @MainActor private func showMeetingList() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == 'Meetings' OR label == 'Back' OR label == 'Show Sidebar'")
        ).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
