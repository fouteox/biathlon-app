package com.fouteox.biathlon

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** The texts generated from the String Catalog the iOS app and the server share. */
@RunWith(RobolectricTestRunner::class)
class CatalogStringsTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun keepsApostrophesAndNumbersPlaceholders() {
        assertEquals("Men's Sprint", context.getString(R.string.race_smsp))
        assertEquals("Updated at 14:05", context.getString(R.string.updated_at_arg, "14:05"))
        assertEquals("Lac-Blanc · France", context.getString(R.string.arg_arg, "Lac-Blanc", "France"))
    }

    @Test
    @Config(qualifiers = "fr")
    fun translatesWithTheCatalogsPlurals() {
        assertEquals("Mis à jour à 14:05", context.getString(R.string.updated_at_arg, "14:05"))
        assertEquals("Sprint hommes", context.getString(R.string.race_smsp))
        assertEquals("1 point", context.resources.getQuantityString(R.plurals.arg_points, 1, 1))
        assertEquals("612 points", context.resources.getQuantityString(R.plurals.arg_points, 612, 612))
    }
}
