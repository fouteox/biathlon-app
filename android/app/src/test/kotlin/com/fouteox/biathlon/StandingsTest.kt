package com.fouteox.biathlon

import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.sample
import java.time.Instant
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The standings, a nation's athletes and an athlete's profile, on the fictional World Cup. */
@RunWith(RobolectricTestRunner::class)
class StandingsTest {
    @get:Rule
    val compose = createComposeRule()

    @Before
    fun openStandings() {
        compose.setContent { BiathlonApp(IbuClient.sample(Instant.now())) }
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
}
