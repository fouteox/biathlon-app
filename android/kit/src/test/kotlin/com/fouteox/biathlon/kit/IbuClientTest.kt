package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.appendPathSegments
import io.ktor.http.takeFrom
import io.ktor.http.URLBuilder
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

class IbuClientTest {
    /** A client of `baseUrl` that checks the URL it is sent and answers with no events. */
    private fun expecting(url: String, baseUrl: Url = IbuClient.IBU_BASE_URL) = IbuClient(
        baseUrl,
        HttpClient(
            MockEngine { request ->
                assertEquals(url, request.url.toString())
                respond("[]")
            },
        ),
    )

    @Test
    fun buildsSortedQuery() = runTest {
        val client = expecting("${IbuClient.IBU_BASE_URL}Events?Level=1&SeasonId=2627")
        assertTrue(client.events(SeasonId("2627")).isEmpty())
    }

    /** The app builds its base URL as the iOS app does: the server URL plus `ibu/`. */
    @ParameterizedTest
    @ValueSource(strings = ["https://example.workers.dev", "https://example.workers.dev/"])
    fun usesTheServerCacheWithTheSamePaths(server: String) = runTest {
        val baseUrl = URLBuilder().takeFrom(server).appendPathSegments("ibu", "").build()
        val client = expecting("https://example.workers.dev/ibu/Events?Level=1&SeasonId=2627", baseUrl)
        assertTrue(client.events(SeasonId("2627")).isEmpty())
    }

    @Test
    fun httpErrorCarriesTheStatus() = runTest {
        val client = stubClient(mapOf("Results?RaceId=R1" to "{}"), HttpStatusCode.ServiceUnavailable)
        val error = assertThrows<IbuException.Http> { client.results("R1") }
        assertEquals(503, error.status)
    }

    @Test
    fun decodingErrorNamesTheEndpoint() = runTest {
        val client = stubClient(mapOf("Results?RaceId=R1" to "not json"))
        val error = assertThrows<IbuException.Decoding> { client.results("R1") }
        assertEquals("Results", error.path)
    }

    /** An athlete's result names its race by ID alone: the race is found among its event's. */
    @Test
    fun findsARaceByItsId() = runTest {
        val client = stubClient(
            mapOf(
                "Competitions?EventId=BT2526SWRLCP09" to
                    "[${race("BT2526SWRLCP09SWSP", "2026-03-19T15:15:00Z", category = "SW", status = 11)}," +
                    "${race("BT2526SWRLCP09SMSP", "2026-03-20T15:15:00Z", status = 11)}]",
            ),
        )
        assertEquals("BT2526SWRLCP09SMSP", client.race("BT2526SWRLCP09SMSP").id)
        val error = assertThrows<IbuException.UnknownRace> { client.race("BT2526SWRLCP09SMPU") }
        assertEquals("BT2526SWRLCP09SMPU", error.raceId)
    }

    @Test
    fun athleteResultsWithoutAnyAreEmpty() = runTest {
        val client = stubClient(mapOf("AllResults?IBUId=BTFRA20910199601" to """{"Results":null}"""))
        assertTrue(client.athleteResults("BTFRA20910199601").isEmpty())
    }

    @Test
    fun cupStandingsAthleteAndResults() = runTest {
        val client = stubClient(
            mapOf(
                "CupResults?CupId=BT2526SWRLCP__SMTS" to fixture("cup-results"),
                "CISBios?IBUId=BTFRA12906200101" to fixture("athlete"),
                "Competitions?EventId=BT2627SWRLCP01" to fixture("competitions"),
            ),
        )
        assertEquals(2, client.cupStandings("BT2526SWRLCP__SMTS").rows.size)
        assertEquals("Eric PERROT", client.athlete("BTFRA12906200101").fullName)
        assertEquals(decode<List<Competition>>(fixture("competitions")), client.competitions("BT2627SWRLCP01"))
    }
}
