package com.fouteox.biathlon

import android.content.Intent
import android.provider.CalendarContract
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.FavoriteSet
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceResults
import com.fouteox.biathlon.kit.ResultRow
import com.fouteox.biathlon.kit.TvGuide
import com.fouteox.biathlon.kit.hasAnalysisRankings
import com.fouteox.biathlon.kit.isFavorite
import java.time.Instant
import java.util.Locale

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
    val tvGuide = rememberTvGuide()
    val guide = tvGuide?.state?.collectAsStateWithLifecycle()?.value?.value
    val favorites = rememberFavoriteSet()
    Screen(race.title(), onBack, actions = { RaceActions(latest, state.value, open) }) { padding ->
        // A relay's teams opened on their legs.
        var expanded by rememberSaveable { mutableStateOf(setOf<String>()) }
        val home = LocalConfiguration.current.locales[0].country.ifEmpty { null }
        // The other countries' channels, folded away.
        var showsOtherCountries by rememberSaveable { mutableStateOf(false) }
        LoadableList(results, padding, alsoLoading = listOfNotNull(tvGuide)) { loaded ->
            val competition = loaded.competition ?: race
            item { RaceSummary(competition, loaded) }
            // Only while it can still be watched live.
            guide?.takeIf { competition.state.canBeFollowedLive }?.listings(competition.startTime, home)?.let { listings ->
                tvCoverage(listings, showsOtherCountries) { showsOtherCountries = !showsOtherCountries }
            }
            if (loaded.rows.isEmpty()) {
                // In the list, below the race's place and start, rather than over them.
                item {
                    val message = if (competition.state == Competition.State.CANCELLED) R.string.race_cancelled else R.string.no_start_list_yet
                    EmptyMessage(stringResource(message))
                }
            } else {
                item { listTitle(loaded, isLive)?.let { SectionHeader(it) } }
                rows(competition, loaded, favorites, expanded, open) { team -> expanded = if (team in expanded) expanded - team else expanded + team }
                (state as? Loadable.Loaded)?.loadedAt?.takeIf { isLive }?.let { loadedAt ->
                    item { SectionFooter(updatedAt(loadedAt)) }
                }
            }
        }
    }
}

/**
 * Who shows the races on TV, from the server, which keeps it by hand; `null` without a server,
 * the screen then going without it.
 */
@Composable
private fun rememberTvGuide(): LoadViewModel<TvGuide>? {
    val server = LocalServerClient.current ?: return null
    val guide = viewModel(key = "tvGuide") { LoadViewModel { server.tvGuide() } }
    WhileStarted(guide) { guide.load() }
    return guide
}

/**
 * The race's actions in the top app bar: a race has dozens of rows, which they would sit below.
 * The analysis and the podium to share once the results are in, the calendar until the start.
 */
@Composable
private fun RowScope.RaceActions(race: Competition, results: RaceResults?, open: (Route) -> Unit) {
    val context = LocalContext.current
    if (results != null && results.isResult && race.hasAnalysisRankings) {
        BarAction(R.drawable.ic_timer, stringResource(R.string.course_range_and_shooting_times)) { open(Route.Analysis(race)) }
    }
    results?.let { podium(race, it) }?.let { podium ->
        BarAction(R.drawable.ic_share, stringResource(R.string.share)) {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, podium)
            context.startActivity(Intent.createChooser(send, null))
        }
    }
    if (race.state == Competition.State.SCHEDULED) {
        val entry = calendarEntry(race.title(), race.startTime, results?.event?.shortDescription)
        // Only with an app to add it, which the system's calendar provider doesn't guarantee.
        if (remember(entry) { entry.resolveActivity(context.packageManager) != null }) {
            BarAction(R.drawable.ic_calendar_add_on, stringResource(R.string.add_to_calendar)) { context.startActivity(entry) }
        }
    }
}

/**
 * The race in the person's calendar app, which asks where to save it: no calendar permission.
 * The IBU gives a race's start, not its end, so it ends when it starts, as on iOS.
 */
