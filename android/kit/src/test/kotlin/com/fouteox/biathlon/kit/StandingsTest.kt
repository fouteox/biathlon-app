package com.fouteox.biathlon.kit

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class StandingsTest {
    private val empty = """{"CupId":"X","Rows":[]}"""
    private val one =
        """{"CupId":"X","AsOf":"after 1 of 26 races","Rows":[{"Rank":"1","IBUId":"A","Name":"A","Nat":"FRA","Score":"90"}]}"""

    @Test
    fun currentSeasonWhenItHasRows() = runTest {
        val client = stubClient(mapOf("CupResults?CupId=BT2627SWRLCP__SWSP" to one))
        val standings = client.worldCupStandings(RaceCategory.WOMEN, StandingsDiscipline.SPRINT, instant("2026-12-10T12:00:00Z"))
        assertEquals("2627", standings.season.rawValue)
        assertFalse(standings.isFallback)
        assertEquals(1, standings.standings.rows.size)
    }

    @Test
    fun previousSeasonBeforeTheFirstRace() = runTest {
        val client = stubClient(
            mapOf("CupResults?CupId=BT2627SWRLCP__SMTS" to empty, "CupResults?CupId=BT2526SWRLCP__SMTS" to one),
        )
        val standings = client.worldCupStandings(RaceCategory.MEN, StandingsDiscipline.TOTAL, instant("2026-10-19T12:00:00Z"))
        assertEquals("2526", standings.season.rawValue)
        assertEquals("2627", standings.requestedSeason.rawValue)
        assertTrue(standings.isFallback)
    }

    /** A season picked on the standings screen shows as it is, even before its first race. */
    @Test
    fun pickedSeasonWithoutFallback() = runTest {
        val client = stubClient(mapOf("CupResults?CupId=BT2627SWRLCP__SMTS" to empty))
        val standings = client.worldCupStandings(RaceCategory.MEN, StandingsDiscipline.TOTAL, SeasonId("2627"))
        assertEquals("2627", standings.season.rawValue)
        assertFalse(standings.isFallback)
        assertTrue(standings.standings.rows.isEmpty())
    }

    @Test
    fun pickedPastSeason() = runTest {
        val client = stubClient(mapOf("CupResults?CupId=BT2425SWRLCP__SWPU" to one))
        val standings = client.worldCupStandings(RaceCategory.WOMEN, StandingsDiscipline.PURSUIT, SeasonId("2425"))
        assertEquals("2425", standings.season.rawValue)
        assertEquals(1, standings.standings.rows.size)
    }
}
