package com.fouteox.biathlon

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
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
