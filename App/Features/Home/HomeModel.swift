import BiathlonKit
import Foundation
import Observation

/// Ce que montre l'accueil : la course en direct s'il y en a une, sinon la
/// prochaine, plus les derniers résultats de l'étape en cours.
@Observable
final class HomeModel {
    struct Snapshot {
        /// L'étape la plus récente déjà commencée et la suivante : une course
        /// peut se terminer après la `EndDate` de son étape, et entre deux
        /// étapes il faut à la fois le dernier résultat et la prochaine course.
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
        /// Étape de la course mise en avant (`RaceId` commence par l'`EventId`).
        var event: BiathlonEvent? {
            guard let race = live ?? next ?? latestFinished else { return events.last }
            return events.first { race.id.hasPrefix($0.id) } ?? events.last
        }
    }

    private(set) var state: Loadable<Snapshot> = .loading

    /// Intervalle de rafraîchissement pendant une course en direct.
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
        // Avant la première étape : dernier résultat de la saison précédente.
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
