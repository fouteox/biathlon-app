import Foundation
import Testing

@testable import Biathlon

struct RaceStartTests {
    /// The calendar goes back to 1957-58: a race's start says its year.
    @Test func namesTheYear() {
        let start = Date(timeIntervalSince1970: 1_795_706_100)  // 2026-11-26 15:15 UTC
        #expect(start.formatted(RaceStart.format.locale(Locale(identifier: "en_US"))).contains("2026"))
    }
}
