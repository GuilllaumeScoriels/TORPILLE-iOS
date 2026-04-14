import XCTest
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
