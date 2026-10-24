import Foundation
import Testing

@testable import BiathlonKit

/// The server's `/v1/tv-coverage` response, as `server/test/tvCoverage.test.ts` checks it.
struct TVGuideTests {
    let guide = try! TVGuide(
        json: Data(
            """
            {"coverage":[
            {"country":"FR","broadcaster":"La Chaîne L'Équipe","url":"https://www.lequipe.fr/tv/",\
            "from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
            {"country":"GB","broadcaster":"TNT Sports","url":"https://www.tntsports.co.uk/biathlon/",\
            "from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
            {"country":"DE","broadcaster":"ARD","url":"https://www.ardmediathek.de/live",\
            "from":"2026-11-23T00:00:00Z","until":"2026-11-30T00:00:00Z"},
            {"country":"DE","broadcaster":"ZDF","url":"https://www.zdf.de/",\
            "from":"2026-11-30T00:00:00Z","until":"2026-12-07T00:00:00Z"}
            ]}
            """.utf8))

    @Test func listsEachCountryInTheGuidesOrder() {
        let listings = guide.listings(at: date("2026-11-26T15:15:00Z"), firstCountry: nil)
        #expect(listings.map(\.country) == ["FR", "GB", "DE"])
        #expect(listings.map(\.names) == [["La Chaîne L'Équipe"], ["TNT Sports"], ["ARD"]])
        #expect(listings[0].broadcasters[0].url == URL(string: "https://www.lequipe.fr/tv/"))
    }

    /// Whatever the app's language: the viewer's own country only moves to the top.
    @Test(arguments: [("DE", ["DE", "FR", "GB"]), ("GB", ["GB", "FR", "DE"]), ("CH", ["FR", "GB", "DE"])])
    func putsTheViewersCountryFirst(region: String, order: [String]) {
        #expect(guide.listings(at: date("2026-11-26T15:15:00Z"), firstCountry: region).map(\.country) == order)
    }

    /// A period includes its first instant and ends just before its last.
    @Test func followsThePeriods() {
        #expect(guide.listings(at: date("2026-11-29T23:59:59Z"), firstCountry: "DE").first?.names == ["ARD"])
        #expect(guide.listings(at: date("2026-11-30T00:00:00Z"), firstCountry: "DE").first?.names == ["ZDF"])
    }

    @Test func leavesOutCountriesWithNothingAnnounced() {
        #expect(guide.listings(at: date("2026-12-10T15:15:00Z"), firstCountry: nil).map(\.country) == ["FR", "GB"])
        #expect(guide.listings(at: date("2027-04-01T12:00:00Z"), firstCountry: nil).isEmpty)
    }

    @Test func groupsTheBroadcastersOfOneCountry() throws {
        let guide = try TVGuide(
            json: Data(
                """
                {"coverage":[
                {"country":"DE","broadcaster":"ZDF","url":"https://www.zdf.de/","from":"2026-11-30T00:00:00Z","until":"2026-12-07T00:00:00Z"},
                {"country":"FR","broadcaster":"La Chaîne L'Équipe","url":"https://www.lequipe.fr/tv/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
                {"country":"DE","broadcaster":"Eurosport","url":"https://www.eurosport.de/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"}
                ]}
                """.utf8))
        let listings = guide.listings(at: date("2026-12-04T13:15:00Z"), firstCountry: nil)
        #expect(listings.map(\.country) == ["DE", "FR"])
        #expect(listings.first?.names == ["ZDF", "Eurosport"])
    }
}

extension TVGuide.Listing {
    fileprivate var names: [String] { broadcasters.map(\.broadcaster) }
}
