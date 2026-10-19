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
            List {
                Section {
                    RaceRow(race: results.competition ?? race)
                    if results.isStartList && !results.isResult {
                        Text("Start list").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(results.standings) { row in
                        if results.competition?.isRelay ?? race.isRelay {
                            DisclosureGroup {
                                ForEach(results.legs(of: row)) { leg in athleteLink(leg) }
                            } label: {
                                ResultLine(row: row, highlighted: isFavorite(row))
                            }
                        } else {
                            athleteLink(row)
                        }
                    }
                }
            }
            .refreshable { await load() }
            .overlay {
                if results.rows.isEmpty {
                    ContentUnavailableView("No start list yet", systemImage: "clock")
                }
            }
        }
        .navigationTitle(race.shortDescription)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let state = liveState, state.phase.canBeFollowedLive, liveActivities.isAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Live Activity", systemImage: "dot.radiowaves.left.and.right", isOn: following(state))
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
    private func athleteLink(_ row: ResultRow) -> some View {
        if let id = row.athleteID {
            NavigationLink(value: Route.athlete(id: id, name: row.name)) {
                ResultLine(row: row, highlighted: isFavorite(row))
            }
        } else {
            ResultLine(row: row, highlighted: isFavorite(row))
        }
    }

    private func isFavorite(_ row: ResultRow) -> Bool {
        FavoriteSet(favorites).contains(row)
    }

    private var liveState: RaceLiveState? { loader.state.value.flatMap(RaceLiveState.init) }

    private func following(_ state: RaceLiveState) -> Binding<Bool> {
        Binding {
            liveActivities.followedRaceIDs.contains(race.id)
        } set: { follow in
            Task {
                guard follow else { return await liveActivities.stopFollowing(raceID: race.id) }
                do {
                    try await liveActivities.follow(
                        RaceActivityAttributes(raceID: race.id, name: race.shortDescription), state: state)
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
        case is ActivityAuthorizationError, is URLError:
            error.localizedDescription
        default:
            String(localized: "Live Activities are temporarily unavailable.")
        }
    }

    private func load() async {
        await loader.load { try await ibu.results(raceID: race.id) }
        if let liveState { await liveActivities.update(raceID: race.id, with: liveState) }
    }
}
