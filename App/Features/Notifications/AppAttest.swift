import CryptoKit
import DeviceCheck
import Foundation
import os

/// Signs requests to the notification server with an App Attest key, which proves
/// they come from this app on a genuine Apple device (protocol in server/src/keys.ts).
///
/// Following Apple's "Establishing your app's integrity": one key per install, attested
/// once with a one-time challenge from the server, then one assertion per request.
final class AppAttest {
    enum Failure: Error {
        case unsupported
        case server(status: Int)
    }

    private let serverURL: URL
    private let service = DCAppAttestService.shared
    private let defaults: UserDefaults

    /// Keys don't survive reinstalls, device migration or restores, which may bring
    /// these values back: an `invalidKey` error then starts over with a new key.
    private enum DefaultsKey {
        /// Key the server accepted.
        static let keyID = "appAttest.keyID"
        /// Key and challenge of an attestation that failed with `serverUnavailable`:
        /// Apple asks to retry with the same key and the same `clientDataHash`.
        static let pendingKeyID = "appAttest.pendingKeyID"
        static let pendingChallenge = "appAttest.pendingChallenge"
    }

    init(serverURL: URL, defaults: UserDefaults = .standard) {
        self.serverURL = serverURL
        self.defaults = defaults
    }

    /// Sends `request` with an assertion over its method, path and body, attesting
    /// a new key first when there is none or the server no longer knows it.
    func send(_ request: URLRequest) async throws -> HTTPURLResponse {
        guard service.isSupported else { throw Failure.unsupported }
        var retried = false
        while true {
            let keyID = try await attestedKey()
            do {
                let (data, response) = try await URLSession.shared.data(for: try await signed(request, keyID: keyID))
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 401, !retried, Self.isUnknownKey(data) {
                    Logger.notifications.info("The server doesn't know the App Attest key, attesting a new one")
                    defaults.removeObject(forKey: DefaultsKey.keyID)
                    retried = true
                    continue
                }
                return http
            } catch let error as DCError where error.code == .invalidKey && !retried {
                Logger.notifications.info("The App Attest key is no longer valid, attesting a new one")
                defaults.removeObject(forKey: DefaultsKey.keyID)
                retried = true
            }
        }
    }

    private func attestedKey() async throws -> String {
        if let keyID = defaults.string(forKey: DefaultsKey.keyID) { return keyID }
        let keyID: String
        let challenge: String
        if let pendingKey = defaults.string(forKey: DefaultsKey.pendingKeyID),
            let pendingChallenge = defaults.string(forKey: DefaultsKey.pendingChallenge)
        {
            (keyID, challenge) = (pendingKey, pendingChallenge)
        } else {
            keyID = try await service.generateKey()
            challenge = try await fetchChallenge(purpose: "attest")
        }
        let attestation: Data
        do {
            attestation = try await service.attestKey(
                keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        } catch let error as DCError where error.code == .serverUnavailable {
            // The server accepts an attest challenge for a day; past that, it rejects the
            // registration below and the next sync starts over with a new key.
            defaults.set(keyID, forKey: DefaultsKey.pendingKeyID)
            defaults.set(challenge, forKey: DefaultsKey.pendingChallenge)
            throw error
        } catch {
            // Apple: for any other error, discard the key and create a new one next time.
            clearPending()
            throw error
        }
        clearPending()

        var request = URLRequest(url: serverURL.appending(path: "v1/app-attest/keys"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KeyRegistration(keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge))
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 else { throw Failure.server(status: status) }
        defaults.set(keyID, forKey: DefaultsKey.keyID)
        return keyID
    }

    private func clearPending() {
        defaults.removeObject(forKey: DefaultsKey.pendingKeyID)
        defaults.removeObject(forKey: DefaultsKey.pendingChallenge)
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

    private static func isUnknownKey(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(ServerError.self, from: data))?.error == "unknown key"
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
