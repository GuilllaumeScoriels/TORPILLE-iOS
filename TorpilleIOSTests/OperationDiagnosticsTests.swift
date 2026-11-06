import XCTest
import FirebaseAuth
@testable import TorpilleIOS

final class OperationDiagnosticsTests: XCTestCase {
    func testCommunityCreationDiagnosticIncludesStepDomainAndCode() {
        let error = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )

        let message = OperationDiagnostics.message(for: .createAdminMembership, error: error)

        XCTAssertTrue(message.contains("create-admin-membership"))
        XCTAssertTrue(message.contains("FIRFirestoreErrorDomain"))
        XCTAssertTrue(message.contains("Code: 7"))
        XCTAssertTrue(message.contains("Missing or insufficient permissions."))
    }

    func testCommunityCreationDiagnosticIncludesFailureReasonWhenAvailable() {
        let error = NSError(
            domain: "CustomDomain",
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "Operation failed.",
                NSLocalizedFailureReasonErrorKey: "Auth token is stale."
            ]
        )

        let message = OperationDiagnostics.message(for: .refreshToken, error: error)

        XCTAssertTrue(message.contains("refresh-token"))
        XCTAssertTrue(message.contains("Raison: Auth token is stale."))
    }
}

final class UserFacingErrorTests: XCTestCase {
    func testFirestoreDiagnosticsNeverReachTheUser() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Missing or insufficient permissions.",
            "details": "private/path", NSUnderlyingErrorKey: NSError(domain: "Internal", code: 99)
        ])
        let text = UserFacingError.message(for: error)
        XCTAssertEqual(text, "Cette action n’est pas autorisée avec ce compte.")
        for detail in ["Firestore", "permissions", "private/path", "Internal", "99", "NSLocalized"] {
            XCTAssertFalse(text.contains(detail))
        }
    }

    func testUnknownSDKAndServerErrorsHaveSafeFallbacks() {
        for domain in ["UnknownSDK", "FIRFunctionsErrorDomain", "FIRAuthErrorDomain", "FIRStorageErrorDomain"] {
            let error = NSError(domain: domain, code: 999, userInfo: [NSLocalizedDescriptionKey: "SECRET internal stack trace", "details": "SECRET"])
            XCTAssertFalse(UserFacingError.message(for: error).contains("SECRET"))
        }
    }

    func testUsefulValidationAndScheduleMessagesRemainVisible() {
        XCTAssertEqual(UserFacingError.message(for: TorpilleError.pseudoAlreadyUsed), TorpilleError.pseudoAlreadyUsed.errorDescription)
        let message = "Les torpilles sont fermées à cet horaire. Tu peux seulement répondre à une torpille reçue."
        XCTAssertEqual(UserFacingError.message(for: NSError(domain: "FIRFunctionsErrorDomain", code: 9,
            userInfo: [NSLocalizedDescriptionKey: message])), message)
    }

    func testCurrentFunctionsSDKDomainShowsReviewedServerMessages() {
        // FirebaseFunctions' real FunctionsErrorDomain is "com.firebase.functions".
        let message = "Cette torpille ne peut plus recevoir de réponse."
        XCTAssertEqual(UserFacingError.message(for: NSError(domain: "com.firebase.functions", code: 9,
            userInfo: [NSLocalizedDescriptionKey: message])), message)
        XCTAssertEqual(UserFacingError.message(for: NSError(domain: "com.firebase.functions", code: 5,
            userInfo: [NSLocalizedDescriptionKey: "NOT FOUND"])), UserFacingError.unavailable)
        XCTAssertFalse(UserFacingError.message(for: NSError(domain: "com.firebase.functions", code: 999,
            userInfo: [NSLocalizedDescriptionKey: "SECRET internal"])).contains("SECRET"))
    }

    func testWrappedDiagnosticIsNotTreatedAsProductCopy() {
        XCTAssertEqual(UserFacingError.message(for: TorpilleError.missingData("Domaine: FIRFirestoreErrorDomain Code: 7")), UserFacingError.fallback)
        XCTAssertEqual(UserFacingError.message(for: TorpilleError.uploadFailed("Buckets testés : private-bucket")), UserFacingError.fallback)
    }

    func testNetworkAndExpiredSessionHaveActionableMessages() {
        XCTAssertEqual(UserFacingError.message(for: URLError(.notConnectedToInternet)), UserFacingError.network)
        XCTAssertEqual(UserFacingError.message(for: NSError(domain: "FIRAuthErrorDomain", code: 17014)), "Reconnecte-toi pour effectuer cette action.")
    }
}

