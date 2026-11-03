package com.fouteox.biathlon

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.Clock
import java.time.Instant
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay

/**
 * Runs [block] each time the screen is started, as it shows (back from another screen too) or
 * as the app comes back, and cancels it as the screen stops: SwiftUI's `task` on iOS.
 */
@Composable
fun WhileStarted(vararg keys: Any?, block: suspend CoroutineScope.() -> Unit) {
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner, *keys) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED, block)
    }
}

/** Runs [refresh] every 20 seconds while [isLive], as long as the screen shows. */
@Composable
fun RefreshWhileLive(isLive: Boolean, refresh: suspend () -> Unit) {
    WhileStarted(isLive) {
        while (isLive) {
            delay(LIVE_REFRESH_INTERVAL)
            refresh()
        }
    }
}

private val LIVE_REFRESH_INTERVAL = 20.seconds

/** The clock that countdowns read, which tests set. */
val LocalClock = staticCompositionLocalOf<Clock> { Clock.systemDefaultZone() }

/** The time now, updated every few seconds while the screen shows, for labels that count down. */
@Composable
fun currentTime(): Instant {
    val clock = LocalClock.current
    var now by remember(clock) { mutableStateOf(clock.instant()) }
    WhileStarted(clock) {
        while (true) {
            now = clock.instant()
            delay(CLOCK_TICK)
        }
    }
    return now
}

private val CLOCK_TICK = 10.seconds
