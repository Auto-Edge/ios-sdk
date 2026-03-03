import Foundation

/// AutoEdge SDK for on-device ML model delivery and analytics.
///
/// Use this SDK to:
/// - Load and cache ML models from your AutoEdge server
/// - Check for and download model updates
/// - Report inference metrics for analytics
///
/// Example usage:
/// ```swift
/// let sdk = AutoEdgeSDK.shared
/// sdk.configure(serverURL: URL(string: "https://your-server.com")!)
///
/// // Load a model
/// let modelURL = try await sdk.loadModel(modelId: "my-model")
///
/// // Report inference metrics
/// sdk.reportInference(modelId: "my-model", latencyMs: 15.5)
/// ```
public final class AutoEdgeSDK {

    // MARK: - Singleton

    /// Shared SDK instance.
    public static let shared = AutoEdgeSDK()

    // MARK: - Properties

    private var apiClient: APIClient?
    private var modelManager: ModelManager?
    private var updateChecker: UpdateChecker?
    private var analyticsReporter: AnalyticsReporter?

    private var isConfigured = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configure the SDK with your server URL.
    ///
    /// - Parameters:
    ///   - serverURL: Base URL of your AutoEdge server.
    ///   - deviceIdentifier: Optional custom device identifier. If nil, uses a generated UUID.
    ///   - flushInterval: Interval for flushing analytics events (default: 30 seconds).
    public func configure(
        serverURL: URL,
        deviceIdentifier: String? = nil,
        flushInterval: TimeInterval = 30
    ) {
        let identifier = deviceIdentifier ?? getOrCreateDeviceIdentifier()

        apiClient = APIClient(baseURL: serverURL)
        modelManager = ModelManager(apiClient: apiClient!)
        updateChecker = UpdateChecker(apiClient: apiClient!)
        analyticsReporter = AnalyticsReporter(
            apiClient: apiClient!,
            deviceIdentifier: identifier,
            flushInterval: flushInterval
        )

        isConfigured = true

        // Register device
        Task {
            await registerDevice(identifier: identifier)
        }
    }

    // MARK: - Model Loading

    /// Load a model, downloading if necessary.
    ///
    /// This method will:
    /// 1. Check if the model is cached locally
    /// 2. Check for updates if cached
    /// 3. Download the latest version if needed
    /// 4. Return the local file URL
    ///
    /// - Parameter modelId: The model identifier.
    /// - Returns: Local file URL to the model.
    /// - Throws: AutoEdgeError if loading fails.
    public func loadModel(modelId: String) async throws -> URL {
        guard let modelManager = modelManager else {
            throw AutoEdgeError.notConfigured
        }
        return try await modelManager.loadModel(modelId: modelId)
    }

    /// Load a specific version of a model.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier.
    ///   - version: The version to load.
    /// - Returns: Local file URL to the model.
    /// - Throws: AutoEdgeError if loading fails.
    public func loadModel(modelId: String, version: String) async throws -> URL {
        guard let modelManager = modelManager else {
            throw AutoEdgeError.notConfigured
        }
        return try await modelManager.loadModel(modelId: modelId, version: version)
    }

    // MARK: - Update Checking

    /// Check if an update is available for a model.
    ///
    /// - Parameter modelId: The model identifier.
    /// - Returns: Update information if available, nil otherwise.
    /// - Throws: AutoEdgeError if check fails.
    public func checkForUpdate(modelId: String) async throws -> UpdateInfo? {
        guard let updateChecker = updateChecker, let modelManager = modelManager else {
            throw AutoEdgeError.notConfigured
        }

        let currentVersion = modelManager.getCachedVersion(modelId: modelId)
        return try await updateChecker.checkForUpdate(
            modelId: modelId,
            currentVersion: currentVersion
        )
    }

    // MARK: - Analytics

    /// Report an inference event.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier.
    ///   - latencyMs: Inference latency in milliseconds.
    ///   - memoryBytes: Optional memory usage in bytes.
    public func reportInference(
        modelId: String,
        latencyMs: Double,
        memoryBytes: Int? = nil
    ) {
        guard let analyticsReporter = analyticsReporter,
              let modelManager = modelManager else { return }

        let version = modelManager.getCachedVersion(modelId: modelId)
        analyticsReporter.reportInference(
            modelId: modelId,
            version: version,
            latencyMs: latencyMs,
            memoryBytes: memoryBytes
        )
    }

    /// Report a custom event.
    ///
    /// - Parameters:
    ///   - eventType: The event type.
    ///   - modelId: Optional model identifier.
    public func reportEvent(eventType: String, modelId: String? = nil) {
        guard let analyticsReporter = analyticsReporter else { return }
        analyticsReporter.reportEvent(eventType: eventType, modelId: modelId, version: nil)
    }

    /// Flush pending analytics events immediately.
    public func flushAnalytics() async {
        await analyticsReporter?.flush()
    }

    // MARK: - Cache Management

    /// Clear the model cache.
    ///
    /// - Parameter modelId: Optional model ID to clear. If nil, clears all cached models.
    public func clearCache(modelId: String? = nil) {
        modelManager?.clearCache(modelId: modelId)
    }

    /// Get the current cache size in bytes.
    public func getCacheSize() -> Int {
        return modelManager?.getCacheSize() ?? 0
    }

    // MARK: - Private Methods

    private func getOrCreateDeviceIdentifier() -> String {
        let key = "com.autoedge.deviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newIdentifier = UUID().uuidString
        UserDefaults.standard.set(newIdentifier, forKey: key)
        return newIdentifier
    }

    private func registerDevice(identifier: String) async {
        guard let apiClient = apiClient else { return }

        do {
            let deviceInfo = DeviceInfo(
                deviceIdentifier: identifier,
                deviceType: getDeviceType(),
                osVersion: getOSVersion()
            )
            try await apiClient.registerDevice(deviceInfo)
        } catch {
            // Log but don't fail - device registration is not critical
            print("AutoEdgeSDK: Failed to register device: \(error)")
        }
    }

    private func getDeviceType() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #elseif os(macOS)
        return "Mac"
        #else
        return "Unknown"
        #endif
    }

    private func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - Supporting Types

/// Information about an available update.
public struct UpdateInfo {
    /// The latest available version.
    public let latestVersion: String

    /// Current version on device (if any).
    public let currentVersion: String?

    /// Size of the update in bytes.
    public let fileSizeBytes: Int?

    /// Whether an update is available.
    public var hasUpdate: Bool {
        guard let current = currentVersion else { return true }
        return current != latestVersion
    }
}

/// Errors that can occur in the SDK.
public enum AutoEdgeError: Error, LocalizedError {
    case notConfigured
    case networkError(Error)
    case downloadFailed(String)
    case modelNotFound(String)
    case invalidResponse
    case cacheError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AutoEdgeSDK is not configured. Call configure(serverURL:) first."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .modelNotFound(let modelId):
            return "Model not found: \(modelId)"
        case .invalidResponse:
            return "Invalid response from server"
        case .cacheError(let message):
            return "Cache error: \(message)"
        }
    }
}
