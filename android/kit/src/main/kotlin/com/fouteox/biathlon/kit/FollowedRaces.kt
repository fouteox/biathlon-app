package com.fouteox.biathlon.kit

import java.time.Duration
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

/**
 * The races the user follows live, as `FollowedRaces` on iOS: each one's Live Update shows from
 * its topic's first message, shortly before the start (`RaceLiveState.LEAD`), until its end.
 */
@Serializable
data class FollowedRaces(private val races: Map<String, Race> = emptyMap()) {
    @Serializable
    data class Race(
        /** The IBU's name, for a kind of race the app doesn't know. */
        val name: String,
        /** The race's start when it was followed, in seconds since 1970. */
        val start: Long,
        /** When the state on screen was published, in seconds since 1970; `null` before the first. */
        val shown: Long? = null,
    )

    val raceIds: Set<String> get() = races.keys

    operator fun get(raceId: String): Race? = races[raceId]

    fun follow(raceId: String, name: String, start: Instant) =
        FollowedRaces(races + (raceId to Race(name, start.epochSecond)))

    fun unfollow(raceId: String) = FollowedRaces(races - raceId)

    /**
     * Whether `update` is of a race followed, and newer than the state on screen: FCM doesn't keep
     * messages in order. The server's current state, without a date, always is.
     */
    fun isNew(update: LiveUpdate): Boolean {
        val race = races[update.raceId] ?: return false
        val publishedAt = update.publishedAt ?: return true
        return race.shown == null || publishedAt.epochSecond > race.shown
    }

    /** Whether `update` was published before the state on screen, which it must not replace. */
    fun isOlder(update: LiveUpdate.Update): Boolean {
        val shown = races[update.raceId]?.shown ?: return false
        return update.publishedAt.epochSecond < shown
    }

    fun shown(update: LiveUpdate.Update) =
        races[update.raceId]?.let { FollowedRaces(races + (update.raceId to it.copy(shown = update.publishedAt.epochSecond))) } ?: this

    /** Without the races that started more than [RETENTION] before `now`, whose end never came. */
    fun pruned(now: Instant) = FollowedRaces(races.filterValues { now.epochSecond < it.start + RETENTION.seconds })

    /** As the app keeps it on the device. */
    fun encoded(): String = Json.encodeToString(serializer(), this)

    companion object {
        /** The races `encoded` kept; none when nothing or something unreadable was kept. */
        fun decoded(text: String?): FollowedRaces = text?.let {
            try {
                Json.decodeFromString(serializer(), it)
            } catch (_: SerializationException) {
                null
            }
        } ?: FollowedRaces()

        /**
         * A race is kept this long after the start it was followed with, as on iOS: a race postponed
         * by less still gets its Live Update.
         */
        val RETENTION: Duration = Duration.ofDays(2)
    }
}
