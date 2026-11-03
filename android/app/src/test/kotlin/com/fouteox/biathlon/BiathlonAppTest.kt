package com.fouteox.biathlon

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.hasContentDescription
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
import com.fouteox.biathlon.kit.SeasonId
import com.fouteox.biathlon.kit.sample
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respondError
import io.ktor.http.HttpStatusCode
import java.time.Instant
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The app on the fictional World Cup, whatever the date. */
@RunWith(RobolectricTestRunner::class)
class BiathlonAppTest {
    @get:Rule
    val compose = createComposeRule()

    private fun launch(client: IbuClient = IbuClient.sample(Instant.now())) {
        compose.launchApp(client)
    }

    @Test
    fun opensOnHome() {
        launch()
        compose.onAllNodesWithText("Home").onFirst().assertExists()
        compose.onNodeWithText("Calendar").assertExists()
    }

    @Test
    @Config(qualifiers = "fr")
    fun speaksFrench() {
        launch()
        compose.onAllNodesWithText("Accueil").onFirst().assertExists()
    }

    @Test
    @Config(qualifiers = "de")
    fun speaksGerman() {
        launch()
        compose.onAllNodesWithText("Übersicht").onFirst().assertExists()
    }

    /** The live race heads the home screen and opens on its results, which say they are live. */
    @Test
    fun homeOpensTheLiveRace() {
        launch(IbuClient.sample(Instant.now(), liveRace = true))
        compose.waitForText("Live")
        compose.onNodeWithText("Live").performClick()
        compose.waitForText("Results · Live")
        // Below the results, at the end of the list.
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Updated at", substring = true))
    }

    /** A past season's event, then its race, with results, and back. */
    @Test
    fun calendarOpensAnEventAndItsRaces() {
        launch()
        compose.onNodeWithText("Calendar").performClick()
        compose.onNodeWithText("Season", substring = true).performClick()
        compose.onNodeWithText(SeasonId.containing(Instant.now()).previous.displayName).performClick()
        // A past season opens on its last event, below the first.
        compose.waitForText("Hohenwald")
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Nordvik"))
        compose.onNodeWithText("Nordvik").performClick()
        compose.waitForText("Men's Sprint")
        compose.onNodeWithText("Men's Sprint").performClick()
        compose.waitForText("VANGEN A.")
        compose.onNodeWithText("Results").assertExists()
        compose.onNodeWithContentDescription("Back").performClick()
        compose.waitForText("Women's Sprint")
    }

    /** A past season opens on its last event, not on the current season's position. */
    @Test
    @Config(qualifiers = "h360dp")
    fun aPastSeasonOpensOnItsLastEvent() {
        launch()
        compose.onNodeWithText("Calendar").performClick()
        compose.waitForText("Nordvik")
        compose.onNodeWithText("Season", substring = true).performClick()
        compose.onNodeWithText(SeasonId.containing(Instant.now()).previous.displayName).performClick()
        compose.waitForText("Hohenwald")
        compose.onNodeWithText("Hohenwald").assertIsDisplayed()
        compose.onNodeWithText("Nordvik").assertIsNotDisplayed()
    }

    /** A first load that fails says so, and tries again on demand. */
    @Test
    fun aFailedLoadOffersToTryAgain() {
        launch(IbuClient(httpClient = HttpClient(MockEngine { respondError(HttpStatusCode.ServiceUnavailable) })))
        compose.waitForText("Unable to load")
        compose.onNodeWithText("Results are temporarily unavailable.").assertExists()
        compose.onNodeWithText("Try again").performClick()
        compose.waitForText("Unable to load")
        compose.onNode(hasContentDescription("Back")).assertDoesNotExist()
    }

    /** Settings, from Home, say where the data comes from and the app's version, under the notifications, as the iOS app's settings. */
    @Test
    fun settingsSayWhereTheDataComesFrom() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("IBU Datacenter"))
        compose.onNodeWithText("IBU Datacenter").assertExists()
        compose.onNodeWithText(BuildConfig.VERSION_NAME).assertExists()
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithText("IBU Datacenter").assertDoesNotExist()
    }
}
