package com.fouteox.biathlon.kit

/**
 * A race's category and discipline: after its 14-character `EventId`, a `RaceId` goes on with
 * its `catId` and `DisciplineId`, e.g. `BT2526SWRLCP03SMMS` for the men's mass start of
 * Le Grand-Bornand. A few older IDs add a fifth character, e.g. `BT1314SWRLCP08SMSPS`.
 *
 * The app names a race from its kind, in the device's language, rather than with the IBU's
 * English `ShortDescription`, as the iOS app and the server's alerts do.
 */
enum class RaceKind(val code: String) {
    MEN_SPRINT("SMSP"),
    WOMEN_SPRINT("SWSP"),
    MEN_PURSUIT("SMPU"),
    WOMEN_PURSUIT("SWPU"),
    MEN_INDIVIDUAL("SMIN"),
    WOMEN_INDIVIDUAL("SWIN"),
    MEN_SHORT_INDIVIDUAL("SMSI"),
    WOMEN_SHORT_INDIVIDUAL("SWSI"),
    MEN_MASS_START("SMMS"),
    WOMEN_MASS_START("SWMS"),
    MEN_RELAY("SMRL"),
    WOMEN_RELAY("SWRL"),
    MIXED_RELAY("MXRL"),
    SINGLE_MIXED_RELAY("MXSR"),
    ;

    companion object {
        /** `null` for a kind the IBU adds later: the app then keeps the IBU's name. */
        fun of(raceId: String): RaceKind? {
            val code = raceId.drop(EVENT_ID_LENGTH).take(4)
            return entries.firstOrNull { it.code == code }
        }
    }
}
