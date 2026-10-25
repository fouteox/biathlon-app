import BiathlonKit
import DeviceCheck
import Foundation
import Testing

@testable import Biathlon

struct AppAttestTests {
    /// Apple asks to attest the same key with the same `clientDataHash` once it is reachable again.
    @Test func attestsTheSameKeyAgainOnceAppleIsBack() async throws {
        let service = FakeAttestService(attestFailures: [DCError(.serverUnavailable)])
        let server = ServerStub(["DELETE /v1/devices/ab12": [.init(204)]])
        let appAttest = AppAttest(server: server.client, service: service, defaults: try .empty())
        let request = try SignedRequest.device(token: "ab12", nil)

        await #expect(throws: DCError.self) { try await appAttest.send(request) }
        try await appAttest.send(request)

        #expect(service.generatedKeys == ["key1"])
        #expect(service.attestations.count == 2)
        #expect(Set(service.attestations).count == 1)
        #expect(await server.requests(to: "POST /v1/app-attest/keys").count == 1)
        #expect(await server.requests(to: "DELETE /v1/devices/ab12").count == 1)
    }

    /// After a reinstall or a restore, the server may not know the key the app kept.
    @Test func attestsANewKeyWhenTheServerDoesNotKnowIt() async throws {
        let defaults = try UserDefaults.empty()
        defaults.set("old", forKey: "appAttest.keyID")
        let service = FakeAttestService()
        let server = ServerStub([
            "DELETE /v1/devices/ab12": [.init(401, #"{"error":"unknown key"}"#), .init(204)]
        ])
        let appAttest = AppAttest(server: server.client, service: service, defaults: defaults)

        try await appAttest.send(try .device(token: "ab12", nil))

        #expect(service.generatedKeys == ["key1"])
        let keys = await server.requests(to: "DELETE /v1/devices/ab12").map {
            $0.value(forHTTPHeaderField: "X-App-Attest-Key-Id")
        }
        #expect(keys == ["old", "key1"])
    }

    @Test func attestsOneKeyForSimultaneousSends() async throws {
        let service = FakeAttestService()
        let server = ServerStub(["DELETE /v1/devices/ab12": [.init(204)]])
        let appAttest = AppAttest(server: server.client, service: service, defaults: try .empty())
        let request = try SignedRequest.device(token: "ab12", nil)

        async let first: Void = appAttest.send(request)
        async let second: Void = appAttest.send(request)
        _ = try await (first, second)

        #expect(service.generatedKeys == ["key1"])
        #expect(service.attestations.count == 1)
        #expect(await server.requests(to: "POST /v1/app-attest/keys").count == 1)
        #expect(await server.requests(to: "DELETE /v1/devices/ab12").count == 2)
    }
}
