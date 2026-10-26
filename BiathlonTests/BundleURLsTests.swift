import Foundation
import Testing

@testable import Biathlon

struct BundleURLsTests {
    @Test func readsTheServerURLFromTheInfoPlist() {
        #expect(Bundle.main.serverURL == URL(string: "https://biathlon-server.fouteox.workers.dev"))
    }

    @Test func hasNoURLForAMissingKey() {
        #expect(Bundle.main.url(forInfoDictionaryKey: "BiathlonMissingURL") == nil)
    }
}
