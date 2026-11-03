package com.fouteox.biathlon.kit

import com.fouteox.biathlon.kit.RaceAnalysis.Measure.COURSE
import com.fouteox.biathlon.kit.RaceAnalysis.Measure.RANGE
import com.fouteox.biathlon.kit.RaceAnalysis.Measure.SHOOTING
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class RaceAnalysisTest {
    /** A race with `shootings` shootings, whose analysis the IBU publishes or not. */
    private fun race(shootings: Int, hasAnalysis: Boolean = true, legs: Int = 0) = decode<Competition>(
        """{"RaceId":"BT2526SWRLCP01SMSP","ShortDescription":"Men 10 km Sprint","StartTime":"2025-12-06T15:30:00Z",""" +
            """"StatusId":11,"HasAnalysis":$hasAnalysis,"NrShootings":$shootings,"NrLegs":$legs}""",
    )

    @Test
    fun eachRankingHasItsType() {
        assertEquals("CRST", RaceAnalysis(COURSE).typeId)
        assertEquals("CRS3", RaceAnalysis(COURSE, 3).typeId)
        assertEquals("RNGT", RaceAnalysis(RANGE).typeId)
        assertEquals("RNG2", RaceAnalysis(RANGE, 2).typeId)
        assertEquals("STTM", RaceAnalysis(SHOOTING).typeId)
        assertEquals("S4TM", RaceAnalysis(SHOOTING, 4).typeId)
    }

    /** A lap before each shooting and after the last. */
    @Test
    fun lapsSurroundTheShootings() {
        val sprint = race(shootings = 2)
        assertEquals(listOf(1, 2, 3), sprint.segments(COURSE))
        assertEquals(listOf(1, 2), sprint.segments(RANGE))
        assertEquals(listOf(1, 2), sprint.segments(SHOOTING))
    }

    @Test
    fun everyRankingOfARace() {
        assertEquals(
            listOf(
                RaceAnalysis(COURSE), RaceAnalysis(COURSE, 1), RaceAnalysis(COURSE, 2),
                RaceAnalysis(RANGE), RaceAnalysis(RANGE, 1),
                RaceAnalysis(SHOOTING), RaceAnalysis(SHOOTING, 1),
            ),
            RaceAnalysis.all(shootings = 1),
        )
    }

    /** The same lap or shooting, if the other measure has it, else the whole race. */
    @Test
    fun anotherMeasureKeepsTheSegmentItHas() {
        val sprint = race(shootings = 2)
        assertEquals(RaceAnalysis(RANGE, 2), RaceAnalysis(COURSE, 2).measuring(RANGE, sprint))
        assertEquals(RaceAnalysis(SHOOTING), RaceAnalysis(COURSE, 3).measuring(SHOOTING, sprint))
        assertEquals(RaceAnalysis(COURSE), RaceAnalysis(RANGE).measuring(COURSE, sprint))
    }

    /** Relays rank their legs apart from their teams, which the app doesn't show yet. */
    @Test
    fun onlyIndividualRacesWithAnAnalysisHaveRankings() {
        assertTrue(race(shootings = 4).hasAnalysisRankings)
        assertFalse(race(shootings = 4, hasAnalysis = false).hasAnalysisRankings)
        assertFalse(race(shootings = 2, legs = 4).hasAnalysisRankings)
    }

    @Test
    fun fetchesARanking() = runTest {
        val client = stubClient(
            mapOf(
                "AnalyticResults?RaceId=BT2526SWRLCP01SMSP&TypeId=RNG2" to
                    """{"RaceId":"BT2526SWRLCP01SMSP","IsStartList":false,"IsResult":true,"Results":[""" +
                    """{"IBUId":"BTITA1","Name":"GIACOMEL Tommaso","Nat":"ITA","Rank":"1","Shootings":"1+0",""" +
                    """"TotalTime":"39.0","Behind":"0.0"}]}""",
            ),
        )

        val ranking = client.analysis(RaceAnalysis(RANGE, 2), "BT2526SWRLCP01SMSP")

        assertTrue(ranking.isResult)
        assertEquals(listOf("39.0"), ranking.rows.map { it.totalTime })
    }
}
