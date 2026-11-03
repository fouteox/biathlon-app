package com.fouteox.biathlon.kit

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FavoriteStandingsTest {
    private fun rows(rows: String) = """{"Rows":[$rows]}"""

    private val client = stubClient(
        mapOf(
            "CupResults?CupId=BT2627SWRLCP__SMTS" to rows("""{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"300"}"""),
            "CupResults?CupId=BT2627SWRLCP__SWTS" to rows("""{"Rank":"4","IBUId":"BTNOR2","Name":"B","Nat":"NOR","Score":"150"}"""),
            "CupResults?CupId=BT2627SWRLCP__SMNC" to rows("""{"Rank":"2","IBUId":"FRA","Name":"France","Nat":"FRA"}"""),
            "CupResults?CupId=BT2627SWRLCP__SWNC" to
                rows("""{"Rank":"1","Name":"Norway","Nat":"NOR"},{"Rank":"3","Name":"France","Nat":"FRA"}"""),
        ),
    )

    @Test
    fun findsAnAthleteInEitherCategory() = runTest {
        val standings = client.favoriteStandings(instant("2026-12-10T12:00:00Z"))
        assertEquals("2627", standings.season.rawValue)
        assertFalse(standings.isFallback)
        assertEquals("1", standings.standingOfAthlete("BTFRA1")?.rank)
        assertEquals("150", standings.standingOfAthlete("BTNOR2")?.score)
        assertNull(standings.standingOfAthlete("BTGER1"))
    }

    /** A nation by its code, which the Nations Cup rows carry as `Nat` or as `IBUId`, men's first. */
    @Test
    fun listsANationsRanksMenFirst() = runTest {
        val standings = client.favoriteStandings(instant("2026-12-10T12:00:00Z"))
        assertEquals(
            listOf("SM 2", "SW 3"),
            standings.standingsOfNation("FRA").map { (category, row) -> "${category.code} ${row.rank.orEmpty()}" },
        )
        assertEquals(listOf(RaceCategory.WOMEN), standings.standingsOfNation("NOR").map { it.first })
        assertTrue(standings.standingsOfNation("GER").isEmpty())
    }

    /**
     * Until every one of the four standings has rows, all four come from the previous season:
     * around the opening races, a women's standing without rows yet must not show next to the
     * men's new one.
     */
    @Test
    fun previousSeasonForAllFourWhileAnyIsEmpty() = runTest {
        val routes = mapOf(
            "CupResults?CupId=BT2627SWRLCP__SMTS" to rows("""{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"60"}"""),
            "CupResults?CupId=BT2627SWRLCP__SWTS" to rows(""),
            "CupResults?CupId=BT2627SWRLCP__SMNC" to rows("""{"Rank":"1","Name":"France","Nat":"FRA"}"""),
            "CupResults?CupId=BT2627SWRLCP__SWNC" to rows(""),
            "CupResults?CupId=BT2526SWRLCP__SMTS" to rows("""{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"1000"}"""),
            "CupResults?CupId=BT2526SWRLCP__SWTS" to rows("""{"Rank":"1","IBUId":"BTNOR2","Name":"B","Nat":"NOR","Score":"900"}"""),
            "CupResults?CupId=BT2526SWRLCP__SMNC" to rows("""{"Rank":"1","Name":"France","Nat":"FRA"}"""),
            "CupResults?CupId=BT2526SWRLCP__SWNC" to rows("""{"Rank":"1","Name":"Norway","Nat":"NOR"}"""),
        )
        val standings = stubClient(routes).favoriteStandings(instant("2026-11-28T12:00:00Z"))
        assertEquals("2526", standings.season.rawValue)
        assertEquals("2627", standings.requestedSeason.rawValue)
        assertTrue(standings.isFallback)
        assertEquals("1000", standings.standingOfAthlete("BTFRA1")?.score)
    }
}
