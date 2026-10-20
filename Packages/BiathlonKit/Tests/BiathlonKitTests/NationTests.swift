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
}
