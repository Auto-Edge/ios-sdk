import Foundation

/// Manages model downloading and caching.
final class ModelManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let modelCache: ModelCache

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        self.modelCache = ModelCache()
    }

    // MARK: - Model Loading

    /// Load a model, downloading if necessary.
    func loadModel(modelId: String, version: String? = nil) async throws -> URL {
        // Check if we have a cached version
        if let version = version, let cachedURL = modelCache.getCachedModel(modelId: modelId, version: version) {
            return cachedURL
        }

        // For "latest", check if we have any cached version and if it's up to date
        if version == nil {
            if let (cachedVersion, cachedURL) = modelCache.getLatestCachedModel(modelId: modelId) {
                // Check if there's a newer version
                let updateResponse = try await apiClient.checkForUpdate(
                    modelId: modelId,
                    currentVersion: cachedVersion,
                    deviceIdentifier: nil
                )

                if !updateResponse.hasUpdate {
                    return cachedURL
                }
            }
        }

        // Download the model
        let (tempURL, response) = try await apiClient.downloadModel(modelId: modelId, version: version)

        // Get version from response headers
        let downloadedVersion = response.value(forHTTPHeaderField: "X-Model-Version") ?? version ?? "unknown"

        // Move to cache
        let cachedURL = try modelCache.cacheModel(
            tempURL: tempURL,
            modelId: modelId,
            version: downloadedVersion
        )

        return cachedURL
    }

    /// Get the cached version for a model, if any.
    func getCachedVersion(modelId: String) -> String? {
        return modelCache.getLatestCachedModel(modelId: modelId)?.0
    }

    /// Clear the cache.
    func clearCache(modelId: String? = nil) {
        modelCache.clearCache(modelId: modelId)
    }

    /// Get total cache size in bytes.
    func getCacheSize() -> Int {
        return modelCache.getTotalSize()
    }
}
