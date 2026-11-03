package com.fouteox.biathlon.kit

import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.FieldSource

/** The fictional World Cup the screens' tests run on: each screen finds what it shows, whatever the date. */
class SampleDataTest {
    @ParameterizedTest
    @FieldSource("DATES")
    fun homeFeaturesTheNextRaceOrTheLatestResults(now: Instant) = runTest {
        val feed = IbuClient.sample(now).homeFeed(now)
        assertTrue(feed.next != null || feed.latestFinished != null)
        feed.next?.let { assertTrue(it.startTime > now) }
        feed.latestFinished?.let {
            assertTrue(it.startTime < now)
            assertEquals(true, feed.latestResults?.isResult)
            assertEquals(false, feed.latestResults?.rows?.isEmpty())
        }
    }

    @ParameterizedTest
    @FieldSource("DATES")
    fun everyStandingsTableHasRows(now: Instant) = runTest {
        val client = IbuClient.sample(now)
        for (category in RaceCategory.WITH_STANDINGS) {
            for (discipline in StandingsDiscipline.entries) {
                val rows = client.worldCupStandings(category, discipline, now).standings.rows
                assertFalse(rows.isEmpty())
                assertTrue(rows.all { it.isNation == (discipline == StandingsDiscipline.NATIONS) })
                assertFalse(rows.first().bibColors.isEmpty(), "The leader wears a bib")
            }
        }
    }

    /** A past season, as the standings' season picker and the calendar show it. */
    @ParameterizedTest
    @FieldSource("DATES")
    fun pastSeasonsHaveFinishedEvents(now: Instant) = runTest {
        val client = IbuClient.sample(now)
        val season = SeasonId.containing(now).previous.previous
        assertFalse(client.worldCupStandings(RaceCategory.WOMEN, StandingsDiscipline.SPRINT, season).standings.rows.isEmpty())
        val events = client.events(season)
        assertFalse(events.isEmpty())
        for (event in events) {
            val races = client.competitions(event.id)
            assertFalse(races.isEmpty())
            assertTrue(races.all { it.state == Competition.State.FINISHED && it.kind != null && it.eventId == event.id })
        }
    }

    /** An athlete of the standings opens on a profile, with results in races that are over. */
    @ParameterizedTest
    @FieldSource("DATES")
    fun athletesHaveAProfileAndResults(now: Instant) = runTest {
        val client = IbuClient.sample(now)
        val row = client.worldCupStandings(RaceCategory.WOMEN, StandingsDiscipline.TOTAL, now).standings.rows.first()
        val id = checkNotNull(row.athleteId)

        val bio = client.athlete(id)
        assertFalse(bio.fullName.isEmpty())
        assertEquals(row.nation, bio.nation)
        assertEquals(Gender.WOMAN, bio.gender)
        assertNull(bio.photoUrl, "No photo to download")

        val history = AthleteHistory(client.athleteResults(id), now)
        val results = history.results(history.initialSeason)
        assertFalse(results.isEmpty())
        for (result in results) {
            val race = client.race(checkNotNull(result.raceId))
            assertEquals(Competition.State.FINISHED, race.state)
            assertEquals(RaceCategory.WOMEN, race.category)
        }
        assertNotNull(client.worldCupStanding(id, RaceCategory.WOMEN, history.initialSeason))
    }

    /** A nation's screen lists its athletes from the overall standings. */
    @Test
    fun nationsHaveAthletes() = runTest {
        val now = instant("2027-01-20T12:00:00Z")
        val client = IbuClient.sample(now)
        val nations = client.worldCupStandings(RaceCategory.MEN, StandingsDiscipline.NATIONS, now)
        val overall = client.worldCupStandings(RaceCategory.MEN, StandingsDiscipline.TOTAL, now)
        for (nation in nations.standings.rows) {
            assertFalse(overall.standings.athletes(checkNotNull(nation.nation)).isEmpty())
        }
    }

    /** The search finds a fictional athlete whose profile opens. */
    @Test
    fun searchFindsAnAthleteByEitherName() = runTest {
        val client = IbuClient.sample(Instant.now())
        val byFamilyName = client.searchAthletes("mart")
        assertEquals(listOf("Hugo MARTEL"), byFamilyName.map { it.name })
        assertEquals(byFamilyName.map { it.id }, client.searchAthletes("Hugo Martel").map { it.id })
        assertEquals("Hugo MARTEL", client.athlete(byFamilyName.first().id).fullName)
        assertTrue(client.searchAthletes("zz").isEmpty())
    }

    /** Asked for, a race is live on any day, with provisional results, and the home shows it. */
    @ParameterizedTest
    @FieldSource("DATES")
    fun aRaceIsLiveWhenAskedFor(now: Instant) = runTest {
        val feed = IbuClient.sample(now, liveRace = true).homeFeed(now)
        val live = checkNotNull(feed.live)
        assertTrue(live.startTime < now)
        assertEquals(true, feed.liveResults?.isResult)
        assertEquals(10, feed.liveResults?.rows?.size)
        assertNull(IbuClient.sample(now).homeFeed(now).live)
    }

    @Test
    fun oldSeasonsAreInTheirYears() = runTest {
        val events = IbuClient.sample(Instant.now()).events(SeasonId("9899"))
        assertEquals(instant("1998-12-01T12:00:00Z"), events.first().startDate)
    }

    @Test
    fun racesStillToComeHaveNoResultsYet() = runTest {
        val now = instant("2026-08-15T12:00:00Z")
        val client = IbuClient.sample(now)
        val next = checkNotNull(client.homeFeed(now).next)
        val results = client.results(next.id)
        assertEquals(next.id, results.competition?.id)
        assertFalse(results.isResult)
        assertTrue(results.rows.isEmpty())
    }

    /** Every ranking of a finished race lists its athletes; races still to come have none. */
    @Test
    fun finishedRacesHaveTheirAnalysis() = runTest {
        val now = instant("2027-01-20T12:00:00Z")
        val client = IbuClient.sample(now)
        val feed = client.homeFeed(now)
        val finished = checkNotNull(feed.latestResults?.competition)
        assertTrue(finished.hasAnalysisRankings)
        for (analysis in RaceAnalysis.all(checkNotNull(finished.shootingCount))) {
            assertEquals(10, client.analysis(analysis, finished.id).rows.size, analysis.typeId)
        }
        assertFalse(checkNotNull(feed.next).hasAnalysisRankings)
    }

    @Test
    fun unknownRoutesAreNotFound() = runTest {
        val error = assertThrows<IbuException.Http> { IbuClient.sample(Instant.now()).athlete("BTXXX0") }
        assertEquals(404, error.status)
    }

    companion object {
        /** Off season, during an event, between two events, and after the last one. */
        @JvmField
        val DATES = listOf("2026-08-15T12:00:00Z", "2026-12-03T12:00:00Z", "2027-01-20T12:00:00Z", "2027-04-20T12:00:00Z").map(::instant)
    }
}
