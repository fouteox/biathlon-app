package com.fouteox.biathlon

import android.content.Intent
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.WikidataClient
import com.fouteox.biathlon.kit.sample
import java.net.URI
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** The standings, a nation's athletes and an athlete's profile, on the fictional World Cup. */
@RunWith(RobolectricTestRunner::class)
class StandingsTest {
    @get:Rule
    val compose = createComposeRule()

    /** Whether the athletes' results fail to load, as the IBU's API sometimes does. */
    private var resultsUnavailable = false

    @Before
    fun openStandings() {
        compose.launchApp(
            IbuClient.sample(Instant.now()) { it == "AllResults" && resultsUnavailable },
            WikidataClient.sample(mapOf("BTNORSM01" to mapOf("en" to URI("https://en.wikipedia.org/wiki/Aksel_Vangen")))),
        )
        compose.onNodeWithText("Standings").performClick()
        compose.waitForText("VANGEN A.")
    }

    @Test
    fun theLeaderWearsTheYellowBib() {
        compose.onNodeWithText("Men · Overall").assertExists()
        compose.onNodeWithContentDescription("Yellow bib").assertExists()
    }

    @Test
    fun picksTheCategoryAndTheDiscipline() {
        compose.onNodeWithText("Men").performClick()
        compose.onNodeWithText("Women").performClick()
        compose.waitForText("SOLBERG I.")
        compose.onNodeWithText("Overall").performClick()
        compose.onNodeWithText("Nations").performClick()
        compose.waitForText("Women · Nations")
        compose.onNodeWithText("Norway").assertExists()
    }

    /** A nation's row opens on its athletes in the overall standings. */
    @Test
    fun aNationListsItsAthletes() {
        compose.onNodeWithText("Overall").performClick()
        compose.onNodeWithText("Nations").performClick()
        compose.waitForText("Norway")
        compose.onNodeWithText("Norway").performClick()
        compose.waitForText("HOLTE S.")
        compose.onNodeWithText("VANGEN A.").assertExists()
        compose.onNodeWithText("MARTEL H.").assertDoesNotExist()
    }

    /** An athlete's profile, with their standing and results, each opening its race. */
    @Test
    fun anAthleteOpensOnTheirProfileAndResults() {
        compose.onNodeWithText("VANGEN A.").performClick()
        compose.waitForText("Aksel VANGEN")
        compose.waitForText("1 · 1000 points")
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Men's Sprint"))
        compose.onAllNodesWithText("Men's Sprint").onFirst().performClick()
        compose.waitForText("Results")
        compose.onNodeWithText("VANGEN A.").assertExists()
    }

    /** Pulling the profile reloads the results and the standing too, which load on their own. */
    @Test
    fun pullingAnAthleteReloadsTheirResults() {
        resultsUnavailable = true
        compose.onNodeWithText("VANGEN A.").performClick()
        compose.waitForText("Aksel VANGEN")
        compose.onNodeWithText("1 · 1000 points").assertDoesNotExist()
        resultsUnavailable = false
        compose.onNode(hasScrollToNodeAction()).performTouchInput { swipeDown() }
        compose.waitForText("1 · 1000 points")
    }

    /** The athlete's Wikipedia article opens in the browser. */
    @Test
    fun anAthleteLinksToTheirWikipediaArticle() {
        compose.onNodeWithText("VANGEN A.").performClick()
        compose.waitForText("Wikipedia")
        compose.onNodeWithText("Wikipedia").performClick()
        val intent = shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("https://en.wikipedia.org/wiki/Aksel_Vangen", intent.dataString)
    }
}
