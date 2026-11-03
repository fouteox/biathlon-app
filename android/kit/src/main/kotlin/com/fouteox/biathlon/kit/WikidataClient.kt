package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.Url
import io.ktor.http.isSuccess
import java.net.URI
import java.net.URISyntaxException
import java.util.Locale
import kotlinx.serialization.Serializable

/**
 * Client for the Wikidata Query Service, which finds an athlete's Wikipedia articles from their
 * IBU ID: Wikidata's property P2459, "IBU biathlete ID". Wikidata's data is CC0.
 *
 * Wikimedia asks every client for a User-Agent naming it, with a way to reach its developer
 * (https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy). Each
 * device sends its own requests: the Query Service limits each User-Agent and IP
 * (https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual#Query_limits).
 */
class WikidataClient(
    private val userAgent: String,
    private val httpClient: HttpClient = HttpClient(OkHttp),
) {
    suspend fun wikipediaArticles(ibuId: String): WikipediaArticles {
        val response = httpClient.get(ENDPOINT) {
            parameter("query", articlesQuery(ibuId))
            header(HttpHeaders.UserAgent, userAgent)
            header(HttpHeaders.Accept, "application/sparql-results+json")
        }
        if (!response.status.isSuccess()) throw WikidataException.Http(response.status.value)
        val results = try {
            IbuJson.decodeFromString<SparqlResults>(response.bodyAsText())
        } catch (error: IllegalArgumentException) {
            throw WikidataException.Decoding(error)
        }
        return WikipediaArticles(
            results.results.bindings
                .mapNotNull { binding -> binding.article.value.toUri()?.let { binding.language.value to it } }
                .distinctBy { it.first }
                .toMap(),
        )
    }

    /** A SPARQL result, as https://www.w3.org/TR/sparql11-results-json/ lays it out. */
    @Serializable
    private data class SparqlResults(val results: Bindings) {
        @Serializable
        data class Bindings(val bindings: List<Binding>)

        @Serializable
        data class Binding(val article: Value, val language: Value)

        @Serializable
        data class Value(val value: String)
    }

    companion object {
        val ENDPOINT = Url("https://query.wikidata.org/sparql")

        /** The athlete's articles in every Wikipedia, with each Wikipedia's language code. */
        internal fun articlesQuery(ibuId: String): String {
            // A SPARQL string escapes its backslashes and quotes.
            val literal = ibuId.replace("\\", "\\\\").replace("\"", "\\\"")
            return "SELECT ?article ?language WHERE { " +
                "?athlete wdt:P2459 \"$literal\" . " +
                "?article schema:about ?athlete ; schema:inLanguage ?language ; " +
                "schema:isPartOf/wikibase:wikiGroup \"wikipedia\" . }"
        }
    }
}

private fun String.toUri(): URI? = try {
    URI(this)
} catch (_: URISyntaxException) {
    null
}

/** An athlete's Wikipedia articles, each by its Wikipedia's language code (`fr`, `de`, `nb`…). */
data class WikipediaArticles(val urls: Map<String, URI>) {
    /** The article in the first of `languages` (the reader's, in order) that has one, else in English. */
    fun article(languages: List<Locale>): URI? =
        // The language tag, unlike `Locale.getLanguage()`, gives current codes: `he`, not `iw`.
        (languages.map { it.toLanguageTag().substringBefore('-') } + "en").firstNotNullOfOrNull(urls::get)
}

/** Failures of the Wikidata Query Service. The athlete's screen then goes without the link. */
sealed class WikidataException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Http(val status: Int) : WikidataException("HTTP $status")

    class Decoding(cause: Throwable) : WikidataException("Unreadable SPARQL results", cause)
}
