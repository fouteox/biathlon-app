package com.fouteox.biathlon

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
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
            stored.remove(SYNCED)
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
        // Nothing new for the server, or a device it never had to forget.
        if (synced == request || (registration == null && synced?.startsWith("$fid ") != true)) return Outcome.DONE
        return try {
            server.registerAndroidDevice(fid, registration, integrityToken)
            store.edit { it[SYNCED] = request }
            Outcome.DONE
        } catch (error: ServerException.Http) {
            Log.e(TAG, "Server sync refused", error)
            if (error.status == 429 || error.status >= 500) Outcome.RETRY else Outcome.FAILED
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

        private val Context.store by preferencesDataStore("push")

        fun open(context: Context, server: ServerClient, settings: NotificationSettings, integrityToken: suspend (String) -> String) =
            PushRegistration(server, settings, context.store, integrityToken)
    }
}
