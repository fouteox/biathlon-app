package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.BiathlonEvent
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.SeasonId
import com.fouteox.biathlon.kit.eventToShow
import com.fouteox.biathlon.kit.groupedByDay
import com.fouteox.biathlon.kit.groupedByMonth
import com.fouteox.biathlon.kit.phase
import java.time.Instant
import java.time.ZoneId

/** The World Cup calendar of a season, by month, opening on the event underway or the next one. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(open: (Route) -> Unit) {
    val client = LocalIbuClient.current
    val seasons = remember { SeasonId.since(SeasonId.FIRST_WITH_RACES, Instant.now()) }
    var season by rememberSaveable { mutableStateOf(seasons.first().rawValue) }
    // A season's list keeps its own data: picking it again shows it at once, then refreshes it.
    // Its fetch captures the season it was made for, not the state, which can be another's.
    val shown = SeasonId(season)
    val events = viewModel(key = shown.rawValue) { LoadViewModel { client.events(shown) } }
    WhileStarted(events) { events.load() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.calendar)) },
                actions = { SeasonPicker(seasons, SeasonId(season)) { season = it.rawValue } },
            )
        },
    ) { padding ->
        val zone = ZoneId.systemDefault()
        // Kept per season, so that coming back from an event leaves the list where it was.
        val listState = rememberSaveable(season, saver = LazyListState.Saver) { LazyListState() }
        val loaded by events.state.collectAsStateWithLifecycle()
        var scrolledSeason by rememberSaveable { mutableStateOf<String?>(null) }
        // The season opens on the event underway, or the next one, not on November: once per season.
        LaunchedEffect(loaded, season) {
            val list = loaded.value ?: return@LaunchedEffect
            if (scrolledSeason == season) return@LaunchedEffect
            scrolledSeason = season
            val event = list.eventToShow(Instant.now(), zone) ?: return@LaunchedEffect
            listState.scrollToItem(calendarIndex(list, event, zone))
        }
        LoadableList(events, padding, listState, empty = { if (it.isEmpty()) R.string.calendar_not_published else null }) { list ->
            calendar(list, zone, open)
        }
    }
}

/** By month: the season runs from November to March, and a month is how people place an event in time. */
private fun LazyListScope.calendar(events: List<BiathlonEvent>, zone: ZoneId, open: (Route) -> Unit) {
    val now = Instant.now()
    for (month in events.groupedByMonth(zone)) {
        item(key = month.period.toString()) { SectionHeader(formatted(month.period)) }
        items(month.items, key = { it.id }) { event ->
            EventRow(event, Modifier.clickable { open(Route.Event(event)) }, event.phase(now, zone))
        }
    }
}

/** The event's position in [calendar]'s list, after its month's header and those before it. */
private fun calendarIndex(events: List<BiathlonEvent>, event: BiathlonEvent, zone: ZoneId): Int {
    var index = 0
    for (month in events.groupedByMonth(zone)) {
        index += 1
        val position = month.items.indexOf(event)
        if (position >= 0) return index + position
        index += month.items.size
    }
    return 0
}

@Composable
private fun SeasonPicker(seasons: List<SeasonId>, selection: SeasonId, select: (SeasonId) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }) { Text(stringResource(R.string.season_arg, selection.displayName)) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            for (season in seasons) {
                DropdownMenuItem(
                    text = { Text(season.displayName) },
                    onClick = {
                        expanded = false
                        select(season)
                    },
                )
            }
        }
    }
}

/** An event's races, by day: the day once in the header, the time on each row. */
@Composable
fun EventScreen(event: BiathlonEvent, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    val races = viewModel { LoadViewModel { client.competitions(event.id) } }
    WhileStarted(races) { races.load() }
    Screen(Nation.titled(event.shortDescription, event.nation), onBack) { padding ->
        val zone = ZoneId.systemDefault()
        LoadableList(races, padding, empty = { if (it.isEmpty()) R.string.schedule_not_published else null }) { list ->
            for (day in list.groupedByDay(zone)) {
                item(key = day.period.toString()) { SectionHeader(formatted(day.period, DateSkeleton.DAY)) }
                items(day.items, key = { it.id }) { race ->
                    RaceRow(race, Modifier.clickable { open(Route.Race(race)) }, StartDetail.TIME_ONLY)
                }
            }
        }
    }
}

/**
 * An event's place, dates and championship, in the calendar and at the top of the home screen.
 * Over a whole season, past events recede and the one underway says so.
 */
@Composable
fun EventRow(event: BiathlonEvent, modifier: Modifier = Modifier, phase: BiathlonEvent.Phase? = null) {
    val past = phase == BiathlonEvent.Phase.PAST
    val colors = if (past) {
        ListItemDefaults.colors(headlineColor = MaterialTheme.colorScheme.onSurfaceVariant, supportingColor = MaterialTheme.colorScheme.outline)
    } else {
        ListItemDefaults.colors()
    }
    ListItem(
        modifier = modifier,
        colors = colors,
        leadingContent = { Text(Nation.flag(event.nation) ?: event.nation.orEmpty(), style = MaterialTheme.typography.headlineSmall) },
        headlineContent = { Text(event.shortDescription, fontWeight = FontWeight.SemiBold) },
        supportingContent = {
            Column {
                Text(formattedDays(event.startDate, event.endDate))
                val championship = when {
                    event.isWorldChampionships -> R.string.world_championships
                    event.isOlympics -> R.string.olympic_games
                    else -> null
                }
                championship?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold) }
            }
        },
        trailingContent = if (phase == BiathlonEvent.Phase.UNDERWAY) {
            { Text(stringResource(R.string.underway), color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold) }
        } else {
            null
        },
    )
}
