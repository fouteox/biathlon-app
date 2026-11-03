package com.fouteox.biathlon.kit

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * A client answering from [SampleWorldCup] instead of the network, so that the screens' tests
 * depend on neither the network nor the IBU's calendar. The data is fictional: the IBU's terms
 * forbid redistributing theirs.
 */
fun IbuClient.Companion.sample(now: Instant, liveRace: Boolean = false): IbuClient {
    val worldCup = SampleWorldCup(now, liveRace)
    return IbuClient(
        httpClient = HttpClient(
            MockEngine { request ->
                val body = worldCup.response(request.url.segments.last(), request.url.parameters.names().associateWith { request.url.parameters[it].orEmpty() })
                if (body == null) respond("", HttpStatusCode.NotFound) else respond(body.toString())
            },
        ),
    )
}

/**
 * A fictional World Cup, the same every season, as the iOS app's: three events of four races, and
 * ten athletes per category, ranked in the same order everywhere. The races before `now` are
 * over, with results. With `liveRace`, the season's first race still to come (its last, once they
 * are all over) is live instead, started 20 minutes ago, with provisional results: what the
 * screens show during a race, on any day.
 */
class SampleWorldCup(private val now: Instant, liveRace: Boolean = false) {
    /** The race that is live, if one is. */
    private val liveRaceId: String? = if (liveRace) firstRaceToCome(now) else null

    /** The JSON of an IBU API response, `null` for what the API wouldn't find. */
    internal fun response(path: String, query: Map<String, String>): JsonElement? = when (path) {
        "Events" -> query["SeasonId"]?.let { season -> JsonArray(events(SeasonId(season)).map { it.json }) }
        "Competitions" -> query["EventId"]?.let(::event)?.let { event -> JsonArray(races(event).map { it.json }) }
        "Results" -> query["RaceId"]?.let(::race)?.let(::results)
        "AnalyticResults" -> query["RaceId"]?.let(::race)?.let { race -> query["TypeId"]?.let { analysis(race, it) } }
        "CupResults" -> query["CupId"]?.let(::standings)
        "CISBios" -> query["IBUId"]?.let(::athlete)?.bio
        "AllResults" -> query["IBUId"]?.let(::athlete)?.let { buildJsonObject { put("Results", history(it)) } }
        "Athletes" -> buildJsonObject { put("Athletes", JsonArray(athletes(query).map { it.match })) }
        else -> null
    }

    // Calendar

    private class Event(val season: SeasonId, number: Int, val place: String, val nation: String, val start: Instant) {
        val id = "BT${season.rawValue}SWRLCP${"%02d".format(Locale.ROOT, number)}"

        val json: JsonObject
            get() = buildJsonObject {
                put("EventId", id)
                put("ShortDescription", place)
                put("Nat", nation)
                put("StartDate", start.toString())
                put("EndDate", start.plus(Duration.ofDays(6)).toString())
            }
    }

    private class Race(val event: Event, val kind: RaceKind, val start: Instant, val isOver: Boolean, val isLive: Boolean = false) {
        val id = event.id + kind.code

        /** Results, final or provisional. */
        val hasResults get() = isOver || isLive

        /** Two in a sprint, four in a pursuit. */
        val shootings get() = if (kind == RaceKind.MEN_SPRINT || kind == RaceKind.WOMEN_SPRINT) 2 else 4

        /** A kind starts with its category's `catId`. */
        val category get() = checkNotNull(RaceCategory.of(kind.code.take(2)))

        val json: JsonObject
            get() = buildJsonObject {
                put("RaceId", id)
                put("catId", category.code)
                put("ShortDescription", kind.name)
                put("StartTime", start.toString())
                put("IsLive", isLive)
                put("StatusId", if (isOver) 11 else 1)
                put("ScheduleStatus", if (isOver) "FINISHED" else "SCHEDULED")
                put("NrShootings", shootings)
                put("HasAnalysis", isOver)
            }
    }

    private fun races(event: Event): List<Race> = PROGRAM.map { (kind, days, hours) ->
        val start = start(event, days, hours)
        if (event.id + kind.code == liveRaceId) {
            Race(event, kind, now.minus(Duration.ofMinutes(20)), isOver = false, isLive = true)
        } else {
            Race(event, kind, start, isOver = start < now)
        }
    }

    private fun event(id: String): Event? =
        if (id.length == EVENT_ID_LENGTH) events(SeasonId(id.drop(2).take(4))).firstOrNull { it.id == id } else null

    private fun race(id: String): Race? = event(Competition.eventId(id))?.let { event -> races(event).firstOrNull { it.id == id } }

    private fun results(race: Race): JsonObject =
        response(race, if (race.hasResults) ranked(athletes(race.category), race, minutes = 24) else emptyList())

