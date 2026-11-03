package com.fouteox.biathlon.kit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Locale

class SeasonIdTest {
    private val now = instant("2026-10-19T12:00:00Z")

    /** The season rolls over on July 1, in UTC like the server. */
    @Test
    fun containing() {
        assertEquals("2627", SeasonId.containing(instant("2026-10-19T12:00:00Z")).rawValue)
        assertEquals("2627", SeasonId.containing(instant("2027-03-01T12:00:00Z")).rawValue)
        assertEquals("2526", SeasonId.containing(instant("2026-06-30T23:59:00Z")).rawValue)
    }

    @Test
    fun since() {
        assertEquals(listOf("2627", "2526", "2425"), SeasonId.since(SeasonId("2425"), now).map { it.rawValue })
        // The oldest seasons biathlonresults.com lists: `Seasons` goes back to 1957-58.
        assertEquals("1957-58", SeasonId.since(SeasonId.FIRST_WITH_RACES, now).last().displayName)
        assertEquals(50, SeasonId.since(SeasonId.FIRST_WORLD_CUP, now).size)
    }

    @Test
    fun previousAndDisplayName() {
        assertEquals("2526", SeasonId("2627").previous.rawValue)
        assertEquals("2026-27", SeasonId("2627").displayName)
        assertTrue(SeasonId("9899") < SeasonId("0001"))
        assertEquals("9900", SeasonId("0001").previous.rawValue)
        assertEquals("1998-99", SeasonId("9899").displayName)
    }

    /** An ID, not a text: its digits stay ASCII whatever the device's language. */
    @Test
    fun asciiDigitsInEveryLocale() {
        val locale = Locale.getDefault()
        Locale.setDefault(Locale.forLanguageTag("ar-EG"))
        try {
            assertEquals("2627", SeasonId.containing(now).rawValue)
        } finally {
            Locale.setDefault(locale)
        }
    }
}
