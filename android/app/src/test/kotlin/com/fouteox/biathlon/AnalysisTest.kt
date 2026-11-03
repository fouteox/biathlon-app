package com.fouteox.biathlon

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.sample
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** A finished sprint of the fictional World Cup's last season, which has its analysis. */
@RunWith(RobolectricTestRunner::class)
class AnalysisTest {
    @get:Rule
    val compose = createComposeRule()

    private val client = IbuClient.sample(Instant.now())
    private val sprint: Competition = runBlocking { client.race("BT2526SWRLCP01SMSP") }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { MaterialTheme { CompositionLocalProvider(LocalIbuClient provides client, content = content) } }
    }

    /** The results lead to the analysis once they are final. */
    @Test
    fun theResultsOpenTheAnalysis() {
        val opened = mutableListOf<Route>()
        show { RaceScreen(sprint, open = { opened += it }, onBack = {}) }
        compose.waitForText("VANGEN A.")
        compose.onNodeWithContentDescription("Course, range and shooting times").performClick()
        assertEquals(Route.Analysis::class, opened.single()::class)
    }

    /** Each measure ranks the athletes apart, over the whole race or a lap or shooting it keeps. */
    @Test
    fun ranksByMeasureAndSegment() {
        show { AnalysisScreen(sprint, open = {}, onBack = {}) }
        compose.waitForText("Course · Whole race")
        compose.onNodeWithText("Whole race").performClick()
        compose.onNodeWithText("Lap 2").performClick()
        compose.waitForText("Course · Lap 2")
        compose.onNodeWithText("Course").performClick()
        compose.onNodeWithText("Range").performClick()
        compose.waitForText("Range · Shooting 2")
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Time on the range, from entering it to leaving it, shooting included."))
    }
}
