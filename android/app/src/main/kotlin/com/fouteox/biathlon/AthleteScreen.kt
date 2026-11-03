package com.fouteox.biathlon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.fouteox.biathlon.kit.AthleteBio
import com.fouteox.biathlon.kit.AthleteHistory
import com.fouteox.biathlon.kit.AthleteResult
import com.fouteox.biathlon.kit.CupRow
import com.fouteox.biathlon.kit.Gender
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.SeasonId
import com.fouteox.biathlon.kit.worldCupStanding
import java.time.Instant
import java.time.ZoneOffset

/** An athlete's profile, then their World Cup results season by season, with their overall standing. */
@Composable
fun AthleteScreen(athleteId: String, name: String, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    val bio = viewModel(key = "bio") { LoadViewModel { client.athlete(athleteId) } }
    // Loaded on its own: the profile shows without waiting for it, and without it.
    val history = viewModel(key = "history") { LoadViewModel { AthleteHistory(client.athleteResults(athleteId), Instant.now()) } }
    WhileStarted(bio) { bio.load() }
    WhileStarted(history) { history.load() }
    val loadedBio by bio.state.collectAsStateWithLifecycle()
    val loadedHistory by history.state.collectAsStateWithLifecycle()
    // The season picked; until then, the one the history opens on.
    var picked by rememberSaveable { mutableStateOf<String?>(null) }
    val athleteHistory = loadedHistory.value
    val season = picked?.let(::SeasonId) ?: athleteHistory?.initialSeason
    val category = loadedBio.value?.gender?.category
    Screen(
        name,
        onBack,
        pickers = if (athleteHistory != null && season != null) {
            { SeasonPicker(athleteHistory.seasons, season) { picked = it.rawValue } }
        } else {
            null
        },
    ) { padding ->
        val standing = if (season != null && category != null) rememberStanding(athleteId, category, season) else null
        val loadedStanding = standing?.state?.collectAsStateWithLifecycle()?.value
        LoadableList(bio, padding, alsoLoading = listOfNotNull(history, standing)) { profile ->
            item { Profile(profile) }
            profile.nation?.let { nation ->
                // The nation opens on the athlete's standings, the men's when the IBU gives no gender.
                item {
                    ListItem(
                        headlineContent = { Text(Nation.namedTitle(nation)) },
                        modifier = Modifier.clickable { open(Route.Nation(nation, profile.gender?.category ?: RaceCategory.MEN)) },
                    )
                }
            }
            if (athleteHistory != null && season != null) history(athleteHistory, season, loadedStanding, open)
        }
    }
}

/** The athlete's row in the season's overall standings, keyed by what it depends on. */
@Composable
private fun rememberStanding(athleteId: String, category: RaceCategory, season: SeasonId): LoadViewModel<CupRow?> {
    val client = LocalIbuClient.current
    val standing = viewModel(key = "standing/$category/$season") { LoadViewModel { client.worldCupStanding(athleteId, category, season) } }
    WhileStarted(standing) { standing.load() }
    return standing
}

@Composable
private fun Profile(bio: AthleteBio) {
    ListItem(
        leadingContent = {
            // The photo over a placeholder, which shows while it loads, or without one.
            Box(Modifier.size(72.dp).clip(CircleShape)) {
                Icon(
                    painterResource(R.drawable.ic_account_circle),
                    contentDescription = null,
                    Modifier.fillMaxSize(),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // The name beside it says who it is.
                AsyncImage(bio.photoUrl?.toString(), contentDescription = null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
        },
        headlineContent = { Text(bio.fullName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) },
        supportingContent = {
            Column {
                if (bio.isDeceased) Text(stringResource(if (bio.gender == Gender.WOMAN) R.string.deceased_woman else R.string.deceased))
                bio.birthdate?.let { birthdate ->
                    // Birthdates arrive at midnight UTC, so they are formatted in UTC.
                    val date = formatted(birthdate.atOffset(ZoneOffset.UTC).toLocalDate(), DateSkeleton.BIRTHDATE)
                    val age = bio.age(Instant.now())
                    Text(age?.let { stringResource(R.string.arg_arg, date, pluralStringResource(R.plurals.arg_years_old, it, it)) } ?: date)
                }
            }
        },
    )
}

private fun LazyListScope.history(history: AthleteHistory, season: SeasonId, standing: Loadable<CupRow?>?, open: (Route) -> Unit) {
    item { SectionHeader(seasonTitle(season)) }
    if (standing is Loadable.Loaded) item { OverallStanding(standing.value) }
    val results = history.results(season)
    if (results.isEmpty()) item { SectionFooter(stringResource(R.string.no_world_cup_results_this_season)) }
    items(results, key = { it.id }) { ResultSummary(it, open) }
    item { SectionFooter(stringResource(R.string.world_cup_world_championships_and_olympic_races)) }
}

@Composable
private fun seasonTitle(season: SeasonId) = stringResource(R.string.season_arg, season.displayName)

/** The athlete's place in the season's World Cup overall standings, with their points. */
@Composable
private fun OverallStanding(row: CupRow?) {
    ListItem(
        headlineContent = { Text(stringResource(R.string.overall)) },
        trailingContent = { Text(row?.let { rankAndPoints(it) } ?: stringResource(R.string.not_ranked)) },
    )
}

/** The standing in a phrase, "7 · 612 points". */
@Composable
fun rankAndPoints(row: CupRow): String {
    val rank = row.rank ?: "–"
    val score = row.score ?: return rank
    val points = score.toIntOrNull()?.let { pluralStringResource(R.plurals.arg_points, it, it) } ?: score
    return stringResource(R.string.arg_arg, rank, points)
}

/** One of an athlete's results: the race, where it was held and the athlete's rank. */
@Composable
private fun ResultSummary(result: AthleteResult, open: (Route) -> Unit) {
    val title = result.kind?.let { stringResource(it.title) } ?: result.competition.orEmpty()
    val raceId = result.raceId
    ListItem(
        modifier = if (raceId != null) Modifier.clickable { open(Route.RaceById(raceId, title)) } else Modifier,
        headlineContent = { Text(title) },
        supportingContent = result.place?.let { { Text(it) } },
        trailingContent = result.rank?.let { { Text(it, style = MaterialTheme.typography.titleMedium) } },
    )
}
