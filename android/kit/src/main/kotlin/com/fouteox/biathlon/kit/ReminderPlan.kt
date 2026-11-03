package com.fouteox.biathlon.kit

import java.time.Duration
import java.time.Instant

/** A "N minutes before the start" reminder, as BiathlonKit's `Reminder`. */
data class Reminder(val race: Competition, val fireTime: Instant)

/** Which local reminders to schedule, as BiathlonKit's `ReminderPlan`. */
object ReminderPlan {
    /** Only races in the coming week are scheduled; later ones are added on a later refresh. */
    val HORIZON: Duration = Duration.ofDays(7)

    /** Reminders for the upcoming races of `categories`, skipping those that would fire in less than a second. */
    fun reminders(races: List<Competition>, categories: Set<RaceCategory>, minutesBefore: Int, now: Instant): List<Reminder> =
        races.mapNotNull { race ->
            val category = race.category
            if (race.state != Competition.State.SCHEDULED || category == null || category !in categories) return@mapNotNull null
            val fireTime = race.startTime.minus(Duration.ofMinutes(minutesBefore.toLong()))
            if (Duration.between(now, fireTime) < Duration.ofSeconds(1)) null else Reminder(race, fireTime)
        }
}

/** Races starting after `now` and within `horizon`. */
suspend fun IbuClient.upcomingRaces(now: Instant, horizon: Duration): List<Competition> {
    val end = now.plus(horizon)
    val events = events(SeasonId.containing(now)).filter { it.endDate >= now && it.startDate <= end }
    return competitions(events).filter { it.startTime > now && it.startTime <= end }
}
