import Foundation

extension Bundle {
    /// Base URL of the Cloudflare Worker, from the `BiathlonServerURL` Info.plist key.
    var serverURL: URL? {
        guard let raw = object(forInfoDictionaryKey: "BiathlonServerURL") as? String, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
