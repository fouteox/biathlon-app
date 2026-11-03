package com.fouteox.biathlon

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.fouteox.biathlon.kit.RaceCategory
import com.fouteox.biathlon.kit.SeasonId
import com.fouteox.biathlon.kit.StandingsDiscipline

/** The choices a screen filters its list by, as Material filter chips under the top app bar. */
@Composable
fun PickerRow(content: @Composable RowScope.() -> Unit) {
    FlowRow(
        Modifier.padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = { content() },
    )
}

/** A chip showing its value, which opens the other values in a menu, each as [optionText] writes it. */
@Composable
fun <T> MenuPicker(
    selection: T,
    options: List<T>,
    text: @Composable (T) -> String,
    optionText: @Composable (T) -> String = text,
    select: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        FilterChip(
            selected = false,
            onClick = { expanded = true },
            label = { Text(text(selection)) },
            trailingIcon = { Icon(painterResource(R.drawable.ic_arrow_drop_down), contentDescription = null, Modifier.size(FilterChipDefaults.IconSize)) },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            for (option in options) {
                DropdownMenuItem(
                    text = { Text(optionText(option)) },
                    onClick = {
                        expanded = false
                        select(option)
                    },
                )
            }
        }
    }
}

@Composable
fun SeasonPicker(seasons: List<SeasonId>, selection: SeasonId, select: (SeasonId) -> Unit) {
    MenuPicker(selection, seasons, { stringResource(R.string.season_arg, it.displayName) }, { it.displayName }, select)
}

@Composable
fun CategoryPicker(selection: RaceCategory, select: (RaceCategory) -> Unit) {
    MenuPicker(selection, RaceCategory.WITH_STANDINGS, { stringResource(it.title) }, select = select)
}

@Composable
fun DisciplinePicker(selection: StandingsDiscipline, select: (StandingsDiscipline) -> Unit) {
    MenuPicker(selection, StandingsDiscipline.entries, { stringResource(it.label) }, select = select)
}
