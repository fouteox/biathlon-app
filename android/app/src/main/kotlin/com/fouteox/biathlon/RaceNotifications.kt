package com.fouteox.biathlon

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.fouteox.biathlon.kit.RaceKind

/** The app's notifications: the server's alerts and the reminders before a start, each in its own channel. */
object RaceNotifications {
    /** The server's `ANDROID_ALERT_CHANNEL` (server/src/payload.ts). */
    const val ALERT_CHANNEL = "race-alerts"
    const val REMINDER_CHANNEL = "race-reminders"

    private const val ALERT_ID = 1
    private const val REMINDER_ID = 2

    /** Creates the channels, or renames them after a change of language. */
    fun createChannels(context: Context) {
        NotificationManagerCompat.from(context).createNotificationChannelsCompat(
            listOf(
                channel(ALERT_CHANNEL, context.getString(R.string.race_alerts)),
                channel(REMINDER_CHANNEL, context.getString(R.string.reminders)),
            ),
        )
    }

    // Heads-up, as the iOS app's banners.
    private fun channel(id: String, name: String) =
        NotificationChannelCompat.Builder(id, NotificationManagerCompat.IMPORTANCE_HIGH).setName(name).build()

    /**
     * The text of a server alert, from the keys and arguments it carries (`buildAndroidNotification` in
     * server/src/payload.ts) as Android resolves them itself while the app is in the background.
     * The title names the race from its ID, as the server's `titleLocKey`.
     */
    fun alertText(context: Context, raceId: String, title: String?, bodyKey: String?, bodyArgs: Array<String>?): Pair<String, String>? {
        val raceTitle = RaceKind.of(raceId)?.let { context.getString(it.title) } ?: title ?: return null
        val body = when (bodyKey) {
            "push_cancelled" -> context.getString(R.string.push_cancelled)
            "push_rescheduled" -> bodyArgs?.takeIf { it.size == 2 }?.let { context.getString(R.string.push_rescheduled, it[0], it[1]) }
            else -> null
        } ?: return null
        return raceTitle to body
    }

    /** A reminder's text, under the race's name. */
    fun reminderText(context: Context, minutes: Int): String =
        context.resources.getQuantityString(R.plurals.starts_in_arg_minutes, minutes, minutes)

    fun showAlert(context: Context, raceId: String, title: String, body: String) =
        show(context, ALERT_CHANNEL, raceId, ALERT_ID, title, body)

    fun showReminder(context: Context, raceId: String, title: String, body: String) =
        show(context, REMINDER_CHANNEL, raceId, REMINDER_ID, title, body)

    /** One notification per race and channel, which a later one replaces. */
    private fun show(context: Context, channel: String, raceId: String, id: Int, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(raceId, id, notification)
    }
}
