import Foundation

/// What the widget and the Live Activity open in the app: a race, under the app's URL scheme
/// (`biathlon://race/<id>?name=<IBU name>`), so that a tap lands on the race and not on the Home tab.
enum DeepLink: Equatable {
    static let scheme = "biathlon"

    /// A race by its ID, with the IBU's English name for a kind the app doesn't know.
    case race(id: String, name: String)

    var url: URL {
        switch self {
        case .race(let id, let name):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "race"
            components.path = "/\(id)"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            return components.url!
        }
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Self.scheme, components.host == "race"
        else { return nil }
        let id = components.path.trimmingPrefix("/")
        guard !id.isEmpty else { return nil }
        self = .race(id: String(id), name: components.queryItems?.first { $0.name == "name" }?.value ?? "")
    }
}
