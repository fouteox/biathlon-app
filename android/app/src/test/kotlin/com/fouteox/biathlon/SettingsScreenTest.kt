package com.fouteox.biathlon

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.core.content.getSystemService
import com.fouteox.biathlon.kit.RaceCategory
import java.time.Duration
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowAlarmManager

/** The notification settings, as on iOS: everything off until the user turns it on. */
@RunWith(RobolectricTestRunner::class)
class SettingsScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val settings = temporaryNotificationSettings()

    private fun showSettings() {
        compose.showScreen(notifications = settings) { SettingsScreen(onBack = {}) }
        compose.waitForText("Reminder before the start")
    }

    private fun preferences() = runBlocking { settings.preferences.first() }

    @Test
    fun turnsTheAlertsOnByCategory() {
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        showSettings()
        compose.onNodeWithText("Race cancelled").assertIsOff().performClick()
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Mixed"))
        // Scrolled to the top of the list, under the top app bar, which a tap would hit: toggled as TalkBack does.
        compose.onNodeWithText("Mixed").assertIsOn().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitUntil { preferences().categories == setOf(RaceCategory.MEN, RaceCategory.WOMEN) }
        assertTrue(preferences().cancellationAlerts)
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Race cancelled"))
        compose.onNodeWithText("Race cancelled").assertIsOn()
    }

    @Test
    fun choosesHowLongBeforeTheStartToRemind() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        showSettings()
        compose.onNodeWithText("Notify me").assertDoesNotExist()
        compose.onNodeWithText("Reminder before the start").performClick()
        compose.waitForText("Notify me")
        compose.onNodeWithText("15 min").performClick()
        compose.onNodeWithText("30 min").performClick()
        compose.waitUntil { preferences().reminderMinutes == 30 }
        assertEquals(true, preferences().reminderEnabled)
    }

    @Test
    fun asksForTheExactAlarmAccessTheRemindersNeed() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        runBlocking { settings.update { it.copy(reminderEnabled = true) } }
        showSettings()
        compose.waitForText("Allow alarms and reminders so that reminders arrive on time.")
        compose.onNodeWithText("Allow").assertExists()
    }

    @Test
    fun pointsToTheSystemSettingsWhenNotificationsAreOff() {
        shadowOf(checkNotNull(RuntimeEnvironment.getApplication().getSystemService<NotificationManager>())).setNotificationsEnabled(false)
        runBlocking { settings.update { it.copy(reschedulingAlerts = true) } }
        showSettings()
        compose.waitForText("Notifications are turned off in Settings.")
        compose.onNodeWithText("Open Settings").assertExists()
    }

    /** Debug builds: the Live Update's every state, then its end, without a race. */
    @Test
    fun showsTheLiveUpdateDemo() {
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        RaceNotifications.createChannels(RuntimeEnvironment.getApplication())
        showSettings()
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("End the live update demo"))
        val notifications = shadowOf(checkNotNull(RuntimeEnvironment.getApplication().getSystemService<NotificationManager>()))
        val texts = (1..3).map {
            compose.onNodeWithText("Show the next live update demo state").performSemanticsAction(SemanticsActions.OnClick)
            notifications.allNotifications.single().extras.getCharSequence(Notification.EXTRA_TEXT).toString()
        }
        assertTrue(texts[0].startsWith("Start "))
        assertEquals("1 🇫🇷 PERROT E. 12:41.6", texts[2])
        compose.onNodeWithText("End the live update demo").performSemanticsAction(SemanticsActions.OnClick)
        val end = notifications.allNotifications.single()
        assertEquals("Finished", end.extras.getString(Notification.EXTRA_SUB_TEXT))
        assertEquals(Duration.ofMinutes(1).toMillis(), end.timeoutAfter)
    }
}
