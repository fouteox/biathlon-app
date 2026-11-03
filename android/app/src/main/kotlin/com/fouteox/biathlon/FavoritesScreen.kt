package com.fouteox.biathlon

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.FavoriteSet
import com.fouteox.biathlon.kit.FavoriteStandings
import com.fouteox.biathlon.kit.Gender
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.favoriteStandings
import java.time.Instant
import kotlinx.coroutines.launch

/** The favorites, on the device; tests give each their own. */
val LocalFavorites = staticCompositionLocalOf<Favorites> { error("No Favorites provided") }

/** The favorites in the order they were added, `null` until they are read. */
@Composable
fun rememberFavorites(): List<Favorite>? {
    val favorites = LocalFavorites.current
    return favorites.all.collectAsStateWithLifecycle(initialValue = null).value
}

/** The favorites every list marks, none until they are read. */
@Composable
fun rememberFavoriteSet(): FavoriteSet {
    val favorites = LocalFavorites.current
    return favorites.set.collectAsStateWithLifecycle(initialValue = NO_FAVORITES).value
}

private val NO_FAVORITES = FavoriteSet(athleteIds = emptySet(), nations = emptySet())

/** The star of an athlete's or a nation's screen, in its top app bar. */
@Composable
fun FavoriteButton(kind: Favorite.Kind, key: String, name: String, nation: String?) {
    val favorites = LocalFavorites.current
    val isFavorite by remember(favorites, kind, key) { favorites.contains(kind, key) }.collectAsStateWithLifecycle(initialValue = false)
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    IconToggleButton(
        checked = isFavorite,
        onCheckedChange = { checked ->
            haptics.performHapticFeedback(if (checked) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff)
            scope.launch { favorites.toggle(kind, key, name, nation) }
        },
    ) {
        // TalkBack reads the state, "checked" or "not checked", after the name.
        Icon(painterResource(if (isFavorite) R.drawable.ic_star_filled else R.drawable.ic_star), stringResource(R.string.favorite))
    }
}

/** The athletes and nations followed, each with where they stand this season. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(open: (Route) -> Unit) {
    val client = LocalIbuClient.current
    val favorites = LocalFavorites.current
    val all = rememberFavorites()
    // The rows go without their standing until it loads, or if it fails.
    val standings = viewModel(key = "favoriteStandings") { LoadViewModel { client.favoriteStandings(Instant.now()) } }
    WhileStarted(standings) { standings.load() }
    WhileStarted(favorites) { favorites.refreshAthletes(client) }
    val loaded by standings.state.collectAsStateWithLifecycle()
    val isRefreshing by standings.isRefreshing.collectAsStateWithLifecycle()
    Screen(stringResource(R.string.favorites), onBack = null) { padding ->
        val modifier = Modifier.fillMaxSize().padding(padding)
        when {
            all == null -> Box(modifier)
            all.isEmpty() -> Prompt(
                R.drawable.ic_star,
                stringResource(R.string.no_favorites),
                stringResource(R.string.tap_the_star_on_a_biathlete_or_a_team_to_follow_their_results_from_the_home_screen),
                modifier,
            )
            else -> PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = standings::refresh, modifier = modifier) {
                LazyColumn(Modifier.fillMaxSize()) {
                    val shown = loaded.value
                    section(all, Favorite.Kind.ATHLETE, R.string.biathletes, R.string.rank_and_points_in_the_world_cup_overall_standings, shown, open)
                    section(all, Favorite.Kind.NATION, R.string.teams, R.string.rank_in_the_nations_cup_men_and_women, shown, open)
                }
            }
        }
    }
}

private fun LazyListScope.section(
    all: List<Favorite>,
    kind: Favorite.Kind,
    title: Int,
    footer: Int,
    standings: FavoriteStandings?,
    open: (Route) -> Unit,
) {
    val favorites = all.filter { it.kind == kind }
    if (favorites.isEmpty()) return
    item { SectionHeader(stringResource(title)) }
    items(favorites, key = { "${it.kind}/${it.key}" }) { FavoriteRow(it, standings, open) }
    if (standings != null) {
        item {
            Column {
                SectionFooter(stringResource(footer))
                // Before the season's first race, as the standings tab says it.
                if (standings.isFallback) {
                    SectionFooter(
                        stringResource(
                            R.string.season_arg_the_arg_standings_will_appear_after_the_first_race,
                            standings.season.displayName,
                            standings.requestedSeason.displayName,
                        ),
                    )
                }
            }
        }
    }
}

/** A favorite, swiped away to remove it, as TalkBack's actions also can. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FavoriteRow(favorite: Favorite, standings: FavoriteStandings?, open: (Route) -> Unit) {
    val favorites = LocalFavorites.current
    val scope = rememberCoroutineScope()
    val remove = { scope.launch { favorites.remove(favorite) } }
    val removeLabel = stringResource(R.string.remove_from_favorites)
    val route = when (favorite.kind) {
        Favorite.Kind.ATHLETE -> Route.Athlete(favorite.key, favorite.name)
        Favorite.Kind.NATION -> Route.Nation(favorite.key, RaceCategory.MEN)
    }
    SwipeToDismissBox(
        state = rememberSwipeToDismissBoxState(),
        enableDismissFromStartToEnd = false,
        onDismiss = { remove() },
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(painterResource(R.drawable.ic_delete), contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
            }
        },
    ) {
        ListItem(
            modifier = Modifier
                .clickable { open(route) }
                .semantics { customActions = listOf(CustomAccessibilityAction(removeLabel) { remove(); true }) },
            leadingContent = { NationMark(favorite.nation ?: favorite.key) },
            headlineContent = { Text(favorite.title) },
            supportingContent = if (favorite.isDeceased) {
                { Text(stringResource(if (favorite.gender == Gender.WOMAN) R.string.deceased_woman else R.string.deceased)) }
            } else {
                null
            },
            trailingContent = standings?.let { { Text(standing(favorite, it), style = MaterialTheme.typography.bodyMedium) } },
        )
    }
}

/**
 * Where the favorite stands: an athlete's rank and points, a nation's rank in each Nations Cup,
 * or "Not ranked" once the standings are in without them.
 */
@Composable
private fun standing(favorite: Favorite, standings: FavoriteStandings): String = when (favorite.kind) {
    Favorite.Kind.ATHLETE -> standings.standingOfAthlete(favorite.key)?.let { rankAndPoints(it) } ?: stringResource(R.string.not_ranked)
    Favorite.Kind.NATION -> {
        val ranks = standings.standingsOfNation(favorite.key).map { (category, row) -> "${stringResource(category.title)} ${row.rank ?: "–"}" }
        ranks.joinToString(" · ").ifEmpty { stringResource(R.string.not_ranked) }
    }
}
