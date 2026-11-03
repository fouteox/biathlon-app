package com.fouteox.biathlon.kit

import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class HomeFeedTest {
    private val results = """{"RaceId":"X","IsStartList":false,"IsResult":true,"Results":[]}"""

    /** During an event, with a race live, one already finished and the next event announced. */
    private val duringAnEvent = mapOf(
        "Events?Level=1&SeasonId=2627" to
            "[${event("E1", "2026-11-23T12:00:00Z", "2026-11-29T12:00:00Z")}," +
            "${event("E2", "2026-12-01T12:00:00Z", "2026-12-07T12:00:00Z")}]",
        "Competitions?EventId=E1" to
            "[${race("E1-SP", "2026-11-26T15:00:00Z", status = 11, scheduleStatus = "FINISHED")}," +
            "${race("E1-PU", "2026-11-27T11:00:00Z", isLive = true)}," +
            "${race("E1-MS", "2026-11-28T14:00:00Z")}]",
        "Competitions?EventId=E2" to "[${race("E2-SP", "2026-12-04T13:00:00Z")}]",
        "Results?RaceId=E1-PU" to results,
        "Results?RaceId=E1-SP" to results,
    )

    private fun feed(vararg races: String) = HomeFeed(emptyList(), races.map { decode<Competition>(it) })

    @Test
    fun featuresTheLiveRaceTheNextOneAndTheLatestResult() = runTest {
        val feed = stubClient(duringAnEvent).homeFeed(instant("2026-11-27T11:30:00Z"))

        assertEquals("E1-PU", feed.live?.id)
        assertEquals("E1-MS", feed.next?.id)
        assertEquals("E1-SP", feed.latestFinished?.id)
        assertEquals("E1", feed.event?.id)
        assertNotNull(feed.liveResults)
        assertNotNull(feed.latestResults)
    }

    /** The home screen waits for the slowest request of each step, not for their sum. */
    @Test
    fun sendsIndependentRequestsTogether() = runTest(timeout = 10.seconds) {
        val client = rendezvousClient(
            duringAnEvent,
            together = listOf(
                listOf("Competitions?EventId=E1", "Competitions?EventId=E2"),
                listOf("Results?RaceId=E1-PU", "Results?RaceId=E1-SP"),
            ),
        )
        val feed = client.homeFeed(instant("2026-11-27T11:30:00Z"))
        assertNotNull(feed.liveResults)
        assertNotNull(feed.latestResults)
    }

    @Test
    fun beforeTheSeasonFallsBackToThePreviousOne() = runTest {
        val client = stubClient(
            mapOf(
                "Events?Level=1&SeasonId=2627" to "[${event("E1", "2026-11-23T12:00:00Z", "2026-11-29T12:00:00Z")}]",
                "Events?Level=1&SeasonId=2526" to
                    "[${event("P8", "2026-03-09T12:00:00Z", "2026-03-15T12:00:00Z")}," +
                    "${event("P9", "2026-03-16T12:00:00Z", "2026-03-22T12:00:00Z")}]",
                "Competitions?EventId=P9" to
                    "[${race("P9-MS", "2026-03-22T13:00:00Z", status = 11, scheduleStatus = "FINISHED")}]",
                "Competitions?EventId=E1" to "[${race("E1-IN", "2026-11-26T15:15:00Z")}]",
                "Results?RaceId=P9-MS" to results,
            ),
        )

        val feed = client.homeFeed(instant("2026-10-19T12:00:00Z"))

        assertEquals(listOf("P9", "E1"), feed.events.map { it.id })
        assertNull(feed.live)
        assertEquals("E1-IN", feed.next?.id)
        assertEquals("P9-MS", feed.latestFinished?.id)
        assertEquals("E1", feed.event?.id)
        assertEquals("P9", feed.latestFinished?.let(feed::event)?.id)
    }

    @Test
    fun cancelledRacesAreNeverNext() {
        val feed = feed(
            race("A", "2026-11-28T10:00:00Z", status = 6, scheduleStatus = "CANCELLED"),
            race("B", "2026-11-28T14:00:00Z"),
        )
        assertEquals("B", feed.next?.id)
    }

    @Test
    fun isEmptyWithoutAnyRaceOrEvent() {
        assertTrue(feed().isEmpty)
        assertTrue(feed(race("A", "2026-11-28T10:00:00Z", status = 6, scheduleStatus = "CANCELLED")).isEmpty)
        assertFalse(feed(race("B", "2026-11-28T14:00:00Z")).isEmpty)
    }

    /** Opened before a race, the app fetches the feed again at the start, so the live race shows without a pull to refresh. */
    @Test
    fun theAppRefreshesAtTheNextStart() {
        val feed = feed(race("NEXT", "2026-11-27T12:10:00Z"))
        assertEquals(instant("2026-11-27T12:10:00Z"), feed.nextStartRefreshTime(instant("2026-11-27T11:30:00Z")))
    }

    /** The IBU marks a race live a little after its start: the app asks again every minute. */
    @Test
    fun theAppRetriesEveryMinuteForARaceLateToStart() {
        val now = instant("2026-11-27T12:11:00Z")
        val feed = feed(race("NEXT", "2026-11-27T12:10:00Z"))
        assertEquals(now.plusSeconds(60), feed.nextStartRefreshTime(now))
    }

    /** While a race is live the app polls it; with no race ahead there is nothing to wait for. */
    @Test
    fun theAppHasNoStartToWaitForWhileLiveOrWithNoRaceAhead() {
        val now = instant("2026-11-27T11:30:00Z")
        val live = feed(race("LIVE", "2026-11-27T11:00:00Z", isLive = true), race("NEXT", "2026-11-28T14:00:00Z"))
        val over = feed(race("DONE", "2026-11-26T15:00:00Z", status = 11, scheduleStatus = "FINISHED"))

        assertNull(live.nextStartRefreshTime(now))
        assertNull(over.nextStartRefreshTime(now))
    }
}
