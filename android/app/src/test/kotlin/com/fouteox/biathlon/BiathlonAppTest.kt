package com.fouteox.biathlon

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class BiathlonAppTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun opensOnHome() {
        compose.setContent { BiathlonApp() }
        compose.onNodeWithText("Home").assertExists()
    }

    @Test
    @Config(qualifiers = "fr")
    fun speaksFrench() {
        compose.setContent { BiathlonApp() }
        compose.onNodeWithText("Accueil").assertExists()
    }

    @Test
    @Config(qualifiers = "de")
    fun speaksGerman() {
        compose.setContent { BiathlonApp() }
        compose.onNodeWithText("Übersicht").assertExists()
    }
}
