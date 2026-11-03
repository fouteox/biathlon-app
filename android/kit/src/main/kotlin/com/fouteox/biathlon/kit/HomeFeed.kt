package com.fouteox.biathlon.kit

import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/** What the home screen shows: the live race if there is one, otherwise the next one, plus the latest results. */
class HomeFeed(
    /**
     * The most recent event already started and the next one: a race can finish after its
     * event's `EndDate`, and between two events both the latest result and the next race are needed.
     */
    val events: List<BiathlonEvent>,
    races: List<Competition>,
    val liveResults: RaceResults? = null,
    val latestResults: RaceResults? = null,
) {
    /** Races of [events], by start time. */
    val races: List<Competition> = races.sortedBy { it.startTime }

    val live: Competition? get() = races.firstOrNull { it.state == Competition.State.LIVE }
    val next: Competition? get() = races.firstOrNull { it.state == Competition.State.SCHEDULED }
    val latestFinished: Competition? get() = races.lastOrNull { it.state == Competition.State.FINISHED }

    /**
     * When the app, open before a race with none live, fetches the feed again so the live race
     * shows by itself: at the next race's start, then every minute, as the IBU marks a race live
     * a little after its start. `null` while a race is live, which the app polls, and with no race ahead.
     */
    fun nextStartRefreshTime(now: Instant): Instant? {
        val next = next
        if (live != null || next == null) return null
        return maxOf(next.startTime, now.plusSeconds(LATE_START_INTERVAL_SECONDS))
    }

    /** Event of the featured race. */
    val event: BiathlonEvent?
        get() = (live ?: next ?: latestFinished)?.let(::event) ?: events.lastOrNull()

    /** A race's event (a `RaceId` starts with its `EventId`): between two events, the latest result belongs to the previous one. */
    fun event(race: Competition): BiathlonEvent? = events.firstOrNull { race.id.startsWith(it.id) }

    /** Nothing to feature: no race to show and no event to open. */
    val isEmpty: Boolean get() = live == null && next == null && latestFinished == null && event == null

    companion object {
        const val LATE_START_INTERVAL_SECONDS = 60L
    }
}

/** The races of the most recent event already started and of the next one, without their results. */
suspend fun IbuClient.featuredRaces(now: Instant): HomeFeed {
    val season = SeasonId.containing(now)
    val events = events(season).sortedBy { it.startDate }
    val upcoming = events.firstOrNull { it.startDate > now }
    // Before the first event of a season: the latest result of the previous one.
    val started = events.lastOrNull { it.startDate <= now } ?: events(season.previous).maxByOrNull { it.startDate }
    val featured = listOfNotNull(started, upcoming)
    return HomeFeed(featured, competitions(featured))
}

/** The featured races and the results of the live one and of the latest finished one. */
suspend fun IbuClient.homeFeed(now: Instant): HomeFeed {
    val feed = featuredRaces(now)
    val (live, latest) = coroutineScope {
        listOf(feed.live, feed.latestFinished).map { race -> async { race?.let { results(it.id) } } }.awaitAll()
    }
    return HomeFeed(feed.events, feed.races, live, latest)
}

/** Races of each event, requested together, in the order of `events`. */
internal suspend fun IbuClient.competitions(events: List<BiathlonEvent>): List<Competition> = coroutineScope {
    events.map { async { competitions(it.id) } }.awaitAll().flatten()
}
