import Foundation

/// One of a race's rankings in `AnalyticResults`: of the times on the course, on the range or on
/// the shooting mat, over the whole race or a single lap or shooting.
public struct RaceAnalysis: Hashable, Sendable {
    public enum Measure: String, CaseIterable, Hashable, Sendable {
        /// Skiing, the laps adding up to the total.
        case course
        /// From entering the range to leaving it, the shooting included.
        case range
        /// On the shooting mat, within the time on the range.
        case shooting
    }

    public let measure: Measure
    /// The lap, for the course, or the shooting, for the range and the mat; `nil` for the whole race.
    public let segment: Int?

    public init(measure: Measure, segment: Int? = nil) {
        self.measure = measure
        self.segment = segment
    }

    /// `TypeId` of `AnalyticResults`, as biathlonresults.com names its rankings.
    var typeID: String {
        switch (measure, segment) {
        case (.course, nil): "CRST"
        case (.course, let lap?): "CRS\(lap)"
        case (.range, nil): "RNGT"
        case (.range, let shooting?): "RNG\(shooting)"
        case (.shooting, nil): "STTM"
        case (.shooting, let shooting?): "S\(shooting)TM"
        }
    }

    /// The same lap or shooting in `measure`, or the whole race when `race` has no such segment.
    public func measuring(_ measure: Measure, in race: Competition) -> RaceAnalysis {
        let segments = race.segments(of: measure)
        return RaceAnalysis(measure: measure, segment: segment.flatMap { segments.contains($0) ? $0 : nil })
    }

    /// A lap before each shooting and after the last.
    static func segments(of measure: Measure, shootings: Int) -> [Int] {
        Array(1..<(measure == .course ? shootings + 2 : shootings + 1))
    }

    /// Every ranking of a race with `shootings` shootings, each measure's total before its segments.
    static func all(shootings: Int) -> [RaceAnalysis] {
        Measure.allCases.flatMap { measure in
            [RaceAnalysis(measure: measure)]
                + segments(of: measure, shootings: shootings).map { RaceAnalysis(measure: measure, segment: $0) }
        }
    }
}

extension Competition {
    /// Whether the app shows the race's analysis: not for relays, whose rankings list each leg
    /// apart from its team.
    public var hasAnalysisRankings: Bool { hasAnalysis && !isRelay && shootingCount != nil }

    /// The laps, for the course, or the shootings, for the range and the mat.
    public func segments(of measure: RaceAnalysis.Measure) -> [Int] {
        RaceAnalysis.segments(of: measure, shootings: shootingCount ?? 0)
    }
}

extension IBUClient {
    /// The athletes ranked by `analysis`, with their time in the place of the race's.
    public func analysis(_ analysis: RaceAnalysis, raceID: String) async throws -> RaceResults {
        try await get("AnalyticResults", ["RaceId": raceID, "TypeId": analysis.typeID])
    }
}
