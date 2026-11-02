package com.fouteox.biathlon

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fouteox.biathlon.kit.IBUClient
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.swift.swiftkit.core.SwiftArena

/** What the calendar screen shows. */
sealed interface CalendarState {
    data object Loading : CalendarState
    data class Loaded(val events: List<CalendarEvent>) : CalendarState
    data object Failed : CalendarState
}

/**
 * Loads the season's calendar with the client that [makeClient] creates: the live one in the app,
 * a sample one in tests. The client lives as long as the view model, in an arena closed with it.
 */
class SeasonCalendarViewModel(makeClient: (SwiftArena) -> IBUClient) : ViewModel() {
    private val arena = SwiftArena.ofConfined()
    private val client = makeClient(arena)
    private val mutableState = MutableStateFlow<CalendarState>(CalendarState.Loading)
    val state: StateFlow<CalendarState> = mutableState.asStateFlow()

    init {
        viewModelScope.launch {
            mutableState.value = runCatching { client.seasonCalendar(Instant.now()) }
                .fold(onSuccess = CalendarState::Loaded, onFailure = { CalendarState.Failed })
        }
    }

    override fun onCleared() {
        arena.close()
    }
}
