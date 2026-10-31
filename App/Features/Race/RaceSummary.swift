import BiathlonKit
import Foundation

/// A race told in a sentence, which Siri reads and a share sends: race and place first.
enum RaceSummary {
    /// The race's name and place, as the widget names them.
    static func heading(of race: Competition, at event: BiathlonEvent?) -> String {
        [race.title, event?.shortDescription].compactMap(\.self).joined(separator: ", ")
    }

    /// The race's winner and the two after, names as a voice reads them; `nil` before its results.
    static func podium(of race: Competition, at event: BiathlonEvent?, results: RaceResults)
        -> LocalizedStringResource?
    {
        let podium = results.podium.map { $0.spokenName() }
        guard let winner = podium.first else { return nil }
        let heading = heading(of: race, at: event)
        guard podium.count == 3 else { return "\(heading): \(winner) wins." }
        return "\(heading): \(winner) wins, ahead of \(podium[1]) and \(podium[2])."
    }
}
