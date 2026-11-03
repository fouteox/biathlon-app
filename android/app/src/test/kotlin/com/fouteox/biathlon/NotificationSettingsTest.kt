package com.fouteox.biathlon

import com.fouteox.biathlon.kit.NotificationPreferences
import com.fouteox.biathlon.kit.RaceCategory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class NotificationSettingsTest {
    private val settings = temporaryNotificationSettings()

    @Test
    fun startsWithEverythingOff() = runBlocking {
        assertEquals(NotificationPreferences(), settings.preferences.first())
    }

    @Test
    fun keepsEachChange() = runBlocking {
        val changed = NotificationPreferences(
            reminderEnabled = true,
            reminderMinutes = 30,
            cancellationAlerts = true,
            reschedulingAlerts = true,
            categories = setOf(RaceCategory.MIXED),
        )
        settings.update { changed }
        assertEquals(changed, settings.preferences.first())
        settings.update { it.copy(categories = emptySet()) }
        assertEquals(emptySet<RaceCategory>(), settings.preferences.first().categories)
    }
}