    /**
     * A ranking of the race's analysis, the athletes in another order for each measure; none
     * before the race is over or for a lap or shooting the race doesn't have.
     */
    private fun analysis(race: Race, typeId: String): JsonObject {
        val analysis = RaceAnalysis.all(race.shootings).firstOrNull { it.typeId == typeId }
        if (!race.isOver || analysis == null) return response(race, emptyList())
        val athletes = athletes(race.category)
        val shift = 3 * analysis.measure.ordinal
        val minutes = when {
            analysis.measure == RaceAnalysis.Measure.COURSE && analysis.segment == null -> 22
            analysis.measure == RaceAnalysis.Measure.COURSE -> 7
            analysis.measure == RaceAnalysis.Measure.RANGE && analysis.segment == null -> 1
            else -> 0
        }
        return response(race, ranked(athletes.drop(shift) + athletes.take(shift), race, minutes))
    }

    private fun response(race: Race, rows: List<JsonObject>) = buildJsonObject {
        put("IsResult", race.hasResults)
        put("IsStartList", false)
        put("Competition", race.json)
        put("SportEvt", race.event.json)
        put("Results", JsonArray(rows))
    }

    // Athletes

    private class Athlete(val id: String, val givenName: String, val familyName: String, val nation: String, val category: RaceCategory) {
        val row: Map<String, JsonElement>
            get() = mapOf(
                "IBUId" to JsonPrimitive(id),
                "Name" to JsonPrimitive("$familyName $givenName"),
                "FamilyName" to JsonPrimitive(familyName),
                "GivenName" to JsonPrimitive(givenName),
                "ShortName" to JsonPrimitive("$familyName ${givenName.first()}."),
                "Nat" to JsonPrimitive(nation),
            )

        /** As the IBU's search finds the athlete. */
        val match: JsonObject
            get() = buildJsonObject {
                put("IBUId", id)
                put("FamilyName", familyName)
                put("GivenName", givenName)
                put("NAT", nation)
                put("Functions", "Athlete")
            }

        val bio: JsonObject
            get() = buildJsonObject {
                put("IBUId", id)
                put("FullName", "$givenName $familyName")
                put("NAT", nation)
                put("Functions", "Athlete")
                put("Birthdate", "2000-01-15T00:00:00")
                put("GenderId", if (category == RaceCategory.MEN) "M" else "W")
            }
    }

    /** The athletes whose names start like the search's, whatever their case, as the IBU finds them. */
    private fun athletes(query: Map<String, String>): List<Athlete> {
        fun starts(name: String, prefix: String?) = prefix == null || name.lowercase().startsWith(prefix.lowercase())
        return RaceCategory.WITH_STANDINGS.flatMap(::athletes).filter {
            starts(it.familyName, query["FamilyName"]) && starts(it.givenName, query["GivenName"])
        }
    }

    private fun athlete(id: String): Athlete? = RaceCategory.WITH_STANDINGS.flatMap(::athletes).firstOrNull { it.id == id }

    /** The athlete's results of the current season and the previous one, newest first, as `AllResults` lists them. */
    private fun history(athlete: Athlete): JsonArray {
        val rank = athletes(athlete.category).indexOfFirst { it.id == athlete.id } + 1
        val current = SeasonId.containing(now)
        return buildJsonArray {
            listOf(current, current.previous)
                .flatMap { season -> events(season).flatMap(::races).filter { it.isOver && it.category == athlete.category } }
                .sortedByDescending { it.start }
                .forEach { race ->
                    add(
                        buildJsonObject {
                            put("RaceId", race.id)
                            put("Season", race.event.season.rawValue.chunked(2).joinToString("/"))
                            put("Comp", race.kind.name)
                            put("Place", race.event.place)
                            put("Rank", "$rank")
                            put("Level", "WC")
                        },
                    )
                }
        }
    }

    // Standings

    /** Any World Cup table, of any season: the athletes', or the nations' for `NC`. */
    private fun standings(cupId: String): JsonObject? {
        if (cupId.length != 18) return null
        val category = RaceCategory.of(cupId.drop(EVENT_ID_LENGTH).take(2))?.takeIf { it in RaceCategory.WITH_STANDINGS } ?: return null
        val discipline = StandingsDiscipline.entries.firstOrNull { it.code == cupId.takeLast(2) } ?: return null
        val rows = if (discipline == StandingsDiscipline.NATIONS) {
            NATIONS.map { (code, name) -> mapOf("IBUId" to JsonPrimitive(code), "Name" to JsonPrimitive(name), "Nat" to JsonPrimitive(code)) }
        } else {
            athletes(category).map { it.row }
        }
        return buildJsonObject {
            put("CupId", cupId)
            putJsonArray("Rows") {
                rows.forEachIndexed { index, row ->
                    add(
                        JsonObject(
                            row + mapOf("Rank" to JsonPrimitive("${index + 1}"), "Score" to JsonPrimitive("${1_000 - 60 * index}")) +
                                if (index == 0) mapOf("Bibs" to buildJsonArray { add(buildJsonObject { put("Color", "yellow") }) }) else emptyMap(),
                        ),
                    )
                }
            }
        }
    }

