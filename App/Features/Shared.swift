import BiathlonKit
import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case event(BiathlonEvent)
    case race(Competition)
    case athlete(id: String, name: String)
}

extension View {
    func navigationDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .event(let event): EventView(event: event)
            case .race(let race): RaceView(race: race)
            case .athlete(let id, let name): AthleteView(athleteID: id, name: name)
            }
        }
    }

    /// Source credit, as offered in the email to the IBU. A bar with no
    /// background: content scrolls beneath it with the system scroll edge
    /// effect (Liquid Glass).
    func ibuAttribution() -> some View {
        safeAreaBar(edge: .bottom) {
            Text("Données : IBU Datacenter · biathlonresults.com")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }
}

/// Generic loading state for screens.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(any Error)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }
}

struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Chargement impossible", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Réessayer") { Task { await retry() } }
            }
        case .loaded(let value):
            content(value)
        }
    }
}

enum Nation {
    /// IOC codes to ISO codes, for flags.
    private static let iso: [String: String] = [
        "AUT": "AT", "BEL": "BE", "BUL": "BG", "CAN": "CA", "CHN": "CN", "CZE": "CZ",
        "EST": "EE", "FIN": "FI", "FRA": "FR", "GER": "DE", "GBR": "GB", "ITA": "IT",
        "JPN": "JP", "KAZ": "KZ", "KOR": "KR", "LAT": "LV", "LTU": "LT", "MDA": "MD",
        "NOR": "NO", "POL": "PL", "ROU": "RO", "SLO": "SI", "SUI": "CH", "SVK": "SK",
        "SWE": "SE", "UKR": "UA", "USA": "US", "AUS": "AU", "CRO": "HR", "SRB": "RS",
        "ARG": "AR", "BRA": "BR", "DEN": "DK", "ESP": "ES", "GRE": "GR", "HUN": "HU",
        "ISL": "IS", "MGL": "MN", "NED": "NL", "IRL": "IE",
    ]

    static func flag(_ code: String?) -> String {
        guard let code, let iso = iso[code.uppercased()] else { return "🏳️" }
        return iso.unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

extension Competition.State {
    var label: String {
        switch self {
        case .scheduled: "À venir"
        case .live: "En direct"
        case .delayed: "Retardée"
        case .cancelled: "Annulée"
        case .finished: "Terminée"
        }
    }

    var tint: Color {
        switch self {
        case .live: .red
        case .delayed: .orange
        case .cancelled: .gray
        case .finished: .secondary
        case .scheduled: .blue
        }
    }
}

struct RaceRow: View {
    let race: Competition

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(race.shortDescription).font(.headline)
                Text(race.startTime, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(race.state.label)
                .font(.caption.bold())
                .foregroundStyle(race.state.tint)
        }
    }
}
