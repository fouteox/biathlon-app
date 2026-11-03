package com.fouteox.biathlon

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.fouteox.biathlon.kit.Competition
import com.fouteox.biathlon.kit.LiveUpdate
import com.fouteox.biathlon.kit.Nation
import com.fouteox.biathlon.kit.RaceKind
import com.fouteox.biathlon.kit.RaceLiveState
import java.time.Instant

/**
 * The app's notifications: the server's alerts, the reminders before a start and the races
 * followed live, each in its own channel.
 */
object RaceNotifications {
    /** The server's `ANDROID_ALERT_CHANNEL` (server/src/payload.ts). */
    const val ALERT_CHANNEL = "race-alerts"
    const val REMINDER_CHANNEL = "race-reminders"
    const val LIVE_UPDATE_CHANNEL = "live-updates"

    private const val ALERT_ID = 1
    private const val REMINDER_ID = 2
    private const val LIVE_UPDATE_ID = 3

    /** Creates the channels, or renames them after a change of language. */
    fun createChannels(context: Context) {
        NotificationManagerCompat.from(context).createNotificationChannelsCompat(
            listOf(
                channel(ALERT_CHANNEL, context.getString(R.string.race_alerts)),
                channel(REMINDER_CHANNEL, context.getString(R.string.reminders)),
                // Not heads-up: the first state shows in the status bar, the next ones replace it in silence.
                NotificationChannelCompat.Builder(LIVE_UPDATE_CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                    .setName(context.getString(R.string.live_updates))
                    .build(),
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
        notify(
            context,
            raceId,
            id,
            builder(context, channel, title)
                .setContentText(body)
                .setAutoCancel(true)
                .build(),
        )
    }

    /**
     * A followed race as its Live Update shows it (https://developer.android.com/develop/ui/views/notifications/live-update),
     * as the iOS app's Live Activity: an ongoing notification Android promotes to the top of the
     * shade, the lock screen and a status bar chip, with the action to unpin it Android asks of
     * events the user follows. Then its end, which stays until its dismissal without being promoted.
     * A tap opens the race. [name]: the IBU's English name of the race.
     */
    fun showLiveUpdate(context: Context, name: String, update: LiveUpdate, now: Instant = Instant.now()) {
        val state = update.state
        val leaders = state.leaders.map(::leaderLine)
        val builder = builder(context, LIVE_UPDATE_CHANNEL, raceTitle(context.resources, update.raceId, name))
            .setContentIntent(DeepLink.Race(update.raceId, name).pendingIntent(context))
            .setSubText(context.getString(state.phase.label))
            .setContentText(leaders.firstOrNull() ?: startText(context, state))
        // The podium in full once the notification shows expanded, as Android shows Live Updates.
        if (leaders.size > 1) builder.setStyle(NotificationCompat.BigTextStyle().bigText(leaders.joinToString("\n")))
        when (update) {
            is LiveUpdate.Update -> {
                val unpin = LiveUpdates.unpinIntent(context, update.raceId)
                builder
                    .setOngoing(true)
                    .setRequestPromotedOngoing(true)
                    .setOnlyAlertOnce(true)
                    .addAction(0, context.getString(R.string.unpin), unpin)
                    // Unfollowed when dismissed: Android asks not to post a dismissed Live Update again.
                    .setDeleteIntent(unpin)
                chip(builder, state, now)
            }
            is LiveUpdate.End -> {
                val shown = update.dismissal.toEpochMilli() - now.toEpochMilli()
                if (shown <= 0) return cancelLiveUpdate(context, update.raceId)
                builder.setOnlyAlertOnce(true).setAutoCancel(true).setTimeoutAfter(shown)
            }
        }
        notify(context, update.raceId, LIVE_UPDATE_ID, builder.build())
    }

    fun isLiveUpdateShown(context: Context, raceId: String): Boolean =
        NotificationManagerCompat.from(context).activeNotifications.any { it.tag == raceId && it.id == LIVE_UPDATE_ID }

    fun cancelLiveUpdate(context: Context, raceId: String) = NotificationManagerCompat.from(context).cancel(raceId, LIVE_UPDATE_ID)

    /** The start until someone leads, unless the race won't run. */
    private fun startText(context: Context, state: RaceLiveState): String? = state.takeIf { it.phase.canBeFollowedLive }?.let {
        context.getString(R.string.start_arg, DateSkeleton.TIME.format(it.startTime, android.text.format.DateFormat.is24HourFormat(context), context.resources.configuration.locales[0]))
    }

    /** "1 🇫🇷 PERROT E. 48:12.3", as the leaders' lines of the iOS app's Live Activity. */
    private fun leaderLine(leader: RaceLiveState.Leader) =
        listOfNotNull(leader.rank, Nation.titled(leader.name, leader.nation), leader.result).joinToString(" ")

    /**
     * The status bar chip: the leader's nation, short enough to show whole (fewer than 7
     * characters), or a countdown to the start while nobody leads; the app's icon alone otherwise.
     */
    private fun chip(builder: NotificationCompat.Builder, state: RaceLiveState, now: Instant) {
        val leader = state.leaders.firstOrNull()
        when {
            leader != null -> leader.nation?.let(builder::setShortCriticalText)
            state.phase == Competition.State.SCHEDULED && state.startTime > now -> builder
                .setWhen(state.startTime.toEpochMilli())
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        }
    }

    /** A notification that opens the app, as the iOS app's alerts and reminders do. */
    private fun builder(context: Context, channel: String, title: String): NotificationCompat.Builder {
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentIntent(open)
    }

    private fun notify(context: Context, raceId: String, id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        NotificationManagerCompat.from(context).notify(raceId, id, notification)
    }
}
