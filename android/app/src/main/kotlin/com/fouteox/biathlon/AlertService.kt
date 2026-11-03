package com.fouteox.biathlon

import android.annotation.SuppressLint
import com.fouteox.biathlon.kit.LiveUpdate
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.runBlocking

/**
 * Receives the server's alerts and the followed races' states through FCM, addressed to this installation's Firebase Installation ID
 * (https://firebase.google.com/docs/cloud-messaging/android/client). With the installation ID,
 * FCM reports registrations to [onRegistered] and no longer calls `onNewToken`, which lint still asks for.
 */
@SuppressLint("MissingFirebaseInstanceTokenRefresh")
class AlertService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        val app = application as BiathlonApplication
        // Called on FCM's own background thread, which may wait for the store.
        runBlocking {
            app.pushRegistration?.registered(installationId)
            app.liveUpdates?.resubscribe()
        }
        NotificationWork.syncPush(this)
    }

    /**
     * Android shows the alerts itself while the app is in the background; in the foreground, FCM
     * hands them to the app, which shows them the same way, as the iOS app shows banners.
     */
    override fun onMessageReceived(message: RemoteMessage) {
        // A followed race's state, which the app always shows itself: the server sends it as data only.
        LiveUpdate.parse(message.data)?.let { update ->
            runBlocking { (application as BiathlonApplication).liveUpdates?.receive(update) }
            return
        }
        val raceId = message.data["raceId"] ?: return
        message.notification?.let { notification ->
            RaceNotifications.alertText(this, raceId, notification.title, notification.bodyLocalizationKey, notification.bodyLocalizationArgs)
                ?.let { (title, body) -> RaceNotifications.showAlert(this, raceId, title, body) }
        }
        // A start moved: its reminder moves too.
        if (message.data.containsKey("startTime")) NotificationWork.refreshReminders(this)
    }
}
