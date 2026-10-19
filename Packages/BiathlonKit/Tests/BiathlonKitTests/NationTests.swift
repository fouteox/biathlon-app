import Testing

@testable import BiathlonKit

struct NationTests {
    @Test(arguments: [("FRA", "🇫🇷"), ("GER", "🇩🇪"), ("SUI", "🇨🇭"), ("SLO", "🇸🇮"), ("nor", "🇳🇴")])
    func iocCodesBecomeFlags(code: String, flag: String) {
        #expect(Nation.flag(code) == flag)
    }

    @Test func unknownCodeHasNoFlag() {
        #expect(Nation.flag("XXX") == nil)
        #expect(Nation.flag(nil) == nil)
    }
}
