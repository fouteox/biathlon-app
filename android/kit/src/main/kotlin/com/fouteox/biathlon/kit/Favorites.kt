package com.fouteox.biathlon.kit

import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** The athletes and nations a user follows, to pick out their result rows. */
data class FavoriteSet(val athleteIds: Set<String>, val nations: Set<String>) {
    val isEmpty: Boolean get() = athleteIds.isEmpty() && nations.isEmpty()

    fun contains(row: ResultRow): Boolean = row.athleteId in athleteIds || row.nation in nations

    /**
     * A standings row is a favorite as a result row is: the athlete, or anyone of a favorite
     * nation; a nation's own row through its code.
     */
    fun contains(row: CupRow): Boolean =
        row.athleteId in athleteIds || (row.nation ?: row.name.takeIf { row.isNation }) in nations
}

/** The favorites' rows, in the standings' order, to show at the top with their rank. */
fun CupStandings.favorites(favorites: FavoriteSet): List<CupRow> = rows.filter(favorites::contains)

/** A standings row is a favorite itself or, for a relay team, through one of its legs. */
fun RaceResults.isFavorite(row: ResultRow, favorites: FavoriteSet): Boolean =
    favorites.contains(row) || (row.isTeam && legs(row).any(favorites::contains))

/** The first `top` standings, then the favorites ranked below them: each row once. */
fun RaceResults.featuredStandings(top: Int, favorites: FavoriteSet): List<ResultRow> =
    standings.take(top) + standings.drop(top).filter { isFavorite(it, favorites) }

/**
 * The overall standings of the season, athletes' and nations', men's and women's: where each
 * favorite stands, for the list of favorites.
 */
class FavoriteStandings internal constructor(
    /** The season the standings are from: the previous one until the current has its first race. */
    val season: SeasonId,
    /** The season containing the request date. */
    val requestedSeason: SeasonId,
    private val athletes: Map<RaceCategory, CupStandings>,
    private val nations: Map<RaceCategory, CupStandings>,
) {
    /** The previous season's standings, shown until the current season has its first race. */
    val isFallback: Boolean get() = season != requestedSeason

    /** Before the season's first race, any of the four can still be empty. */
    internal val isEmpty: Boolean get() = (athletes.values + nations.values).any { it.rows.isEmpty() }

    /** The athlete's row, in whichever category they race. */
    fun standingOfAthlete(id: String): CupRow? =
        RaceCategory.WITH_STANDINGS.firstNotNullOfOrNull { category -> athletes[category]?.rows?.firstOrNull { it.athleteId == id } }

    /** The nation's rows, men's then women's, in the Nations Cup, which keys them by code. */
    fun standingsOfNation(code: String): List<Pair<RaceCategory, CupRow>> =
        RaceCategory.WITH_STANDINGS.mapNotNull { category ->
            nations[category]?.rows?.firstOrNull { it.nation == code || it.athleteId == code }?.let { category to it }
        }
}

/**
 * The four standings at once, all of one season: the current one, or the previous one while any
 * of the four is still empty, so the favorites never mix two seasons around the opening races.
 */
suspend fun IbuClient.favoriteStandings(now: Instant): FavoriteStandings {
    val requested = SeasonId.containing(now)
    val current = favoriteStandings(requested, requested)
    return if (current.isEmpty) favoriteStandings(requested.previous, requested) else current
}

private suspend fun IbuClient.favoriteStandings(season: SeasonId, requested: SeasonId): FavoriteStandings = coroutineScope {
    fun standings(category: RaceCategory, discipline: StandingsDiscipline) =
        async { cupStandings(Cup.worldCupId(season, category, discipline)) }

    val athletes = RaceCategory.WITH_STANDINGS.associateWith { standings(it, StandingsDiscipline.TOTAL) }
    val nations = RaceCategory.WITH_STANDINGS.associateWith { standings(it, StandingsDiscipline.NATIONS) }
    FavoriteStandings(
        season,
        requested,
        athletes.mapValues { it.value.await() },
        nations.mapValues { it.value.await() },
    )
}
