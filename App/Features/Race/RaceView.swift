import ActivityKit
import BiathlonKit
import SwiftData
import SwiftUI
import os

struct RaceView: View {
    let race: Competition
    @Environment(\.ibu) private var ibu
    @Environment(LiveActivities.self) private var liveActivities
    @State private var loader = Loader<RaceResults>()
    @State private var liveActivityFailed = false
    @State private var liveActivityFailure = ""
    @Query private var favorites: [Favorite]

    private var isLive: Bool {
        (loader.state.value?.competition ?? race).state == .live
    }

    var body: some View {
        LoadableView(state: loader.state, retry: load) { results in
            let competition = results.competition ?? race
            List {
                // The title already names the race.
                Section {
                    LabeledContent {
                        competition.state.badge
                    } label: {
                        RaceStart(race: competition)
                    }
                }
                if !results.rows.isEmpty {
                    Section {
                        ForEach(results.standings) { row in
                            if competition.isRelay {
                                DisclosureGroup {
                                    ForEach(results.legs(of: row)) { leg in athleteLink(leg, in: results) }
                                } label: {
                                    ResultLine(row: row, highlighted: isFavorite(row, in: results))
                                }
                            } else {
                                athleteLink(row, in: results)
                            }
                        }
                    } header: {
                        Self.listTitle(of: results)
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if results.rows.isEmpty {
                    if competition.state == .cancelled {
                        ContentUnavailableView("Race cancelled", systemImage: "xmark.circle")
                    } else {
                        ContentUnavailableView("No start list yet", systemImage: "clock")
                    }
                }
            }
        }
        .navigationTitle(race.shortDescription)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A followed race keeps its toggle to stop following.
            if liveActivities.isAvailable, canBeFollowed || liveActivities.followedRaceIDs.contains(race.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Live Activity", systemImage: "dot.radiowaves.left.and.right", isOn: following)
                }
            }
        }
        .alert("Unable to start the Live Activity", isPresented: $liveActivityFailed) {
        } message: {
            Text(liveActivityFailure)
        }
        .task { await load() }
        .refreshingWhileLive(isLive, action: load)
    }

    @ViewBuilder
    private func athleteLink(_ row: ResultRow, in results: RaceResults) -> some View {
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) {
                ResultLine(row: row, highlighted: isFavorite(row, in: results))
            }
        } else {
            ResultLine(row: row, highlighted: isFavorite(row, in: results))
        }
    }

    /// Only what the response says the rows are: before the start list is out, the API can
    /// return provisional rows that are neither.
    private static func listTitle(of results: RaceResults) -> Text? {
        if results.isResult {
            Text("Results")
        } else if results.isStartList {
            Text("Start list")
        } else {
            nil
        }
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
                    try await liveActivities.follow(raceID: race.id, name: race.shortDescription)
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
            String(localized: "This race can't be followed live yet. Try again closer to the start.")
        case LiveActivities.Failure.ended:
            String(localized: "This race is over.")
        case is ActivityAuthorizationError, is URLError:
            error.localizedDescription
        default:
            String(localized: "Live Activities are temporarily unavailable.")
        }
    }

    private func load() async {
        await loader.load { try await ibu.results(raceID: race.id) }
    }
}
