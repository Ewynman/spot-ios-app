//
//  SpotUITests.swift
//  SpotUITests
//
//  Created by Edward Wynman on 7/10/25.
//
//  High-signal launch and navigation smoke tests for Spot. These tests run
//  against a fresh app launch and assume no signed-in Supabase session, so
//  the user lands on the unauthenticated WelcomeView. CI environments
//  without an `iCloud` keychain entry meet that assumption by default.
//

import XCTest

final class SpotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenShowsBrandAndAuthEntryPoints() throws {
        let app = XCUIApplication()
        app.launch()

        // App shows the launch screen briefly while AuthViewModel resolves.
        // Wait until the unauthenticated WelcomeView has rendered. If the
        // user is signed in (e.g. on a developer's local sim), this test
        // surfaces that fact via failure rather than silently passing.
        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(
            getStartedButton.waitForExistence(timeout: 15),
            "Welcome screen should show a Get Started button when unauthenticated"
        )
    }

    @MainActor
    func testWelcomeScreenExposesLoginEntryPoint() throws {
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["Login"]
        XCTAssertTrue(
            loginButton.waitForExistence(timeout: 15),
            "Welcome screen should expose a Login entry point"
        )
    }

    @MainActor
    func testTappingLoginNavigatesToLoginScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["Login"]
        guard loginButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Welcome screen not reachable — likely already signed in on this simulator.")
        }
        loginButton.tap()

        // LoginView shows fields/buttons consumed by LoginViewLogs; since
        // strings can drift, look for the absence of Get Started and any
        // Sign In affordance instead.
        let getStartedAfterTap = app.buttons["Get Started"]
        let signInAffordance = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sign'")).firstMatch
        let predicate = NSPredicate { _, _ in
            !getStartedAfterTap.exists || signInAffordance.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertNotEqual(result, .timedOut, "Tapping Login should navigate away from the welcome screen")
    }
}
