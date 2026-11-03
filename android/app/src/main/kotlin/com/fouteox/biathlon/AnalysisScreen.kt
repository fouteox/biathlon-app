package com.fouteox.biathlon

import androidx.annotation.StringRes
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.RaceAnalysis
import com.fouteox.biathlon.kit.analysis
import com.fouteox.biathlon.kit.segments

/**
 * A finished race's rankings of the times on the course, on the range and on the shooting mat,
 * over the whole race or a single lap or shooting.
 */
@Composable
fun AnalysisScreen(race: Competition, open: (Route) -> Unit, onBack: () -> Unit) {
    val client = LocalIbuClient.current
    var measure by rememberSaveable { mutableStateOf(RaceAnalysis.Measure.COURSE) }
    var segment by rememberSaveable { mutableStateOf<Int?>(null) }
    val analysis = RaceAnalysis(measure, segment)
    val ranking = viewModel(key = "analysis/$measure/$segment") { LoadViewModel { client.analysis(analysis, race.id) } }
    WhileStarted(ranking) { ranking.load() }
    Screen(
        stringResource(R.string.analysis),
        onBack,
        pickers = {
            MenuPicker(measure, RaceAnalysis.Measure.entries, { stringResource(it.title) }) {
                // Another measure keeps the lap or shooting it also has.
                val measured = analysis.measuring(it, race)
                measure = measured.measure
                segment = measured.segment
            }
            MenuPicker(segment, listOf(null) + race.segments(measure), { segmentTitle(measure, it) }) { segment = it }
        },
    ) { padding ->
        val favorites = rememberFavoriteSet()
        LoadableList(ranking, padding) { results ->
            // The ranking shown, named in the list itself and not only in the pickers.
            item { SectionHeader(stringResource(R.string.arg_arg, stringResource(measure.title), segmentTitle(measure, segment))) }
            items(results.rows, key = { it.id }) { ResultLink(it, favorites.contains(it), open) }
            item { SectionFooter(stringResource(measure.explanation)) }
        }
    }
}

@Composable
private fun segmentTitle(measure: RaceAnalysis.Measure, segment: Int?): String = when {
    segment == null -> stringResource(R.string.whole_race)
    measure == RaceAnalysis.Measure.COURSE -> stringResource(R.string.lap_arg, segment)
    else -> stringResource(R.string.shooting_arg, segment)
}

@get:StringRes
private val RaceAnalysis.Measure.title: Int
    get() = when (this) {
        RaceAnalysis.Measure.COURSE -> R.string.course
        RaceAnalysis.Measure.RANGE -> R.string.range
        RaceAnalysis.Measure.SHOOTING -> R.string.shooting
    }

/** What the measure counts, under its ranking. */
@get:StringRes
private val RaceAnalysis.Measure.explanation: Int
    get() = when (this) {
        RaceAnalysis.Measure.COURSE -> R.string.skiing_time_without_the_time_on_the_range
        RaceAnalysis.Measure.RANGE -> R.string.time_on_the_range_from_entering_it_to_leaving_it_shooting_included
        RaceAnalysis.Measure.SHOOTING -> R.string.time_on_the_shooting_mat_part_of_the_time_on_the_range
    }
