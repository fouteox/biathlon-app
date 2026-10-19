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
        case server(status: Int)
    }

    private let serverURL: URL
    private let service = DCAppAttestService.shared
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

    init(serverURL: URL, defaults: UserDefaults = .standard) {
        self.serverURL = serverURL
        self.defaults = defaults
    }

    /// Sends `request` with an assertion over its method, path and body, attesting
    /// a new key first when there is none or the server no longer knows it.
    func send(_ request: URLRequest) async throws -> HTTPURLResponse {
        guard service.isSupported else { throw Failure.unsupported }
        let previous = queue
        let task = Task {
            await previous?.value
            return try await sendSigned(request)
        }
        queue = Task { _ = await task.result }
        return try await task.value
    }

    private func sendSigned(_ request: URLRequest) async throws -> HTTPURLResponse {
        var retried = false
        while true {
            do {
                let keyID = try await attestedKey()
                let (data, response) = try await URLSession.shared.data(for: try await signed(request, keyID: keyID))
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 401, !retried, Self.serverError(data) == "unknown key" {
                    Logger.notifications.info("The server doesn't know the App Attest key, attesting a new one")
                    defaults.removeObject(forKey: DefaultsKey.keyID)
                    retried = true
                    continue
                }
                return http
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
            let challenge = try await fetchChallenge(purpose: "attest")
            pending = Pending(keyID: try await service.generateKey(), challenge: challenge)
            // Saved before attesting: if the app is terminated meanwhile, the next sync reuses this key.
            savePending(pending)
        }

        if pending.attestation == nil {
            do {
                pending.attestation = try await service.attestKey(
                    pending.keyID, clientDataHash: Data(SHA256.hash(data: Data(pending.challenge.utf8))))
            } catch let error as DCError where error.code == .serverUnavailable {
                // The key stays pending: the next sync retries with the same key and hash.
                throw error
            } catch {
                // Apple: for any other error, discard the key and create a new one next time.
                clearPending()
                throw error
            }
        }
        savePending(pending)

        var request = URLRequest(url: serverURL.appending(path: "v1/app-attest/keys"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KeyRegistration(
                keyId: pending.keyID,
                attestation: pending.attestation?.base64EncodedString() ?? "",
                challenge: pending.challenge
            ))
        // A transport error keeps the key pending: the next sync sends the same attestation.
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let error = Self.serverError(data)
        // "key already attested": an earlier try was stored but its answer was lost.
        guard status == 204 || error == "key already attested" else {
            // Any other refusal, an expired challenge included, won't change: start over.
            if (400..<500).contains(status) {
                clearPending()
                // A key saved by an earlier sync gets one immediate retry with a new key.
                if saved != nil { return try await attestNewKey() }
            }
            throw Failure.server(status: status)
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

    /// Adds the assertion headers. The signed bytes are the challenge, the method and
    /// path, then the body, exactly as `clientData` in server/src/keys.ts builds them.
    private func signed(_ request: URLRequest, keyID: String) async throws -> URLRequest {
        guard let url = request.url, let method = request.httpMethod else { throw URLError(.badURL) }
        let challenge = try await fetchChallenge(purpose: "assert")
        let clientData =
            Data("\(challenge)\n\(method) \(url.path(percentEncoded: true))\n".utf8) + (request.httpBody ?? Data())
        let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
        var signed = request
        signed.setValue(keyID, forHTTPHeaderField: "X-App-Attest-Key-Id")
        signed.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
        signed.setValue(challenge, forHTTPHeaderField: "X-App-Attest-Challenge")
        return signed
    }

    private func fetchChallenge(purpose: String) async throws -> String {
        var request = URLRequest(
            url: serverURL.appending(path: "v1/app-attest/challenges").appending(queryItems: [
                URLQueryItem(name: "purpose", value: purpose)
            ]))
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 201 else { throw Failure.server(status: status) }
        return try JSONDecoder().decode(Challenge.self, from: data).challenge
    }

    private static func serverError(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ServerError.self, from: data))?.error
    }

    private struct KeyRegistration: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String
    }

    private struct Challenge: Decodable {
        let challenge: String
    }

    private struct ServerError: Decodable {
        let error: String
    }
}
