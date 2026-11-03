package com.fouteox.biathlon

import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.StandingsDiscipline
import com.fouteox.biathlon.kit.worldCupStandings
import java.time.Instant

/** A nation's athletes, from the World Cup overall standings: the API lists them nowhere else. */
@Composable
fun NationScreen(nation: String, initialCategory: RaceCategory, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    var category by rememberSaveable { mutableStateOf(initialCategory) }
    val shown = category
    val standings = viewModel(key = shown.name) {
        LoadViewModel { client.worldCupStandings(shown, StandingsDiscipline.TOTAL, Instant.now()) }
    }
    WhileStarted(standings) { standings.load() }
    Screen(
        Nation.namedTitle(nation),
        onBack,
        pickers = { CategoryPicker(category) { category = it } },
        actions = { FavoriteButton(Favorite.Kind.NATION, nation, Nation.localizedName(nation), nation) },
    ) { padding ->
        LoadableList(standings, padding, empty = { if (it.standings.athletes(nation).isEmpty()) R.string.no_athletes_in_the_standings else null }) { loaded ->
            val athletes = loaded.standings.athletes(nation)
            if (athletes.isEmpty()) return@LoadableList
            item { SectionHeader(standingsTitle(shown, StandingsDiscipline.TOTAL)) }
            items(athletes, key = { it.id }) { StandingRow(it, shown, open) }
            item { SectionFooter(stringResource(R.string.the_athletes_who_scored_world_cup_points_in_arg, loaded.season.displayName)) }
        }
    }
}
