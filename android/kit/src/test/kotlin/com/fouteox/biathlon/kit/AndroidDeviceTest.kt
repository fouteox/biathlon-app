package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.content.OutgoingContent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** `PUT` and `DELETE /v1/android-devices/:fid`, as `server/test/android.test.ts` checks them. */
class AndroidDeviceTest {
    private val requests = mutableListOf<HttpRequestData>()
    private val hashes = mutableListOf<String>()

    private fun server(status: HttpStatusCode = HttpStatusCode.NoContent) = ServerClient(
        Url("https://server.example/"),
        HttpClient(
            MockEngine { request ->
                requests += request
                respond("", status)
            },
        ),
    )

    private val token: suspend (String) -> String = { hash ->
        hashes += hash
        "integrity-token"
    }

    private val HttpRequestData.text: String
        get() = when (val body = body) {
            is OutgoingContent.ByteArrayContent -> body.bytes().decodeToString()
            else -> ""
        }

    @Test
    fun hashesTheMethodThePathAndTheBodyAsTheServerDoes() {
        // The server's own test vector.
        assertEquals("rQr28Hi93CLw0gY8VSoeZ8IV6j31uhi2UanhldbJwSY", requestHash("PUT", "/v1/android-devices/x", "{}".encodeToByteArray()))
    }

    @Test
    fun registersWithATokenBoundToTheRequest() = runTest {
        val registration = AndroidDeviceRegistration(listOf("SW"), cancellation = true, rescheduling = true, "de-DE", "Europe/Berlin")
        server().registerAndroidDevice("fid-1", registration, token)

        val request = requests.single()
        assertEquals(HttpMethod.Put, request.method)
        assertEquals("https://server.example/v1/android-devices/fid-1", request.url.toString())
        assertEquals("integrity-token", request.headers["X-Play-Integrity-Token"])
        assertEquals(
            """{"categories":["SW"],"cancellation":true,"rescheduling":true,"locale":"de-DE","timeZone":"Europe/Berlin"}""",
            request.text,
        )
        assertEquals("application/json", request.body.contentType.toString())
        assertEquals(listOf(requestHash("PUT", "/v1/android-devices/fid-1", request.text.encodeToByteArray())), hashes)
    }

    @Test
    fun unregistersWithoutABody() = runTest {
        server().registerAndroidDevice("fid-1", null, token)

        val request = requests.single()
        assertEquals(HttpMethod.Delete, request.method)
        assertEquals("", request.text)
        assertEquals(listOf(requestHash("DELETE", "/v1/android-devices/fid-1", ByteArray(0))), hashes)
    }

    @Test
    fun reportsTheServersRefusal() = runTest {
        val error = assertThrows<ServerException.Http> {
            server(HttpStatusCode.Unauthorized).registerAndroidDevice("fid-1", null, token)
        }
        assertEquals(401, error.status)
    }
}
