import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Client for the notification server's `/v1/` routes (server/src/index.ts).
///
/// The routes that change what the server stores take an App Attest assertion over the
/// request (server/src/keys.ts): `send(_:sign:)` fetches its challenge and adds its headers.
public struct ServerClient: Sendable {
    public let baseURL: URL
    private let transport: HTTPTransport

    public init(baseURL: URL, transport: @escaping HTTPTransport = URLSession.shared.transport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    // MARK: TV guide

    public func tvGuide() async throws -> TVGuide {
        let route = "v1/tv-coverage"
        let (status, data) = try await perform(URLRequest(url: baseURL.appending(path: route)))
        guard status == 200 else { throw ServerError(status: status, body: data) }
        return try Self.decode(route) { try TVGuide(json: data) }
    }

    // MARK: Live Activities

    /// The APNs broadcast channel of the race's Live Activities in `environment`.
    public func liveChannel(raceID: String, environment: APNsEnvironment) async throws -> LiveChannelLookup {
        let route = "v1/races/\(raceID)/channels/\(environment.rawValue)"
        let (status, data) = try await perform(URLRequest(url: baseURL.appending(path: route)))
        // Default strategies, like ActivityKit's for the `content-state` of the broadcasts.
        switch status {
        case 200: return .open(try Self.decode(route) { try JSONDecoder().decode(LiveChannel.self, from: data) })
        case 404: return .notOpen
        case 410: return .ended(try Self.decode(route) { try JSONDecoder().decode(Ended.self, from: data) }.state)
        default: throw ServerError(status: status, body: data)
        }
    }

    // MARK: App Attest

    /// A single-use challenge for an attestation or an assertion.
    public func challenge(for purpose: AppAttestPurpose) async throws -> String {
        let route = "v1/app-attest/challenges"
        var request = URLRequest(
            url: baseURL.appending(path: route).appending(queryItems: [
                URLQueryItem(name: "purpose", value: purpose.rawValue)
            ]))
        request.httpMethod = "POST"
        let (status, data) = try await perform(request)
        guard status == 201 else { throw ServerError(status: status, body: data) }
        return try Self.decode(route) { try JSONDecoder().decode(Challenge.self, from: data) }.challenge
    }

    /// Stores the key Apple attested with the `attest` challenge `challenge`.
    public func registerKey(id: String, attestation: Data, challenge: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/app-attest/keys"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KeyRegistration(keyId: id, attestation: attestation.base64EncodedString(), challenge: challenge))
        let (status, data) = try await perform(request)
        guard status != 204 else { return }
        let error = ServerError(status: status, body: data)
        // "key already attested": an earlier try was stored but its answer was lost.
        guard case .http(401, "key already attested"?) = error else { throw error }
    }

    /// Sends `request` with the assertion `sign` makes over its challenge, method, path and
    /// body, exactly as `clientData` in server/src/keys.ts rebuilds them.
    public func send(
        _ request: SignedRequest, sign: (_ clientData: Data) async throws -> AppAttestAssertion
    ) async throws {
        let challenge = try await challenge(for: .assert)
        let url = baseURL.appending(path: request.path)
        var signed = URLRequest(url: url)
        signed.httpMethod = request.method
        if let body = request.body {
            signed.setValue("application/json", forHTTPHeaderField: "Content-Type")
            signed.httpBody = body
        }
        let assertion = try await sign(
            Data("\(challenge)\n\(request.method) \(url.path(percentEncoded: true))\n".utf8) + (request.body ?? Data()))
        signed.setValue(assertion.keyID, forHTTPHeaderField: "X-App-Attest-Key-Id")
        signed.setValue(assertion.assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
        signed.setValue(challenge, forHTTPHeaderField: "X-App-Attest-Challenge")
        let (status, data) = try await perform(signed)
        guard (200..<300).contains(status) else { throw ServerError(status: status, body: data) }
    }

    // MARK: Transport

    private func perform(_ request: URLRequest) async throws -> (status: Int, data: Data) {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
        return (http.statusCode, data)
    }

    private static func decode<T>(_ route: String, _ decode: () throws -> T) throws -> T {
        do {
            return try decode()
        } catch {
            throw ServerError.decoding(route: route, underlying: error)
        }
    }

    private struct Challenge: Decodable {
        let challenge: String
    }

    private struct KeyRegistration: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String
    }

    private struct Ended: Decodable {
        let state: RaceLiveState
    }
}

/// Failures of the notification server.
public enum ServerError: Error {
    case invalidResponse
    /// A status the route doesn't answer with on success, with the server's `error` message.
    case http(status: Int, message: String?)
    /// The server no longer knows the App Attest key that signed the request: a new one must be attested.
    case unknownKey
    case decoding(route: String, underlying: any Error)

