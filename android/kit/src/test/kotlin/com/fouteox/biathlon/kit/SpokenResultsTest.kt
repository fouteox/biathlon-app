package com.fouteox.biathlon.kit

import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** What a share or a voice says of a race's results, as the iOS app's `SpokenResultsTests`. */
class SpokenResultsTest {
    private fun row(name: String, family: String? = null, given: String? = null, nation: String = "NOR", isTeam: Boolean = false) =
        ResultRow(name = name, familyName = family, givenName = given, nation = nation, isTeam = isTeam)

    @Test
    fun athletesGivenNameFirstWithoutCapitals() {
        val row = row("FILLON MAILLET Quentin", family = "FILLON MAILLET", given = "Quentin", nation = "FRA")
        assertEquals("Quentin Fillon Maillet", row.spokenName(Locale.FRANCE))
    }

    @Test
    fun eachPartOfAHyphenatedNameKeepsItsCapital() {
        assertEquals("Johan-Olav Smoerdal Botn", row("x", family = "SMOERDAL BOTN", given = "Johan-Olav").spokenName(Locale.ENGLISH))
        assertEquals("Anna Weidel-Preuss", row("x", family = "WEIDEL-PREUSS", given = "Anna").spokenName(Locale.GERMAN))
    }

    @Test
    fun teamsByTheirNation() {
        assertEquals("Norwegen", row("NORWAY", family = "NORWAY", given = "", isTeam = true).spokenName(Locale.GERMANY))
    }

    @Test
    fun theFullNameWithoutItsParts() {
        assertEquals("BOTN Johan-Olav", row("BOTN Johan-Olav").spokenName())
    }
}
