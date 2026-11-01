import ActivityKit
import BiathlonKit
import SwiftData
import SwiftUI
import os

struct RaceView: View {
    let race: Competition
    @Environment(\.ibu) private var ibu
    @Environment(\.server) private var server
    @Environment(LiveActivities.self) private var liveActivities
    @State private var loader = Loader<RaceResults>()
    @State private var tvGuide = Loader<TVGuide>()
    /// When the results last loaded, which the list says while the race is live.
    @State private var updatedAt: Date?
    @State private var liveActivityFailed = false
    @State private var liveActivityFailure = ""
    @State private var calendarEntry: RaceCalendarEntry?
    @Query private var favorites: [Favorite]

    /// The race as its results last gave it, or as the calendar did.
    private var latest: Competition { loader.state.value?.competition ?? race }

    private var isLive: Bool { latest.state == .live }

    var body: some View {
        LoadableView(state: loader.state, retry: load) { results in
            let competition = results.competition ?? race
            List {
                // The title already names the race: where and when it is held, in one row, with
                // its state once it is no longer upcoming.
                Section {
                    LabeledContent {
                        competition.state.badge
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let event = results.event {
                                EventPlace(event: event)
                            }
                            RaceStart(race: competition)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                // Only while it can still be watched live.
                if competition.state.canBeFollowedLive, let listings = tvListings(of: competition) {
                    TVCoverageSection(listings: listings)
                }
                if !results.rows.isEmpty {
                    Section {
                        ForEach(results.standings) { row in
                            if competition.isRelay {
                                DisclosureGroup {
                                    ForEach(results.legs(of: row)) { leg in
                                        ResultLink(row: leg, highlighted: isFavorite(leg, in: results))
                                    }
                                } label: {
                                    ResultLine(row: row, highlighted: isFavorite(row, in: results))
                                }
                            } else {
                                ResultLink(row: row, highlighted: isFavorite(row, in: results))
                            }
                        }
                    } header: {
                        Self.listTitle(of: results, live: isLive)
                    } footer: {
                        // The list changes under the reader while the race is live: when it last did.
                        if isLive, let updatedAt {
                            Text("Updated at \(updatedAt, format: .dateTime.hour().minute())")
                        }
                    }
                } else {
                    // In the list, below the sections above it, rather than over them.
                    Section {
                        if competition.state == .cancelled {
                            ContentUnavailableView("Race cancelled", systemImage: "xmark.circle")
                        } else {
                            ContentUnavailableView("No start list yet", systemImage: "clock")
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle(race.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A race has dozens of rows: the analysis sits in the bar rather than below them all.
            if let analysis {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: analysis) {
                        Label("Course, range and shooting times", systemImage: "stopwatch")
                    }
                }
            }
            if let podium {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: String(localized: podium))
                        .accessibilityIdentifier("share")
                }
            }
            if latest.state == .scheduled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                        calendarEntry = RaceCalendarEntry(race: latest, event: loader.state.value?.event)
                    }
                }
            }
            // A followed race keeps its toggle to stop following.
            if liveActivities.isAvailable, canBeFollowed || liveActivities.followedRaceIDs.contains(race.id) {
                // A state, apart from the actions before it.
                if analysis != nil || podium != nil || latest.state == .scheduled {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Live Activity", systemImage: "dot.radiowaves.left.and.right", isOn: following)
                }
            }
        }
        .sheet(item: $calendarEntry) { entry in
            RaceCalendarEditor(entry: entry).ignoresSafeArea()
        }
        .alert("Unable to start the Live Activity", isPresented: $liveActivityFailed) {
        } message: {
            Text(liveActivityFailure)
        }
        .task { await load() }
        .task {
            guard let server else { return }
            await tvGuide.load { try await server.tvGuide() }
        }
        .refreshingWhileLive(isLive, action: load)
    }

    /// The analysis of the results, once they are in and the IBU has timed the race.
    private var analysis: Route? {
        guard let results = loader.state.value, results.isResult, latest.hasAnalysisRankings else { return nil }
        return .analysis(latest)
    }

    /// The podium in a sentence, to share once the results are in.
    private var podium: LocalizedStringResource? {
        guard let results = loader.state.value else { return nil }
        return RaceSummary.podium(of: latest, at: results.event, results: results)
    }

    /// Only what the response says the rows are: before the start list is out, the API can
    /// return provisional rows that are neither. Live, the title says so.
    private static func listTitle(of results: RaceResults, live: Bool) -> Text? {
        let title: Text? =
            if results.isResult {
                Text("Results")
            } else if results.isStartList {
                Text("Start list")
            } else {
                nil
            }
        guard live else { return title }
        guard let title else { return Text("Live") }
        return Text("\(title) · \(Text("Live"))")
    }

    /// Nothing until the guide loads, or without a server, the guide then never loading.
    private func tvListings(of competition: Competition) -> TVGuide.Listings? {
        tvGuide.state.value?.listings(at: competition.startTime, home: Locale.current.region?.identifier)
    }

    private func isFavorite(_ row: ResultRow, in results: RaceResults) -> Bool {
        results.isFavorite(row, in: FavoriteSet(favorites))
    }

    /// While the calendar lists the race as upcoming or live, as on the server, which opens its
    /// channels: the results can lag behind the calendar, as for a cancellation called off.
    /// The results, which the screen reloads, show a race reinstated while it is open.
    private var canBeFollowed: Bool {
        [race, loader.state.value?.competition].contains { $0?.state.canBeFollowedLive == true }
    }

    private var following: Binding<Bool> {
        Binding {
            liveActivities.followedRaceIDs.contains(race.id)
        } set: { follow in
            Task {
                guard follow else { return await liveActivities.stopFollowing(raceID: race.id) }
                do {
                    try await liveActivities.follow(
                        raceID: race.id, name: race.shortDescription, startTime: latest.startTime)
                } catch {
                    Logger.notifications.error(
                        "Starting the Live Activity failed: \(String(describing: error), privacy: .public)")
                    liveActivityFailure = Self.message(for: error)
                    liveActivityFailed = true
                }
            }
        }
    }

    /// ActivityKit and network errors carry a plain system message; the others go to the log.
    private static func message(for error: any Error) -> String {
        switch error {
        case LiveActivities.Failure.noChannel:
            String(localized: "This race can't be followed live yet. Try again in a few minutes.")
        case LiveActivities.Failure.ended:
            String(localized: "This race is over.")
        case is ActivityAuthorizationError, is URLError:
            error.localizedDescription
        default:
            String(localized: "Live Activities are temporarily unavailable.")
        }
    }

    private func load() async {
        if await loader.load({ try await ibu.results(raceID: race.id) }) {
            updatedAt = .now
        }
    }
}

/// A result row leading to its athlete, when it has one.
struct ResultLink: View {
    let row: ResultRow
    let highlighted: Bool

    var body: some View {
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) {
                ResultLine(row: row, highlighted: highlighted)
            }
        } else {
            ResultLine(row: row, highlighted: highlighted)
        }
    }
}

/// A race known by its ID alone, such as an athlete's result: found among its event's races first.
struct RaceByIDView: View {
    let raceID: String
    let title: String
    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<Competition>()

    var body: some View {
        LoadableView(state: loader.state, retry: load) { race in
            RaceView(race: race)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        await loader.load { try await ibu.race(id: raceID) }
    }
}
