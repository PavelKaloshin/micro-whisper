import XCTest
@testable import Whisper

/// Verifies `KeychainService`'s API-key storage. Under XCTest the service uses an
/// in-memory store (see `KeychainService.isRunningTests`), so these tests never
/// touch the real macOS Keychain and never trigger a login-password prompt.
final class KeychainServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainService.shared.deleteAPIKey()
    }

    override func tearDown() {
        KeychainService.shared.deleteAPIKey()
        super.tearDown()
    }

    func testSaveGetDeleteRoundTrip() {
        XCTAssertNil(KeychainService.shared.getAPIKey(), "starts empty")
        XCTAssertFalse(KeychainService.shared.hasAPIKey)

        XCTAssertTrue(KeychainService.shared.saveAPIKey("sk-TEST-123"))
        XCTAssertEqual(KeychainService.shared.getAPIKey(), "sk-TEST-123")
        XCTAssertTrue(KeychainService.shared.hasAPIKey)

        XCTAssertTrue(KeychainService.shared.deleteAPIKey())
        XCTAssertNil(KeychainService.shared.getAPIKey())
        XCTAssertFalse(KeychainService.shared.hasAPIKey)
    }

    func testSaveOverwritesPreviousKey() {
        XCTAssertTrue(KeychainService.shared.saveAPIKey("first"))
        XCTAssertTrue(KeychainService.shared.saveAPIKey("second"))
        XCTAssertEqual(KeychainService.shared.getAPIKey(), "second")
    }

    func testDeleteWhenEmptyIsSafe() {
        XCTAssertTrue(KeychainService.shared.deleteAPIKey())
        XCTAssertNil(KeychainService.shared.getAPIKey())
    }
}
