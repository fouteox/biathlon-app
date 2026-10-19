import BiathlonKit
import SwiftUI

struct StandingsView: View {
    enum Gender: String, CaseIterable, Identifiable {
        case men = "M", women = "W"
        var id: String { rawValue }
        var label: LocalizedStringResource { self == .men ? "Men" : "Women" }
    }

    enum Discipline: String, CaseIterable, Identifiable {
        case total = "TS", sprint = "SP", pursuit = "PU", individual = "IN", massStart = "MS", nations = "NC"
        var id: String { rawValue }
        var label: LocalizedStringResource {
            switch self {
            case .total: "Overall"
            case .sprint: "Sprint"
            case .pursuit: "Pursuit"
            case .individual: "Individual"
            case .massStart: "Mass start"
            case .nations: "Nations"
            }
        }
    }

    @Environment(\.ibu) private var ibu
    @State private var gender = Gender.men
    @State private var discipline = Discipline.total
    @State private var state: Loadable<SeasonStandings> = .loading

    private var key: String { gender.rawValue + discipline.rawValue }

    var body: some View {
        LoadableView(state: state, retry: load) { loaded in
            let season = loaded.season
            let standings = loaded.standings
            List {
                Section {
                    ForEach(standings.rows) { row in
                        StandingRow(row: row)
                    }
                } footer: {
                    if season != .current {
                        Text("Season \(season.displayName): the \(SeasonID.current.displayName) standings will appear after the first race.")
                    } else if let asOf = standings.asOf {
                        Text(asOf)
                    }
                }
            }
            .refreshable { await load() }
        }
        // Filters live in system bars rather than a custom header, so the
        // list scrolls under the glass with the scroll edge effect.
        .safeAreaBar(edge: .top) {
            Picker("Category", selection: $gender) {
                ForEach(Gender.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .toolbar {
            Picker("Discipline", selection: $discipline) {
                ForEach(Discipline.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .navigationTitle("Standings")
        .ibuAttribution()
        .task(id: key) { await load() }
    }

    /// Before the first race the season's standings are empty, so the
    /// previous season's are shown instead.
    private func load() async {
        state = .loading
        do {
            let current = SeasonID.current
            let standings = try await ibu.cupStandings(cupID: Cup.worldCupID(current, "S" + key))
            if standings.rows.isEmpty {
                let previous = current.previous
                state = .loaded(SeasonStandings(season: previous, standings: try await ibu.cupStandings(cupID: Cup.worldCupID(previous, "S" + key))))
            } else {
                state = .loaded(SeasonStandings(season: current, standings: standings))
            }
        } catch {
            state = .failed(error)
        }
    }
}

private struct SeasonStandings {
    let season: SeasonID
    let standings: CupStandings
}

private struct StandingRow: View {
    let row: CupRow

    var body: some View {
        let content = HStack(spacing: 12) {
            Text(row.rank ?? "–")
                .font(.headline.monospacedDigit())
                .frame(width: 36, alignment: .leading)
            Text(Nation.flag(row.isNation ? row.nation ?? row.name : row.nation))
            Text(row.shortName ?? row.name)
            if row.bibColors.contains("yellow") {
                Image(systemName: "tshirt.fill").foregroundStyle(.yellow)
            }
            Spacer()
            if let change = row.rankChange, change != 0 {
                Image(systemName: change < 0 ? "arrow.up" : "arrow.down")
                    .font(.caption)
                    .foregroundStyle(change < 0 ? .green : .red)
            }
            Text(row.score ?? "")
                .font(.subheadline.monospacedDigit().bold())
            if row.isNation, let nation = row.nation {
                FavoriteButton(kind: .nation, key: nation, name: row.name, nation: nation)
            }
        }
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) { content }
        } else {
            content
        }
    }
}
