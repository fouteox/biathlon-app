package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.net.URI
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.NullSource
import org.junit.jupiter.params.provider.ValueSource

/** The server's `/v1/tv-coverage` response, as `server/test/tvCoverage.test.ts` and the iOS app's tests check it. */
class TvGuideTest {
    private val json = """
        {"coverage":[
        {"country":"FR","broadcaster":"La Chaîne L'Équipe","url":"https://www.lequipe.fr/tv/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
        {"country":"GB","broadcaster":"TNT Sports","url":"https://www.tntsports.co.uk/biathlon/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
        {"country":"DE","broadcaster":"ARD","url":"https://www.ardmediathek.de/live","from":"2026-11-23T00:00:00Z","until":"2026-11-30T00:00:00Z"},
        {"country":"DE","broadcaster":"ZDF","url":"https://www.zdf.de/","from":"2026-11-30T00:00:00Z","until":"2026-12-07T00:00:00Z"}
        ]}
    """.trimIndent()

    private val guide: TvGuide = IbuJson.decodeFromString(json)

    private val TvGuide.Listing.names get() = broadcasters.map { it.broadcaster }

    @Test
    fun setsTheViewersCountryApart() {
        val listings = guide.listings(instant("2026-11-26T15:15:00Z"), "FR")
        assertEquals("FR", listings.home?.country)
        assertEquals(listOf("La Chaîne L'Équipe"), listings.home?.names)
        assertEquals(URI("https://www.lequipe.fr/tv/"), listings.home?.broadcasters?.first()?.url)
        assertEquals(listOf("GB", "DE"), listings.others.map { it.country })
        assertEquals(listOf(listOf("TNT Sports"), listOf("ARD")), listings.others.map { it.names })
    }

    /** Whatever the app's language: the other countries keep the guide's order. */
    @ParameterizedTest
    @CsvSource("DE, FR GB", "GB, FR DE")
    fun keepsTheOthersInTheGuidesOrder(region: String, others: String) {
        val listings = guide.listings(instant("2026-11-26T15:15:00Z"), region)
        assertEquals(region, listings.home?.country)
        assertEquals(others.split(" "), listings.others.map { it.country })
    }

    /** A viewer elsewhere, or with no region, has no country of their own in the guide. */
    @ParameterizedTest
    @NullSource
    @ValueSource(strings = ["CH"])
    fun hasNoHomeOutsideTheGuidesCountries(region: String?) {
        val listings = guide.listings(instant("2026-11-26T15:15:00Z"), region)
        assertNull(listings.home)
        assertEquals(listOf("FR", "GB", "DE"), listings.others.map { it.country })
    }

    /** A period includes its first instant and ends just before its last. */
    @Test
    fun followsThePeriods() {
        assertEquals(listOf("ARD"), guide.listings(instant("2026-11-29T23:59:59Z"), "DE").home?.names)
        assertEquals(listOf("ZDF"), guide.listings(instant("2026-11-30T00:00:00Z"), "DE").home?.names)
    }

    @Test
    fun leavesOutCountriesWithNothingAnnounced() {
        val listings = guide.listings(instant("2026-12-10T15:15:00Z"), "DE")
        assertNull(listings.home)
        assertEquals(listOf("FR", "GB"), listings.others.map { it.country })
        assertTrue(guide.listings(instant("2027-04-01T12:00:00Z"), "FR").isEmpty)
    }

    @Test
    fun groupsTheBroadcastersOfOneCountry() {
        val guide: TvGuide = IbuJson.decodeFromString(
            """
            {"coverage":[
            {"country":"DE","broadcaster":"ZDF","url":"https://www.zdf.de/","from":"2026-11-30T00:00:00Z","until":"2026-12-07T00:00:00Z"},
            {"country":"FR","broadcaster":"La Chaîne L'Équipe","url":"https://www.lequipe.fr/tv/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"},
            {"country":"DE","broadcaster":"Eurosport","url":"https://www.eurosport.de/","from":"2026-11-23T00:00:00Z","until":"2027-03-22T00:00:00Z"}
            ]}
            """.trimIndent(),
        )
        val listings = guide.listings(instant("2026-12-04T13:15:00Z"), "DE")
        assertEquals(listOf("ZDF", "Eurosport"), listings.home?.names)
        assertEquals(listOf("FR"), listings.others.map { it.country })
    }

    private fun server(status: HttpStatusCode, body: String = "") = ServerClient(
        Url("https://example.workers.dev/"),
        HttpClient(
            MockEngine { request ->
                assertEquals("https://example.workers.dev/v1/tv-coverage", request.url.toString())
                respond(body, status)
            },
        ),
    )

    @Test
    fun loadsTheGuideFromTheServer() = runTest {
        assertEquals(guide, server(HttpStatusCode.OK, json).tvGuide())
    }

    @Test
    fun aFailedLoadCarriesTheStatus() = runTest {
        assertEquals(503, assertThrows<ServerException.Http> { server(HttpStatusCode.ServiceUnavailable).tvGuide() }.status)
    }

    @Test
    fun anUnreadableAnswerNamesTheRoute() = runTest {
        assertEquals("v1/tv-coverage", assertThrows<ServerException.Decoding> { server(HttpStatusCode.OK, "not json").tvGuide() }.route)
    }
}
