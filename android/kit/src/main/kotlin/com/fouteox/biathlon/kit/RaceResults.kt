package com.fouteox.biathlon.kit

import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Response of `Results?RaceId=`: start list before the race, results after. */
@Serializable
data class RaceResults(
    @SerialName("IsStartList") val isStartList: Boolean = false,
    @SerialName("IsResult") val isResult: Boolean = false,
    @SerialName("Competition") val competition: Competition? = null,
    /** The event the race belongs to, where it is held. */
    @SerialName("SportEvt") val event: BiathlonEvent? = null,
    @SerialName("Results") val rows: List<ResultRow> = emptyList(),
) {
    /** For a relay, team rows only; otherwise every row. */
    val standings: List<ResultRow>
        get() = rows.filter { it.isTeam }.ifEmpty { rows }

    /**
     * The athlete or team ranked first, once anyone is: a start list ranks nobody, and someone
     * out of the race (DNS, DNF…) leads nobody.
     */
    val leader: ResultRow?
        get() = standings.firstOrNull { it.rank != null && it.irm == null }

    /** The first three, without the athletes or teams who didn't finish: none before the results. */
    val podium: List<ResultRow>
        get() = if (isResult) standings.filter { it.irm == null }.take(3) else emptyList()

    fun legs(team: ResultRow): List<ResultRow> =
        rows.filter { !it.isTeam && it.teamId != null && it.teamId == team.teamId }
}

@Serializable
data class ResultRow(
    @SerialName("IBUId") val athleteId: String? = null,
    @SerialName("IsTeam") val isTeam: Boolean = false,
    @SerialName("TeamId") @Serializable(LooseStringSerializer::class) val teamId: String? = null,
    @SerialName("Name") val name: String = "",
    @SerialName("ShortName") val shortName: String? = null,
    @SerialName("FamilyName") val familyName: String? = null,
    @SerialName("GivenName") val givenName: String? = null,
    @SerialName("Nat") val nation: String? = null,
    @SerialName("Leg") @Serializable(LooseIntSerializer::class) val leg: Int? = null,
    @SerialName("Rank") @Serializable(LooseStringSerializer::class) val rank: String? = null,
    @SerialName("Shootings") val shootings: String? = null,
    @SerialName("TotalTime") val totalTime: String? = null,
    @SerialName("Behind") val behind: String? = null,
    /** `DNF`, `DNS`, `DSQ`, `LAP`… */
    @SerialName("IRM") val irm: String? = null,
) {
    val id: String get() = "${teamId.orEmpty()}-${athleteId ?: name}-${leg ?: 0}"

    /**
     * The name as a voice reads it: a team by its nation, an athlete given name first and family
     * name out of capitals, which a voice would spell out ("Johan-Olav Smoerdal Botn").
     */
    fun spokenName(locale: Locale = Locale.getDefault()): String {
        if (isTeam && nation != null) return Nation.localizedName(nation, locale)
        if (familyName.isNullOrEmpty()) return name
        val family = familyName.capitalizedWords(locale)
        return if (givenName.isNullOrEmpty()) family else "$givenName $family"
    }
}

/** Each word with a capital, the rest in lowercase, as Foundation's `capitalized`: words end at what isn't a letter. */
private fun String.capitalizedWords(locale: Locale): String {
    val lower = lowercase(locale)
    return buildString {
        lower.forEachIndexed { index, char ->
            append(if (index == 0 || !lower[index - 1].isLetter()) char.titlecase(locale) else char.toString())
        }
    }
}
