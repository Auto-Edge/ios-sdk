import Foundation

/// HTTP client for AutoEdge API communication.
final class APIClient {

    // MARK: - Properties

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Initialization

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Device Registration

    func registerDevice(_ deviceInfo: DeviceInfo) async throws -> DeviceResponse {
        let url = baseURL.appendingPathComponent("/api/v1/ota/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(deviceInfo)

        return try await perform(request)
    }

    // MARK: - Update Checking

    func checkForUpdate(
        modelId: String,
        currentVersion: String?,
        deviceIdentifier: String?
    ) async throws -> UpdateCheckResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/v1/ota/check-update/\(modelId)"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems: [URLQueryItem] = []
        if let version = currentVersion {
            queryItems.append(URLQueryItem(name: "current_version", value: version))
        }
        if let device = deviceIdentifier {
            queryItems.append(URLQueryItem(name: "device_identifier", value: device))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        return try await perform(request)
    }

    // MARK: - Model Download

    func downloadModel(
        modelId: String,
        version: String?
    ) async throws -> (URL, HTTPURLResponse) {
        let versionPath = version ?? "latest"
        let url = baseURL.appendingPathComponent("/api/v1/ota/download/\(modelId)/\(versionPath)")

        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutoEdgeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AutoEdgeError.downloadFailed("Server returned status \(httpResponse.statusCode)")
        }

        return (tempURL, httpResponse)
    }

    // MARK: - Analytics

    func sendAnalyticsEvents(_ events: [AnalyticsEventPayload]) async throws {
        let url = baseURL.appendingPathComponent("/api/v1/analytics/events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = BatchEventsPayload(events: events)
        request.httpBody = try encoder.encode(body)

        // Fire and forget - we don't need the response
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AutoEdgeError.networkError(
                NSError(domain: "AutoEdgeSDK", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to send analytics"
                ])
            )
        }
    }

    // MARK: - Private Methods

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AutoEdgeError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw AutoEdgeError.networkError(
                    NSError(domain: "AutoEdgeSDK", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"
                    ])
                )
            }

            return try decoder.decode(T.self, from: data)
        } catch let error as AutoEdgeError {
            throw error
        } catch {
            throw AutoEdgeError.networkError(error)
        }
    }
}

// MARK: - Request/Response Types

struct DeviceInfo: Encodable {
    let deviceIdentifier: String
    let deviceType: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "device_identifier"
        case deviceType = "device_type"
        case osVersion = "os_version"
    }
}

struct DeviceResponse: Decodable {
    let id: String
    let deviceIdentifier: String
    let deviceType: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case deviceType = "device_type"
        case osVersion = "os_version"
    }
}

struct UpdateCheckResponse: Decodable {
    let hasUpdate: Bool
    let currentVersion: String?
    let latestVersion: String?
    let downloadUrl: String?
    let fileSizeBytes: Int?
    let fileHash: String?

    enum CodingKeys: String, CodingKey {
        case hasUpdate = "has_update"
        case currentVersion = "current_version"
        case latestVersion = "latest_version"
        case downloadUrl = "download_url"
        case fileSizeBytes = "file_size_bytes"
        case fileHash = "file_hash"
    }
}

struct AnalyticsEventPayload: Encodable {
    let eventType: String
    let deviceIdentifier: String?
    let modelId: String?
    let modelVersion: String?
    let inferenceLatencyMs: Double?
    let memoryUsageBytes: Int?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case deviceIdentifier = "device_identifier"
        case modelId = "model_id"
        case modelVersion = "model_version"
        case inferenceLatencyMs = "inference_latency_ms"
        case memoryUsageBytes = "memory_usage_bytes"
    }
}

struct BatchEventsPayload: Encodable {
    let events: [AnalyticsEventPayload]
}
