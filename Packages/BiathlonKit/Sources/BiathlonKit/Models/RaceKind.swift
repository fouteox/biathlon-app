/// A race's category and discipline: a `RaceId` ends with its `catId` and `DisciplineId`,
/// e.g. `BT2526SWRLCP03SMMS` for the men's mass start of Le Grand-Bornand.
///
/// The app names a race from its kind, in the device's language, rather than with the
/// IBU's English `ShortDescription`. The server's alerts do the same (`server/src/payload.ts`).
public enum RaceKind: String, CaseIterable, Sendable {
    case menSprint = "SMSP"
    case womenSprint = "SWSP"
    case menPursuit = "SMPU"
    case womenPursuit = "SWPU"
    case menIndividual = "SMIN"
    case womenIndividual = "SWIN"
    case menShortIndividual = "SMSI"
    case womenShortIndividual = "SWSI"
    case menMassStart = "SMMS"
    case womenMassStart = "SWMS"
    case menRelay = "SMRL"
    case womenRelay = "SWRL"
    case mixedRelay = "MXRL"
    case singleMixedRelay = "MXSR"

    /// `nil` for a kind the IBU adds later: the app then keeps the IBU's name.
    public init?(raceID: String) {
        self.init(rawValue: String(raceID.suffix(4)))
    }

    /// The race's name in the app's String Catalog, also sent as an alert's `title-loc-key`.
    public var localizationKey: String { "race.\(rawValue)" }
}
