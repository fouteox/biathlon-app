package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import java.net.URI
import java.util.Locale
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/**
 * `wikipedia-articles.json` is the Query Service's answer for Julia Simon on 2026-10-28, down to
 * four of her 27 articles, as the iOS app's tests read it.
 */
class WikidataClientTest {
    private val userAgent = "Biathlon/1.0 (https://github.com/fouteox/biathlon-app)"

    /** A client answering `body` with `status`, which hands each request it gets to `inspect`. */
    private fun client(
        status: HttpStatusCode = HttpStatusCode.OK,
        body: String = fixture("wikipedia-articles"),
        inspect: MockRequestHandleScope.(HttpRequestData) -> Unit = {},
    ) = WikidataClient(
        userAgent,
        HttpClient(
            MockEngine { request ->
                inspect(request)
                respond(body, status)
            },
        ),
    )

    /** Wikimedia asks for a User-Agent naming the app; the athlete is found by their IBU ID, property P2459. */
    @Test
    fun asksTheQueryServiceForTheAthletesArticles() = runTest {
        val client = client { request ->
            assertEquals("https://query.wikidata.org/sparql", request.url.toString().substringBefore('?'))
            assertTrue(request.url.parameters["query"].orEmpty().contains("""wdt:P2459 "BTFRA20910199601""""))
            assertEquals(userAgent, request.headers[HttpHeaders.UserAgent])
            assertEquals("application/sparql-results+json", request.headers[HttpHeaders.Accept])
        }
        assertEquals(4, client.wikipediaArticles("BTFRA20910199601").urls.size)
    }

    /** The ID stays a single string in the query, whatever it holds. */
    @Test
    fun escapesTheIdInTheQuery() {
        assertTrue(WikidataClient.articlesQuery("""A" } \ B""").contains("""wdt:P2459 "A\" } \\ B" ."""))
    }

    /** The URLs keep their percent-encoding as Wikipedia gives it. */
    @Test
    fun decodesEachArticleByLanguage() = runTest {
        val articles = client().wikipediaArticles("BTFRA20910199601")
        assertEquals(URI("https://fr.wikipedia.org/wiki/Julia_Simon"), articles.urls["fr"])
        assertEquals(URI("https://en.wikipedia.org/wiki/Julia_Simon_(biathlete)"), articles.urls["en"])
        assertEquals(URI("https://no.wikipedia.org/wiki/Julia_Simon"), articles.urls["nb"])
    }

    /** An athlete Wikidata doesn't know, or without an article, has none. */
    @Test
    fun anUnknownAthleteHasNoArticle() = runTest {
        val body = """{"head":{"vars":["article","language"]},"results":{"bindings":[]}}"""
        val articles = client(body = body).wikipediaArticles("BTXXX00000000000")
        assertTrue(articles.urls.isEmpty())
        assertNull(articles.article(listOf(Locale.FRANCE)))
    }

    @Test
    fun aFailedLoadCarriesTheStatus() = runTest {
        val error = assertThrows<WikidataException.Http> {
            client(HttpStatusCode.TooManyRequests).wikipediaArticles("BTFRA20910199601")
        }
        assertEquals(429, error.status)
    }

    /** The reader's languages in their order, then English; Norwegian Bokmål's Wikipedia is `nb` too. */
    @ParameterizedTest
    @CsvSource(
        "fr-FR en-GB, https://fr.wikipedia.org/wiki/Julia_Simon",
        "de, https://de.wikipedia.org/wiki/Julia_Simon",
        "nb-NO, https://no.wikipedia.org/wiki/Julia_Simon",
        "ja-JP de-DE, https://de.wikipedia.org/wiki/Julia_Simon",
        "ja-JP, https://en.wikipedia.org/wiki/Julia_Simon_(biathlete)",
    )
    fun picksTheReadersLanguage(languages: String, expected: String) = runTest {
        val articles = client().wikipediaArticles("BTFRA20910199601")
        assertEquals(URI(expected), articles.article(languages.split(" ").map(Locale::forLanguageTag)))
    }

    /** Hebrew's Wikipedia is `he`, which Java's `Locale.getLanguage()` long called `iw`. */
    @Test
    fun namesLanguagesByTheirCurrentCodes() {
        val articles = WikipediaArticles(mapOf("he" to URI("https://he.wikipedia.org/wiki/A")))
        assertEquals(URI("https://he.wikipedia.org/wiki/A"), articles.article(listOf(Locale.forLanguageTag("he-IL"))))
    }

    /** Without an article in their languages or in English, the reader gets none. */
    @Test
    fun noArticleInTheReadersLanguagesNorInEnglish() {
        val articles = WikipediaArticles(mapOf("de" to URI("https://de.wikipedia.org/wiki/A")))
        assertNull(articles.article(listOf(Locale.FRANCE)))
    }
}
