package com.fouteox.biathlon

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.sample
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The favorites, followed from the athletes' and nations' screens, and marked on every list. */
@RunWith(RobolectricTestRunner::class)
class FavoritesScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val favorites = inMemoryFavorites()

    private fun follow(kind: Favorite.Kind, key: String, name: String, nation: String?) {
        runBlocking { favorites.toggle(kind, key, name, nation) }
    }

    private fun openTab(name: String) {
        compose.onAllNodesWithText(name).onFirst().performClick()
    }

    @Test
    fun saysHowToFollowWhenThereAreNoFavorites() {
        compose.launchApp(favorites = favorites)
        openTab("Favorites")
        compose.waitForText("No favorites")
        compose.onNodeWithText("Tap the star on a biathlete or a team to follow their results from the home screen.").assertExists()
    }

    /** The star on an athlete's screen lists them in the tab, under their IBU name, with their standing. */
    @Test
    fun theStarFollowsAnAthlete() {
        compose.launchApp(favorites = favorites)
        openTab("Standings")
        compose.waitForText("VANGEN A.")
        compose.onNodeWithText("VANGEN A.").performClick()
        compose.waitForText("Aksel VANGEN")
        compose.onNodeWithContentDescription("Favorite").assertIsOff().performClick()
        compose.waitUntil { runCatching { compose.onNodeWithContentDescription("Favorite").assertIsOn() }.isSuccess }
        openTab("Favorites")
        compose.waitForText("Biathletes")
        compose.waitForText("1 · 1000 points")
        compose.onNodeWithText("Aksel VANGEN").assertExists()
        compose.onNodeWithText("Rank and points in the World Cup overall standings.").assertExists()
    }

    @Test
    fun listsANationWithItsNationsCupRanks() {
        follow(Favorite.Kind.NATION, "NOR", "Norway", "NOR")
        compose.launchApp(favorites = favorites)
        openTab("Favorites")
        compose.waitForText("Teams")
        compose.waitForText("Men 1 · Women 1")
        compose.onNodeWithText("Norway").performClick()
        compose.waitForText("Men · Overall")
    }

    /** Swiped away, or through TalkBack's actions. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun removesAFavorite() {
        follow(Favorite.Kind.ATHLETE, "BTNORSM01", "VANGEN Aksel", "NOR")
        compose.launchApp(favorites = favorites)
        openTab("Favorites")
        compose.waitForText("Aksel VANGEN")
        compose.onNodeWithText("Aksel VANGEN").performCustomAccessibilityActionWithLabel("Remove from favorites")
        compose.waitForText("No favorites")
    }

    /** The reader's own first in the standings, then in their place, marked. */
    @Test
    fun theStandingsShowTheFavoritesFirst() {
        follow(Favorite.Kind.ATHLETE, "BTNORSM01", "VANGEN Aksel", "NOR")
        compose.launchApp(favorites = favorites)
        openTab("Standings")
        compose.waitForText("My favorites")
        compose.waitUntil { compose.onAllNodesWithText("VANGEN A.").fetchSemanticsNodes().size == 2 }
        compose.onAllNodesWithContentDescription("Favorite").fetchSemanticsNodes().let { check(it.size == 2) }
    }

    /** Before anything is typed, the search suggests the favorite athletes. */
    @Test
    fun theSearchSuggestsTheFavoriteAthletes() {
        follow(Favorite.Kind.ATHLETE, "BTNORSM01", "VANGEN Aksel", "NOR")
        follow(Favorite.Kind.NATION, "FRA", "France", "FRA")
        compose.launchApp(favorites = favorites)
        openTab("Search")
        compose.waitForText("VANGEN Aksel")
        compose.onNodeWithText("France").assertDoesNotExist()
        compose.onNodeWithText("Search for a biathlete").assertDoesNotExist()
    }

    /** A race's results mark the favorite's row. */
    @Test
    fun theResultsMarkAFavorite() {
        follow(Favorite.Kind.ATHLETE, "BTNORSM01", "VANGEN Aksel", "NOR")
        val client = IbuClient.sample(Instant.now())
        val race = runBlocking { client.race("BT2526SWRLCP01SMSP") }
        compose.showScreen(client, favorites = favorites) { RaceScreen(race, open = {}, onBack = {}) }
        compose.waitForText("VANGEN A.")
        compose.waitUntil { compose.onAllNodesWithContentDescription("Favorite").fetchSemanticsNodes().size == 1 }
    }
}
