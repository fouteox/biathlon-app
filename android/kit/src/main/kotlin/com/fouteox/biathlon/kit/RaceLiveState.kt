package com.fouteox.biathlon.kit

import java.time.Duration
import java.time.Instant
import kotlin.math.roundToLong
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * What a race's Live Update shows, as `RaceLiveState` on iOS: the server builds it from the
 * calendar and `Results?RaceId=` (`liveState` in server/src/live.ts), the same state for the
 * Live Activities' broadcasts and the races' FCM topics, checked against the shared
 * `live-activity.json` fixture.
 */
@Serializable
data class RaceLiveState(
    val phase: Competition.State,
    @Serializable(ReferenceDateSerializer::class) val startTime: Instant,
    /** The first ranked rows, at most three (`LEADER_COUNT` on the server). */
    val leaders: List<Leader>,
) {
    @Serializable
    data class Leader(
        val rank: String,
        val name: String,
        val nation: String? = null,
        /** The leader's time, then each follower's gap to them. */
        val result: String? = null,
    )

    companion object {
        /** The race's topic opens this long before the start (`ACTIVITY_LEAD_MS`, server/src/live.ts). */
        val LEAD: Duration = Duration.ofMinutes(30)

        /**
         * A race starting at `startTime`, from its start list to its result, then cancelled
         * instead: every state its Live Update shows, for trying it without a race in the app's
         * developer settings, as on iOS.
         */
        fun demo(startTime: Instant): List<RaceLiveState> {
            val firstPodium = listOf(
                Leader("1", "PERROT E.", "FRA", "12:41.6"),
                Leader("2", "LAEGREID S.", "NOR", "+4.2"),
                Leader("3", "SAMUELSSON S.", "SWE", "+9.8"),
            )
            val result = demoResult(startTime)
            return listOf(
                RaceLiveState(Competition.State.SCHEDULED, startTime, emptyList()),
                RaceLiveState(Competition.State.LIVE, startTime, emptyList()),
                RaceLiveState(Competition.State.LIVE, startTime, firstPodium),
                RaceLiveState(Competition.State.LIVE, startTime, result.leaders),
                result,
                RaceLiveState(Competition.State.CANCELLED, startTime, emptyList()),
            )
        }

        /** The demo race's result, which its Live Update shows once ended. */
        fun demoResult(startTime: Instant) = RaceLiveState(
            Competition.State.FINISHED,
            startTime,
            listOf(
                Leader("1", "JACQUELIN E.", "FRA", "24:58.3"),
                Leader("2", "PERROT E.", "FRA", "+2.1"),
                Leader("3", "LAEGREID S.", "NOR", "+6.4"),
            ),
        )
    }
}

/**
 * A date in seconds since 2001-01-01, as Foundation's `Date` encodes itself: the state is the iOS
 * Live Activity's `content-state` too.
 */
internal object ReferenceDateSerializer : KSerializer<Instant> {
    /** Seconds between the UNIX epoch and Foundation's reference date (`REFERENCE_DATE_S` on the server). */
    private const val REFERENCE_DATE_S = 978_307_200L

    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("ReferenceDate", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Instant =
        Instant.ofEpochMilli(((decoder.decodeDouble() + REFERENCE_DATE_S) * 1000).roundToLong())

    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeDouble(value.toEpochMilli() / 1000.0 - REFERENCE_DATE_S)
}
