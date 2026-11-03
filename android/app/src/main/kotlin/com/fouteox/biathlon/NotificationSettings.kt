package com.fouteox.biathlon

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.fouteox.biathlon.kit.NotificationPreferences
import com.fouteox.biathlon.kit.RaceCategory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** The user's notification preferences, kept on the device as the iOS app keeps them in `UserDefaults`. */
class NotificationSettings(private val store: DataStore<Preferences>) {
    val preferences: Flow<NotificationPreferences> = store.data.map { it.notificationPreferences() }.distinctUntilChanged()

    suspend fun update(change: (NotificationPreferences) -> NotificationPreferences) {
        store.edit { stored ->
            val preferences = change(stored.notificationPreferences())
            stored[REMINDER_ENABLED] = preferences.reminderEnabled
            stored[REMINDER_MINUTES] = preferences.reminderMinutes
            stored[CANCELLATION_ALERTS] = preferences.cancellationAlerts
            stored[RESCHEDULING_ALERTS] = preferences.reschedulingAlerts
            stored[CATEGORIES] = preferences.categories.map { it.code }.toSet()
        }
    }

    private fun Preferences.notificationPreferences(): NotificationPreferences {
        val defaults = NotificationPreferences()
        return NotificationPreferences(
            reminderEnabled = this[REMINDER_ENABLED] ?: defaults.reminderEnabled,
            reminderMinutes = this[REMINDER_MINUTES]?.takeIf { it in NotificationPreferences.REMINDER_CHOICES } ?: defaults.reminderMinutes,
            cancellationAlerts = this[CANCELLATION_ALERTS] ?: defaults.cancellationAlerts,
            reschedulingAlerts = this[RESCHEDULING_ALERTS] ?: defaults.reschedulingAlerts,
            categories = this[CATEGORIES]?.mapNotNull(RaceCategory::of)?.toSet() ?: defaults.categories,
        )
    }

    companion object {
        private val REMINDER_ENABLED = booleanPreferencesKey("reminderEnabled")
        private val REMINDER_MINUTES = intPreferencesKey("reminderMinutes")
        private val CANCELLATION_ALERTS = booleanPreferencesKey("cancellationAlerts")
        private val RESCHEDULING_ALERTS = booleanPreferencesKey("reschedulingAlerts")
        private val CATEGORIES = stringSetPreferencesKey("categories")

        private val Context.store by preferencesDataStore("notifications")

        fun open(context: Context) = NotificationSettings(context.store)
    }
}
