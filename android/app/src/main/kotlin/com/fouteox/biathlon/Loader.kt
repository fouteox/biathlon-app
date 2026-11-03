package com.fouteox.biathlon

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What a screen shows of its data. */
sealed interface Loadable<out T> {
    data object Loading : Loadable<Nothing>

    /** [loadedAt]: when the value was fetched, which a live race's results say. */
    data class Loaded<T>(override val value: T, val loadedAt: Instant) : Loadable<T>

    data class Failed(val error: Exception) : Loadable<Nothing>

    val value: T? get() = (this as? Loaded<T>)?.value
}

/**
 * A screen's data, loaded with one policy for every screen, as on iOS:
 * - a cancelled load (the screen went away) changes nothing;
 * - a failed refresh keeps the data already shown, only a first load shows the error;
 * - every failure is logged.
 */
class LoadViewModel<T>(private val fetch: suspend () -> T) : ViewModel() {
    private val mutableState = MutableStateFlow<Loadable<T>>(Loadable.Loading)
    val state: StateFlow<Loadable<T>> = mutableState.asStateFlow()

    private val mutableIsRefreshing = MutableStateFlow(false)

    /** Whether a refresh the user asked for, pulling the list or trying again, is running. */
    val isRefreshing: StateFlow<Boolean> = mutableIsRefreshing.asStateFlow()

    suspend fun load() {
        val result = attempt(fetch)
        if (result is Loadable.Loaded || state.value !is Loadable.Loaded) mutableState.value = result
    }

    /** A load the user asked for, pulling the list or trying again, in the view model's scope. */
    fun refresh() {
        viewModelScope.launch {
            mutableIsRefreshing.value = true
            try {
                load()
            } finally {
                mutableIsRefreshing.value = false
            }
        }
    }

}

/** `fetch`'s value, or its failure, logged; a cancelled load (the screen went away) is no result. */
suspend fun <T> attempt(fetch: suspend () -> T): Loadable<T> = try {
    Loadable.Loaded(fetch(), Instant.now())
} catch (cancellation: CancellationException) {
    throw cancellation
} catch (error: Exception) {
    Log.e("Loader", "Load failed", error)
    Loadable.Failed(error)
}
