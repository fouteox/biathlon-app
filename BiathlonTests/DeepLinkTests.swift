import Foundation
import Testing

@testable import Biathlon

struct DeepLinkTests {
    @Test func aRaceLinkComesBackAsItWent() throws {
        let link = DeepLink.race(id: "BT2627SWRLCP01SMSP", name: "Men 10 km Sprint")
        #expect(link.url.absoluteString == "biathlon://race/BT2627SWRLCP01SMSP?name=Men%2010%20km%20Sprint")
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func anotherSchemeOrHostIsNoLink() throws {
        #expect(DeepLink(url: try #require(URL(string: "https://race/BT2627SWRLCP01SMSP"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "biathlon://athlete/BTFRA1"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "biathlon://race/"))) == nil)
    }
}
