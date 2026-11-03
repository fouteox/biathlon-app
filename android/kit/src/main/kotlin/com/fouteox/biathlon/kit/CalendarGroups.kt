package com.fouteox.biathlon.kit

import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/** Items that share a calendar period (a day, a month), as a list shows them under one header. */
data class DatedGroup<P : Comparable<P>, T>(val period: P, val items: List<T>)

/** The items by the period their instant falls in: periods and items in time order. */
private fun <P : Comparable<P>, T> List<T>.grouped(period: (Instant) -> P, instant: (T) -> Instant): List<DatedGroup<P, T>> =
    sortedBy(instant).groupBy { period(instant(it)) }.toSortedMap().map { (key, items) -> DatedGroup(key, items) }

/** The events by month of their first day, as the calendar lists a season. */
fun List<BiathlonEvent>.groupedByMonth(zone: ZoneId): List<DatedGroup<YearMonth, BiathlonEvent>> =
    grouped({ YearMonth.from(it.atZone(zone)) }, BiathlonEvent::startDate)

/** The races by day, as an event's schedule lists them: the day in the header, the time on the row. */
fun List<Competition>.groupedByDay(zone: ZoneId): List<DatedGroup<LocalDate, Competition>> =
    grouped({ it.atZone(zone).toLocalDate() }, Competition::startTime)

/**
 * Where the event stands at `now`: underway from the start of its first day to the end of its
 * last one, since the IBU gives its dates without times.
 */
fun BiathlonEvent.phase(now: Instant, zone: ZoneId): BiathlonEvent.Phase {
    val day = now.atZone(zone).toLocalDate()
    return when {
        day < startDate.atZone(zone).toLocalDate() -> BiathlonEvent.Phase.UPCOMING
        day > endDate.atZone(zone).toLocalDate() -> BiathlonEvent.Phase.PAST
        else -> BiathlonEvent.Phase.UNDERWAY
    }
}

/** The event a season's calendar opens on: the one underway, otherwise the next; after the last one, that last one. */
fun List<BiathlonEvent>.eventToShow(now: Instant, zone: ZoneId): BiathlonEvent? {
    val ordered = sortedBy { it.startDate }
    return ordered.firstOrNull { it.phase(now, zone) != BiathlonEvent.Phase.PAST } ?: ordered.lastOrNull()
}
