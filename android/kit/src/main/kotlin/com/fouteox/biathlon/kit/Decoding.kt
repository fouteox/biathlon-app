package com.fouteox.biathlon.kit

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/**
 * The IBU API's JSON: the app reads only the fields it shows, and a `null` the API sends where
 * a field has a default (`"IsLive": null`) takes that default.
 */
internal val IbuJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
}

/** IBU dates come either with `Z` (`2026-11-26T15:15:00Z`) or with no time zone, meaning UTC (`2001-06-29T00:00:00`). */
private fun parseIbuInstant(raw: String): Instant? {
    val withZone = if (raw.endsWith("Z") || raw.contains('+')) raw else raw + "Z"
    return try {
        OffsetDateTime.parse(withZone).toInstant()
    } catch (_: DateTimeParseException) {
        null
    }
}

/** A date the model can't do without, such as a race's start. */
internal object IbuInstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("IbuInstant", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): Instant {
        val raw = decoder.decodeString()
        return parseIbuInstant(raw) ?: throw SerializationException("Unreadable IBU date: $raw")
    }

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** Reads a field from its JSON element, for the fields whose JSON type varies; `null` reads as `null`. */
internal abstract class JsonElementSerializer<T : Any>(name: String, kind: PrimitiveKind) : KSerializer<T?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(name, kind).nullable

    abstract fun read(element: JsonPrimitive): T?

    abstract fun write(value: T): JsonPrimitive

    override fun deserialize(decoder: Decoder): T? =
        when (val element = (decoder as JsonDecoder).decodeJsonElement()) {
            is JsonNull -> null
            is JsonPrimitive -> read(element)
            else -> null
        }

    override fun serialize(encoder: Encoder, value: T?) {
        (encoder as JsonEncoder).encodeJsonElement(value?.let(::write) ?: JsonNull)
    }
}

/** A date the app can do without, such as a birthdate: left out when unreadable. */
internal object LenientIbuInstantSerializer : JsonElementSerializer<Instant>("LenientIbuInstant", PrimitiveKind.STRING) {
    override fun read(element: JsonPrimitive) = if (element.isString) parseIbuInstant(element.content) else null

    override fun write(value: Instant) = JsonPrimitive(value.toString())
}

/** Ranks, points and distances come either as strings or as numbers: they are read as strings. */
internal object LooseStringSerializer : JsonElementSerializer<String>("LooseString", PrimitiveKind.STRING) {
    override fun read(element: JsonPrimitive) =
        element.content.takeIf { element.isString || it.toDoubleOrNull() != null }

    override fun write(value: String) = JsonPrimitive(value)
}

/** Numbers that come either as numbers or as strings. */
internal object LooseIntSerializer : JsonElementSerializer<Int>("LooseInt", PrimitiveKind.INT) {
    override fun read(element: JsonPrimitive) = element.content.toIntOrNull()

    override fun write(value: Int) = JsonPrimitive(value)
}
