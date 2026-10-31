import Foundation
import Testing

@testable import BiathlonKit

struct RaceAnalysisTests {
    /// A race with `shootings` shootings, whose analysis the IBU publishes or not.
    private static func race(shootings: Int, hasAnalysis: Bool = true, legs: Int = 0) throws -> Competition {
        try decode(
            """
            {"RaceId":"BT2526SWRLCP01SMSP","ShortDescription":"Men 10 km Sprint","StartTime":"2025-12-06T15:30:00Z",\
            "StatusId":11,"HasAnalysis":\(hasAnalysis),"NrShootings":\(shootings),"NrLegs":\(legs)}
            """)
    }

    @Test(arguments: [
        (RaceAnalysis(measure: .course), "CRST"), (RaceAnalysis(measure: .course, segment: 3), "CRS3"),
        (RaceAnalysis(measure: .range), "RNGT"), (RaceAnalysis(measure: .range, segment: 2), "RNG2"),
        (RaceAnalysis(measure: .shooting), "STTM"), (RaceAnalysis(measure: .shooting, segment: 4), "S4TM"),
    ])
    func eachRankingHasItsType(analysis: RaceAnalysis, typeID: String) {
        #expect(analysis.typeID == typeID)
    }

    /// A lap before each shooting and after the last.
    @Test func lapsSurroundTheShootings() throws {
        let sprint = try Self.race(shootings: 2)
        #expect(sprint.segments(of: .course) == [1, 2, 3])
        #expect(sprint.segments(of: .range) == [1, 2])
        #expect(sprint.segments(of: .shooting) == [1, 2])
    }

    @Test func everyRankingOfARace() {
        #expect(
            RaceAnalysis.all(shootings: 1) == [
                .init(measure: .course), .init(measure: .course, segment: 1), .init(measure: .course, segment: 2),
                .init(measure: .range), .init(measure: .range, segment: 1),
                .init(measure: .shooting), .init(measure: .shooting, segment: 1),
            ])
    }

    /// The same lap or shooting, if the other measure has it, else the whole race.
    @Test func anotherMeasureKeepsTheSegmentItHas() throws {
        let sprint = try Self.race(shootings: 2)
        let secondLap = RaceAnalysis(measure: .course, segment: 2)
        #expect(secondLap.measuring(.range, in: sprint) == .init(measure: .range, segment: 2))
        let lastLap = RaceAnalysis(measure: .course, segment: 3)
        #expect(lastLap.measuring(.shooting, in: sprint) == .init(measure: .shooting))
        #expect(RaceAnalysis(measure: .range).measuring(.course, in: sprint) == .init(measure: .course))
    }

    /// Relays rank their legs apart from their teams, which the app doesn't show yet.
    @Test func onlyIndividualRacesWithAnAnalysisHaveRankings() throws {
        #expect(try Self.race(shootings: 4).hasAnalysisRankings)
        #expect(try !Self.race(shootings: 4, hasAnalysis: false).hasAnalysisRankings)
        #expect(try !Self.race(shootings: 2, legs: 4).hasAnalysisRankings)
    }

    @Test func fetchesARanking() async throws {
        let client = stubClient([
            "AnalyticResults?RaceId=BT2526SWRLCP01SMSP&TypeId=RNG2": """
            {"RaceId":"BT2526SWRLCP01SMSP","IsStartList":false,"IsResult":true,"Results":[
            {"IBUId":"BTITA1","Name":"GIACOMEL Tommaso","Nat":"ITA","Rank":"1","Shootings":"1+0",\
            "TotalTime":"39.0","Behind":"0.0"}]}
            """
        ])

        let ranking = try await client.analysis(.init(measure: .range, segment: 2), raceID: "BT2526SWRLCP01SMSP")

        #expect(ranking.isResult)
        #expect(ranking.rows.map(\.totalTime) == ["39.0"])
    }
}
