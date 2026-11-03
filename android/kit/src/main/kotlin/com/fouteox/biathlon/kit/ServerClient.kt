package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.http.URLBuilder
import io.ktor.http.Url
import io.ktor.http.appendPathSegments

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
}

/** Failures of the server. The screens then go without what it adds. */
sealed class ServerException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Http(val status: Int) : ServerException("HTTP $status")

    class Decoding(val route: String, cause: Throwable) : ServerException("Unreadable $route", cause)
}
