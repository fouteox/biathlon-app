package com.fouteox.biathlon

import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeContentTestRule

/** Waits for a text the network brings, which the fictional World Cup serves at once. */
fun ComposeContentTestRule.waitForText(text: String) {
    waitUntil(5_000L) { onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }
}
