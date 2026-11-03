package com.fouteox.biathlon.kit

import java.time.Instant

/** An athlete's World Cup circuit results, season by season, as their profile shows them. */
class AthleteHistory(results: List<AthleteResult>, now: Instant) {
    /**
     * The World Cup, World Championships and Olympic races, which the rest of the app follows,
     * newest first as `AllResults` lists them.
     */
    val results: List<AthleteResult> = results.filter { it.isWorldCupCircuit }

    private val withResults = this.results.mapNotNull { it.seasonId }.toSet()

    private val current = SeasonId.containing(now)

    /** The current season, then those with results, newest first. */
    val seasons: List<SeasonId> = listOf(current) + (withResults - current).sortedDescending()

    /**
     * The season the profile opens on: the newest with results, so that before the athlete's
     * first race of the season it shows the last one, as the standings do.
     */
    val initialSeason: SeasonId = withResults.maxOrNull() ?: current

    fun results(season: SeasonId): List<AthleteResult> = results.filter { it.seasonId == season }
}

/** The athlete's row in the World Cup overall standings of `category` for `season`, or `null` when they scored no points. */
suspend fun IbuClient.worldCupStanding(athleteId: String, category: RaceCategory, season: SeasonId): CupRow? =
    cupStandings(Cup.worldCupId(season, category, StandingsDiscipline.TOTAL)).rows.firstOrNull { it.athleteId == athleteId }
