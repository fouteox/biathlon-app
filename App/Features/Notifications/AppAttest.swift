import BiathlonKit
import CryptoKit
import DeviceCheck
import Foundation
import os

/// Signs requests to the notification server with an App Attest key, which proves
/// they come from this app on a genuine Apple device (protocol in server/src/keys.ts).
///
/// Following Apple's "Establishing your app's integrity": one key per install, attested
/// once with a challenge from the server, then one assertion per request.
final class AppAttest {
    enum Failure: Error {
        case unsupported
    }

    private let server: ServerClient
    private let service: any AppAttestService
    private let defaults: UserDefaults
    /// The last send: sends run one at a time, so that a single key is attested and
    /// assertion counters grow in the order of the changes they carry.
    private var queue: Task<Void, Never>?

    /// Keys don't survive reinstalls, device migration or restores, which may bring
    /// these values back: an `invalidKey` error then starts over with a new key.
    private enum DefaultsKey {
        /// Key the server accepted.
        static let keyID = "appAttest.keyID"
        /// `Pending` key, not yet accepted by the server.
        static let pending = "appAttest.pending"
    }

    /// A key on its way to the server, kept until the server answers so that a failure
    /// doesn't cost a new key: Apple asks to generate keys only when needed.
    private struct Pending: Codable {
        let keyID: String
        /// Kept to retry `attestKey` after `serverUnavailable` with the same key and
        /// `clientDataHash`, as Apple asks. The server accepts it for a day.
        let challenge: String
        /// Set once Apple attested the key, until the server confirms it stored it.
        var attestation: Data?
    }

    init(
        server: ServerClient, service: any AppAttestService = DCAppAttestService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.server = server
        self.service = service
        self.defaults = defaults
    }

    /// Sends `request` with an assertion over its method, path and body, attesting
    /// a new key first when there is none or the server no longer knows it.
    func send(_ request: SignedRequest) async throws {
        guard service.isSupported else { throw Failure.unsupported }
        let previous = queue
        let task = Task {
            await previous?.value
            try await sendSigned(request)
        }
        queue = Task { _ = await task.result }
        try await task.value
    }

    private func sendSigned(_ request: SignedRequest) async throws {
        var retried = false
        while true {
            do {
                let keyID = try await attestedKey()
                try await server.send(request) { clientData in
                    AppAttestAssertion(
                        keyID: keyID,
                        assertion: try await service.generateAssertion(
                            keyID, clientDataHash: Data(SHA256.hash(data: clientData))))
                }
                return
            } catch ServerError.unknownKey where !retried {
                Logger.notifications.info("The server doesn't know the App Attest key, attesting a new one")
                defaults.removeObject(forKey: DefaultsKey.keyID)
                retried = true
            } catch let error as DCError where error.code == .invalidKey && !retried {
                // From the stored key, or from a pending one a restore brought back.
                Logger.notifications.info("The App Attest key is no longer valid, attesting a new one")
                defaults.removeObject(forKey: DefaultsKey.keyID)
                retried = true
            }
        }
    }

    private func attestedKey() async throws -> String {
        if let keyID = defaults.string(forKey: DefaultsKey.keyID) { return keyID }
        return try await attestNewKey()
    }

    private func attestNewKey() async throws -> String {
        var pending: Pending
        let saved = loadPending()
        if let saved {
            pending = saved
        } else {
            // The challenge first: a failed fetch then leaves no unused key behind.
            let challenge = try await server.challenge(for: .attest)
            pending = Pending(keyID: try await service.generateKey(), challenge: challenge)
            // Saved before attesting: if the app is terminated meanwhile, the next sync reuses this key.
            savePending(pending)
        }

        let attestation: Data
        if let attested = pending.attestation {
            attestation = attested
        } else {
            do {
                attestation = try await service.attestKey(
                    pending.keyID, clientDataHash: Data(SHA256.hash(data: Data(pending.challenge.utf8))))
            } catch let error as DCError where error.code == .serverUnavailable {
                // The key stays pending: the next sync retries with the same key and hash.
                throw error
            } catch {
                // Apple: for any other error, discard the key and create a new one next time.
                clearPending()
                throw error
            }
            pending.attestation = attestation
            savePending(pending)
        }

        // A transport error or a server failure keeps the key pending: the next sync sends the same attestation.
        do {
            try await server.registerKey(id: pending.keyID, attestation: attestation, challenge: pending.challenge)
        } catch let error as ServerError where error.isRefusal {
            // Any refusal, an expired challenge included, won't change: start over.
            clearPending()
            // A key saved by an earlier sync gets one immediate retry with a new key.
            if saved != nil { return try await attestNewKey() }
            throw error
        }
        defaults.set(pending.keyID, forKey: DefaultsKey.keyID)
        clearPending()
        return pending.keyID
    }

    private func loadPending() -> Pending? {
        defaults.data(forKey: DefaultsKey.pending).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
    }

    private func savePending(_ pending: Pending) {
        defaults.set(try? JSONEncoder().encode(pending), forKey: DefaultsKey.pending)
    }

    private func clearPending() {
        defaults.removeObject(forKey: DefaultsKey.pending)
    }
}

/// What `AppAttest` uses of `DCAppAttestService`, which tests replace.
protocol AppAttestService {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

extension DCAppAttestService: AppAttestService {}
