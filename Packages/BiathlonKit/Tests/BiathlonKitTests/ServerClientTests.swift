import Foundation
import Testing

@testable import BiathlonKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The server's answers, as server/src/index.ts gives them.
struct ServerClientTests {
    /// A `content-state` as ActivityKit decodes it: a `Date` is seconds since 2001-01-01.
    static let liveState = #"{"phase":"live","startTime":816448500,"leaders":[]}"#
    static let decodedState = RaceLiveState(
        phase: .live, startTime: Date(timeIntervalSinceReferenceDate: 816_448_500), leaders: [])

    @Test func loadsTheTVGuide() async throws {
        let server = ServerStub([
            "GET /v1/tv-coverage": [
                .init(
                    200,
                    #"{"coverage":[{"country":"FR","broadcaster":"L'Équipe","url":"https://www.lequipe.fr/tv/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"}]}"#
                )
            ]
        ])
        let guide = try await server.client.tvGuide()
        #expect(guide.coverage.map(\.broadcaster) == ["L'Équipe"])
    }

    @Test func aFailedLoadCarriesTheStatus() async {
        let server = ServerStub(["GET /v1/tv-coverage": [.init(503)]])
        let error = await #expect(throws: ServerError.self) { try await server.client.tvGuide() }
        guard case .http(503, nil) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    @Test func anUnreadableAnswerNamesTheRoute() async {
        let server = ServerStub(["GET /v1/tv-coverage": [.init(200, "not json")]])
        let error = await #expect(throws: ServerError.self) { try await server.client.tvGuide() }
        guard case .decoding("v1/tv-coverage", _) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    @Test func findsTheOpenChannelOfTheEnvironment() async throws {
        let server = ServerStub([
            "GET /v1/races/R1/channels/sandbox": [
                .init(200, #"{"channelId":"C1","state":\#(Self.liveState),"timestamp":1795000000}"#)
            ]
        ])
        let lookup = try await server.client.liveChannel(raceID: "R1", environment: .sandbox)
        #expect(lookup == .open(LiveChannel(id: "C1", state: Self.decodedState, timestamp: 1_795_000_000)))
    }

    @Test func aRaceWithoutChannelHasNoneYet() async throws {
        let server = ServerStub([
            "GET /v1/races/R1/channels/production": [.init(404, #"{"error":"no channel for this race"}"#)]
        ])
        #expect(try await server.client.liveChannel(raceID: "R1", environment: .production) == .notOpen)
    }

    @Test func anEndedRaceGivesItsFinalStateAndDismissalDate() async throws {
        let server = ServerStub([
            "GET /v1/races/R1/channels/sandbox": [
                .init(410, #"{"state":\#(Self.liveState),"dismissalDate":1795001800}"#)
            ]
        ])
        #expect(
            try await server.client.liveChannel(raceID: "R1", environment: .sandbox)
                == .ended(
                    LiveActivityEnd(
                        finalState: Self.decodedState, dismissalDate: Date(timeIntervalSince1970: 1_795_001_800))))
    }

    @Test func asksForAChallengeOfItsPurpose() async throws {
        let server = ServerStub(["POST /v1/app-attest/challenges": [.init(201, #"{"challenge":"c1"}"#)]])
        #expect(try await server.client.challenge(for: .attest) == "c1")
        let request = try #require(await server.requests.first)
        #expect(request.url?.query == "purpose=attest")
    }

    @Test func registersAnAttestedKey() async throws {
        let server = ServerStub(["POST /v1/app-attest/keys": [.init(204)]])
        try await server.client.registerKey(id: "K1", attestation: Data([1, 2, 3]), challenge: "c1")
        let body = try #require(await server.requests.first?.httpBody)
        #expect(
            try JSONDecoder().decode([String: String].self, from: body)
                == ["keyId": "K1", "attestation": "AQID", "challenge": "c1"])
    }

    /// An earlier registration was stored but its answer was lost.
    @Test func aKeyAlreadyAttestedIsRegistered() async throws {
        let server = ServerStub(["POST /v1/app-attest/keys": [.init(401, #"{"error":"key already attested"}"#)]])
        try await server.client.registerKey(id: "K1", attestation: Data(), challenge: "c1")
    }

    @Test func aRefusedKeyIsARefusal() async {
        let server = ServerStub(["POST /v1/app-attest/keys": [.init(401, #"{"error":"invalid challenge"}"#)]])
        let error = await #expect(throws: ServerError.self) {
            try await server.client.registerKey(id: "K1", attestation: Data(), challenge: "c1")
        }
        #expect(error?.isRefusal == true)
        guard case .http(401, "invalid challenge"?) = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    /// The bytes server/src/keys.ts rebuilds and checks the assertion against.
    @Test func signsTheChallengeTheMethodThePathAndTheBody() async throws {
        let server = ServerStub([
            "POST /v1/app-attest/challenges": [.init(201, #"{"challenge":"c1"}"#)],
            "PUT /v1/live-activity-starts/ab12": [.init(204)],
        ])
        let request = try SignedRequest.liveActivityStarts(
            token: "ab12",
            LiveActivityStartsRegistration(
                environment: .sandbox, favorites: FavoriteSet(athleteIDs: ["B2", "A1"], nations: ["FRA"]),
                races: ["R2", "R1"]))
        var clientData: Data?
        try await server.client.send(request) { data in
            clientData = data
            return AppAttestAssertion(keyID: "K1", assertion: Data([1, 2, 3]))
        }
        let sent = try #require(await server.requests.last)
        let body = try #require(sent.httpBody)
        #expect(sent.httpMethod == "PUT")
        #expect(
            try JSONDecoder().decode(StartsBody.self, from: body)
                == StartsBody(environment: "sandbox", athletes: ["A1", "B2"], nations: ["FRA"], races: ["R1", "R2"]))
        #expect(clientData == Data("c1\nPUT /v1/live-activity-starts/ab12\n".utf8) + body)
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "X-App-Attest-Key-Id") == "K1")
        #expect(sent.value(forHTTPHeaderField: "X-App-Attest-Assertion") == "AQID")
        #expect(sent.value(forHTTPHeaderField: "X-App-Attest-Challenge") == "c1")
    }

    @Test func aDeletionHasNoBody() async throws {
        let server = ServerStub([
            "POST /v1/app-attest/challenges": [.init(201, #"{"challenge":"c1"}"#)],
            "DELETE /v1/devices/ab12": [.init(204)],
        ])
        try await server.client.send(try SignedRequest.device(token: "ab12", nil)) { clientData in
            #expect(String(decoding: clientData, as: UTF8.self) == "c1\nDELETE /v1/devices/ab12\n")
            return AppAttestAssertion(keyID: "K1", assertion: Data())
        }
        #expect(await server.requests.last?.httpBody == nil)
    }

    @Test func aDeviceRegistrationListsItsCategoriesInOrder() throws {
        let request = try SignedRequest.device(
            token: "ab12",
            DeviceRegistration(
                environment: .production, categories: [.women, .men], cancellation: true, rescheduling: false,
                locale: "fr-FR", timeZone: "Europe/Paris"))
        let body = try JSONDecoder().decode(DeviceBody.self, from: try #require(request.body))
        #expect(
            body
                == DeviceBody(
                    environment: "production", categories: ["SM", "SW"], cancellation: true, rescheduling: false,
                    locale: "fr-FR", timeZone: "Europe/Paris"))
    }

    /// The server tells the app to attest a new key.
    @Test func anUnknownKeyIsReported() async {
        let server = ServerStub([
            "POST /v1/app-attest/challenges": [.init(201, #"{"challenge":"c1"}"#)],
            "DELETE /v1/devices/ab12": [.init(401, #"{"error":"unknown key"}"#)],
        ])
        let error = await #expect(throws: ServerError.self) {
            try await server.client.send(try SignedRequest.device(token: "ab12", nil)) { _ in
                AppAttestAssertion(keyID: "K1", assertion: Data())
            }
        }
        guard case .unknownKey = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    private struct StartsBody: Decodable, Equatable {
        let environment: String
        let athletes: [String]
        let nations: [String]
        let races: [String]
    }

    private struct DeviceBody: Decodable, Equatable {
        let environment: String
        let categories: [String]
        let cancellation: Bool
        let rescheduling: Bool
        let locale: String
        let timeZone: String
    }
}
