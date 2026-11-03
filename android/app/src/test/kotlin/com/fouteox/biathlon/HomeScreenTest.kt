package com.fouteox.biathlon

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.performScrollToNode
import com.fouteox.biathlon.kit.BiathlonEvent
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.HomeFeed
import com.fouteox.biathlon.kit.RaceResults
import com.fouteox.biathlon.kit.ResultRow
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class HomeScreenTest {
    @get:Rule
    val compose = createComposeRule()

    /** The leader of the live race won the latest one too: both lists show her, apart. */
    @Test
    fun showsAnAthleteInBothTheLiveRaceAndTheLatestResult() {
        val now = Instant.now()
        val event = BiathlonEvent("BT2627SWRLCP01", "Nordvik", now.minus(Duration.ofDays(2)), now.plus(Duration.ofDays(4)))
        val finished = Competition("BT2627SWRLCP01SWSP", "Women 7.5 km Sprint", now.minus(Duration.ofDays(1)), statusId = 11)
        val live = Competition("BT2627SWRLCP01SWPU", "Women 10 km Pursuit", now.minus(Duration.ofMinutes(20)), isLive = true)
        val leader = ResultRow(athleteId = "BTNORSW01", name = "SOLBERG Ingrid", shortName = "SOLBERG I.", nation = "NOR", rank = "1")
        val feed = HomeFeed(
            events = listOf(event),
            races = listOf(finished, live),
            liveResults = RaceResults(isResult = true, competition = live, rows = listOf(leader)),
            latestResults = RaceResults(isResult = true, competition = finished, rows = listOf(leader)),
        )
        val loaded = LoadViewModel { feed }
        runBlocking { loaded.load() }
        compose.setContent {
            MaterialTheme { HomeScreen(loaded, open = {}) }
        }
        compose.waitForText("SOLBERG I.")
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("All results"))
        compose.waitUntil { compose.onAllNodes(hasText("SOLBERG I.")).fetchSemanticsNodes().size == 2 }
    }
}
