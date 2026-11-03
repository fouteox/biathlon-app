package com.fouteox.biathlon.kit

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FavoriteSetTest {
    private val favorites = FavoriteSet(athleteIds = setOf("BTFRA1"), nations = setOf("NOR"))

    @Test
    fun matchesAthletesAndNations() {
        assertTrue(favorites.contains(decode<ResultRow>("""{"IBUId":"BTFRA1","Name":"A","Nat":"FRA"}""")))
        assertFalse(favorites.contains(decode<ResultRow>("""{"IBUId":"BTFRA2","Name":"B","Nat":"FRA"}""")))
        assertTrue(favorites.contains(decode<ResultRow>("""{"IsTeam":true,"Name":"NORWAY","Nat":"NOR","TeamId":"NOR1"}""")))
    }

    @Test
    fun aNationKeyNeverMatchesAnAthleteId() {
        assertFalse(favorites.contains(decode<ResultRow>("""{"IBUId":"NOR","Name":"Odd","Nat":"SWE"}""")))
    }

    /**
     * The World Cup standings: an athlete by ID or through a favorite nation, a nation by its
     * code, which the nations standings carry as `Nat` or, failing that, as the row's name.
     */
    @Test
    fun picksTheFavoritesOutOfTheStandings() {
        val standings = decode<CupStandings>(
            """{"Rows":[{"Rank":"1","IBUId":"BTSWE1","Name":"A","Nat":"SWE"},{"Rank":"2","IBUId":"BTFRA1","Name":"B","Nat":"FRA"},""" +
                """{"Rank":"3","IBUId":"BTNOR2","Name":"C","Nat":"NOR"},{"Rank":"4","IBUId":"BTGER1","Name":"D","Nat":"GER"}]}""",
        )
        assertEquals(listOf("B", "C"), standings.favorites(favorites).map { it.name })

        val nations = decode<CupStandings>(
            """{"Rows":[{"Rank":"1","Name":"Norway","Nat":"NOR"},{"Rank":"2","Name":"NOR"},{"Rank":"3","Name":"France","Nat":"FRA"}]}""",
        )
        assertEquals(listOf("1", "2"), nations.favorites(favorites).map { it.rank })
    }

    @Test
    fun isEmptyWithoutAthletesOrNations() {
        assertTrue(FavoriteSet(emptySet(), emptySet()).isEmpty)
        assertFalse(FavoriteSet(emptySet(), setOf("NOR")).isEmpty)
        assertFalse(FavoriteSet(setOf("BTFRA1"), emptySet()).isEmpty)
    }

    @Test
    fun aRelayTeamIsAFavoriteThroughItsLegs() {
        val results = decode<RaceResults>(
            """{"IsResult":true,"Results":[{"IsTeam":true,"Name":"FRANCE","Nat":"FRA","TeamId":"FRA1"},""" +
                """{"IBUId":"BTFRA1","Name":"A","Nat":"FRA","TeamId":"FRA1","Leg":1},""" +
                """{"IsTeam":true,"Name":"SWEDEN","Nat":"SWE","TeamId":"SWE1"},""" +
                """{"IBUId":"BTSWE1","Name":"C","Nat":"SWE","TeamId":"SWE1","Leg":1},""" +
                """{"IsTeam":true,"Name":"NORWAY","Nat":"NOR","TeamId":"NOR1"}]}""",
        )
        assertEquals(listOf("FRANCE", "NORWAY"), results.featuredStandings(top = 0, favorites).map { it.name })
    }

    @Test
    fun anIndividualRaceKeepsItsFavoriteRows() {
        val results = decode<RaceResults>(
            """{"IsResult":true,"Results":[{"IBUId":"BTFRA1","Name":"A","Nat":"FRA"},{"IBUId":"BTFRA2","Name":"B","Nat":"FRA"}]}""",
        )
        assertEquals(listOf("A"), results.featuredStandings(top = 0, favorites).map { it.name })
    }

    /** The top rows, then the favorites ranked below them, each row once. */
    @Test
    fun featuresTheTopThenTheFavoritesBelowIt() {
        val results = decode<RaceResults>(
            """{"IsResult":true,"Results":[{"IBUId":"BTSWE1","Name":"A","Nat":"SWE"},{"IBUId":"BTFRA1","Name":"B","Nat":"FRA"},""" +
                """{"IBUId":"BTGER1","Name":"C","Nat":"GER"},{"IBUId":"BTITA1","Name":"D","Nat":"ITA"},""" +
                """{"IBUId":"BTNOR1","Name":"E","Nat":"NOR"}]}""",
        )
        assertEquals(listOf("A", "B", "C", "E"), results.featuredStandings(top = 3, favorites).map { it.name })
    }
}