    /// The failure of a request the server answered with `status` and `body`.
    init(status: Int, body: Data) {
        struct Body: Decodable { let error: String }
        let message = (try? JSONDecoder().decode(Body.self, from: body))?.error
        self = status == 401 && message == "unknown key" ? .unknownKey : .http(status: status, message: message)
    }

    /// The server refused the request itself (a 4xx status): sending it again changes nothing.
    public var isRefusal: Bool {
        switch self {
        case .http(let status, _): (400..<500).contains(status)
        case .unknownKey: true
        case .invalidResponse, .decoding: false
        }
    }
}

/// APNs environment of the build. The server keeps device tokens and Live Activity
/// channels per environment.
public enum APNsEnvironment: String, Encodable, Sendable {
    case sandbox, production
}

/// What the server knows of a race's Live Activity channel.
public enum LiveChannelLookup: Equatable, Sendable {
    case open(LiveChannel)
    /// The server has no channel for the race yet.
    case notOpen
    /// The race's activity is over, with its final state.
    case ended(RaceLiveState)
}

/// A race's APNs broadcast channel, with the state last published on it: the channel stores no messages.
public struct LiveChannel: Decodable, Equatable, Sendable {
    public let id: String
    public let state: RaceLiveState
    /// The `timestamp` of the broadcast that published `state`, in seconds since 1970 like
    /// that of an ActivityKit push.
    public let timestamp: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id = "channelId"
        case state, timestamp
    }
}

public enum AppAttestPurpose: String, Sendable {
    case attest, assert
}

/// An App Attest assertion, by the key `keyID`.
public struct AppAttestAssertion: Sendable {
    public let keyID: String
    public let assertion: Data

    public init(keyID: String, assertion: Data) {
        self.keyID = keyID
        self.assertion = assertion
    }
}

/// A change to what the server stores for a token, sent with an assertion by `ServerClient.send(_:sign:)`.
public struct SignedRequest: Equatable, Sendable {
    public let method: String
    /// Relative to the server's base URL.
    public let path: String
    public let body: Data?

    /// Registers the APNs device token for push alerts, or unregisters it without `registration`.
    public static func device(token: String, _ registration: DeviceRegistration?) throws -> Self {
        try Self(path: "v1/devices/\(token)", registration)
    }

    /// Registers the push-to-start token with the favorites, or deletes them without `registration`.
    public static func liveActivityStarts(token: String, _ registration: LiveActivityStartsRegistration?) throws
        -> Self
    {
        try Self(path: "v1/live-activity-starts/\(token)", registration)
    }

    /// A `PUT` of `registration`, or a `DELETE` without it.
    private init(path: String, _ registration: (some Encodable)?) throws {
        self.path = path
        method = registration == nil ? "DELETE" : "PUT"
        body = try registration.map { try JSONEncoder().encode($0) }
    }
}

/// What the server needs to send this device push alerts (server/src/devices.ts).
public struct DeviceRegistration: Encodable, Sendable {
    let environment: APNsEnvironment
    let categories: [RaceCategory]
    let cancellation: Bool
    let rescheduling: Bool
    let locale: String
    let timeZone: String

    public init(
        environment: APNsEnvironment, categories: Set<RaceCategory>, cancellation: Bool, rescheduling: Bool,
        locale: String, timeZone: String
    ) {
        self.environment = environment
        self.categories = categories.sorted { $0.rawValue < $1.rawValue }
        self.cancellation = cancellation
        self.rescheduling = rescheduling
        self.locale = locale
        self.timeZone = timeZone
    }
}

/// The favorites the server starts Live Activities for (server/src/liveStarts.ts).
public struct LiveActivityStartsRegistration: Encodable, Sendable {
    let environment: APNsEnvironment
    let athletes: [String]
    let nations: [String]

    public init(environment: APNsEnvironment, favorites: FavoriteSet) {
        self.environment = environment
        athletes = favorites.athleteIDs.sorted()
        nations = favorites.nations.sorted()
    }
}
