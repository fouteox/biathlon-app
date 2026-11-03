package com.fouteox.biathlon

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.fouteox.biathlon.kit.FollowedRaces
import com.fouteox.biathlon.kit.LiveUpdate
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.ServerException
import com.google.firebase.messaging.FirebaseMessaging
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The races the user follows live, as `LiveActivities` on iOS: each one's Live Update shows the
 * state the server publishes on the race's FCM topic, from shortly before the start
 * (`RaceLiveState.LEAD`) until its end. Only races the user picks: Android keeps Live Updates
 * for activities the user starts, not for their interests
 * (https://developer.android.com/develop/ui/views/notifications/live-update#user-initiated).
 */
class LiveUpdates(
    private val context: Context,
    private val server: ServerClient,
    private val topics: Topics,
    private val store: DataStore<Preferences>,
    /** Where a race catches up once its topic's subscription succeeds, outliving the screen that followed it. */
    private val scope: CoroutineScope,
) {
    /** The races' FCM topics, which tests replace. */
    interface Topics {
        /** Subscribes to `topic`, then calls [onSubscribed] once the device is subscribed, which can come much later. */
        fun subscribe(topic: String, onSubscribed: () -> Unit)

        fun unsubscribe(topic: String)
    }

    /**
     * FCM keeps each subscription change and retries it until it succeeds, completing its task
     * then (https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessaging#subscribeToTopic(java.lang.String)):
     * nothing to retry here.
     */
    object FcmTopics : Topics {
        override fun subscribe(topic: String, onSubscribed: () -> Unit) {
            FirebaseMessaging.getInstance().subscribeToTopic(topic).addOnSuccessListener { onSubscribed() }
        }

        override fun unsubscribe(topic: String) {
            FirebaseMessaging.getInstance().unsubscribeFromTopic(topic)
        }
    }

    /** A race followed after its end. */
    class RaceOverException : Exception("The race is over")

    /** Changes run one after another, each on the races the last one left. */
    private val lock = Mutex()

    val followed: Flow<Set<String>> = store.data.map { FollowedRaces.decoded(it[RACES]).raceIds }

    /**
     * Follows a race: its Live Update shows its current state at once when its topic is open,
     * from the topic's first message otherwise. A race over is not followed.
     */
    suspend fun follow(raceId: String, name: String, start: Instant) = lock.withLock {
        edit { it.follow(raceId, name, start) }
        subscribe(raceId)
        when (val current = lookUp(raceId)) {
            is LiveUpdate.Update -> showIfNew(current)
            is LiveUpdate.End -> {
                stopAlone(raceId)
                throw RaceOverException()
            }
            null -> Unit
        }
    }

    suspend fun stop(raceId: String) = lock.withLock { stopAlone(raceId) }

    private suspend fun stopAlone(raceId: String) {
        edit { it.unfollow(raceId) }
        topics.unsubscribe(LiveUpdate.topic(raceId))
        RaceNotifications.cancelLiveUpdate(context, raceId)
    }

    /** A message of a race's topic: a state newer than the one on screen, or the race's end. */
    suspend fun receive(update: LiveUpdate, now: Instant = Instant.now()) = lock.withLock {
        val races = races()
        val race = races[update.raceId]
        when {
            // Unfollowed while its unsubscription was on its way, or after its end.
            race == null -> topics.unsubscribe(LiveUpdate.topic(update.raceId))
            update is LiveUpdate.Update -> showIfNew(update)
            // A cancellation called off: the reinstated race's state is newer than its end.
            !races.isNew(update) -> Unit
            update is LiveUpdate.End -> {
                RaceNotifications.showLiveUpdate(context, race.name, update, now)
                edit { it.unfollow(update.raceId) }
                topics.unsubscribe(LiveUpdate.topic(update.raceId))
            }
        }
    }

    /**
     * Shows a newer state, or the same one again where it is no longer on screen: after a restart,
     * or before the permission to notify. Never an older one, which would let older messages through.
     */
    private suspend fun showIfNew(update: LiveUpdate.Update) {
        val races = races()
        if (races.isOlder(update) || !races.isNew(update) && RaceNotifications.isLiveUpdateShown(context, update.raceId)) return
        RaceNotifications.showLiveUpdate(context, checkNotNull(races[update.raceId]).name, update)
        edit { it.shown(update) }
    }

    /**
     * As the app comes to the foreground: forgets the races whose end never came, then shows each
     * followed race's current state, in case its topic's messages were missed.
     */
    suspend fun refresh(now: Instant = Instant.now()) {
        val stale = lock.withLock { races().let { it.raceIds - it.pruned(now).raceIds } }
        stale.forEach { stop(it) }
        lock.withLock { races().raceIds }.forEach { catchUp(it, now) }
    }

    /**
     * Subscribes to the followed races' topics again once FCM registers the installation: Firebase
     * doesn't say that subscriptions outlive a new installation ID.
     */
    suspend fun resubscribe() = lock.withLock {
        races().raceIds.forEach(::subscribe)
    }

    /**
     * Subscribes to the race's topic, then catches up once subscribed: a message published before
     * then, the topic's first or the race's end, never reaches the device.
     */
    private fun subscribe(raceId: String) = topics.subscribe(LiveUpdate.topic(raceId)) { scope.launch { catchUp(raceId) } }

    /** Shows the race's current state, as the server last published it. */
    private suspend fun catchUp(raceId: String, now: Instant = Instant.now()) {
        lookUp(raceId)?.let { receive(it, now) }
    }

    /** The race's current state; `null` before its topic opens, or when the server can't be reached, its topic then bringing the next. */
    private suspend fun lookUp(raceId: String): LiveUpdate? = try {
        server.liveUpdate(raceId)
    } catch (error: ServerException) {
        Log.e(TAG, "Live state lookup failed", error)
        null
    } catch (error: IOException) {
        Log.w(TAG, "Live state unreachable", error)
        null
    }

    private suspend fun races() = FollowedRaces.decoded(store.data.first()[RACES])

    private suspend fun edit(transform: (FollowedRaces) -> FollowedRaces) {
        store.edit { it[RACES] = transform(FollowedRaces.decoded(it[RACES])).encoded() }
    }

    /** Stops following a race from its Live Update: its Unpin action, or its dismissal. */
    class UnpinReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val raceId = intent.data?.schemeSpecificPart ?: return
            // Without a server, only the developer settings' demo shows.
            val liveUpdates = (context.applicationContext as BiathlonApplication).liveUpdates
                ?: return RaceNotifications.cancelLiveUpdate(context, raceId)
            val pending = goAsync()
            CoroutineScope(Dispatchers.Default).launch {
                try {
                    liveUpdates.stop(raceId)
                } finally {
                    pending.finish()
                }
            }
        }
    }

    companion object {
        private const val TAG = "LiveUpdates"
        private const val SCHEME = "biathlon-live-update"

        private val RACES = stringPreferencesKey("races")

        private val Context.store by preferencesDataStore("live-updates")

        fun open(context: Context, server: ServerClient) =
            LiveUpdates(context, server, FcmTopics, context.store, CoroutineScope(SupervisorJob() + Dispatchers.Default))

        /** Unpins the race's Live Update, told apart from the other races' by its data. */
        fun unpinIntent(context: Context, raceId: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, UnpinReceiver::class.java).setData(Uri.fromParts(SCHEME, raceId, null)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