private final class ReviewAuthStub: AuthSessionManaging {
    var currentUID = "review-test"
    var isCurrentUserEmailVerified = true
    var signInError: Error?
    var signInCalls = 0
    var signUpCalls = 0
    var signUpError: Error?
    var verificationError: Error?
    var verificationCalls = 0
    var signOutCalls = 0
    var resetCalls = 0
    var suspendReset = false
    var pendingReset: CheckedContinuation<Void, Never>?
    var reloadCalls = 0
    var receivedPassword: String?
    var suspendSignIn = false
    var pendingSignIn: CheckedContinuation<Void, Never>?
    func signIn(email: String, password: String) async throws {
        signInCalls += 1
        receivedPassword = password
        if suspendSignIn {
            await withCheckedContinuation { pendingSignIn = $0 }
        }
        if let signInError { throw signInError }
    }
    func signUp(email: String, password: String) async throws {
        signUpCalls += 1
        receivedPassword = password
        if let signUpError { throw signUpError }
    }
    func reloadCurrentUser() async throws { reloadCalls += 1 }
    func sendEmailVerification() async throws {
        verificationCalls += 1
        if let verificationError { throw verificationError }
    }
    func sendPasswordReset(email: String) async throws {
        resetCalls += 1
        if suspendReset { await withCheckedContinuation { pendingReset = $0 } }
    }
    func setLanguageCode(_ languageCode: String?) { }
    func signOut() throws { signOutCalls += 1 }
}

