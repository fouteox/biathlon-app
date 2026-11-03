package com.fouteox.biathlon

import android.content.res.Resources
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceKind
import com.fouteox.biathlon.kit.ResultRow
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.WikidataClient
import kotlinx.coroutines.flow.combine

/** The app's client, which tests replace with the fictional World Cup. */
val LocalIbuClient = staticCompositionLocalOf<IbuClient> { error("No IbuClient provided") }

/** The server, `null` in a build without one; tests replace it too. */
val LocalServerClient = staticCompositionLocalOf<ServerClient?> { null }

/** Finds athletes' Wikipedia articles; tests replace it too. */
val LocalWikidataClient = staticCompositionLocalOf<WikidataClient> { error("No WikidataClient provided") }

/** A race's name in the device's language, from the catalog the iOS app and the server's alerts share. */
@get:StringRes
val RaceKind.title: Int
    get() = when (this) {
        RaceKind.MEN_SPRINT -> R.string.race_smsp
        RaceKind.WOMEN_SPRINT -> R.string.race_swsp
        RaceKind.MEN_PURSUIT -> R.string.race_smpu
        RaceKind.WOMEN_PURSUIT -> R.string.race_swpu
        RaceKind.MEN_INDIVIDUAL -> R.string.race_smin
        RaceKind.WOMEN_INDIVIDUAL -> R.string.race_swin
        RaceKind.MEN_SHORT_INDIVIDUAL -> R.string.race_smsi
        RaceKind.WOMEN_SHORT_INDIVIDUAL -> R.string.race_swsi
        RaceKind.MEN_MASS_START -> R.string.race_smms
        RaceKind.WOMEN_MASS_START -> R.string.race_swms
        RaceKind.MEN_RELAY -> R.string.race_smrl
        RaceKind.WOMEN_RELAY -> R.string.race_swrl
        RaceKind.MIXED_RELAY -> R.string.race_mxrl
        RaceKind.SINGLE_MIXED_RELAY -> R.string.race_mxsr
    }

/** Falls back to the IBU's English name for a kind the app doesn't know yet. */
@Composable
@ReadOnlyComposable
fun Competition.title(): String = title(LocalResources.current)

/** [title], outside a screen. */
fun Competition.title(resources: Resources): String = raceTitle(resources, id, shortDescription)

/** A race's title from its ID, falling back to [name], the IBU's English name, for a kind the app doesn't know. */
fun raceTitle(resources: Resources, raceId: String, name: String): String = RaceKind.of(raceId)?.let { resources.getString(it.title) } ?: name

@get:StringRes
val Competition.State.label: Int
    get() = when (this) {
        Competition.State.SCHEDULED -> R.string.upcoming
        Competition.State.LIVE -> R.string.live
        Competition.State.CANCELLED -> R.string.cancelled
        Competition.State.FINISHED -> R.string.finished
    }

val Competition.State.tint: Color
    @Composable @ReadOnlyComposable
    get() = when (this) {
        Competition.State.LIVE -> MaterialTheme.colorScheme.error
        Competition.State.SCHEDULED -> MaterialTheme.colorScheme.primary
        Competition.State.CANCELLED, Competition.State.FINISHED -> MaterialTheme.colorScheme.onSurfaceVariant
    }

