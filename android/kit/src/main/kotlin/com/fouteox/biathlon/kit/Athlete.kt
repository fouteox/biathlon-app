package com.fouteox.biathlon.kit

import java.net.URI
import java.net.URISyntaxException
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Athlete profile, from `CISBios?IBUId=`. Only what the app shows is decoded. */
@Serializable
data class AthleteBio(
    @SerialName("IBUId") val id: String,
    @SerialName("FullName") private val fullNameField: String? = null,
    @SerialName("FamilyName") private val familyName: String? = null,
    @SerialName("GivenName") private val givenName: String? = null,
    @SerialName("NAT") val nation: String? = null,
    /** Date without a time, returned at midnight UTC: display it in UTC so the day doesn't shift. */
    @SerialName("Birthdate") @Serializable(LenientIbuInstantSerializer::class) val birthdate: Instant? = null,
    @SerialName("PhotoURI") private val photoUri: String? = null,
    @SerialName("Functions") private val functions: String? = null,
    @SerialName("GenderId") private val genderId: String? = null,
) {
    val fullName: String get() = fullNameField ?: listOfNotNull(givenName, familyName).joinToString(" ")

    val photoUrl: URI?
        get() = photoUri?.let {
            try {
                URI(it)
            } catch (_: URISyntaxException) {
                null
            }
        }

    /**
     * `Functions` is "Deceased" instead of "Athlete" once the IBU records an athlete's death
     * (Sivert Guttorm Bakken, Linas Banys); a retirement isn't recorded.
     */
    val isDeceased: Boolean get() = functions == "Deceased"

    /** `null` when the IBU doesn't give it. */
    val gender: Gender? get() = Gender.entries.firstOrNull { it.code == genderId }

    /**
     * The athlete's age on `instant`, counted in UTC like the birthdate; `null` without a
     * birthdate or once the IBU records their death, as it gives no date of death.
     */
    fun age(instant: Instant): Int? {
        if (birthdate == null || isDeceased) return null
        return ChronoUnit.YEARS.between(birthdate.atOffset(ZoneOffset.UTC), instant.atOffset(ZoneOffset.UTC)).toInt()
    }
}

/** An athlete's gender, as `GenderId` gives it. */
enum class Gender(internal val code: String, val category: RaceCategory) {
    MAN("M", RaceCategory.MEN),
    WOMAN("W", RaceCategory.WOMEN),
}

/** One row of `AllResults?IBUId=`: an athlete's history. */
@Serializable
data class AthleteResult(
    @SerialName("RaceId") val raceId: String? = null,
    @SerialName("Season") @Serializable(LooseStringSerializer::class) val season: String? = null,
    @SerialName("Comp") val competition: String? = null,
    @SerialName("Place") val place: String? = null,
    @SerialName("Rank") @Serializable(LooseStringSerializer::class) val rank: String? = null,
    /**
     * The circuit: "WC", "WCH" and "OWG" for the World Cup, the World Championships and the
     * Olympics, the races of `Events?Level=1`; others for the IBU Cup, juniors or summer events.
     */
    @SerialName("Level") private val level: String? = null,
) {
    val id: String get() = raceId ?: "${season.orEmpty()}-${competition.orEmpty()}-${place.orEmpty()}"

    /** The races the app follows everywhere else. */
    internal val isWorldCupCircuit: Boolean get() = level in WORLD_CUP_LEVELS

    val kind: RaceKind? get() = raceId?.let(RaceKind::of)

    /** The season of `Season`, which reads "25/26" (`SeasonId` comes empty). */
    val seasonId: SeasonId?
        get() = season?.takeIf { SEASON.matches(it) }?.let { SeasonId(it.replace("/", "")) }

    private companion object {
        val WORLD_CUP_LEVELS = setOf("WC", "WCH", "OWG")
        val SEASON = Regex("""\d\d/\d\d""")
    }
}
