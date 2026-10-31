import BiathlonKit
import Foundation
import Testing

@testable import Biathlon

struct BundleURLsTests {
    @Test func readsTheServerURLFromTheInfoPlist() {
        #expect(Bundle.main.serverURL == URL(string: "https://biathlon-server.fouteox.workers.dev"))
    }

    /// Wikimedia asks for the app's name and version, with a way to reach its developer.
    @Test func namesTheAppToWikimedia() throws {
        let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(Bundle.main.wikimediaUserAgent == "Biathlon/\(version) (https://github.com/fouteox/biathlon-app)")
    }

    @Test func hasNoURLForAMissingKey() {
        #expect(Bundle.main.url(forInfoDictionaryKey: "BiathlonMissingURL") == nil)
    }

    @Test func readsTheIBUThroughTheServersCache() throws {
        let server = ServerClient(baseURL: try #require(URL(string: "https://example.com")))
        #expect(IBUClient(cachedBy: server).baseURL == URL(string: "https://example.com/ibu/"))
    }

    @Test func readsTheIBUDirectlyWithoutAServer() {
        #expect(IBUClient(cachedBy: nil).baseURL == IBUClient.ibuBaseURL)
    }
}
