package com.fouteox.biathlon.kit

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AthleteHistoryTest {
    /** A minimal `AllResults` row, whose `Season` reads "25/26". */
    private fun result(raceId: String, season: String, level: String = "WC") =
        """{"RaceId":"$raceId","SeasonId":null,"Season":"$season","Level":"$level","Place":"Oslo","Rank":"2."}"""

    private fun history(rows: List<String>, now: String) =
        AthleteHistory(decode(rows.joinToString(",", "[", "]")), instant(now))

    @Test
    fun resultsKnowTheirSeason() {
        assertEquals(SeasonId("2526"), decode<AthleteResult>(result("BT2526SWRLCP09SWSP", "25/26")).seasonId)
        assertNull(decode<AthleteResult>("""{"RaceId":"BT2526SWRLCP09SWSP","Season":null}""").seasonId)
    }

    /** The seasons with World Cup circuit results, newest first, and the current one even without results. */
    @Test
    fun seasonsStartWithTheCurrentOne() {
        val history = history(
            listOf(
                result("BT2425SWRLCP01SWSP", "24/25"),
                result("SB2627SIBUL1MUSWSF", "26/27", level = "SBSIBUL1"),
                result("BT2526SWRLOG__SWIN", "25/26", level = "OWG"),
                result("BT2526SWRLCP09SWSP", "25/26"),
            ),
            now = "2026-10-26T12:00:00Z",
        )
        assertEquals(listOf("2627", "2526", "2425"), history.seasons.map { it.rawValue })
        assertEquals(
            listOf("BT2425SWRLCP01SWSP", "BT2526SWRLOG__SWIN", "BT2526SWRLCP09SWSP"),
            history.results.map { it.raceId },
        )
        assertEquals(
            listOf("BT2526SWRLOG__SWIN", "BT2526SWRLCP09SWSP"),
            history.results(SeasonId("2526")).map { it.raceId },
        )
        assertTrue(history.results(SeasonId("2627")).isEmpty())
    }

    /** Before the athlete's first race of the season, the profile opens on their last season, as the standings do. */
    @Test
    fun opensOnTheLastSeasonWithResults() {
        assertEquals("2526", history(listOf(result("BT2526SWRLCP09SWSP", "25/26")), "2026-10-26T12:00:00Z").initialSeason.rawValue)
        val inSeason = history(
            listOf(result("BT2627SWRLCP01SWSP", "26/27"), result("BT2526SWRLCP09SWSP", "25/26")),
            "2026-12-01T12:00:00Z",
        )
        assertEquals("2627", inSeason.initialSeason.rawValue)
        val newcomer = history(emptyList(), "2026-10-26T12:00:00Z")
        assertEquals(listOf("2627"), newcomer.seasons.map { it.rawValue })
        assertEquals("2627", newcomer.initialSeason.rawValue)
    }

    /** The athlete's row in the overall standings of their category and of the season. */
    @Test
    fun worldCupStandingOfAnAthlete() = runTest {
        val client = stubClient(
            mapOf(
                "CupResults?CupId=BT2526SWRLCP__SWTS" to
                    """{"Rows":[{"Rank":"1","IBUId":"BTFRA1","Name":"A","Nat":"FRA","Score":"1000"},""" +
                    """{"Rank":"6","IBUId":"BTFRA20910199601","Name":"SIMON Julia","Nat":"FRA","Score":"827"}]}""",
            ),
        )
        val season = SeasonId("2526")
        val standing = client.worldCupStanding("BTFRA20910199601", RaceCategory.WOMEN, season)
        assertEquals("6", standing?.rank)
        assertEquals("827", standing?.score)
        assertNull(client.worldCupStanding("BTFRA9", RaceCategory.WOMEN, season))
    }
}
