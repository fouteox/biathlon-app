import Foundation

extension Bundle {
    /// Base URL of the Cloudflare Worker, from the `BiathlonServerURL` Info.plist key.
    var serverURL: URL? { url(forInfoDictionaryKey: "BiathlonServerURL") }

    /// The privacy policy App Review asks the app to link to, from the `BiathlonPrivacyPolicyURL`
    /// Info.plist key.
    var privacyPolicyURL: URL? { url(forInfoDictionaryKey: "BiathlonPrivacyPolicyURL") }

    /// How the app names itself to Wikimedia, which asks for a way to reach its developer:
    /// `Biathlon/1.0 (https://github.com/fouteox/biathlon-app)`.
    var wikimediaUserAgent: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return "Biathlon/\(version) (https://github.com/fouteox/biathlon-app)"
    }

    /// The URL an Info.plist key holds, `nil` when the key is missing or empty.
    func url(forInfoDictionaryKey key: String) -> URL? {
        guard let raw = object(forInfoDictionaryKey: key) as? String, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
