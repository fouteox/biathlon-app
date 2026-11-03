package com.fouteox.biathlon.kit

import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class CalendarGroupsTest {
    /** Paris: the IBU's noon UTC dates fall on the same day, its 23:30 UTC starts on the next. */
    private val paris = ZoneId.of("Europe/Paris")

    private val events = listOf(
        decode<BiathlonEvent>(event("E3", "2027-01-07T12:00:00Z", "2027-01-10T12:00:00Z")),
        decode<BiathlonEvent>(event("E1", "2026-11-28T12:00:00Z", "2026-12-06T12:00:00Z")),
        decode<BiathlonEvent>(event("E2", "2026-12-11T12:00:00Z", "2026-12-14T12:00:00Z")),
    )

    /** An event starting on November 28 at noon UTC belongs to November, whichever month it ends in. */
    @Test
    fun groupsEventsByTheMonthTheyStartInInDateOrder() {
        val groups = events.groupedByMonth(paris)

        assertEquals(listOf(YearMonth.of(2026, 11), YearMonth.of(2026, 12), YearMonth.of(2027, 1)), groups.map { it.period })
        assertEquals(listOf(listOf("E1"), listOf("E2"), listOf("E3")), groups.map { group -> group.items.map { it.id } })
    }

    @Test
    fun groupsRacesByLocalDay() {
        // 23:30 UTC on the 5th is already the 6th in Paris.
        val races = listOf(
            decode<Competition>(race("B", "2026-12-05T23:30:00Z")),
            decode<Competition>(race("A", "2026-12-05T13:15:00Z")),
            decode<Competition>(race("C", "2026-12-06T11:00:00Z")),
        )
        val groups = races.groupedByDay(paris)

        assertEquals(listOf(LocalDate.of(2026, 12, 5), LocalDate.of(2026, 12, 6)), groups.map { it.period })
        assertEquals(listOf(listOf("A"), listOf("B", "C")), groups.map { group -> group.items.map { it.id } })
    }

    @Test
    fun anEventIsUnderwayFromItsFirstDayToTheEndOfItsLast() {
        val event = events[1] // E1: November 28 to December 6
        assertEquals(BiathlonEvent.Phase.UPCOMING, event.phase(instant("2026-11-27T23:59:00Z"), ZoneOffset.UTC))
        assertEquals(BiathlonEvent.Phase.UNDERWAY, event.phase(instant("2026-11-28T00:00:00Z"), ZoneOffset.UTC))
        assertEquals(BiathlonEvent.Phase.UNDERWAY, event.phase(instant("2026-12-06T23:59:00Z"), ZoneOffset.UTC))
        assertEquals(BiathlonEvent.Phase.PAST, event.phase(instant("2026-12-07T00:00:00Z"), ZoneOffset.UTC))
    }

    @Test
    fun theCalendarOpensOnTheEventUnderwayOtherwiseTheNextOne() {
        assertEquals("E1", events.eventToShow(instant("2026-10-31T12:00:00Z"), ZoneOffset.UTC)?.id)
        assertEquals("E1", events.eventToShow(instant("2026-12-01T12:00:00Z"), ZoneOffset.UTC)?.id)
        assertEquals("E2", events.eventToShow(instant("2026-12-08T12:00:00Z"), ZoneOffset.UTC)?.id)
        // After the season's last event, the calendar stays on it.
        assertEquals("E3", events.eventToShow(instant("2027-06-01T12:00:00Z"), ZoneOffset.UTC)?.id)
        assertNull(emptyList<BiathlonEvent>().eventToShow(instant("2027-06-01T12:00:00Z"), ZoneOffset.UTC))
    }
}
