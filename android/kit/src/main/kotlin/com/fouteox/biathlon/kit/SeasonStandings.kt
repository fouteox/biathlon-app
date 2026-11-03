package com.fouteox.biathlon.kit

import java.time.Instant

/** World Cup standings of a season: by default the current one, or the previous until the current one has its first race. */
data class SeasonStandings(
    /** The season shown. */
    val season: SeasonId,
    /** The season containing the request date. */
    val requestedSeason: SeasonId,
    val standings: CupStandings,
) {
    val isFallback: Boolean get() = season != requestedSeason
}

/** The current season's standings, or the previous season's until the current one has its first race. */
suspend fun IbuClient.worldCupStandings(category: RaceCategory, discipline: StandingsDiscipline, now: Instant): SeasonStandings {
    val current = worldCupStandings(category, discipline, SeasonId.containing(now))
    if (current.standings.rows.isNotEmpty()) return current
    val previous = worldCupStandings(category, discipline, current.season.previous)
    return previous.copy(requestedSeason = current.season)
}

/** The standings of `season`, as they are, even empty before its first race. */
suspend fun IbuClient.worldCupStandings(category: RaceCategory, discipline: StandingsDiscipline, season: SeasonId): SeasonStandings =
    SeasonStandings(season, season, cupStandings(Cup.worldCupId(season, category, discipline)))
