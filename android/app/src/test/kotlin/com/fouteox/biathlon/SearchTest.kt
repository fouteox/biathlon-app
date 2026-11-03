package com.fouteox.biathlon

import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The search tab, on the fictional World Cup's athletes. */
@RunWith(RobolectricTestRunner::class)
class SearchTest {
    @get:Rule
    val compose = createComposeRule()

    @Before
    fun openSearch() {
        compose.launchApp()
        compose.onAllNodesWithText("Search").onFirst().performClick()
        compose.onNodeWithText("Search for a biathlete").assertExists()
    }

    /** The field of the full-screen search the bar opens on. */
    private fun type(text: String) {
        compose.onAllNodes(hasSetTextAction()).onLast().performClick()
        compose.waitForIdle()
        compose.onAllNodes(hasSetTextAction()).onLast().performTextReplacement(text)
    }

    /** The start of a name finds the athlete, who opens on their profile. */
    @Test
    fun findsAnAthleteByTheStartOfTheirName() {
        type("vang")
        compose.waitForText("Aksel VANGEN")
        // The results show in the full-screen search, over the same results below the bar.
        compose.onAllNodesWithText("Aksel VANGEN").onLast().performClick()
        compose.waitForText("1 · 1000 points")
    }

    @Test
    fun saysWhenNoAthleteMatches() {
        type("zzz ")
        compose.waitForText("No results for “zzz”")
        compose.onAllNodesWithText("Check the spelling or try a new search.").onLast().assertExists()
    }
}
