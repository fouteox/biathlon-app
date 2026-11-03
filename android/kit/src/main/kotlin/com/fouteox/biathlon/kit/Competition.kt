package com.fouteox.biathlon.kit

import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A `RaceId` starts with its 14-character `EventId`, as biathlonresults.com reads it. */
internal const val EVENT_ID_LENGTH = 14

/** A race, from `Competitions?EventId=` or the `Competition` block of `Results`. */
@Serializable
data class Competition(
    @SerialName("RaceId") val id: String,
    @SerialName("ShortDescription") val shortDescription: String,
    @SerialName("StartTime") @Serializable(IbuInstantSerializer::class) val startTime: Instant,
    @SerialName("StatusId") @Serializable(LooseIntSerializer::class) private val statusId: Int? = null,
    @SerialName("StatusText") private val statusText: String? = null,
    @SerialName("ScheduleStatus") private val scheduleStatus: String? = null,
    @SerialName("IsLive") val isLive: Boolean = false,
    @SerialName("catId") private val categoryId: String? = null,
    @SerialName("NrLegs") @Serializable(LooseIntSerializer::class) private val legCount: Int? = null,
    /** Whether the IBU publishes the race's analysis: its rankings of course, range and shooting times. */
    @SerialName("HasAnalysis") val hasAnalysis: Boolean = false,
    /** Shootings of each athlete, or of each leg of a relay. */
    @SerialName("NrShootings") @Serializable(LooseIntSerializer::class) val shootingCount: Int? = null,
) {
    /**
     * Same rules as the server (`server/src/ibu.ts`), checked against the shared
     * `race-status.json` fixture. Observed values: StatusId 1 "Scheduled", 6 "Cancelled",
     * 11 "Final". biathlonresults.com shows results from StatusId 10, which covers results not
     * yet official.
     */
    val state: State
        get() {
            if (isLive) return State.LIVE
            val text = "${scheduleStatus.orEmpty()} ${statusText.orEmpty()}".uppercase()
            val status = statusId ?: 0
            return when {
                "CANCEL" in text || status == CANCELLED_STATUS_ID -> State.CANCELLED
                "FINISHED" in text || status >= FIRST_RESULT_STATUS_ID -> State.FINISHED
                else -> State.SCHEDULED
            }
        }

    enum class State { SCHEDULED, LIVE, CANCELLED, FINISHED }

    val eventId: String get() = eventId(id)

    val category: RaceCategory? get() = categoryId?.let(RaceCategory::of)

    val kind: RaceKind? get() = RaceKind.of(id)

    val isRelay: Boolean get() = (legCount ?: 0) > 1

    companion object {
        private const val CANCELLED_STATUS_ID = 6
        private const val FIRST_RESULT_STATUS_ID = 10

        fun eventId(raceId: String): String = raceId.take(EVENT_ID_LENGTH)
    }
}
