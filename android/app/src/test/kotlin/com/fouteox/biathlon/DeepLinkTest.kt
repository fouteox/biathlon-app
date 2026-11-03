package com.fouteox.biathlon

import android.content.Intent
import android.net.Uri
import android.util.Xml
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.xmlpull.v1.XmlPullParser

/** What the widget, the Live Update and the app shortcuts open, as on iOS (Shared/DeepLink.swift). */
@RunWith(RobolectricTestRunner::class)
class DeepLinkTest {
    private val context = RuntimeEnvironment.getApplication()

    @Test
    fun aRaceLinkCarriesItsIdAndItsName() {
        val link = DeepLink.Race("BT2627SWRLCP01SMSP", "Men 10 km Sprint & Pursuit?")
        assertEquals("biathlon://race/BT2627SWRLCP01SMSP?name=Men%2010%20km%20Sprint%20%26%20Pursuit%3F", link.uri.toString())
        assertEquals(link, DeepLink.of(link.intent(context)))
    }

    @Test
    fun theShortcutsLinksNameNoRace() {
        assertEquals(DeepLink.NextRace, DeepLink.of(DeepLink.NextRace.intent(context)))
        assertEquals(DeepLink.LatestResult, DeepLink.of(DeepLink.LatestResult.intent(context)))
    }

    /** Back to the app already open, on top of its task, rather than in a second one. */
    @Test
    fun opensTheAppAlreadyOpen() {
        val intent = DeepLink.NextRace.intent(context)
        assertEquals(MainActivity::class.java.name, intent.component?.className)
        val flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        assertEquals(flags, intent.flags and flags)
    }

    @Test
    fun otherLinksOpenNothing() {
        for (uri in listOf("biathlon://race/", "biathlon://athlete/123", "https://race/BT2627SWRLCP01SMSP")) {
            assertNull(uri, DeepLink.of(Intent(Intent.ACTION_VIEW, Uri.parse(uri))))
        }
        assertNull(DeepLink.of(Intent(Intent.ACTION_MAIN)))
    }

    /** Each app shortcut of res/xml/shortcuts.xml opens a link of the app, in MainActivity. */
    @Test
    fun theAppShortcutsOpenTheirLinks() {
        val parser = context.resources.getXml(R.xml.shortcuts)
        val links = mutableMapOf<String, DeepLink?>()
        var shortcut: String? = null
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG) continue
            val attributes = Xml.asAttributeSet(parser)
            when (parser.name) {
                "shortcut" -> shortcut = attributes.getAttributeValue(ANDROID, "shortcutId")
                "intent" -> {
                    assertEquals(MainActivity::class.java.name, attributes.getAttributeValue(ANDROID, "targetClass"))
                    val intent = Intent(attributes.getAttributeValue(ANDROID, "action"), Uri.parse(attributes.getAttributeValue(ANDROID, "data")))
                    links[checkNotNull(shortcut)] = DeepLink.of(intent)
                }
            }
        }
        assertEquals(mapOf("next-race" to DeepLink.NextRace, "latest-result" to DeepLink.LatestResult), links)
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
    }
}
