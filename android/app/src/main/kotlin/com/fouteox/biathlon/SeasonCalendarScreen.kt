package com.fouteox.biathlon

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The season's events, one row each with its place, nation and dates. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeasonCalendarScreen(viewModel: SeasonCalendarViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.calendar_title)) }) }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            when (val current = state) {
                CalendarState.Loading -> CircularProgressIndicator()
                CalendarState.Failed -> Text(stringResource(R.string.calendar_unavailable))
                is CalendarState.Loaded -> EventList(current.events)
            }
        }
    }
}

@Composable
private fun EventList(events: List<CalendarEvent>) {
    val dates = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withZone(ZoneId.systemDefault())
    LazyColumn(Modifier.fillMaxSize()) {
        items(events, key = CalendarEvent::id) { event ->
            ListItem(
                headlineContent = { Text(event.place) },
                supportingContent = { Text("${dates.format(event.start)} – ${dates.format(event.end)}") },
                trailingContent = event.nation?.let { nation -> { Text(nation) } },
            )
        }
    }
}
