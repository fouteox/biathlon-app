package com.fouteox.biathlon

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The store listings that play/publish.sh sends to Google Play, one per language of the app,
 * within Google Play's limits (https://support.google.com/googleplay/android-developer/answer/9859152).
 */
class PlayListingTest {
    /** Tests run in the app's module folder. */
    private val listings = File("../play/listings")

    @Test
    fun listsTheAppInEachOfItsLanguages() {
        assertEquals(setOf("de-DE", "en-US", "fr-FR"), listings.list()?.toSet())
    }

    @Test
    fun staysWithinGooglePlaysLimits() {
        for (language in checkNotNull(listings.listFiles())) {
            for ((file, limit) in LIMITS) {
                val text = File(language, file).readText().removeSuffix("\n")
                val length = text.codePointCount(0, text.length)
                assertTrue("${language.name}/$file: $length characters", length in 1..limit)
            }
        }
    }

    private companion object {
        val LIMITS = mapOf("title.txt" to 30, "short-description.txt" to 80, "full-description.txt" to 4_000)
    }
}
