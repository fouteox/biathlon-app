package com.fouteox.biathlon.kit

import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** As BiathlonKit's `ReminderPlanTests`. */
class ReminderPlanTest {
    private val now = instant("2026-11-26T12:00:00Z")

    @Test
    fun remindsBeforeEachMatchingRace() {
        val races = listOf(
            race("men", "2026-11-26T15:15:00Z", category = "SM"),
            race("women", "2026-11-27T12:00:00Z", category = "SW"),
            race("mixed", "2026-11-27T15:00:00Z", category = "MX"),
        ).map { decode<Competition>(it) }
        val reminders = ReminderPlan.reminders(races, setOf(RaceCategory.MEN, RaceCategory.WOMEN), minutesBefore = 15, now)
        assertEquals(listOf("men", "women"), reminders.map { it.race.id })
        assertEquals(instant("2026-11-26T15:00:00Z"), reminders.first().fireTime)
    }

    @Test
    fun skipsRacesThatAreNotUpcomingOrTooClose() {
        val races = listOf(
            race("cancelled", "2026-11-26T18:00:00Z", status = 6, scheduleStatus = "CANCELLED"),
            race("live", "2026-11-26T11:00:00Z", isLive = true),
            race("tooClose", "2026-11-26T12:10:00Z"),
        ).map { decode<Competition>(it) }
        assertTrue(ReminderPlan.reminders(races, setOf(RaceCategory.MEN), minutesBefore = 15, now).isEmpty())
    }

    @Test
    fun upcomingRacesStayWithinTheHorizon() = runTest {
        val client = stubClient(
            mapOf(
                "Events?Level=1&SeasonId=2627" to
                    "[${event("past", "2026-11-16T12:00:00Z", "2026-11-22T12:00:00Z")}," +
                    "${event("now", "2026-11-23T12:00:00Z", "2026-11-29T12:00:00Z")}," +
                    "${event("later", "2026-12-10T12:00:00Z", "2026-12-14T12:00:00Z")}]",
                "Competitions?EventId=now" to
                    "[${race("started", "2026-11-26T11:00:00Z")},${race("soon", "2026-11-27T11:00:00Z")}]",
            ),
        )
        assertEquals(listOf("soon"), client.upcomingRaces(now, ReminderPlan.HORIZON).map { it.id })
    }

    @Test
    fun loadsTheRacesOfEveryEventTogetherInCalendarOrder() = runTest(timeout = 10.seconds) {
        val client = rendezvousClient(
            mapOf(
                "Events?Level=1&SeasonId=2627" to
                    "[${event("first", "2026-11-23T12:00:00Z", "2026-11-29T12:00:00Z")}," +
                    "${event("second", "2026-11-30T12:00:00Z", "2026-12-06T12:00:00Z")}]",
                "Competitions?EventId=first" to "[${race("A", "2026-11-27T11:00:00Z")}]",
                "Competitions?EventId=second" to "[${race("B", "2026-12-02T11:00:00Z")}]",
            ),
            together = listOf(listOf("Competitions?EventId=first", "Competitions?EventId=second")),
        )
        assertEquals(listOf("A", "B"), client.upcomingRaces(now, ReminderPlan.HORIZON).map { it.id })
    }
}
