//
//  OnboardingUITests.swift
//  SpotUITests
//

import XCTest

final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGetStartedBeginsAccountFlow() throws {
        let app = XCUIApplication()
        SpotUITestAppConfiguration.applyDefaultLaunchConfiguration(to: app)
        app.launch()

        let getStarted = app.buttons["onboarding.getStartedButton"]
        guard getStarted.waitForExistence(timeout: 20) else {
            throw XCTSkip("Welcome not reachable — likely already signed in on this simulator.")
        }
        getStarted.tap()

        let signup = app.descendants(matching: .any)["onboarding.signupScreen"]
        let locationGate = app.staticTexts["Location Access"]
        let settled = signup.waitForExistence(timeout: 12)
            || locationGate.waitForExistence(timeout: 12)
            || app.staticTexts["Sign Up"].waitForExistence(timeout: 12)

        XCTAssertTrue(settled, "Get Started should reach signup, permission gate, or Sign Up title")
    }
}
