package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import java.net.URI
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/**
 * A client answering as the Query Service would, without the network: each athlete of [articles]
 * with their articles by language, every other one with none, as the fictional World Cup's.
 */
fun WikidataClient.Companion.sample(articles: Map<String, Map<String, URI>> = emptyMap()): WikidataClient =
    WikidataClient(
        "Biathlon/test",
        HttpClient(
            MockEngine { request ->
                val ibuId = Regex("""wdt:P2459 "([^"]*)"""").find(request.url.parameters["query"].orEmpty())?.groupValues?.get(1)
                respond(sparqlResults(articles[ibuId].orEmpty()).toString())
            },
        ),
    )

private fun sparqlResults(articles: Map<String, URI>) = buildJsonObject {
    putJsonObject("head") { putJsonArray("vars") { add("article"); add("language") } }
    putJsonObject("results") {
        putJsonArray("bindings") {
            for ((language, url) in articles) {
                addJsonObject {
                    putJsonObject("article") { put("type", "uri"); put("value", url.toString()) }
                    putJsonObject("language") { put("type", "literal"); put("value", language) }
                }
            }
        }
    }
}