/** The state in race lists, where upcoming goes without a badge: the start time says it. */
@Composable
fun StateBadge(state: Competition.State) {
    if (state != Competition.State.SCHEDULED) {
        Text(stringResource(state.label), color = state.tint, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
    }
}

/**
 * A screen of the app: its title in the top app bar, with a back button below a tab's root and
 * its [actions] at the end, and the choices it filters its list by under the bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Screen(
    title: String,
    onBack: (() -> Unit)?,
    pickers: (@Composable RowScope.() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(title) },
                    navigationIcon = {
                        if (onBack != null) {
                            IconButton(onClick = onBack) {
                                Icon(painterResource(R.drawable.ic_arrow_back), contentDescription = stringResource(R.string.back))
                            }
                        }
                    },
                    actions = actions,
                )
                pickers?.let { PickerRow(it) }
            }
        },
        content = content,
    )
}

/**
 * A screen's list once its data loads, pulled to refresh; until then, a progress indicator,
 * or what went wrong with a button to try again. [alsoLoading]: the data the list shows besides
 * its own, which loads on its own and refreshes with it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> LoadableList(
    viewModel: LoadViewModel<T>,
    padding: PaddingValues,
    listState: LazyListState = rememberLazyListState(),
    empty: (T) -> Int? = { null },
    alsoLoading: List<LoadViewModel<*>> = emptyList(),
    content: LazyListScope.(T) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val all = listOf(viewModel) + alsoLoading
    val isRefreshing by remember(all) { combine(all.map { it.isRefreshing }) { flags -> flags.any { it } } }
        .collectAsStateWithLifecycle(initialValue = false)
    val refresh = { all.forEach { it.refresh() } }
    val modifier = Modifier.fillMaxSize().padding(padding)
    when (val current = state) {
        Loadable.Loading -> LoadProgress(modifier)
        is Loadable.Failed -> LoadFailure(refresh, isRetrying = isRefreshing, modifier)
        is Loadable.Loaded -> PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = refresh, modifier = modifier) {
            LazyColumn(Modifier.fillMaxSize(), state = listState) { content(current.value) }
            empty(current.value)?.let { message -> EmptyMessage(stringResource(message), Modifier.align(Alignment.Center)) }
        }
    }
}

/** A button in the top app bar, named for TalkBack. */
@Composable
fun BarAction(@DrawableRes icon: Int, label: String, onClick: () -> Unit) {
    IconButton(onClick = onClick) { Icon(painterResource(icon), contentDescription = label) }
}

@Composable
fun LoadProgress(modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

/** A first load that failed, with a button to try again. */
@Composable
fun LoadFailure(retry: () -> Unit, isRetrying: Boolean, modifier: Modifier = Modifier) {
    Column(
        modifier.padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.unable_to_load), style = MaterialTheme.typography.titleLarge)
        Text(stringResource(R.string.results_are_temporarily_unavailable), textAlign = TextAlign.Center)
        Button(onClick = retry, enabled = !isRetrying) { Text(stringResource(R.string.try_again)) }
    }
}

/** What a list would show, when it has nothing to. */
@Composable
fun EmptyMessage(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier.padding(32.dp),
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

/** What to do, or what happened, in place of a list: [icon], a title and a line below it. */
@Composable
fun Prompt(@DrawableRes icon: Int, title: String, text: String, modifier: Modifier = Modifier) {
    Column(
        modifier.padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

/** A list section's title, as Material lists head their groups. */
@Composable
fun SectionHeader(text: String) {
    Text(
        text,
        Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp).semantics { heading() },
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
    )
}

/** A line under a section, as the iOS app's section footers. */
@Composable
fun SectionFooter(text: String) {
    Text(
        text,
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** A nation's flag, or its IOC code when no flag is known. */
@Composable
fun NationMark(code: String?) {
    val flag = Nation.flag(code)
    when {
        flag != null -> Text(flag)
        code != null -> Text(code, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A name in a list row, bold with a star when it is a favorite's: the same mark on every list. */
@Composable
fun RowName(name: String, highlighted: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(name, fontWeight = if (highlighted) FontWeight.Bold else null)
        if (highlighted) {
            Icon(
                painterResource(R.drawable.ic_star_filled),
                stringResource(R.string.favorite),
                Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/** An athlete's or a team's result: rank or status (DNF…), flag, name, shootings, time and gap. */
@Composable
fun ResultLine(row: ResultRow, highlighted: Boolean, modifier: Modifier = Modifier) {
    ListItem(
        modifier = modifier,
        leadingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(row.irm ?: row.rank.orEmpty(), Modifier.width(40.dp), style = MaterialTheme.typography.titleMedium)
                NationMark(row.nation)
            }
        },
        headlineContent = { RowName(row.shortName ?: row.name, highlighted) },
        supportingContent = row.shootings?.let { { Text(it) } },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End) {
                row.totalTime?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                row.behind?.takeIf { it != "0.0" }?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            }
        },
    )
}

/** A result row leading to its athlete, when it has one. */
@Composable
fun ResultLink(row: ResultRow, highlighted: Boolean, open: (Route) -> Unit, modifier: Modifier = Modifier) {
    val id = row.athleteId
    ResultLine(row, highlighted, if (id != null) modifier.clickable { open(Route.Athlete(id, row.name)) } else modifier)
}

/** How much of a race's start a row says: all of it, or the time alone under a header that gives the day. */
enum class StartDetail(val skeleton: DateSkeleton) {
    FULL(DateSkeleton.START),
    TIME_ONLY(DateSkeleton.TIME),
}

@Composable
fun RaceRow(race: Competition, modifier: Modifier = Modifier, start: StartDetail = StartDetail.FULL) {
    ListItem(
        modifier = modifier,
        headlineContent = { Text(race.title(), fontWeight = FontWeight.SemiBold) },
        supportingContent = { Text(formatted(race.startTime, start.skeleton)) },
        trailingContent = { StateBadge(race.state) },
    )
}
