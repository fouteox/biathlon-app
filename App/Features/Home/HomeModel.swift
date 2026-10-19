import BiathlonKit
import Foundation
import Observation

/// What the home screen shows: the live race if there is one, otherwise the
/// next one, plus the latest results of the current event.
@Observable
final class HomeModel {
    struct Snapshot {
        /// The most recent event already started and the next one: a race
        /// can finish after its event's `EndDate`, and between two events
        /// both the latest result and the next race are needed.
        var events: [BiathlonEvent] = []
        var races: [Competition] = []
        var liveResults: RaceResults?
        var latestResults: RaceResults?

        var live: Competition? { races.first { $0.state == .live } }
        var next: Competition? {
            races.filter { $0.state == .scheduled || $0.state == .delayed }
                .min { $0.startTime < $1.startTime }
        }
        var latestFinished: Competition? {
            races.filter { $0.state == .finished }.max { $0.startTime < $1.startTime }
        }
        /// Event of the featured race (`RaceId` starts with the `EventId`).
        var event: BiathlonEvent? {
            guard let race = live ?? next ?? latestFinished else { return events.last }
            return events.first { race.id.hasPrefix($0.id) } ?? events.last
        }
    }

    private(set) var state: Loadable<Snapshot> = .loading

    /// Refresh interval while a race is live.
    static let livePollInterval: Duration = .seconds(20)

    func load(using client: IBUClient, now: Date = .now) async {
        do {
            state = .loaded(try await fetch(client, now: now))
        } catch is CancellationError {
            return
        } catch {
            if state.value == nil { state = .failed(error) }
        }
    }

    var isLive: Bool { state.value?.live != nil }

    private func fetch(_ client: IBUClient, now: Date) async throws -> Snapshot {
        var snapshot = Snapshot()
        let season = SeasonID.containing(now)
        let sorted = try await client.events(season: season).sorted { $0.startDate < $1.startDate }
        let upcoming = sorted.first { $0.startDate > now }
        var started = sorted.last { $0.startDate <= now }
        // Before the first event: latest result of the previous season.
        if started == nil {
            started = try await client.events(season: season.previous).max { $0.startDate < $1.startDate }
        }
        snapshot.events = [started, upcoming].compactMap(\.self)

        var races: [Competition] = []
        for event in snapshot.events {
            races += try await client.competitions(eventID: event.id)
        }
        snapshot.races = races.sorted { $0.startTime < $1.startTime }
        if let live = snapshot.live {
            snapshot.liveResults = try await client.results(raceID: live.id)
        }
        if let finished = snapshot.latestFinished {
            snapshot.latestResults = try await client.results(raceID: finished.id)
        }
        return snapshot
    }
}
