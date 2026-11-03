package com.fouteox.biathlon

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.CupRow
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.SeasonId
import com.fouteox.biathlon.kit.SeasonStandings
import com.fouteox.biathlon.kit.StandingsDiscipline
import com.fouteox.biathlon.kit.favorites
import com.fouteox.biathlon.kit.worldCupStandings
import java.time.Instant

@get:StringRes
val RaceCategory.title: Int
    get() = when (this) {
        RaceCategory.MEN -> R.string.men
        RaceCategory.WOMEN -> R.string.women
        RaceCategory.MIXED -> R.string.mixed
    }

@get:StringRes
val StandingsDiscipline.label: Int
    get() = when (this) {
        StandingsDiscipline.TOTAL -> R.string.overall
        StandingsDiscipline.SPRINT -> R.string.sprint
        StandingsDiscipline.PURSUIT -> R.string.pursuit
        StandingsDiscipline.INDIVIDUAL -> R.string.individual
        StandingsDiscipline.MASS_START -> R.string.mass_start
        StandingsDiscipline.NATIONS -> R.string.nations
    }

/** The standings' title, "Men · Overall", so the list reads on its own. */
@Composable
fun standingsTitle(category: RaceCategory, discipline: StandingsDiscipline) =
    stringResource(R.string.arg_arg, stringResource(category.title), stringResource(discipline.label))

/** The World Cup standings of a category, a discipline and a season, back to the first World Cup. */
@Composable
fun StandingsScreen(open: (Route) -> Unit) {
    val client = LocalIbuClient.current
    val seasons = remember { SeasonId.since(SeasonId.FIRST_WORLD_CUP, Instant.now()) }
    var category by rememberSaveable { mutableStateOf(RaceCategory.MEN) }
    var discipline by rememberSaveable { mutableStateOf(StandingsDiscipline.TOTAL) }
    // The season picked; until then, the current one, or the previous before its first race.
    var picked by rememberSaveable { mutableStateOf<String?>(null) }
    // Each choice keeps its own data, its fetch capturing the choice it was made for.
    val shownCategory = category
    val shownDiscipline = discipline
    val shownSeason = picked?.let(::SeasonId)
    val standings = viewModel(key = "$shownCategory/$shownDiscipline/$shownSeason") {
        LoadViewModel {
            if (shownSeason == null) {
                client.worldCupStandings(shownCategory, shownDiscipline, Instant.now())
            } else {
                client.worldCupStandings(shownCategory, shownDiscipline, shownSeason)
            }
        }
    }
    WhileStarted(standings) { standings.load() }
    val loaded by standings.state.collectAsStateWithLifecycle()
    val season = shownSeason ?: loaded.value?.season ?: SeasonId.containing(Instant.now())
    Screen(
        stringResource(R.string.standings),
        onBack = null,
        pickers = {
            CategoryPicker(category) { category = it }
            DisciplinePicker(discipline) { discipline = it }
            SeasonPicker(seasons, season) { picked = it.rawValue }
        },
    ) { padding ->
        val favorites = rememberFavoriteSet()
        LoadableList(standings, padding, empty = ::emptyMessage) { result ->
            // The reader's own first, with their rank; they keep their place below.
            val mine = result.standings.favorites(favorites)
            if (mine.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.my_favorites)) }
                items(mine, key = { "mine/${it.id}" }) { row -> StandingRow(row, shownCategory, open, highlighted = true) }
            }
            item { SectionHeader(standingsTitle(shownCategory, shownDiscipline)) }
            items(result.standings.rows, key = { it.id }) { row -> StandingRow(row, shownCategory, open, favorites.contains(row)) }
            item { standingsFooter(result)?.let { SectionFooter(it) } }
        }
    }
}

/** Before a season's first race, its standings are empty; a past season's can be too. */
private fun emptyMessage(result: SeasonStandings): Int? = when {
    result.standings.rows.isNotEmpty() -> null
    result.season < SeasonId.containing(Instant.now()) -> R.string.no_standings
    else -> R.string.no_standings_yet
}

@Composable
private fun standingsFooter(result: SeasonStandings): String? = when {
    result.isFallback -> stringResource(
        R.string.season_arg_the_arg_standings_will_appear_after_the_first_race,
        result.season.displayName,
        result.requestedSeason.displayName,
    )
    result.standings.rows.isEmpty() && result.season < SeasonId.containing(Instant.now()) ->
        stringResource(R.string.the_ibu_has_no_standings_for_arg, result.season.displayName)
    result.standings.rows.isEmpty() -> stringResource(R.string.the_arg_standings_will_appear_after_the_first_race, result.season.displayName)
    else -> result.standings.asOf
}

/** A row of the World Cup standings, which opens its athlete or its nation; [highlighted] for a favorite. */
@Composable
fun StandingRow(row: CupRow, category: RaceCategory, open: (Route) -> Unit, highlighted: Boolean = false) {
    val nation = if (row.isNation) row.nation ?: row.name else row.nation
    val route = row.athleteId?.let { Route.Athlete(it, row.name) } ?: Route.Nation(nation.orEmpty(), category)
    ListItem(
        modifier = Modifier.clickable { open(route) },
        leadingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(row.rank.orEmpty(), Modifier.width(40.dp), style = MaterialTheme.typography.titleMedium)
                NationMark(nation)
            }
        },
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RowName(if (row.isNation) Nation.localizedName(nation.orEmpty()) else row.shortName ?: row.name, highlighted)
                if ("yellow" in row.bibColors) {
                    // The leader's bib is yellow: here the color is the information.
                    Icon(painterResource(R.drawable.ic_apparel), stringResource(R.string.yellow_bib), Modifier.size(18.dp), tint = YELLOW_BIB)
                }
            }
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.rankChange?.takeIf { it != 0 }?.let { change -> RankChange(change) }
                row.score?.let { score ->
                    val spoken = score.toIntOrNull()?.let { pluralStringResource(R.plurals.arg_points, it, it) } ?: score
                    Text(score, Modifier.semantics { contentDescription = spoken }, fontWeight = FontWeight.Bold)
                }
            }
        },
    )
}

/** Places gained (negative) or lost since the last race. */
@Composable
private fun RankChange(change: Int) {
    val up = change < 0
    Icon(
        painterResource(if (up) R.drawable.ic_arrow_upward else R.drawable.ic_arrow_downward),
        contentDescription = stringResource(if (up) R.string.up else R.string.down),
        Modifier.size(16.dp),
        tint = if (up) RANK_UP else MaterialTheme.colorScheme.error,
    )
}

/** The leader's yellow bib and a gain in rank, colors that carry information, as on iOS. */
private val YELLOW_BIB = Color(0xFFF4C430)
private val RANK_UP = Color(0xFF2E7D32)
