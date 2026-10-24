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

    @Test func setsTheViewersCountryApart() {
        let listings = guide.listings(at: date("2026-11-26T15:15:00Z"), home: "FR")
        #expect(listings.home?.country == "FR")
        #expect(listings.home?.names == ["La Chaîne L'Équipe"])
        #expect(listings.home?.broadcasters.first?.url == URL(string: "https://www.lequipe.fr/tv/"))
        #expect(listings.others.map(\.country) == ["GB", "DE"])
        #expect(listings.others.map(\.names) == [["TNT Sports"], ["ARD"]])
    }

    /// Whatever the app's language: the other countries keep the guide's order.
    @Test(arguments: [("DE", ["FR", "GB"]), ("GB", ["FR", "DE"])])
    func keepsTheOthersInTheGuidesOrder(region: String, others: [String]) {
        let listings = guide.listings(at: date("2026-11-26T15:15:00Z"), home: region)
        #expect(listings.home?.country == region)
        #expect(listings.others.map(\.country) == others)
    }

    /// A viewer elsewhere, or with no region, has no country of their own in the guide.
    @Test(arguments: ["CH", nil] as [String?])
    func hasNoHomeOutsideTheGuidesCountries(region: String?) {
        let listings = guide.listings(at: date("2026-11-26T15:15:00Z"), home: region)
        #expect(listings.home == nil)
        #expect(listings.others.map(\.country) == ["FR", "GB", "DE"])
    }

    /// A period includes its first instant and ends just before its last.
    @Test func followsThePeriods() {
        #expect(guide.listings(at: date("2026-11-29T23:59:59Z"), home: "DE").home?.names == ["ARD"])
        #expect(guide.listings(at: date("2026-11-30T00:00:00Z"), home: "DE").home?.names == ["ZDF"])
    }

    @Test func leavesOutCountriesWithNothingAnnounced() {
        let listings = guide.listings(at: date("2026-12-10T15:15:00Z"), home: "DE")
        #expect(listings.home == nil)
        #expect(listings.others.map(\.country) == ["FR", "GB"])
        #expect(guide.listings(at: date("2027-04-01T12:00:00Z"), home: "FR").isEmpty)
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
        let listings = guide.listings(at: date("2026-12-04T13:15:00Z"), home: "DE")
        #expect(listings.home?.names == ["ZDF", "Eurosport"])
        #expect(listings.others.map(\.country) == ["FR"])
    }
}

extension TVGuide.Listing {
    fileprivate var names: [String] { broadcasters.map(\.broadcaster) }
}
