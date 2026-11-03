package com.fouteox.biathlon.kit

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

class AthleteSearchTest {
    private fun person(id: String, family: String, given: String, functions: String = "Athlete") =
        """{"IBUId":"$id","FamilyName":"$family","GivenName":"$given","NAT":"FRA","Functions":"$functions"}"""

    private fun answer(vararg people: String) = """{"RequestId":"","Athletes":[${people.joinToString(",")}]}"""

    private fun query(familyName: String? = null, givenName: String? = null) = AthleteSearch.Query(familyName, givenName)

    @Test
    fun oneWordStartsEitherName() {
        assertEquals(listOf(query(familyName = "quentin"), query(givenName = "quentin")), AthleteSearch.queries("  Quentin "))
    }

    @Test
    fun severalWordsAreEitherNameOrBothNamesSplitAnywhereInEitherOrder() {
        assertEquals(
            listOf(
                query(familyName = "quentin fillon maillet"),
                query(givenName = "quentin fillon maillet"),
                query(familyName = "fillon maillet", givenName = "quentin"),
                query(familyName = "quentin", givenName = "fillon maillet"),
                query(familyName = "maillet", givenName = "quentin fillon"),
                query(familyName = "quentin fillon", givenName = "maillet"),
            ),
            AthleteSearch.queries("Quentin Fillon Maillet"),
        )
    }

    @Test
    fun blankTextSearchesNothing() = runTest {
        assertTrue(AthleteSearch.queries(" \n").isEmpty())
        assertTrue(stubClient(emptyMap()).searchAthletes(" ").isEmpty())
    }

    /** Family names first, each athlete once, without the officials the search also finds. */
    @Test
    fun mergesTheAnswersInOrder() = runTest {
        val client = stubClient(
            mapOf(
                "Athletes?FamilyName=simon" to answer(
                    person("BTFRA20910199601", "SIMON", "Julia"),
                    person("SWE-16-565EV", "SIMONSSON", "Emil", "Official"),
                    person("BTHUN22309197401", "SIMON", "Agnes", "Not active"),
                ),
                "Athletes?GivenName=simon" to answer(
                    person("BTFRA11003199901", "DESTHIEUX", "Simon"),
                    person("BTFRA20910199601", "SIMON", "Julia"),
                ),
            ),
        )

        val found = client.searchAthletes("Simon")

        assertEquals(listOf("BTFRA20910199601", "BTHUN22309197401", "BTFRA11003199901"), found.map { it.id })
        assertEquals("Julia SIMON", found.first().name)
        assertEquals("FRA", found.first().nation)
    }

    /** Active, former and deceased athletes, even when also officials; officials alone left out. */
    @ParameterizedTest
    @CsvSource("Athlete, true", "Not active, true", "Deceased, true", "'Athlete, Official', true", "Official, false")
    fun keepsAthletesOnly(functions: String, isAthlete: Boolean) {
        assertEquals(isAthlete, decode<AthleteMatch>(person("BTNOR11807199801", "BAKKEN", "Sivert Guttorm", functions)).isAthlete)
    }

    @Test
    fun findsAnAthleteByBothNames() = runTest {
        val client = stubClient(
            mapOf(
                "Athletes?FamilyName=julia%20simon" to answer(),
                "Athletes?GivenName=julia%20simon" to answer(),
                "Athletes?FamilyName=simon&GivenName=julia" to answer(person("BTFRA20910199601", "SIMON", "Julia")),
                "Athletes?FamilyName=julia&GivenName=simon" to answer(),
            ),
        )

        assertEquals(listOf("BTFRA20910199601"), client.searchAthletes("Julia Simon").map { it.id })
    }
}
