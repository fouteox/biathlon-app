package com.fouteox.biathlon.kit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NotificationPreferencesTest {
    @Test
    fun startsWithEverythingOff() {
        val preferences = NotificationPreferences()
        assertFalse(preferences.anyEnabled)
        assertEquals(15, preferences.reminderMinutes)
        assertEquals(RaceCategory.entries.toSet(), preferences.categories)
    }

    @Test
    fun wantsPushForAnAlertTypeAndACategory() {
        assertTrue(NotificationPreferences(cancellationAlerts = true).wantsPush)
        assertTrue(NotificationPreferences(reschedulingAlerts = true).wantsPush)
        assertFalse(NotificationPreferences(cancellationAlerts = true, categories = emptySet()).wantsPush)
        assertFalse(NotificationPreferences(reminderEnabled = true).wantsPush)
        assertTrue(NotificationPreferences(reminderEnabled = true).anyEnabled)
    }

    @Test
    fun registersWhatTheServerReads() {
        val preferences = NotificationPreferences(
            cancellationAlerts = true,
            categories = setOf(RaceCategory.WOMEN, RaceCategory.MEN),
        )
        assertEquals(
            AndroidDeviceRegistration(listOf("SM", "SW"), cancellation = true, rescheduling = false, "fr-FR", "Europe/Paris"),
            preferences.registration("fr-FR", "Europe/Paris"),
        )
        assertNull(NotificationPreferences(reminderEnabled = true).registration("fr-FR", "Europe/Paris"))
    }
}
