import Foundation

/// Manages local model file caching.
final class ModelCache {

    // MARK: - Properties

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let metadataFile = "cache_metadata.json"

    private var metadata: CacheMetadata
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        // Use app's caches directory
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("AutoEdgeModels", isDirectory: true)

        // Ensure directory exists
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load or create metadata
        metadata = Self.loadMetadata(from: cacheDirectory, metadataFile: metadataFile) ?? CacheMetadata()
    }

    // MARK: - Cache Operations

    /// Get a cached model by ID and version.
    func getCachedModel(modelId: String, version: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = metadata.models[modelId],
              entry.version == version else {
            return nil
        }

        let url = cacheDirectory.appendingPathComponent(entry.filename)
        guard fileManager.fileExists(atPath: url.path) else {
            // Clean up stale metadata
            metadata.models.removeValue(forKey: modelId)
            saveMetadata()
            return nil
        }

        return url
    }

    /// Get the latest cached model for a model ID.
    func getLatestCachedModel(modelId: String) -> (version: String, url: URL)? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = metadata.models[modelId] else {
            return nil
        }

        let url = cacheDirectory.appendingPathComponent(entry.filename)
        guard fileManager.fileExists(atPath: url.path) else {
            metadata.models.removeValue(forKey: modelId)
            saveMetadata()
            return nil
        }

        return (entry.version, url)
    }

    /// Cache a model file.
    func cacheModel(tempURL: URL, modelId: String, version: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        // Generate filename
        let filename = "\(modelId)_\(version).mlpackage"
        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        // Remove existing file if present
        try? fileManager.removeItem(at: destinationURL)

        // Move temp file to cache
        try fileManager.moveItem(at: tempURL, to: destinationURL)

        // Update metadata
        let fileSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int) ?? 0
        metadata.models[modelId] = CacheEntry(
            version: version,
            filename: filename,
            fileSize: fileSize,
            cachedAt: Date()
        )
        saveMetadata()

        return destinationURL
    }

    /// Clear the cache.
    func clearCache(modelId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let modelId = modelId {
            // Clear specific model
            if let entry = metadata.models.removeValue(forKey: modelId) {
                let url = cacheDirectory.appendingPathComponent(entry.filename)
                try? fileManager.removeItem(at: url)
            }
        } else {
            // Clear all
            for entry in metadata.models.values {
                let url = cacheDirectory.appendingPathComponent(entry.filename)
                try? fileManager.removeItem(at: url)
            }
            metadata.models.removeAll()
        }

        saveMetadata()
    }

    /// Get total cache size in bytes.
    func getTotalSize() -> Int {
        lock.lock()
        defer { lock.unlock() }

        return metadata.models.values.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Private Methods

    private func saveMetadata() {
        let url = cacheDirectory.appendingPathComponent(metadataFile)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: url)
        }
    }

    private static func loadMetadata(from directory: URL, metadataFile: String) -> CacheMetadata? {
        let url = directory.appendingPathComponent(metadataFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }
}

// MARK: - Supporting Types

private struct CacheMetadata: Codable {
    var models: [String: CacheEntry] = [:]
}

private struct CacheEntry: Codable {
    let version: String
    let filename: String
    let fileSize: Int
    let cachedAt: Date
}
