package com.fouteox.biathlon

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.fouteox.biathlon.kit.ServerClient
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.io.File
import java.nio.file.Files
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The device's registration on the server, which each costs a Play Integrity token. */
@RunWith(RobolectricTestRunner::class)
class PushRegistrationTest {
    private val requests = mutableListOf<HttpRequestData>()
    private var status = HttpStatusCode.NoContent
    private val settings = temporaryNotificationSettings()
    private val registration = PushRegistration(
        ServerClient(
            Url("https://server.example/"),
            HttpClient(
                MockEngine { request ->
                    requests += request
                    respond("", status)
                },
            ),
        ),
        settings,
        PreferenceDataStoreFactory.create { File(Files.createTempDirectory("push").toFile(), "push.preferences_pb") },
        integrityToken = { "token" },
    )

    private suspend fun sync() = registration.sync(Locale.FRANCE, ZoneId.of("Europe/Paris"))

    private suspend fun turnAlertsOn() = settings.update { it.copy(cancellationAlerts = true) }

    @Test
    fun waitsForFcmToRegisterTheInstallation() = runBlocking {
        turnAlertsOn()
        assertEquals(PushRegistration.Outcome.DONE, sync())
        assertEquals(emptyList<HttpRequestData>(), requests)
    }

    @Test
    fun sendsEachRegistrationOnce() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        assertEquals(PushRegistration.Outcome.DONE, sync())
        assertEquals(PushRegistration.Outcome.DONE, sync())
        assertEquals(listOf(HttpMethod.Put), requests.map { it.method })
        assertEquals("https://server.example/v1/android-devices/fid-1", requests.single().url.toString())
    }

    /** Firebase: send the ID each time FCM reports it, as it can rotate. */
    @Test
    fun sendsAgainEachTimeFcmReportsTheInstallation() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        sync()
        registration.registered("fid-1")
        sync()
        registration.registered("fid-2")
        sync()
        assertEquals(listOf("fid-1", "fid-1", "fid-2"), requests.map { it.url.segments.last() })
    }

    @Test
    fun forgetsTheDeviceOnceAlertsAreOff() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        sync()
        settings.update { it.copy(cancellationAlerts = false, reminderEnabled = true) }
        sync()
        sync()
        assertEquals(listOf(HttpMethod.Put, HttpMethod.Delete), requests.map { it.method })
    }

    /** FCM may report the installation again before the server has forgotten it. */
    @Test
    fun stillForgetsTheDeviceAfterFcmReportsItAgain() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        sync()
        settings.update { it.copy(cancellationAlerts = false) }
        status = HttpStatusCode.ServiceUnavailable
        sync()
        registration.registered("fid-1")
        status = HttpStatusCode.NoContent
        sync()
        assertEquals(listOf(HttpMethod.Put, HttpMethod.Delete, HttpMethod.Delete), requests.map { it.method })
    }

    /** The server may have registered the device although its answer was lost. */
    @Test
    fun forgetsADeviceWhoseRegistrationGotNoAnswer() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        status = HttpStatusCode.GatewayTimeout
        sync()
        settings.update { it.copy(cancellationAlerts = false) }
        status = HttpStatusCode.NoContent
        sync()
        sync()
        assertEquals(listOf(HttpMethod.Put, HttpMethod.Delete), requests.map { it.method })
    }

    @Test
    fun triesToForgetAgainAfterAFailedAttempt() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        status = HttpStatusCode.GatewayTimeout
        sync()
        settings.update { it.copy(cancellationAlerts = false) }
        sync()
        status = HttpStatusCode.NoContent
        sync()
        sync()
        assertEquals(listOf(HttpMethod.Put, HttpMethod.Delete, HttpMethod.Delete), requests.map { it.method })
    }

    /** A DELETE whose answer is lost may have reached the server: turning alerts on again registers again. */
    @Test
    fun registersAgainAfterAnUnansweredUnregistration() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        sync()
        settings.update { it.copy(cancellationAlerts = false) }
        status = HttpStatusCode.GatewayTimeout
        sync()
        turnAlertsOn()
        status = HttpStatusCode.NoContent
        sync()
        sync()
        assertEquals(listOf(HttpMethod.Put, HttpMethod.Delete, HttpMethod.Put), requests.map { it.method })
    }

    @Test
    fun hasNothingToForgetForADeviceNeverRegistered() = runBlocking {
        registration.registered("fid-1")
        assertEquals(PushRegistration.Outcome.DONE, sync())
        assertEquals(emptyList<HttpRequestData>(), requests)
    }

    @Test
    fun retriesWhileTheServerIsUnavailableOnly() = runBlocking {
        registration.registered("fid-1")
        turnAlertsOn()
        status = HttpStatusCode.ServiceUnavailable
        assertEquals(PushRegistration.Outcome.RETRY, sync())
        status = HttpStatusCode.Unauthorized
        assertEquals(PushRegistration.Outcome.FAILED, sync())
        status = HttpStatusCode.NoContent
        assertEquals(PushRegistration.Outcome.DONE, sync())
        assertEquals(3, requests.size)
    }
}
