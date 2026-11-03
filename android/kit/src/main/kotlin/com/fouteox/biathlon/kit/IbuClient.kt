package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.URLBuilder
import io.ktor.http.Url
import io.ktor.http.appendPathSegments
import io.ktor.http.isSuccess
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Client for the biathlonresults.com API.
 *
 * [baseUrl] can also point to the server's read-only cache (`/ibu/`), which exposes the same
 * paths as the IBU API.
 */
class IbuClient(
    val baseUrl: Url = IBU_BASE_URL,
    private val httpClient: HttpClient = HttpClient(OkHttp),
) {
    // Calendar

    /** World Cup events (`Level=1`) of a season. */
    suspend fun events(season: SeasonId): List<BiathlonEvent> =
        get("Events", "SeasonId" to season.rawValue, "Level" to "1")

    suspend fun competitions(eventId: String): List<Competition> = get("Competitions", "EventId" to eventId)

    /** The race [id], among its event's: a race known by its ID alone, such as an athlete's result. */
    suspend fun race(id: String): Competition =
        competitions(Competition.eventId(id)).firstOrNull { it.id == id } ?: throw IbuException.UnknownRace(id)

    // Results

    suspend fun results(raceId: String): RaceResults = get("Results", "RaceId" to raceId)

    // Standings

    suspend fun cupStandings(cupId: String): CupStandings = get("CupResults", "CupId" to cupId)

    // Athletes

    suspend fun athlete(id: String): AthleteBio = get("CISBios", "IBUId" to id)

    suspend fun athleteResults(id: String): List<AthleteResult> =
        get<AthleteResultsEnvelope>("AllResults", "IBUId" to id).results.orEmpty()

    @Serializable
    private data class AthleteResultsEnvelope(@SerialName("Results") val results: List<AthleteResult>? = null)

    // Transport

    private suspend inline fun <reified T> get(path: String, vararg query: Pair<String, String>): T {
        val url = URLBuilder(baseUrl).apply {
            appendPathSegments(path)
            query.sortedBy { it.first }.forEach { (name, value) -> parameters.append(name, value) }
        }.build()
        val response = httpClient.get(url)
        if (!response.status.isSuccess()) throw IbuException.Http(response.status.value)
        return try {
            IbuJson.decodeFromString(response.bodyAsText())
        } catch (error: IllegalArgumentException) {
            // Malformed JSON and unexpected shapes alike: SerializationException is one too.
            throw IbuException.Decoding(path, error)
        }
    }

    companion object {
        val IBU_BASE_URL = Url("https://biathlonresults.com/modules/sportapi/api/")
    }
}

/** Failures of the IBU API. The app shows its own message for them and logs the details. */
sealed class IbuException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Http(val status: Int) : IbuException("HTTP $status")

    class Decoding(val path: String, cause: Throwable) : IbuException("Unreadable $path", cause)

    /** The race isn't among its event's races. */
    class UnknownRace(val raceId: String) : IbuException("Unknown race $raceId")
}
