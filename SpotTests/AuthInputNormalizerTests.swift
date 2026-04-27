//
//  AuthInputNormalizerTests.swift
//  SpotTests
//
//  Created By: Wynman, Edward
//  Date: 04/27/2026
//
//  Tests the pure auth-input helpers AuthService relies on for sign-up,
//  sign-in, password reset, and username/email resolution.
//

import Foundation
import Testing
@testable import Spot

struct AuthInputNormalizerTests {

    @Test func emailIsLowercasedAndTrimmed() {
        #expect(AuthInputNormalizer.normalizeEmail("  Foo@Example.COM  ") == "foo@example.com")
    }

    @Test func emailWithoutWhitespaceJustLowercases() {
        #expect(AuthInputNormalizer.normalizeEmail("BAR@example.com") == "bar@example.com")
    }

    @Test func emailEmptyStringStaysEmpty() {
        #expect(AuthInputNormalizer.normalizeEmail("") == "")
        #expect(AuthInputNormalizer.normalizeEmail("   \n\t ") == "")
    }

    @Test func emailDoesNotStripInternalWhitespace() {
        // Supabase will reject these, but the normalizer never edits the
        // local part — it only trims the boundaries.
        #expect(AuthInputNormalizer.normalizeEmail("Foo Bar@example.com") == "foo bar@example.com")
    }

    @Test func usernameIsTrimmedNotLowercased() {
        #expect(AuthInputNormalizer.normalizeUsername("  Edward  ") == "Edward")
    }

    @Test func usernameLowerIsTrimmedAndLowercased() {
        #expect(AuthInputNormalizer.normalizeUsernameLower("  Edward_42 ") == "edward_42")
    }

    @Test func usernameAllWhitespaceBecomesEmpty() {
        #expect(AuthInputNormalizer.normalizeUsername("   ").isEmpty)
        #expect(AuthInputNormalizer.normalizeUsernameLower("\n\t").isEmpty)
    }
}

struct AuthErrorClassifierTests {

    @Test func detectsAlreadyKeyword() {
        #expect(AuthErrorClassifier.isEmailInUse("User already exists") == true)
    }

    @Test func detectsExistsKeyword() {
        #expect(AuthErrorClassifier.isEmailInUse("This email exists in our system") == true)
    }

    @Test func detectsRegisteredKeyword() {
        #expect(AuthErrorClassifier.isEmailInUse("Email address has been registered") == true)
    }

    @Test func ignoresUnrelatedMessages() {
        #expect(AuthErrorClassifier.isEmailInUse("Network error") == false)
        #expect(AuthErrorClassifier.isEmailInUse("Invalid password") == false)
    }

    @Test func isCaseInsensitive() {
        #expect(AuthErrorClassifier.isEmailInUse("ALREADY IN USE") == true)
        #expect(AuthErrorClassifier.isEmailInUse("eMaIl ExIsTs") == true)
    }

    @Test func errorOverloadDelegatesToMessage() {
        let err = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Already registered"]
        )
        #expect(AuthErrorClassifier.isEmailInUse(error: err) == true)
    }

    @Test func emptyMessageIsNotEmailInUse() {
        #expect(AuthErrorClassifier.isEmailInUse("") == false)
    }
}

struct EmailInUseTypeTests {

    @Test func passwordAccountMessageMentionsSignIn() {
        let type = EmailInUseType.passwordAccount
        #expect(type.message.lowercased().contains("sign in"))
        #expect(type.suggestedActions.contains("Sign In"))
        #expect(type.suggestedActions.contains("Forgot Password"))
    }

    @Test func federatedAppleMessageMentionsApple() {
        let type = EmailInUseType.federatedAccount("apple.com")
        #expect(type.message.contains("Apple"))
        #expect(type.suggestedActions.contains("Continue with Apple"))
    }

    @Test func federatedGoogleMessageMentionsGoogle() {
        let type = EmailInUseType.federatedAccount("google.com")
        #expect(type.message.contains("Google"))
        #expect(type.suggestedActions.contains("Continue with Google"))
    }

    @Test func inconsistentStateProvidesTryAgain() {
        let type = EmailInUseType.inconsistentState
        #expect(type.suggestedActions.contains("Try Again"))
        #expect(!type.message.isEmpty)
    }
}
