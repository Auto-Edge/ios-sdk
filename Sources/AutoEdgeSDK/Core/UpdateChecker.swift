import Foundation

/// Checks for model updates.
final class UpdateChecker {

    // MARK: - Properties

    private let apiClient: APIClient

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Update Checking

    /// Check if an update is available for a model.
    func checkForUpdate(
        modelId: String,
        currentVersion: String?,
        deviceIdentifier: String? = nil
    ) async throws -> UpdateInfo? {
        let response = try await apiClient.checkForUpdate(
            modelId: modelId,
            currentVersion: currentVersion,
            deviceIdentifier: deviceIdentifier
        )

        guard response.hasUpdate, let latestVersion = response.latestVersion else {
            return nil
        }

        return UpdateInfo(
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            fileSizeBytes: response.fileSizeBytes
        )
    }
}
