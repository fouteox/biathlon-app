package com.fouteox.biathlon

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.fouteox.biathlon.kit.Date
import com.fouteox.biathlon.kit.IBUClient
import java.time.Instant
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The calendar screen on BiathlonKit's fictional World Cup, through the Swift library. */
@RunWith(AndroidJUnit4::class)
class SeasonCalendarScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun showsTheSampleSeasonEvents() {
        compose.setContent {
            MaterialTheme {
                SeasonCalendarScreen(viewModel {
                    SeasonCalendarViewModel { arena ->
                        IBUClient.sample(Date.fromInstant(Instant.now(), arena), false, arena)
                    }
                })
            }
        }
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText("Nordvik").fetchSemanticsNodes().isNotEmpty()
        }
        for (place in listOf("Nordvik", "Lac-Blanc", "Hohenwald")) {
            compose.onNodeWithText(place).assertExists()
        }
    }
}
