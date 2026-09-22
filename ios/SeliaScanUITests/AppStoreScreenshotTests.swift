import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [LaunchArgument.uiTesting, LaunchArgument.fixtureScanner]
        app.launch()
        XCTAssertTrue(app.staticTexts[AutomationIdentifier.Result.pageIndicator].waitForExistence(timeout: 10))
    }

    func testStoreScreenshots() {
        capture("01-result")

        app.buttons[AutomationIdentifier.Result.openViewer].tap()
        XCTAssertTrue(app.buttons[AutomationIdentifier.Viewer.done].waitForExistence(timeout: 3))
        capture("02-viewer")
        app.buttons[AutomationIdentifier.Viewer.done].tap()

        app.buttons[AutomationIdentifier.Result.actions].tap()
        XCTAssertTrue(app.buttons[AutomationIdentifier.Actions.reorderPages].waitForExistence(timeout: 3))
        capture("03-actions")
        app.buttons[AutomationIdentifier.Actions.done].tap()

        app.buttons[AutomationIdentifier.Result.signStamp].tap()
        XCTAssertTrue(app.buttons[AutomationIdentifier.MarkEditor.cancel].waitForExistence(timeout: 3))
        capture("04-sign-stamp")
        app.buttons[AutomationIdentifier.MarkEditor.cancel].tap()

        app.buttons[AutomationIdentifier.Result.fileDetails].tap()
        XCTAssertTrue(app.buttons[AutomationIdentifier.FileDetails.cancel].waitForExistence(timeout: 3))
        capture("05-file-details")
        app.buttons[AutomationIdentifier.FileDetails.cancel].tap()

        app.buttons[AutomationIdentifier.Result.recent].tap()
        XCTAssertTrue(app.descendants(matching: .any)[AutomationIdentifier.Recent.list].waitForExistence(timeout: 3))
        capture("06-recent")
    }

    private func capture(_ name: String) {
        let label = ProcessInfo.processInfo.environment["SCREENSHOT_LABEL"] ?? "unknown"
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(label)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
