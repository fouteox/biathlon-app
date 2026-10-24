import Testing

@testable import BiathlonKit

struct NationTests {
    @Test(arguments: [("FRA", "🇫🇷"), ("GER", "🇩🇪"), ("SUI", "🇨🇭"), ("SLO", "🇸🇮"), ("nor", "🇳🇴"), ("AND", "🇦🇩"), ("KOS", "🇽🇰")])
    func iocCodesBecomeFlags(code: String, flag: String) {
        #expect(Nation.flag(code) == flag)
    }

    /// Greenland races in the World Cup (women's sprint, Le Grand-Bornand 2025) under an
    /// IBU code that isn't an IOC one.
    @Test func greenlandHasItsFlag() {
        #expect(Nation.flag("GRL") == "🇬🇱")
    }

    /// `AIN`, Individual Neutral Athletes, has no flag.
    @Test func unknownCodeHasNoFlag() {
        #expect(Nation.flag("AIN") == nil)
        #expect(Nation.flag("XXX") == nil)
        #expect(Nation.flag(nil) == nil)
    }

    @Test func titlesStartWithTheFlagWhenKnown() {
        #expect(Nation.titled("Hochfilzen", nation: "AUT") == "🇦🇹 Hochfilzen")
        #expect(Nation.titled("Hochfilzen", nation: "XXX") == "Hochfilzen")
        #expect(Nation.titled("Hochfilzen", nation: nil) == "Hochfilzen")
    }

    /// The TV guide names countries by ISO code.
    @Test(arguments: [("FR", "🇫🇷"), ("GB", "🇬🇧"), ("de", "🇩🇪")])
    func isoCodesBecomeFlags(code: String, flag: String) {
        #expect(Nation.flag(region: code) == flag)
    }

    @Test(arguments: ["", "F", "FRA", "F1"])
    func malformedISOCodeHasNoFlag(code: String) {
        #expect(Nation.flag(region: code) == nil)
        #expect(Nation.titled("Nowhere", region: code) == "Nowhere")
    }

    @Test func countryNamesStartWithTheirFlag() {
        #expect(Nation.titled("Allemagne", region: "DE") == "🇩🇪 Allemagne")
    }
}
