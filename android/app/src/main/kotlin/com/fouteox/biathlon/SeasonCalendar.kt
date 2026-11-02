package com.fouteox.biathlon

import com.fouteox.biathlon.kit.Date
import com.fouteox.biathlon.kit.IBUClient
import com.fouteox.biathlon.kit.SeasonID
import java.time.Instant
import kotlinx.coroutines.future.await
import org.swift.swiftkit.core.SwiftArena

/** An event of the season's calendar, copied out of BiathlonKit's Swift values. */
data class CalendarEvent(
    val id: String,
    val place: String,
    val nation: String?,
    val start: Instant,
    val end: Instant,
)

/**
 * The events of the season that contains [now]. The Swift values live in an arena of their own,
 * closed once they are copied, so none outlives the call.
 */
suspend fun IBUClient.seasonCalendar(now: Instant): List<CalendarEvent> =
    SwiftArena.ofConfined().use { arena ->
        val season = SeasonID.containing(Date.fromInstant(now, arena), arena)
        events(season, arena).await().map { event ->
            CalendarEvent(
                id = event.id,
                place = event.shortDescription,
                nation = event.nation.orElse(null),
                start = event.getStartDate(arena).toInstant(),
                end = event.getEndDate(arena).toInstant(),
            )
        }
    }