    private companion object {
        /** Places, nations and start dates (month, day, in the season's first or second year). */
        val CALENDAR = listOf(
            Stage("Nordvik", "NOR", month = 12, day = 1, year = 0),
            Stage("Lac-Blanc", "FRA", month = 1, day = 12, year = 1),
            Stage("Hohenwald", "GER", month = 3, day = 9, year = 1),
        )

        /** Each race's kind, and its start in days and hours after its event's. */
        val PROGRAM = listOf(
            Triple(RaceKind.MEN_SPRINT, 2, 3),
            Triple(RaceKind.WOMEN_SPRINT, 3, 3),
            Triple(RaceKind.MEN_PURSUIT, 4, 0),
            Triple(RaceKind.WOMEN_PURSUIT, 4, 2),
        )

        /** The nations of the athletes, in the order of the nations standings, with their English names. */
        val NATIONS = listOf("NOR" to "Norway", "FRA" to "France", "GER" to "Germany", "SWE" to "Sweden", "ITA" to "Italy")

        val NAMES = mapOf(
            RaceCategory.MEN to listOf(
                "Aksel" to "VANGEN", "Hugo" to "MARTEL", "Lukas" to "BRANDT", "Erik" to "LUNDQVIST", "Marco" to "FERRATI",
                "Sindre" to "HOLTE", "Louis" to "DUVERNAY", "Felix" to "KESSLER", "Oskar" to "STRAND", "Luca" to "BENZONI",
            ),
            RaceCategory.WOMEN to listOf(
                "Ingrid" to "SOLBERG", "Chloé" to "BERTIN", "Lena" to "HARTMANN", "Elsa" to "NYGREN", "Giulia" to "ROSSETTI",
                "Maren" to "LIEN", "Manon" to "AUBRY", "Anna" to "WEBER", "Klara" to "EKMAN", "Sara" to "COLOMBO",
            ),
        )

        data class Stage(val place: String, val nation: String, val month: Int, val day: Int, val year: Int)

        fun events(season: SeasonId): List<Event> = CALENDAR.mapIndexed { index, stage ->
            Event(season, index + 1, stage.place, stage.nation, noon(season.start + stage.year, stage.month, stage.day))
        }

        fun start(event: Event, days: Int, hours: Int): Instant = event.start.plus(Duration.ofDays(days.toLong()).plusHours(hours.toLong()))

        /** The season's first race after `now`, or its last once they are all over: a race of an event the home features either way. */
        fun firstRaceToCome(now: Instant): String? {
            val races = events(SeasonId.containing(now)).flatMap { event ->
                PROGRAM.map { (kind, days, hours) -> event.id + kind.code to start(event, days, hours) }
            }
            return (races.firstOrNull { it.second > now } ?: races.lastOrNull())?.first
        }

        /** The category's athletes, in the order of every standings table and result. */
        fun athletes(category: RaceCategory): List<Athlete> = NAMES[category].orEmpty().mapIndexed { index, (given, family) ->
            val nation = NATIONS[index % NATIONS.size].first
            Athlete("BT$nation${category.code}${"%02d".format(Locale.ROOT, index + 1)}", given, family, nation, category)
        }

        /** The athletes in their order, a second apart from `minutes` and ten seconds, each missing once at the second shooting. */
        fun ranked(athletes: List<Athlete>, race: Race, minutes: Int): List<JsonObject> {
            val shootings = (1..race.shootings).joinToString("+") { if (it == 2) "1" else "0" }
            return athletes.mapIndexed { rank, athlete ->
                val seconds = 10 + rank
                JsonObject(
                    athlete.row + mapOf(
                        "Rank" to JsonPrimitive("${rank + 1}"),
                        "Shootings" to JsonPrimitive(shootings),
                        "TotalTime" to JsonPrimitive(if (minutes == 0) "$seconds.0" else "$minutes:${"%02d".format(Locale.ROOT, seconds)}.0"),
                        "Behind" to JsonPrimitive(if (rank == 0) "0.0" else "+$rank.0"),
                    ),
                )
            }
        }

        fun noon(year: Int, month: Int, day: Int): Instant = ZonedDateTime.of(year, month, day, 12, 0, 0, 0, ZoneOffset.UTC).toInstant()
    }
}