@MainActor
final class ReviewSignInTests: XCTestCase {
    private func model(_ repository: ReviewAuthStub, timeout: TimeInterval = 1) -> AuthViewModel {
        let vm = AuthViewModel(authRepository: repository, languageService: AppLanguageService(), operationTimeout: timeout)
        vm.email = "review@example.com"
        vm.password = "test-password"
        return vm
    }
    private func settle(_ vm: AuthViewModel) async throws {
        for _ in 0..<200 {
            if !vm.isLoading { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Sign-in did not leave its loading state")
    }
    func testEmptyEmailShowsErrorWithoutSendingRequest() async throws {
        let repo = ReviewAuthStub()
        let vm = model(repo)
        vm.email = ""
        vm.signIn(hasAcceptedRequiredDocuments: true) { XCTFail("Must not authenticate") }
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(repo.signInCalls, 0)
    }
    func testIncorrectCredentialsProduceVisibleErrorAndAllowRetry() async throws {
        let repo = ReviewAuthStub(), vm: AuthViewModel
        repo.signInError = NSError(domain: "FIRAuthErrorDomain", code: 17009)
        vm = model(repo)
        vm.signIn(hasAcceptedRequiredDocuments: true) { XCTFail("Invalid credentials") }
        try await settle(vm)
        XCTAssertEqual(vm.error, "Email ou mot de passe incorrect.")
        repo.signInError = nil
        var completed = false
        vm.signIn(hasAcceptedRequiredDocuments: true) { completed = true }
        try await settle(vm)
        XCTAssertTrue(completed)
        XCTAssertNil(vm.error)
        XCTAssertEqual(repo.reloadCalls, 0)
    }
    func testProfileFailureIsPropagatedToSignInForm() async throws {
        let vm = model(ReviewAuthStub())
        vm.signIn(hasAcceptedRequiredDocuments: true) {
            throw NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        }
        try await settle(vm)
        XCTAssertEqual(vm.error, "Cette action n’est pas autorisée avec ce compte.")
    }
    func testTimeoutReenablesButtonAndIgnoresLateCompletion() async throws {
        let repo = ReviewAuthStub()
        repo.suspendSignIn = true
        let vm = model(repo, timeout: 0.02)
        var completed = false
        vm.signIn(hasAcceptedRequiredDocuments: true) { completed = true }
        try await settle(vm)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(completed)
        repo.pendingSignIn?.resume()
        repo.pendingSignIn = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertFalse(completed)
        XCTAssertFalse(vm.isLoading)
    }
    func testPasswordIsNotTrimmedAndDoubleTapDoesNotDuplicateRequest() async throws {
        let repo = ReviewAuthStub()
        let vm = model(repo)
        vm.password = "  password with spaces  "
        vm.signIn(hasAcceptedRequiredDocuments: true) { }
        vm.signIn(hasAcceptedRequiredDocuments: true) { }
        try await settle(vm)
        XCTAssertEqual(repo.receivedPassword, "  password with spaces  ")
        XCTAssertEqual(repo.signInCalls, 1)
    }
    func testLoadingContinuesUntilPostAuthenticationWorkFinishes() async throws {
        let vm = model(ReviewAuthStub())
        var continuation: CheckedContinuation<Void, Never>?
        vm.signIn(hasAcceptedRequiredDocuments: true) {
            await withCheckedContinuation { continuation = $0 }
        }
        for _ in 0..<100 {
            if continuation != nil { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isLoading)
        continuation?.resume()
        try await settle(vm)
        XCTAssertNil(vm.error)
    }
    func testLiveAppleReviewAccountCanAuthenticateAndLoadProfile() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["TORPILLE_REVIEW_EMAIL"],
              let password = environment["TORPILLE_REVIEW_PASSWORD"] else {
            throw XCTSkip("Run explicitly with the existing App Review demo credentials")
        }
        let repo = AuthRepository()
        defer { try? repo.signOut() }
        let vm = AuthViewModel(authRepository: repo, languageService: AppLanguageService())
        vm.email = email
        vm.password = password
        let signedIn = expectation(description: "Live account and profile are accessible")
        vm.signIn(hasAcceptedRequiredDocuments: true) {
            XCTAssertTrue(repo.isCurrentUserEmailVerified)
            let profile = try await UserRepository().getMeOrThrow()
            XCTAssertTrue(profile.hasRequiredIdentity)
            signedIn.fulfill()
        }
        await fulfillment(of: [signedIn], timeout: 30)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }
}

@MainActor
final class RegistrationFlowTests: XCTestCase {
    private var savedAcceptance: [String: Any] = [:]
    private var acceptanceKeys: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        acceptanceKeys = [DeviceLegalAcceptance.eulaVersionKey, DeviceLegalAcceptance.privacyPolicyVersionKey]
        if let uid = Auth.auth().currentUser?.uid {
            acceptanceKeys += acceptanceKeys.map { $0 + ".account." + uid }
        }
        for key in acceptanceKeys { savedAcceptance[key] = UserDefaults.standard.object(forKey: key) }
        for key in acceptanceKeys { UserDefaults.standard.set(DeviceLegalAcceptance.currentAcceptanceValue, forKey: key) }
    }

    override func tearDown() async throws {
        for key in acceptanceKeys {
            if let value = savedAcceptance[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try await super.tearDown()
    }

    private func model(_ repo: ReviewAuthStub, timeout: TimeInterval = 1) -> AuthViewModel {
        let vm = AuthViewModel(authRepository: repo, languageService: AppLanguageService(), operationTimeout: timeout)
        vm.email = "new-user@example.com"
        vm.password = "test-password"
        vm.passwordConfirmation = vm.password
        return vm
    }

    private func settle(_ vm: AuthViewModel) async throws {
        for _ in 0..<200 {
            if !vm.isLoading { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Authentication operation remained loading")
    }

    func testRegistrationPreservesPasswordSpacesAndSendsVerificationBeforeSignOut() async throws {
        let repo = ReviewAuthStub()
        repo.isCurrentUserEmailVerified = false
        let vm = model(repo)
        vm.password = "  password with spaces  "
        vm.passwordConfirmation = vm.password
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Unverified users must stay on authentication") }
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Duplicate signup") }
        try await settle(vm)
        XCTAssertEqual(repo.receivedPassword, "  password with spaces  ")
        XCTAssertEqual(repo.signUpCalls, 1)
        XCTAssertEqual(repo.verificationCalls, 1)
        XCTAssertEqual(repo.signOutCalls, 1)
        XCTAssertNotNil(vm.infoMessage)
        XCTAssertNil(vm.error)
    }

    func testRegistrationRejectsConfirmationThatDiffersOnlyInSpaces() {
        let repo = ReviewAuthStub(), vm: AuthViewModel
        vm = model(repo)
        vm.password = " password "
        vm.passwordConfirmation = "password"
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Passwords differ") }
        XCTAssertEqual(repo.signUpCalls, 0)
        XCTAssertNotNil(vm.error)
    }

    func testRegistrationRequiresConsentAndMinimumPasswordLength() {
        let repo = ReviewAuthStub()
        let vm = model(repo)
        vm.signUp(hasAcceptedRequiredDocuments: false) { XCTFail("Consent required") }
        XCTAssertNotNil(vm.error)
        let short = model(repo)
        short.password = "12345"
        short.passwordConfirmation = short.password
        short.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Password too short") }
        XCTAssertNotNil(short.error)
        XCTAssertEqual(repo.signUpCalls, 0)
    }

    func testRepeatedRegistrationResendsVerificationAfterAuthenticating() async throws {
        let repo = ReviewAuthStub()
        repo.isCurrentUserEmailVerified = false
        repo.signUpError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.emailAlreadyInUse.rawValue)
        let vm = model(repo)
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Must verify email first") }
        try await settle(vm)
        XCTAssertEqual(repo.signInCalls, 1)
        XCTAssertEqual(repo.verificationCalls, 1)
        XCTAssertEqual(repo.signOutCalls, 1)
        XCTAssertNotNil(vm.infoMessage)
        XCTAssertNil(vm.error)
    }

    func testRepeatedRegistrationWithWrongPasswordDoesNotSendEmail() async throws {
        let repo = ReviewAuthStub()
        repo.signUpError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.emailAlreadyInUse.rawValue)
        repo.signInError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.wrongPassword.rawValue)
        let vm = model(repo)
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Invalid credentials") }
        try await settle(vm)
        XCTAssertEqual(repo.verificationCalls, 0)
        XCTAssertNotNil(vm.error)
        XCTAssertNil(vm.infoMessage)
    }

    func testAlreadyVerifiedRegistrationPromptsSignInAndSignsOut() async throws {
        let repo = ReviewAuthStub(), vm: AuthViewModel
        repo.signUpError = NSError(domain: AuthErrorDomain, code: AuthErrorCode.emailAlreadyInUse.rawValue)
        vm = model(repo)
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Must explicitly sign in") }
        try await settle(vm)
        XCTAssertEqual(repo.verificationCalls, 0)
        XCTAssertEqual(repo.signOutCalls, 1)
        XCTAssertNotNil(vm.infoMessage)
        XCTAssertNil(vm.error)
    }

    func testVerificationFailureSignsOutAndAllowsRegistrationRetry() async throws {
        let repo = ReviewAuthStub()
        repo.isCurrentUserEmailVerified = false
        repo.verificationError = URLError(.notConnectedToInternet)
        let vm = model(repo)
        vm.signUp(hasAcceptedRequiredDocuments: true) { XCTFail("Email not sent") }
        try await settle(vm)
        XCTAssertEqual(repo.signOutCalls, 1)
        XCTAssertNotNil(vm.error)
        repo.verificationError = nil
        vm.signUp(hasAcceptedRequiredDocuments: true) { }
        try await settle(vm)
        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.infoMessage)
    }

    func testUnverifiedSignInStaysOnFormAndSignsOutEvenWhenEmailFails() async throws {
        let repo = ReviewAuthStub()
        repo.isCurrentUserEmailVerified = false
        repo.verificationError = URLError(.notConnectedToInternet)
        let vm = model(repo)
        vm.signIn(hasAcceptedRequiredDocuments: true) { XCTFail("Unverified email must not enter app") }
        try await settle(vm)
        XCTAssertEqual(repo.signOutCalls, 1)
        XCTAssertNotNil(vm.error)
    }

    func testResetTimeoutAllowsRetryAndIgnoresLateSuccess() async throws {
        let repo = ReviewAuthStub()
        repo.suspendReset = true
        let vm = model(repo, timeout: 0.02)
        vm.resetPassword()
        vm.resetPassword()
        try await settle(vm)
        XCTAssertEqual(repo.resetCalls, 1)
        XCTAssertNotNil(vm.error)
        repo.pendingReset?.resume()
        repo.pendingReset = nil
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNil(vm.infoMessage)
        repo.suspendReset = false
        vm.resetPassword()
        try await settle(vm)
        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.infoMessage)
    }
}
