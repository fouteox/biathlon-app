package com.fouteox.biathlon

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.app.AlarmManagerCompat
import androidx.core.content.getSystemService
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.IbuException
import com.fouteox.biathlon.kit.ReminderPlan
import com.fouteox.biathlon.kit.upcomingRaces
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.flow.first

/**
 * The local "N minutes before the start" reminders, as `ReminderScheduler` on iOS: one exact alarm
 * per race of the coming week. A reminder that comes late is useless, so they need the "Alarms &
 * reminders" access, which Android asks the user for (https://developer.android.com/develop/background-work/services/alarms#exact);
 * without it, none is set and Settings asks for it.
 */
class Reminders(
    private val context: Context,
    private val client: IbuClient,
    private val settings: NotificationSettings,
    private val store: DataStore<Preferences>,
) {
    private val alarms = checkNotNull(context.getSystemService<AlarmManager>())

    /**
     * Sets the alarms of the current preferences in place of the previous ones; `false` when the
     * calendar can't be fetched, which keeps the previous ones.
     */
    suspend fun refresh(now: Instant = Instant.now()): Boolean {
        val preferences = settings.preferences.first()
        val reminders = if (preferences.reminderEnabled && AlarmManagerCompat.canScheduleExactAlarms(alarms)) {
            val races = try {
                client.upcomingRaces(now, ReminderPlan.HORIZON)
            } catch (error: IbuException) {
                Log.e(TAG, "Calendar for reminders failed", error)
                return false
            } catch (error: IOException) {
                Log.w(TAG, "Calendar for reminders unreachable", error)
                return false
            }
            ReminderPlan.reminders(races, preferences.categories, preferences.reminderMinutes, now)
        } else {
            emptyList()
        }
        for (raceId in store.data.first()[SCHEDULED].orEmpty()) {
            alarms.cancel(alarm(raceId, PendingIntent.FLAG_NO_CREATE) ?: continue)
        }
        for (reminder in reminders) {
            val intent = alarmIntent(reminder.race.id)
                .putExtra(EXTRA_TITLE, reminder.race.title(context.resources))
                .putExtra(EXTRA_BODY, RaceNotifications.reminderText(context, preferences.reminderMinutes))
            val operation = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            AlarmManagerCompat.setExactAndAllowWhileIdle(alarms, AlarmManager.RTC_WAKEUP, reminder.fireTime.toEpochMilli(), operation)
        }
        store.edit { it[SCHEDULED] = reminders.map { reminder -> reminder.race.id }.toSet() }
        return true
    }

    /** The alarm of `raceId`, told apart from the others by its data. */
    private fun alarm(raceId: String, flags: Int): PendingIntent? =
        PendingIntent.getBroadcast(context, 0, alarmIntent(raceId), flags or PendingIntent.FLAG_IMMUTABLE)

    private fun alarmIntent(raceId: String) =
        Intent(context, ReminderReceiver::class.java).setData(Uri.fromParts(SCHEME, raceId, null))

    /** Shows a reminder as its alarm goes off. */
    class ReminderReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val raceId = intent.data?.schemeSpecificPart ?: return
            val title = intent.getStringExtra(EXTRA_TITLE) ?: return
            val body = intent.getStringExtra(EXTRA_BODY) ?: return
            RaceNotifications.showReminder(context, raceId, title, body)
        }
    }

    /**
     * Sets the alarms again where Android drops them: after a restart and an update of the app, and
     * once the user grants the "Alarms & reminders" access.
     */
    class RescheduleReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
                -> NotificationWork.refreshReminders(context)
            }
        }
    }

    companion object {
        private const val TAG = "Reminders"
        private const val SCHEME = "biathlon-reminder"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"

        /** The races whose alarms are set, to cancel them at the next refresh. */
        private val SCHEDULED = stringSetPreferencesKey("scheduled")

        private val Context.store by preferencesDataStore("reminders")

        fun open(context: Context, client: IbuClient, settings: NotificationSettings) = Reminders(context, client, settings, context.store)
    }
}
