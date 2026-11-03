package com.fouteox.biathlon.kit

import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale

/** IBU season ID, for example `2627` for the 2026-27 winter. */
@JvmInline
value class SeasonId(val rawValue: String) : Comparable<SeasonId> {
    /** The year the season starts: athletes' histories go back to the 1990s ("98/99"). */
    internal val start: Int
        get() {
            val year = rawValue.take(2).toIntOrNull() ?: 0
            return if (year < 50) 2000 + year else 1900 + year
        }

    val previous: SeasonId get() = starting(start - 1)

    /** `2026-27` */
    val displayName: String get() = "$start-${rawValue.takeLast(2)}"

    override fun compareTo(other: SeasonId) = start.compareTo(other.start)

    override fun toString() = rawValue

    companion object {
        /**
         * The oldest season of biathlonresults.com, whose `Seasons` start in 1957-58: its races
         * are those of the 1958 World Championships in Saalfelden (`BT5758SWRLCH__`).
         */
        val FIRST_WITH_RACES = starting(1957)

        /** The first World Cup season, the oldest with standings (`CupResults?CupId=BT7778SWRLCP__SMTS`). */
        val FIRST_WORLD_CUP = starting(1977)

        fun starting(year: Int) = SeasonId("%02d%02d".format(Locale.ROOT, year % 100, (year + 1) % 100))

        /** The season rolls over on July 1, in UTC like the server. */
        fun containing(instant: Instant): SeasonId {
            val date = instant.atOffset(ZoneOffset.UTC)
            return starting(if (date.monthValue >= 7) date.year else date.year - 1)
        }

        /** The seasons from `first` to the one containing `now`, newest first. */
        fun since(first: SeasonId, now: Instant): List<SeasonId> =
            generateSequence(containing(now)) { it.previous }.takeWhile { it >= first }.toList()
    }
}
