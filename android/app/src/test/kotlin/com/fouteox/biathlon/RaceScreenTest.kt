package com.fouteox.biathlon

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.fouteox.biathlon.kit.IbuClient
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** A relay, from the fixture shared with the iOS app: its teams, each opening on its legs. */
@RunWith(RobolectricTestRunner::class)
class RaceScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val relay = checkNotNull(javaClass.getResource("/relay-results.json")).readText()
    private val client = IbuClient(httpClient = HttpClient(MockEngine { respond(relay) }))

    @Test
    fun relayTeamsOpenOnTheirLegs() {
        val race = checkNotNull(runBlocking { client.results("BT2526SWRLCP01SMRL") }.competition)
        compose.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalIbuClient provides client) { RaceScreen(race, onBack = {}) }
            }
        }
        compose.waitForText("NORWAY")
        compose.onNodeWithText("ULDAL M.").assertDoesNotExist()
        compose.onNodeWithText("NORWAY").performClick()
        compose.onNodeWithText("ULDAL M.").assertExists()
        compose.onNodeWithText("NORWAY").performClick()
        compose.onNodeWithText("ULDAL M.").assertDoesNotExist()
    }
}
