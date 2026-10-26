import Foundation

extension Bundle {
    /// Base URL of the Cloudflare Worker, from the `BiathlonServerURL` Info.plist key.
    var serverURL: URL? { url(forInfoDictionaryKey: "BiathlonServerURL") }

    /// The privacy policy App Review asks the app to link to, from the `BiathlonPrivacyPolicyURL`
    /// Info.plist key.
    var privacyPolicyURL: URL? { url(forInfoDictionaryKey: "BiathlonPrivacyPolicyURL") }

    /// The URL an Info.plist key holds, `nil` when the key is missing or empty.
    func url(forInfoDictionaryKey key: String) -> URL? {
        guard let raw = object(forInfoDictionaryKey: key) as? String, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
