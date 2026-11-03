package com.fouteox.biathlon

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.core.content.getSystemService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/** The server's alerts as the app shows them in the foreground, the same as Android shows them in the background. */
@RunWith(RobolectricTestRunner::class)
class RaceNotificationsTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun namesTheRaceAndWhatHappened() {
        assertEquals(
            "Men's Sprint" to "This race will not take place.",
            RaceNotifications.alertText(context, "BT2627SWRLCP01SMSP", null, "push_cancelled", null),
        )
        assertEquals(
            "Women's Pursuit" to "New start on Thursday at 3:45 PM.",
            RaceNotifications.alertText(context, "BT2627SWRLCP01SWPU", null, "push_rescheduled", arrayOf("Thursday", "3:45 PM")),
        )
    }

    @Test
    fun keepsTheServersTitleForARaceTheAppCannotName() {
        assertEquals(
            "Super sprint" to "This race will not take place.",
            RaceNotifications.alertText(context, "BT2627SWRLCP01SMSS", "Super sprint", "push_cancelled", null),
        )
    }

    @Test
    fun skipsAnAlertItCannotWord() {
        assertNull(RaceNotifications.alertText(context, "BT2627SWRLCP01SMSP", null, "push_unknown", null))
        assertNull(RaceNotifications.alertText(context, "BT2627SWRLCP01SMSP", null, "push_rescheduled", null))
    }

    @Test
    fun showsOneNotificationPerRaceInItsChannel() {
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        RaceNotifications.showAlert(context, "R1", "Men's Sprint", "This race will not take place.")
        RaceNotifications.showAlert(context, "R1", "Men's Sprint", "New start on Thursday at 3:45 PM.")
        RaceNotifications.showReminder(context, "R1", "Men's Sprint", "Starts in 15 minutes")

        val posted = shadowOf(checkNotNull(context.getSystemService<NotificationManager>())).allNotifications
        assertEquals(listOf(RaceNotifications.ALERT_CHANNEL, RaceNotifications.REMINDER_CHANNEL), posted.map { it.channelId })
        assertEquals("New start on Thursday at 3:45 PM.", posted.first().extras.getString(Notification.EXTRA_TEXT))
    }
}
