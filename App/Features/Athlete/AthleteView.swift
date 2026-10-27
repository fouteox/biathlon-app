import BiathlonKit
import SwiftUI

struct AthleteView: View {
    let athleteID: String
    let name: String

    @Environment(\.ibu) private var ibu
    @State private var bio = Loader<AthleteBio>()
    /// Loaded on its own: the profile shows without waiting for it, and without it.
    @State private var history = Loader<AthleteHistory>()
    /// The season picked in the toolbar; until then, the one the history opens on.
    @State private var pickedSeason: SeasonID?
    /// The athlete's row in the season's overall standings, `nil` when they scored no points.
    @State private var standing = Loader<CupRow?>()
    /// Counts the pulls to refresh, which reload the standing through its own task: a new
    /// season cancels that task, so a refresh of the previous one can't land after it.
    @State private var refreshes = 0
    @ScaledMetric private var photoSize = 72.0

    var body: some View {
        LoadableView(state: bio.state, retry: load) { bio in
            List {
                Section {
                    RowStack(spacing: 16) { _ in
                        AsyncImage(url: bio.photoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: photoSize, height: photoSize)
                        .clipShape(.circle)
                        // The name beside it says who it is.
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bio.fullName).font(.title3.bold())
                            if bio.isDeceased {
                                Text(.deceased(bio.gender)).foregroundStyle(.secondary)
                            }
                            if let birthdate = bio.birthdate {
                                Text(birthdate, format: Self.birthdateStyle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let nation = bio.nation {
                    // The nation opens on the athlete's standings, the men's when the IBU gives no gender.
                    Section {
                        NavigationLink(
                            Nation.namedTitle(nation),
                            value: Route.nation(code: nation, category: bio.gender?.category ?? .men))
                        FavoriteButton(
                            kind: .nation, key: nation, name: Nation.localizedName(nation), nation: nation,
                            subject: Nation.namedTitle(nation))
                    }
                }
                if let history = history.state.value, let season {
                    if case .loaded(let row) = standing.state {
                        Section("World Cup standings") {
                            if let row {
                                // A labeled row otherwise also exposes its label on its own.
                                LabeledContent("Overall", value: row.rank ?? "–")
                                    .accessibilityElement(children: .combine)
                                if let score = row.score {
                                    LabeledContent("Points", value: score)
                                        .accessibilityElement(children: .combine)
                                }
                            } else {
                                Text("Not ranked").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Results") {
                        let results = history.results(in: season)
                        if results.isEmpty {
                            ContentUnavailableView("No World Cup results this season", systemImage: "list.number")
                        }
                        ForEach(results) { result in
                            RowStack { _ in
                                VStack(alignment: .leading) {
                                    Text(RaceKind.title(ofRace: result.raceID ?? "", ibuName: result.competition ?? ""))
                                    if let place = result.place {
                                        Text(place).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                RankText(rank: result.rank)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .refreshable {
                refreshes += 1
                await load()
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let history = history.state.value {
                Picker("Season", selection: seasonSelection(default: history.initialSeason)) {
                    ForEach(history.seasons, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            FavoriteButton(kind: .athlete, key: athleteID, name: name, nation: bio.state.value?.nation)
        }
        .task { await load() }
        // Only a new season shows the standing as loading.
        .onChange(of: standingQuery) { standing.reset() }
        .task(id: StandingLoad(query: standingQuery, refresh: refreshes)) { await loadStanding() }
    }

    /// The season shown: the one picked, or the one the history opens on.
    private var season: SeasonID? {
        pickedSeason ?? history.state.value?.initialSeason
    }

    private func seasonSelection(default initial: SeasonID) -> Binding<SeasonID> {
        Binding {
            pickedSeason ?? initial
        } set: {
            pickedSeason = $0
        }
    }

    /// The standing shown depends on the season and on the athlete's category, once both are known.
    private var standingQuery: StandingQuery? {
        guard let season, let category = bio.state.value?.gender?.category else { return nil }
        return StandingQuery(season: season, category: category)
    }

    private struct StandingQuery: Hashable {
        let season: SeasonID
        let category: RaceCategory
    }

    private struct StandingLoad: Hashable {
        let query: StandingQuery?
        let refresh: Int
    }

    /// Birthdates arrive at midnight UTC, so they are formatted in UTC.
    private static let birthdateStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.day().month(.wide).year()
        style.timeZone = .gmt
        return style
    }()

    private func load() async {
        async let bioLoad: Void = bio.load { try await ibu.athlete(id: athleteID) }
        async let historyLoad: Void = history.load {
            AthleteHistory(results: try await ibu.athleteResults(id: athleteID), now: .now)
        }
        _ = await (bioLoad, historyLoad)
    }

    private func loadStanding() async {
        guard let query = standingQuery else { return }
        await standing.load {
            try await ibu.worldCupStanding(of: athleteID, category: query.category, season: query.season)
        }
    }
}
