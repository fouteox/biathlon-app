package com.fouteox.biathlon

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.fouteox.biathlon.kit.IBUClient
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.swift.swiftkit.core.SwiftArena

/**
 * BiathlonKit's live client on the device's network: URLSession over HTTPS, through the
 * curl and OpenSSL that the Swift SDK for Android ships. Trial check, it needs the IBU's API.
 */
@RunWith(AndroidJUnit4::class)
class LiveNetworkTest {
    @Test
    fun loadsTheSeasonCalendarFromTheIBU() {
        val events = SwiftArena.ofConfined().use { arena ->
            runBlocking { IBUClient.live(arena).seasonCalendar(Instant.now()) }
        }
        assertTrue("The IBU's calendar has no event for this season", events.isNotEmpty())
    }
}
