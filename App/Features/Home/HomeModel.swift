import BiathlonKit
import Foundation
import Observation

/// Ce que montre l'accueil : la course en direct s'il y en a une, sinon la
/// prochaine, plus les derniers résultats de l'étape en cours.
@Observable
final class HomeModel {
    struct Snapshot {
        var event: BiathlonEvent?
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
        var events = try await client.events(season: .containing(now))
        if events.isEmpty {
            events = try await client.events(season: SeasonID.containing(now).previous)
        }
        // Étape en cours, sinon la prochaine, sinon la dernière de la saison.
        let event = events.first { $0.startDate <= now && now <= $0.endDate }
            ?? events.filter { $0.startDate > now }.min { $0.startDate < $1.startDate }
            ?? events.max { $0.endDate < $1.endDate }
        snapshot.event = event
        guard let event else { return snapshot }

        snapshot.races = try await client.competitions(eventID: event.id)
            .sorted { $0.startTime < $1.startTime }
        if let live = snapshot.live {
            snapshot.liveResults = try await client.results(raceID: live.id)
        }
        if let finished = snapshot.latestFinished {
            snapshot.latestResults = try await client.results(raceID: finished.id)
        }
        return snapshot
    }
}
