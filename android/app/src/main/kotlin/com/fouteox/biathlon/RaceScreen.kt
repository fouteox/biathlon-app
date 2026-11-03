package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceResults
import com.fouteox.biathlon.kit.ResultRow
import com.fouteox.biathlon.kit.hasAnalysisRankings
import java.time.Instant

/** A race's place and start, then its start list or results, refreshed every 20 seconds while it is live. */
@Composable
fun RaceScreen(race: Competition, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    val results = viewModel(key = "results") { LoadViewModel { client.results(race.id) } }
    WhileStarted(results) { results.load() }
    val state by results.state.collectAsStateWithLifecycle()
    // The race as its results last gave it, or as the calendar did.
    val latest = state.value?.competition ?: race
    val isLive = latest.state == Competition.State.LIVE
    RefreshWhileLive(isLive, results::load)
    // A race has dozens of rows: the analysis sits in the bar rather than below them all.
    val analysis = state.value?.takeIf { it.isResult && latest.hasAnalysisRankings }
    Screen(
        race.title(),
        onBack,
        actions = { if (analysis != null) BarAction(R.drawable.ic_timer, stringResource(R.string.course_range_and_shooting_times)) { open(Route.Analysis(latest)) } },
    ) { padding ->
        // A relay's teams opened on their legs.
        var expanded by rememberSaveable { mutableStateOf(setOf<String>()) }
        LoadableList(results, padding) { loaded ->
            val competition = loaded.competition ?: race
            item { RaceSummary(competition, loaded) }
            if (loaded.rows.isEmpty()) {
                // In the list, below the race's place and start, rather than over them.
                item {
                    val message = if (competition.state == Competition.State.CANCELLED) R.string.race_cancelled else R.string.no_start_list_yet
                    EmptyMessage(stringResource(message))
                }
            } else {
                item { listTitle(loaded, isLive)?.let { SectionHeader(it) } }
                rows(competition, loaded, expanded, open) { team -> expanded = if (team in expanded) expanded - team else expanded + team }
                (state as? Loadable.Loaded)?.loadedAt?.takeIf { isLive }?.let { loadedAt ->
                    item { SectionFooter(updatedAt(loadedAt)) }
                }
            }
        }
    }
}

/** Where and when the race is held, in one row, with its state once it is no longer upcoming. */
@Composable
private fun RaceSummary(race: Competition, results: RaceResults) {
    ListItem(
        overlineContent = results.event?.let { event -> { Text(Nation.titled(event.shortDescription, event.nation)) } },
        headlineContent = { Text(formatted(race.startTime, DateSkeleton.START)) },
        trailingContent = { StateBadge(race.state) },
    )
}

private fun LazyListScope.rows(race: Competition, results: RaceResults, expanded: Set<String>, open: (Route) -> Unit, toggle: (String) -> Unit) {
    if (!race.isRelay) {
        items(results.standings, key = { it.id }) { ResultLink(it, open) }
        return
    }
    for (team in results.standings) {
        val isExpanded = team.id in expanded
        item(key = team.id) {
            val state = stringResource(if (isExpanded) R.string.expanded else R.string.collapsed)
            ResultLine(team, Modifier.clickable { toggle(team.id) }.semantics { stateDescription = state })
        }
        if (isExpanded) items(results.legs(team), key = { it.id }) { ResultLink(it, open, Modifier.padding(start = 24.dp)) }
    }
}

/** A race known by its ID alone, such as an athlete's result: found among its event's races first. */
@Composable
fun RaceByIdScreen(raceId: String, title: String, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    val race = viewModel(key = "race") { LoadViewModel { client.race(raceId) } }
    WhileStarted(race) { race.load() }
    val state by race.state.collectAsStateWithLifecycle()
    when (val loaded = state) {
        is Loadable.Loaded -> RaceScreen(loaded.value, open, onBack)
        // Loading or failed, under the title the link gave.
        else -> Screen(title, onBack) { padding -> LoadableList(race, padding) {} }
    }
}

/**
 * Only what the response says the rows are: before the start list is out, the API can return
 * provisional rows that are neither. Live, the title says so.
 */
@Composable
private fun listTitle(results: RaceResults, live: Boolean): String? {
    val title = when {
        results.isResult -> stringResource(R.string.results)
        results.isStartList -> stringResource(R.string.start_list)
        else -> null
    }
    if (!live) return title
    val liveText = stringResource(R.string.live)
    return title?.let { stringResource(R.string.arg_arg, it, liveText) } ?: liveText
}

/** The list changes under the reader while the race is live: when it last did. */
@Composable
private fun updatedAt(loadedAt: Instant) = stringResource(R.string.updated_at_arg, formatted(loadedAt, DateSkeleton.TIME))
