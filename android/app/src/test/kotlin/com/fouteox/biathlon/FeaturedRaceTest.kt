package com.fouteox.biathlon

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.sample
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The race an app shortcut opens, on the fictional World Cup. */
@RunWith(RobolectricTestRunner::class)
class FeaturedRaceTest {
    @get:Rule
    val compose = createComposeRule()

    /** A screen's lifecycle, which the test stops and starts again, as leaving the app and coming back does. */
    private val owner = object : LifecycleOwner {
        val registry = LifecycleRegistry.createUnsafe(this).apply { currentState = Lifecycle.State.RESUMED }
        override val lifecycle: Lifecycle get() = registry
    }

    /**
     * Back to the screen, the shortcut's race stays the one it opened, whose results the screen
     * shows, even when the feed would now pick another.
     */
    @Test
    fun keepsTheRaceItOpened() {
        var calendarLoads = 0
        val client = IbuClient.sample(Instant.now(), isUnavailable = { path -> if (path == "Events") calendarLoads += 1; false })
        compose.showScreen(client) {
            CompositionLocalProvider(LocalLifecycleOwner provides owner) { FeaturedRaceScreen(FeaturedRace.LATEST_RESULT, open = {}, onBack = {}) }
        }
        compose.waitForText("Results")
        val loads = calendarLoads
        compose.runOnIdle { owner.registry.currentState = Lifecycle.State.CREATED }
        compose.runOnIdle { owner.registry.currentState = Lifecycle.State.RESUMED }
        compose.waitForIdle()
        assertEquals(loads, calendarLoads)
    }
}
