import Foundation

extension IBUClient {
    /// The client for IBU's API over URLSession. jextract cannot bind
    /// `init(baseURL:transport:)`, whose transport is a closure, so Java gets its client here.
    public static func live() -> IBUClient {
        IBUClient()
    }
}
