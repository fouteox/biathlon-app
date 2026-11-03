package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.HomeFeed
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceResults

@Composable
fun HomeScreen(feed: LoadViewModel<HomeFeed>, open: (Route) -> Unit) {
    Screen(stringResource(R.string.home), onBack = null) { padding ->
        LoadableList(feed, padding, empty = { if (it.isEmpty) R.string.no_races else null }) { feed ->
            featured(feed, open)
            val live = feed.live
            val next = feed.next
            // The next race keeps its section while another is live.
            if (live != null && next != null) {
                item { SectionHeader(stringResource(R.string.next_race)) }
                item { RaceRow(next, Modifier.clickable { open(Route.Race(next)) }) }
            }
            val latest = feed.latestResults
            val finished = feed.latestFinished
            if (latest != null && finished != null) latestResult(feed, finished, latest, open)
        }
    }
}

/**
 * The anchor: the live race, otherwise the next one, under its event, the context of the races
 * below; with no race ahead, as after a season's last race, the event on its own.
 */
private fun LazyListScope.featured(feed: HomeFeed, open: (Route) -> Unit) {
    val race = feed.live ?: feed.next
    val event = feed.event
    if (race == null && event != null) item { SectionHeader(stringResource(R.string.event)) }
    if (event != null) item { EventRow(event, Modifier.clickable { open(Route.Event(event)) }) }
    if (race == null) return
    item { RaceHeading(race, Modifier.clickable { open(Route.Race(race)) }) }
    val results = feed.liveResults
    if (race.state == Competition.State.LIVE && results != null) {
        items(results.standings.take(LIVE_TOP), key = { it.id }) { ResultLine(it) }
    }
}

/** The podium of the latest finished race, its name in the header and its start below. */
private fun LazyListScope.latestResult(feed: HomeFeed, race: Competition, results: RaceResults, open: (Route) -> Unit) {
    item { SectionHeader(stringResource(R.string.latest_result_arg, race.title())) }
    items(results.standings.take(PODIUM), key = { it.id }) { ResultLine(it) }
    item {
        ListItem(
            headlineContent = { Text(stringResource(R.string.all_results)) },
            modifier = Modifier.clickable { open(Route.Race(race)) },
        )
    }
    item {
        // Between two events, where: its event is then not the one at the top.
        val start = formatted(race.startTime, DateSkeleton.START)
        val event = feed.event(race)?.takeIf { it != feed.event }
        SectionFooter(event?.let { stringResource(R.string.arg_arg, start, Nation.titled(it.shortDescription, it.nation)) } ?: start)
    }
}

/**
 * The race the home screen is anchored on, larger than the rows below it: its name, its start
 * and, while it is still to come, how far away that is.
 */
@Composable
private fun RaceHeading(race: Competition, modifier: Modifier = Modifier) {
    val isLive = race.state == Competition.State.LIVE
    Column(modifier.padding(horizontal = 16.dp, vertical = 12.dp).semantics(mergeDescendants = true) {}) {
        if (isLive) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(painterResource(R.drawable.ic_live), contentDescription = null, Modifier.size(16.dp), tint = race.state.tint)
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.live), color = race.state.tint, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
            }
        }
        Text(race.title(), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (isLive) {
            Text(stringResource(R.string.start_arg, formatted(race.startTime, DateSkeleton.TIME)), color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Text(formatted(race.startTime, DateSkeleton.START), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(formattedFromNow(race.startTime), style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** The top of a live race's standings, and of a finished race's. */
private const val LIVE_TOP = 5
private const val PODIUM = 3
