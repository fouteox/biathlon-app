package com.fouteox.biathlon.kit

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A person found by the IBU's `Athletes?FamilyName=&GivenName=` search, which matches the start
 * of the family name and of the given name, whatever their case, and returns at most 10 people.
 */
@Serializable
data class AthleteMatch(
    @SerialName("IBUId") val id: String,
    @SerialName("FamilyName") val familyName: String,
    @SerialName("GivenName") val givenName: String,
    @SerialName("NAT") val nation: String? = null,
    /** "Athlete", "Not active" for a former athlete, "Deceased", "Official", or several ("Athlete, Official"). */
    @SerialName("Functions") private val functions: String? = null,
) {
    /** As the athlete's profile names them: `Julia SIMON`. */
    val name: String get() = "$givenName $familyName"

    /** The search also finds the IBU's officials, who have no results. */
    internal val isAthlete: Boolean
        get() = functions.orEmpty().split(",").map { it.trim() }.any { it in ATHLETE_ROLES }

    private companion object {
        val ATHLETE_ROLES = setOf("Athlete", "Not active", "Deceased")
    }
}

/** What the app sends to the IBU's search for the text someone types. */
internal object AthleteSearch {
    data class Query(val familyName: String? = null, val givenName: String? = null) {
        val parameters: List<Pair<String, String>>
            get() = listOfNotNull(familyName?.let { "FamilyName" to it }, givenName?.let { "GivenName" to it })
    }

    /**
     * One word may start either name. Several may be either name alone (`fillon maillet`,
     * `johannes thingnes`), or given names and a family name, each of one word or more, in
     * either order (`quentin fillon maillet`, `simon julia`): every split is searched.
     * Lowercased, so the server's cache serves every spelling.
     */
    fun queries(text: String): List<Query> {
        val words = text.lowercase().split(Regex("""\s+""")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return emptyList()
        val whole = words.joinToString(" ")
        val either = listOf(Query(familyName = whole), Query(givenName = whole))
        val splits = (1 until words.size).flatMap { index ->
            val start = words.take(index).joinToString(" ")
            val end = words.drop(index).joinToString(" ")
            listOf(Query(familyName = end, givenName = start), Query(familyName = start, givenName = end))
        }
        return either + splits
    }

    /** The athletes of every answer, in the order of the queries and of the IBU's answers, once each. */
    fun merge(answers: List<List<AthleteMatch>>): List<AthleteMatch> =
        answers.flatten().filter { it.isAthlete }.distinctBy { it.id }
}

@Serializable
private data class AthletesResponse(@SerialName("Athletes") val athletes: List<AthleteMatch>)

/** The athletes, active or former, whose names start like the words of `text`. */
suspend fun IbuClient.searchAthletes(text: String): List<AthleteMatch> {
    val answers = coroutineScope {
        AthleteSearch.queries(text).map { query ->
            async { get<AthletesResponse>("Athletes", *query.parameters.toTypedArray()).athletes }
        }.awaitAll()
    }
    return AthleteSearch.merge(answers)
}
