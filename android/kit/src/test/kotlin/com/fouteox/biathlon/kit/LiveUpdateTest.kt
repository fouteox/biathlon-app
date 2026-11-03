package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** The races' Live Updates, as the server publishes them (server/test/live.test.ts, "Live Update topics"). */
class LiveUpdateTest {
    private val raceId = "BT2627SWRLCP01SMIN"
    private val live = RaceLiveState(
        Competition.State.LIVE,
        instant("2026-11-26T15:15:00Z"),
        listOf(
            RaceLiveState.Leader("1", "PERROT E.", "FRA", "48:12.3"),
            RaceLiveState.Leader("2", "LAEGREID S.", "NOR", "+7.8"),
            RaceLiveState.Leader("3", "SAMUELSSON S.", "SWE", "+18.7"),
        ),
    )

    @Test
    fun decodesEveryStateOfTheSharedFixture() {
        val states = Json.parseToJsonElement(fixture("live-activity")).jsonArray
            .map { it.jsonObject.getValue("state") }
            .filter { it != JsonNull }
            .map { decode<RaceLiveState>(it.toString()) }
        assertEquals(live, states.first())
        assertEquals(
            listOf(Competition.State.LIVE, Competition.State.FINISHED, Competition.State.SCHEDULED, Competition.State.CANCELLED),
            states.map { it.phase },
        )
        assertEquals(RaceLiveState.Leader("2", "FRANCE", "FRA", "+20.4"), states[1].leaders[1])
    }

    @Test
    fun readsTheTopicsUpdatesAndEnds() {
        val state = IbuJson.encodeToString(RaceLiveState.serializer(), live)
        assertEquals(
            LiveUpdate.Update(raceId, live, instant("2026-11-26T15:30:00Z")),
            LiveUpdate.parse(mapOf("raceId" to raceId, "event" to "update", "state" to state, "timestamp" to "1795707000")),
        )
        assertEquals(
            LiveUpdate.End(raceId, live, instant("2026-11-26T16:00:00Z"), publishedAt = instant("2026-11-26T15:30:00Z")),
            LiveUpdate.parse(
                mapOf("raceId" to raceId, "event" to "end", "state" to state, "timestamp" to "1795707000", "dismissalDate" to "1795708800"),
            ),
        )
        assertEquals("race-$raceId", LiveUpdate.topic(raceId))
    }

    @Test
    fun ignoresTheAlertsAndUnreadableMessages() {
        assertNull(LiveUpdate.parse(mapOf("raceId" to raceId, "startTime" to "2026-11-26T15:45:00.000Z")))
        assertNull(LiveUpdate.parse(mapOf("raceId" to raceId, "event" to "update", "state" to "{", "timestamp" to "1")))
        assertNull(LiveUpdate.parse(mapOf("raceId" to raceId, "event" to "end", "state" to "{\"phase\":\"live\"}", "timestamp" to "1")))
    }

    private fun server(status: HttpStatusCode, body: String) = ServerClient(
        Url("https://server.example/"),
        HttpClient(
            MockEngine { request ->
                assertEquals("https://server.example/v1/races/$raceId/channels/fcm", request.url.toString())
                respond(body, status)
            },
        ),
    )

    private val stateJson: JsonElement get() = Json.parseToJsonElement(IbuJson.encodeToString(RaceLiveState.serializer(), live))

    @Test
    fun looksUpTheTopicsStateUntilTheRaceIsOver() = runTest {
        assertEquals(
            LiveUpdate.Update(raceId, live, instant("2026-11-26T15:30:00Z")),
            server(HttpStatusCode.OK, """{"channelId":"race-$raceId","state":$stateJson,"timestamp":1795707000}""").liveUpdate(raceId),
        )
        assertEquals(
            LiveUpdate.End(raceId, live, instant("2026-11-26T16:00:00Z"), publishedAt = null),
            server(HttpStatusCode.Gone, """{"state":$stateJson,"dismissalDate":1795708800}""").liveUpdate(raceId),
        )
        assertNull(server(HttpStatusCode.NotFound, """{"error":"no channel for this race"}""").liveUpdate(raceId))
        assertThrows<ServerException.Http> { server(HttpStatusCode.ServiceUnavailable, "").liveUpdate(raceId) }
        assertThrows<ServerException.Decoding> { server(HttpStatusCode.OK, "{}").liveUpdate(raceId) }
    }

    @Test
    fun followsRacesUntilTwoDaysAfterTheirStart() {
        val start = instant("2026-11-26T15:15:00Z")
        val races = FollowedRaces().follow(raceId, "Men's 20km Individual", start)
        assertEquals(setOf(raceId), races.raceIds)
        assertEquals(setOf(raceId), races.pruned(instant("2026-11-28T15:14:59Z")).raceIds)
        assertEquals(emptySet<String>(), races.pruned(instant("2026-11-28T15:15:00Z")).raceIds)
        assertEquals(emptySet<String>(), races.unfollow(raceId).raceIds)
    }

    @Test
    fun keepsTheFollowedRacesAsText() {
        val races = FollowedRaces().follow(raceId, "Men's 20km Individual", instant("2026-11-26T15:15:00Z"))
            .shown(LiveUpdate.Update(raceId, live, instant("2026-11-26T15:30:00Z")))
        assertEquals(races, FollowedRaces.decoded(races.encoded()))
        assertEquals(FollowedRaces(), FollowedRaces.decoded(null))
        assertEquals(FollowedRaces(), FollowedRaces.decoded("{"))
    }

    @Test
    fun showsOnlyTheUpdatesNewerThanTheOneOnScreen() {
        val races = FollowedRaces().follow(raceId, "x", instant("2026-11-26T15:15:00Z"))
        val first = LiveUpdate.Update(raceId, live, instant("2026-11-26T15:30:00Z"))
        assertTrue(races.isNew(first))
        val shown = races.shown(first)
        assertFalse(shown.isNew(first))
        assertFalse(shown.isNew(first.copy(publishedAt = instant("2026-11-26T15:29:00Z"))))
        assertTrue(shown.isNew(first.copy(publishedAt = instant("2026-11-26T15:31:00Z"))))
        assertFalse(FollowedRaces().isNew(first))
        assertTrue(shown.isOlder(first.copy(publishedAt = instant("2026-11-26T15:29:00Z"))))
        assertFalse(shown.isOlder(first))
        assertFalse(races.isOlder(first))
    }

    @Test
    fun takesAnEndOlderThanTheStateOnScreenForAReinstatedRacesOld() {
        val shown = FollowedRaces().follow(raceId, "x", instant("2026-11-26T15:15:00Z"))
            .shown(LiveUpdate.Update(raceId, live, instant("2026-11-26T15:30:00Z")))
        val dismissal = instant("2026-11-26T16:00:00Z")
        assertFalse(shown.isNew(LiveUpdate.End(raceId, live, dismissal, publishedAt = instant("2026-11-26T15:29:00Z"))))
        assertTrue(shown.isNew(LiveUpdate.End(raceId, live, dismissal, publishedAt = instant("2026-11-26T15:31:00Z"))))
        // The server's current state, looked up rather than received.
        assertTrue(shown.isNew(LiveUpdate.End(raceId, live, dismissal, publishedAt = null)))
    }
}
