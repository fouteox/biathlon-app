package com.fouteox.biathlon

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.ServerException
import com.google.android.gms.common.api.ApiException
import java.io.IOException
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.flow.first

/**
 * Keeps the server in sync with this device's Firebase Installation ID and the user's alert
 * preferences, as `PushRegistration` does with the APNs token on iOS. Each request carries a
 * Play Integrity token, which costs a quota: a registration the server already has isn't sent again.
 */
class PushRegistration(
    private val server: ServerClient,
    private val settings: NotificationSettings,
    private val store: DataStore<Preferences>,
    private val integrityToken: suspend (requestHash: String) -> String,
) {
    enum class Outcome { DONE, RETRY, FAILED }

    /**
     * FCM delivers to an installation once it is registered, which it reports with its ID: Firebase
     * asks to send the ID to the server each time, as it can rotate.
     */
    suspend fun registered(installationId: String) {
        store.edit { stored ->
            stored[INSTALLATION_ID] = installationId
            stored[RESEND] = true
        }
    }

    /** Sends the current preferences, or unregisters the device when no push alert is wanted. */
    suspend fun sync(locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault()): Outcome {
        val stored = store.data.first()
        // Until FCM has registered the installation, it can't deliver to it.
        val fid = stored[INSTALLATION_ID] ?: return Outcome.DONE
        val registration = settings.preferences.first().registration(locale.toLanguageTag(), zone.id)
        // The registration's data class text: equal for equal registrations.
        val request = "$fid $registration"
        val synced = stored[SYNCED]
        // A request sent without an answer may or may not have changed the server: the current one
        // is sent then, whatever it is.
        val upToDate = stored[SENT] == null && if (registration == null) {
            // Forgotten already, or never registered with this installation.
            synced == request || synced?.startsWith("$fid ") != true
        } else {
            synced == request && stored[RESEND] != true
        }
        if (upToDate) return Outcome.DONE
        return try {
            // A request whose answer is lost may still have reached the server.
            store.edit { it[SENT] = request }
            server.registerAndroidDevice(fid, registration, integrityToken)
            store.edit {
                it[SYNCED] = request
                it.remove(SENT)
                it.remove(RESEND)
            }
            Outcome.DONE
        } catch (error: ServerException.Http) {
            Log.e(TAG, "Server sync refused", error)
            if (error.status == 429 || error.status >= 500) {
                Outcome.RETRY
            } else {
                // Refused: the server kept its state.
                store.edit { it.remove(SENT) }
                Outcome.FAILED
            }
        } catch (error: IOException) {
            Log.w(TAG, "Server unreachable", error)
            Outcome.RETRY
        } catch (error: ApiException) {
            // Play Integrity's errors, which Google advises retrying with a backoff.
            Log.w(TAG, "No integrity token", error)
            Outcome.RETRY
        }
    }

    companion object {
        private const val TAG = "PushRegistration"
        private val INSTALLATION_ID = stringPreferencesKey("installationId")

        /** The request the server last accepted: the installation ID, then the registration. */
        private val SYNCED = stringPreferencesKey("synced")

        /** The request last sent, until the server accepts one: the server's state is unknown meanwhile. */
        private val SENT = stringPreferencesKey("sent")

        /** Set as FCM reports the installation, until the server has its registration again. */
        private val RESEND = booleanPreferencesKey("resend")

        private val Context.store by preferencesDataStore("push")

        fun open(context: Context, server: ServerClient, settings: NotificationSettings, integrityToken: suspend (String) -> String) =
            PushRegistration(server, settings, context.store, integrityToken)
    }
}