private fun calendarEntry(title: String, start: Instant, location: String?): Intent =
    Intent(Intent.ACTION_INSERT)
        .setDataAndType(CalendarContract.Events.CONTENT_URI, CALENDAR_EVENTS_TYPE)
        .putExtra(CalendarContract.Events.TITLE, title)
        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.toEpochMilli())
        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, start.toEpochMilli())
        .putExtra(CalendarContract.Events.EVENT_LOCATION, location)

/** The type of the calendar provider's events, which calendar apps take inserts of (declared in the manifest's queries). */
private const val CALENDAR_EVENTS_TYPE = "vnd.android.cursor.dir/event"

/** The race's winner and the two after, names as a voice reads them, race and place first; `null` before its results. */
@Composable
private fun podium(race: Competition, results: RaceResults): String? {
    val locale = LocalConfiguration.current.locales[0]
    val podium = results.podium.map { it.spokenName(locale) }
    val winner = podium.firstOrNull() ?: return null
    val heading = listOfNotNull(race.title(), results.event?.shortDescription).joinToString(", ")
    return if (podium.size == 3) {
        stringResource(R.string.arg_arg_wins_ahead_of_arg_and_arg, heading, winner, podium[1], podium[2])
    } else {
        stringResource(R.string.arg_arg_wins, heading, winner)
    }
}

/**
 * Who shows the race on TV: the viewer's own country, then the others the server lists, folded
 * away but always there to look up, whatever the app's language. Each broadcaster opens its
 * live stream.
 */
private fun LazyListScope.tvCoverage(listings: TvGuide.Listings, showsOthers: Boolean, toggleOthers: () -> Unit) {
    if (listings.isEmpty) return
    item { SectionHeader(stringResource(R.string.on_tv)) }
    listings.home?.let { broadcasters(it) }
    if (listings.others.isNotEmpty()) {
        item {
            val state = stringResource(if (showsOthers) R.string.expanded else R.string.collapsed)
            ListItem(
                modifier = Modifier.clickable(onClick = toggleOthers).semantics { stateDescription = state },
                headlineContent = { Text(stringResource(R.string.other_countries)) },
                trailingContent = { Icon(painterResource(if (showsOthers) R.drawable.ic_expand_less else R.drawable.ic_expand_more), contentDescription = null) },
            )
        }
        if (showsOthers) listings.others.forEach { broadcasters(it) }
    }
    item { SectionFooter(stringResource(R.string.live_on_tv_or_on_the_broadcaster_s_stream_schedules_can_change)) }
}

private fun LazyListScope.broadcasters(listing: TvGuide.Listing) {
    items(listing.broadcasters, key = { "tv/${it.country}/${it.broadcaster}" }) { coverage ->
        val uriHandler = LocalUriHandler.current
        val country = Nation.titledByRegion(Locale.Builder().setRegion(listing.country).build().displayCountry, listing.country)
        ListItem(
            modifier = Modifier.clickable { uriHandler.openUri(coverage.url.toString()) },
            overlineContent = { Text(country) },
            headlineContent = { Text(coverage.broadcaster) },
        )
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

private fun LazyListScope.rows(
    race: Competition,
    results: RaceResults,
    favorites: FavoriteSet,
    expanded: Set<String>,
    open: (Route) -> Unit,
    toggle: (String) -> Unit,
) {
    // A relay team is a favorite through one of its legs too.
    fun isFavorite(row: ResultRow) = results.isFavorite(row, favorites)
    if (!race.isRelay) {
        items(results.standings, key = { it.id }) { ResultLink(it, isFavorite(it), open) }
        return
    }
    for (team in results.standings) {
        val isExpanded = team.id in expanded
        item(key = team.id) {
            val state = stringResource(if (isExpanded) R.string.expanded else R.string.collapsed)
            ResultLine(team, isFavorite(team), Modifier.clickable { toggle(team.id) }.semantics { stateDescription = state })
        }
        if (isExpanded) items(results.legs(team), key = { it.id }) { ResultLink(it, isFavorite(it), open, Modifier.padding(start = 24.dp)) }
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
