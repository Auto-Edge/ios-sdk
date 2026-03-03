import XCTest
@testable import AutoEdgeSDK

final class AutoEdgeSDKTests: XCTestCase {

    func testSDKNotConfiguredError() async throws {
        let sdk = AutoEdgeSDK.shared

        // Before configuration, loading should fail
        do {
            _ = try await sdk.loadModel(modelId: "test-model")
            XCTFail("Expected error to be thrown")
        } catch let error as AutoEdgeError {
            if case .notConfigured = error {
                // Expected
            } else {
                XCTFail("Expected notConfigured error, got \(error)")
            }
        }
    }

    func testUpdateInfoHasUpdate() {
        let info1 = UpdateInfo(
            latestVersion: "2.0.0",
            currentVersion: "1.0.0",
            fileSizeBytes: 1024
        )
        XCTAssertTrue(info1.hasUpdate)

        let info2 = UpdateInfo(
            latestVersion: "1.0.0",
            currentVersion: "1.0.0",
            fileSizeBytes: 1024
        )
        XCTAssertFalse(info2.hasUpdate)

        let info3 = UpdateInfo(
            latestVersion: "1.0.0",
            currentVersion: nil,
            fileSizeBytes: 1024
        )
        XCTAssertTrue(info3.hasUpdate)
    }

    func testErrorDescriptions() {
        let errors: [AutoEdgeError] = [
            .notConfigured,
            .networkError(NSError(domain: "test", code: 0)),
            .downloadFailed("test"),
            .modelNotFound("test-model"),
            .invalidResponse,
            .cacheError("test")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
