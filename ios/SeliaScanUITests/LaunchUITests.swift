import XCTest
import UIKit

final class LaunchUITests: XCTestCase {
    private func launch(contentSizeCategory: UIContentSizeCategory? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchArgument.uiTesting, LaunchArgument.fixtureScanner]
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory.rawValue]
        }
        app.launch()
        return app
    }

    func testFixtureScanResultAndViewer() {
        let app = launch()
        let pageIndicator = app.staticTexts[AutomationIdentifier.Result.pageIndicator]
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 8))
        XCTAssertEqual(pageIndicator.value as? String, "1/2")
        let preview = app.descendants(matching: .any)[AutomationIdentifier.Result.pagePreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.swipeLeft()
        XCTAssertEqual(pageIndicator.value as? String, "2/2")
        XCTAssertTrue(app.buttons[AutomationIdentifier.Result.actions].exists)
        XCTAssertTrue(app.buttons[AutomationIdentifier.Result.share].exists)

        app.buttons[AutomationIdentifier.Result.openViewer].tap()
        let done = app.buttons[AutomationIdentifier.Viewer.done]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        let viewerPageIndicator = app.staticTexts[AutomationIdentifier.Viewer.pageIndicator]
        XCTAssertTrue(viewerPageIndicator.waitForExistence(timeout: 3))
        XCTAssertEqual(viewerPageIndicator.value as? String, "2/2")
        done.tap()
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 3))
        XCTAssertEqual(pageIndicator.value as? String, "2/2")
    }

    func testRecentAndFileDetails() {
        let app = launch()
        XCTAssertTrue(app.staticTexts[AutomationIdentifier.Result.pageIndicator].waitForExistence(timeout: 8))
        app.buttons[AutomationIdentifier.Result.fileDetails].tap()
        let cancel = app.buttons[AutomationIdentifier.FileDetails.cancel]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        app.buttons[AutomationIdentifier.Result.recent].tap()
        XCTAssertTrue(app.descendants(matching: .any)[AutomationIdentifier.Recent.list].waitForExistence(timeout: 3))
    }

    func testPageOrganizerAndMarkEditorOpen() {
        let app = launch()
        XCTAssertTrue(app.staticTexts[AutomationIdentifier.Result.pageIndicator].waitForExistence(timeout: 8))
        app.buttons[AutomationIdentifier.Result.actions].tap()
        let reorder = app.buttons[AutomationIdentifier.Actions.reorderPages]
        XCTAssertTrue(reorder.waitForExistence(timeout: 3))
        reorder.tap()
        XCTAssertTrue(app.descendants(matching: .any)[AutomationIdentifier.Organizer.list].waitForExistence(timeout: 3))
        app.buttons[AutomationIdentifier.Organizer.done].tap()
        app.buttons[AutomationIdentifier.Actions.done].tap()
        app.buttons[AutomationIdentifier.Result.signStamp].tap()
        let cancel = app.buttons[AutomationIdentifier.MarkEditor.cancel]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
    }

    func testResultActionsRemainReadableAtAccessibilityTextSize() {
        let app = launch(contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge)
        XCTAssertTrue(app.staticTexts[AutomationIdentifier.Result.pageIndicator].waitForExistence(timeout: 8))
        let sign = app.buttons[AutomationIdentifier.Result.signStamp]
        let actions = app.buttons[AutomationIdentifier.Result.actions]
        let share = app.buttons[AutomationIdentifier.Result.share]
        XCTAssertTrue(sign.exists)
        XCTAssertTrue(actions.exists)
        XCTAssertTrue(share.exists)
        XCTAssertGreaterThan(sign.frame.width, 250)
        XCTAssertGreaterThan(actions.frame.width, 250)
        XCTAssertGreaterThan(share.frame.width, 250)
        XCTAssertLessThan(sign.frame.maxY, actions.frame.minY)
        XCTAssertLessThan(actions.frame.maxY, share.frame.minY)
    }
}
