package com.fouteox.biathlon.kit

/**
 * One of a race's rankings in `AnalyticResults`: of the times on the course, on the range or on
 * the shooting mat, over the whole race or a single lap or shooting.
 */
data class RaceAnalysis(
    val measure: Measure,
    /** The lap, for the course, or the shooting, for the range and the mat; `null` for the whole race. */
    val segment: Int? = null,
) {
    enum class Measure {
        /** Skiing, the laps adding up to the total. */
        COURSE,

        /** From entering the range to leaving it, the shooting included. */
        RANGE,

        /** On the shooting mat, within the time on the range. */
        SHOOTING,
    }

    /** `TypeId` of `AnalyticResults`, as biathlonresults.com names its rankings. */
    internal val typeId: String
        get() = when (measure) {
            Measure.COURSE -> "CRS${segment ?: "T"}"
            Measure.RANGE -> "RNG${segment ?: "T"}"
            Measure.SHOOTING -> segment?.let { "S${it}TM" } ?: "STTM"
        }

    /** The same lap or shooting in `measure`, or the whole race when `race` has no such segment. */
    fun measuring(measure: Measure, race: Competition): RaceAnalysis =
        RaceAnalysis(measure, segment?.takeIf { it in race.segments(measure) })

    companion object {
        /** A lap before each shooting and after the last. */
        internal fun segments(measure: Measure, shootings: Int): List<Int> =
            (1..(if (measure == Measure.COURSE) shootings + 1 else shootings)).toList()

        /** Every ranking of a race with `shootings` shootings, each measure's total before its segments. */
        internal fun all(shootings: Int): List<RaceAnalysis> = Measure.entries.flatMap { measure ->
            listOf(RaceAnalysis(measure)) + segments(measure, shootings).map { RaceAnalysis(measure, it) }
        }
    }
}

/** Whether the app shows the race's analysis: not for relays, whose rankings list each leg apart from its team. */
val Competition.hasAnalysisRankings: Boolean get() = hasAnalysis && !isRelay && shootingCount != null

/** The laps, for the course, or the shootings, for the range and the mat. */
fun Competition.segments(measure: RaceAnalysis.Measure): List<Int> = RaceAnalysis.segments(measure, shootingCount ?: 0)

/** The athletes ranked by `analysis`, with their time in the place of the race's. */
suspend fun IbuClient.analysis(analysis: RaceAnalysis, raceId: String): RaceResults =
    get("AnalyticResults", "RaceId" to raceId, "TypeId" to analysis.typeId)
