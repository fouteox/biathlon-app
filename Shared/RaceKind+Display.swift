import BiathlonKit
import Foundation

/// A race's name in the device's language. The keys are manual entries of the String
/// Catalog, which the server's alerts use too, so they are looked up by value.
extension RaceKind {
    var title: LocalizedStringResource { LocalizedStringResource(String.LocalizationValue(localizationKey)) }

    /// Falls back to the IBU's English name for a kind the app doesn't know yet.
    static func title(ofRace raceID: String, ibuName: String) -> String {
        RaceKind(raceID: raceID).map { String(localized: $0.title) } ?? ibuName
    }
}

extension Competition {
    var title: String { RaceKind.title(ofRace: id, ibuName: shortDescription) }
}

extension RaceActivityAttributes {
    var title: String { RaceKind.title(ofRace: raceID, ibuName: name) }
}
