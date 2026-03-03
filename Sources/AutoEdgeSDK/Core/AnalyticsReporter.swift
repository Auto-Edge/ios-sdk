import Foundation

/// Batches and reports analytics events.
final class AnalyticsReporter {

    // MARK: - Properties

    private let apiClient: APIClient
    private let deviceIdentifier: String
    private let flushInterval: TimeInterval

    private var pendingEvents: [AnalyticsEventPayload] = []
    private let lock = NSLock()
    private var flushTask: Task<Void, Never>?

    private let maxBatchSize = 100

    // MARK: - Initialization

    init(apiClient: APIClient, deviceIdentifier: String, flushInterval: TimeInterval) {
        self.apiClient = apiClient
        self.deviceIdentifier = deviceIdentifier
        self.flushInterval = flushInterval

        startPeriodicFlush()
    }

    deinit {
        flushTask?.cancel()
    }

    // MARK: - Event Reporting

    /// Report an inference event.
    func reportInference(
        modelId: String,
        version: String?,
        latencyMs: Double,
        memoryBytes: Int?
    ) {
        let event = AnalyticsEventPayload(
            eventType: "inference",
            deviceIdentifier: deviceIdentifier,
            modelId: modelId,
            modelVersion: version,
            inferenceLatencyMs: latencyMs,
            memoryUsageBytes: memoryBytes
        )
        addEvent(event)
    }

    /// Report a generic event.
    func reportEvent(eventType: String, modelId: String?, version: String?) {
        let event = AnalyticsEventPayload(
            eventType: eventType,
            deviceIdentifier: deviceIdentifier,
            modelId: modelId,
            modelVersion: version,
            inferenceLatencyMs: nil,
            memoryUsageBytes: nil
        )
        addEvent(event)
    }

    /// Flush pending events immediately.
    func flush() async {
        let eventsToSend: [AnalyticsEventPayload]

        lock.lock()
        eventsToSend = pendingEvents
        pendingEvents = []
        lock.unlock()

        guard !eventsToSend.isEmpty else { return }

        do {
            try await apiClient.sendAnalyticsEvents(eventsToSend)
        } catch {
            // Re-add events on failure (with limit to prevent unbounded growth)
            lock.lock()
            let totalCount = pendingEvents.count + eventsToSend.count
            if totalCount <= maxBatchSize * 2 {
                pendingEvents = eventsToSend + pendingEvents
            }
            lock.unlock()

            print("AutoEdgeSDK: Failed to send analytics: \(error)")
        }
    }

    // MARK: - Private Methods

    private func addEvent(_ event: AnalyticsEventPayload) {
        lock.lock()
        pendingEvents.append(event)
        let shouldFlush = pendingEvents.count >= maxBatchSize
        lock.unlock()

        if shouldFlush {
            Task {
                await flush()
            }
        }
    }

    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.flushInterval ?? 30) * 1_000_000_000)
                await self?.flush()
            }
        }
    }
}
