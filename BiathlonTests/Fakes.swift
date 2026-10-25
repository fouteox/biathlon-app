import Foundation
import Testing
import UserNotifications

@testable import Biathlon

extension UserDefaults {
    /// Empty defaults of their own, for one test.
    static func empty() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "BiathlonTests.\(UUID().uuidString)"))
    }
}

/// Generates the keys `key1`, `key2`… and keeps what it is asked to attest.
final class FakeAttestService: AppAttestService {
    struct Attestation: Hashable {
        let keyID: String
        let clientDataHash: Data
    }

    let isSupported = true
    private(set) var generatedKeys: [String] = []
    private(set) var attestations: [Attestation] = []
    /// Thrown by the next attestations, in turn.
    private var attestFailures: [any Error]

    init(attestFailures: [any Error] = []) {
        self.attestFailures = attestFailures
    }

    func generateKey() async throws -> String {
        generatedKeys.append("key\(generatedKeys.count + 1)")
        return generatedKeys[generatedKeys.count - 1]
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestations.append(Attestation(keyID: keyId, clientDataHash: clientDataHash))
        if !attestFailures.isEmpty { throw attestFailures.removeFirst() }
        return Data(keyId.utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        clientDataHash
    }
}

/// Pending notification requests, kept in memory.
final class FakeNotificationCenter: LocalNotificationCenter {
    private(set) var requests: [UNNotificationRequest]

    /// Requests with these identifiers are already pending.
    init(pending identifiers: [String]) {
        requests = identifiers.map {
            UNNotificationRequest(identifier: $0, content: UNNotificationContent(), trigger: nil)
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        requests
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }
}
