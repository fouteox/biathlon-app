package com.fouteox.biathlon.kit

import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource

class NationTest {
    @ParameterizedTest
    @CsvSource("FRA, 🇫🇷", "GER, 🇩🇪", "SUI, 🇨🇭", "SLO, 🇸🇮", "nor, 🇳🇴", "AND, 🇦🇩", "KOS, 🇽🇰")
    fun iocCodesBecomeFlags(code: String, flag: String) {
        assertEquals(flag, Nation.flag(code))
    }

    /** Greenland races in the World Cup (women's sprint, Le Grand-Bornand 2025) under an IBU code that isn't an IOC one. */
    @Test
    fun greenlandHasItsFlag() {
        assertEquals("🇬🇱", Nation.flag("GRL"))
    }

    /** `AIN`, Individual Neutral Athletes, has no flag. */
    @Test
    fun unknownCodeHasNoFlag() {
        assertNull(Nation.flag("AIN"))
        assertNull(Nation.flag("XXX"))
        assertNull(Nation.flag(null))
    }

    @Test
    fun titlesStartWithTheFlagWhenKnown() {
        assertEquals("🇦🇹 Hochfilzen", Nation.titled("Hochfilzen", nation = "AUT"))
        assertEquals("Hochfilzen", Nation.titled("Hochfilzen", nation = "XXX"))
        assertEquals("Hochfilzen", Nation.titled("Hochfilzen", nation = null))
    }

    /** The TV guide names countries by ISO code. */
    @ParameterizedTest
    @CsvSource("FR, 🇫🇷", "GB, 🇬🇧", "de, 🇩🇪")
    fun isoCodesBecomeFlags(code: String, flag: String) {
        assertEquals(flag, Nation.regionFlag(code))
    }

    @ParameterizedTest
    @ValueSource(strings = ["", "F", "FRA", "F1"])
    fun malformedIsoCodeHasNoFlag(code: String) {
        assertNull(Nation.regionFlag(code))
        assertEquals("Nowhere", Nation.titledByRegion("Nowhere", code))
    }

    @Test
    fun countryNamesStartWithTheirFlag() {
        assertEquals("🇩🇪 Allemagne", Nation.titledByRegion("Allemagne", "DE"))
    }

    /** The IBU names nations in English ("Great Britain") or by code: the app names them in the reader's language. */
    @ParameterizedTest
    @CsvSource(
        "FRA, fr-FR, France", "GER, fr-FR, Allemagne", "SUI, de-DE, Schweiz",
        "NED, en-US, Netherlands", "GRL, fr-FR, Groenland", "nor, en-US, Norway",
    )
    fun iocCodesHaveLocalizedNames(code: String, locale: String, name: String) {
        assertEquals(name, Nation.localizedName(code, Locale.forLanguageTag(locale)))
    }

    @Test
    fun unknownCodeNamesItself() {
        assertEquals("AIN", Nation.localizedName("AIN", Locale.FRANCE))
    }

    @Test
    fun nameTitlesStartWithTheFlag() {
        assertEquals("🇫🇷 France", Nation.namedTitle("FRA", Locale.FRANCE))
        assertEquals("AIN", Nation.namedTitle("AIN", Locale.FRANCE))
    }
}
