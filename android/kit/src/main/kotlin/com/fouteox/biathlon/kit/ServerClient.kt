package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.URLBuilder
import io.ktor.http.Url
import io.ktor.http.appendPathSegments
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.isSuccess
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import kotlinx.serialization.Serializable

/** Client for the server's `/v1/` routes (server/src/index.ts), as the iOS app's. */
class ServerClient(
    val baseUrl: Url,
    private val httpClient: HttpClient = HttpClient(OkHttp),
) {
    suspend fun tvGuide(): TvGuide {
        val route = "v1/tv-coverage"
        val response = httpClient.get(URLBuilder(baseUrl).appendPathSegments(route).build())
        if (response.status != HttpStatusCode.OK) throw ServerException.Http(response.status.value)
        return try {
            IbuJson.decodeFromString(response.bodyAsText())
        } catch (error: IllegalArgumentException) {
            throw ServerException.Decoding(route, error)
        }
    }

    /**
     * The race's Live Update as its FCM topic last published it, for a race just followed or a
     * message missed: the topic keeps no message for a device subscribed after it was sent.
     * `null` until the topic opens, shortly before the start (`RaceLiveState.LEAD`).
     */
    suspend fun liveUpdate(raceId: String): LiveUpdate? {
        val route = "v1/races/$raceId/channels/fcm"
        val response = httpClient.get(URLBuilder(baseUrl).appendPathSegments("v1", "races", raceId, "channels", "fcm").build())
        return try {
            when (response.status) {
                HttpStatusCode.OK -> IbuJson.decodeFromString<OpenTopic>(response.bodyAsText())
                    .let { LiveUpdate.Update(raceId, it.state, Instant.ofEpochSecond(it.timestamp)) }
                HttpStatusCode.Gone -> IbuJson.decodeFromString<EndedTopic>(response.bodyAsText())
                    .let { LiveUpdate.End(raceId, it.state, Instant.ofEpochSecond(it.dismissalDate), Instant.ofEpochSecond(it.timestamp)) }
                HttpStatusCode.NotFound -> null
                else -> throw ServerException.Http(response.status.value)
            }
        } catch (error: IllegalArgumentException) {
            throw ServerException.Decoding(route, error)
        }
    }

    /**
     * Registers this device for push alerts by its Firebase Installation ID, or unregisters it
     * when `registration` is `null`. The request carries the Play Integrity token that
     * `integrityToken` gives for its [requestHash], which proves it comes from this app, from
     * Google Play, on a genuine device (server/src/playIntegrity.ts).
     */
    suspend fun registerAndroidDevice(
        fid: String,
        registration: AndroidDeviceRegistration?,
        integrityToken: suspend (requestHash: String) -> String,
    ) {
        val url = URLBuilder(baseUrl).appendPathSegments("v1", "android-devices", fid).build()
        val method = if (registration == null) HttpMethod.Delete else HttpMethod.Put
        // Sent as these exact bytes, which the hash covers.
        val body = registration?.let { IbuJson.encodeToString(it).encodeToByteArray() } ?: ByteArray(0)
        val token = integrityToken(requestHash(method.value, url.encodedPath, body))
        val response = httpClient.request(url) {
            this.method = method
            header(PLAY_INTEGRITY_HEADER, token)
            if (registration != null) setBody(ByteArrayContent(body, ContentType.Application.Json))
        }
        if (!response.status.isSuccess()) throw ServerException.Http(response.status.value)
    }

    private companion object {
        const val PLAY_INTEGRITY_HEADER = "X-Play-Integrity-Token"
    }
}

/** `GET /v1/races/:id/channels/fcm` while the topic is open: its state and when it was published, in seconds since 1970. */
@Serializable
private data class OpenTopic(val state: RaceLiveState, val timestamp: Long)

/** The same once the race is over: its final state and when it goes, in seconds since 1970. */
@Serializable
private data class EndedTopic(val state: RaceLiveState, val dismissalDate: Long, val timestamp: Long)

/** What the server stores of an Android device's alert preferences (`parseAndroidRegistration` in server/src/devices.ts). */
@Serializable
data class AndroidDeviceRegistration(
    val categories: List<String>,
    val cancellation: Boolean,
    val rescheduling: Boolean,
    /** BCP 47, the language the alerts' dates are written in. */
    val locale: String,
    /** IANA, the time zone of the alerts' start times. */
    val timeZone: String,
)

/**
 * The `requestHash` of a Play Integrity token for a request: the unpadded base64url SHA-256 of its
 * method, its path and its raw body, as the server computes it (`requestHash` in server/src/playIntegrity.ts).
 */
fun requestHash(method: String, path: String, body: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256")
    digest.update("$method $path\n".encodeToByteArray())
    digest.update(body)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(digest.digest())
}

/** Failures of the server. The screens then go without what it adds. */
sealed class ServerException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Http(val status: Int) : ServerException("HTTP $status")

    class Decoding(val route: String, cause: Throwable) : ServerException("Unreadable $route", cause)
}
