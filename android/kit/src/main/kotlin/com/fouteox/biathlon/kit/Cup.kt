package com.fouteox.biathlon.kit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** World Cup standings identifiers. */
object Cup {
    /** World Cup standings ID, for example `BT2627SWRLCP__SMTS` for the men's overall standings of 2026-27. */
    fun worldCupId(season: SeasonId, category: RaceCategory, discipline: StandingsDiscipline): String =
        "BT${season.rawValue}SWRLCP__${category.code}${discipline.code}"
}

/** The standings tables of a World Cup season (last part of the cup ID). */
enum class StandingsDiscipline(val code: String) {
    TOTAL("TS"),
    SPRINT("SP"),
    PURSUIT("PU"),
    INDIVIDUAL("IN"),
    MASS_START("MS"),
    NATIONS("NC"),
}

/** Response of `CupResults?CupId=`. */
@Serializable
data class CupStandings(
    @SerialName("AsOf") @Serializable(LooseStringSerializer::class) val asOf: String? = null,
    @SerialName("Rows") val rows: List<CupRow> = emptyList(),
) {
    /**
     * The rows of `nation`'s athletes, in the standings' order. The API lists a nation's
     * athletes nowhere else: its screen shows those who scored points.
     */
    fun athletes(nation: String): List<CupRow> = rows.filter { !it.isNation && it.nation == nation }
}

@Serializable
data class CupRow(
    @SerialName("Rank") @Serializable(LooseStringSerializer::class) val rank: String? = null,
    /** An athlete's ID, or a nation's code in the nations standings. */
    @SerialName("IBUId") private val ibuId: String? = null,
    @SerialName("Name") val name: String = "",
    @SerialName("ShortName") val shortName: String? = null,
    @SerialName("Nat") val nation: String? = null,
    @SerialName("Score") @Serializable(LooseStringSerializer::class) val score: String? = null,
    /** Change since the last race: negative = places gained. */
    @SerialName("RnkDiff") @Serializable(LooseIntSerializer::class) val rankChange: Int? = null,
    @SerialName("Bibs") private val bibs: List<Bib>? = null,
) {
    @Serializable
    data class Bib(@SerialName("Color") val color: String? = null)

    val athleteId: String? get() = ibuId?.takeIf { it != nation }

    val id: String get() = athleteId ?: "${nation.orEmpty()}-$name"

    val bibColors: List<String> get() = bibs.orEmpty().mapNotNull { it.color }

    /** Nations standings: the `IBUId` is the nation's code, the name is the country in English. */
    val isNation: Boolean get() = athleteId == null
}
