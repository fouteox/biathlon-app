package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.time.Instant

/** One of BiathlonKit's fixtures, which the iOS app and the server read too. */
fun fixture(name: String): String =
    checkNotNull(Thread.currentThread().contextClassLoader.getResource("$name.json")) { "No fixture $name" }
        .readText()

internal inline fun <reified T> decode(json: String): T = IbuJson.decodeFromString(json)

fun instant(iso: String): Instant = Instant.parse(iso)

/**
 * An [IbuClient] answering from canned JSON, keyed by `Path?query` with the query parameters
 * sorted as the client sends them (`Events?Level=1&SeasonId=2627`).
 */
fun stubClient(routes: Map<String, String>, status: HttpStatusCode = HttpStatusCode.OK): IbuClient =
    IbuClient(
        httpClient = HttpClient(
            MockEngine { request ->
                val key = routeKey(request.url)
                respond(routes[key] ?: error("Unknown route $key"), status)
            },
        ),
    )

/** `Path?query`, as [stubClient] routes are keyed. */
fun routeKey(url: Url): String = url.segments.last() + "?" + url.encodedQuery

/** A minimal `Competitions` row. */
fun race(
    id: String,
    start: String,
    category: String = "SM",
    status: Int = 1,
    scheduleStatus: String = "SCHEDULED",
    isLive: Boolean = false,
): String =
    """{"RaceId":"$id","catId":"$category","ShortDescription":"$id","StartTime":"$start",""" +
        """"StatusId":$status,"ScheduleStatus":"$scheduleStatus","IsLive":$isLive}"""

/** A minimal `Events` row. */
fun event(id: String, start: String, end: String): String =
    """{"EventId":"$id","ShortDescription":"$id","StartDate":"$start","EndDate":"$end","Nat":"FIN"}"""
