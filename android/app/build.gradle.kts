import groovy.json.JsonSlurper

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

/**
 * A setting of the iOS app's xcconfig files, which hold what both apps share. Their double
 * slashes are escaped (`https:/$()/…`), as xcconfig files read `//` as the start of a comment.
 */
fun xcconfigSetting(file: String, name: String): Provider<String> = providers
    .fileContents(layout.projectDirectory.file("../../Configs/$file"))
    .asText
    .map { text ->
        val setting = checkNotNull(Regex("""^$name\s*=(.*)$""", RegexOption.MULTILINE).find(text)) {
            "$name is missing from Configs/$file"
        }
        setting.groupValues[1].replace("$()", "").trim()
    }

android {
    namespace = "com.fouteox.biathlon"
    compileSdk = libs.versions.compileSdk.get().toInt()
    defaultConfig {
        applicationId = "com.fouteox.biathlon"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = xcconfigSetting("Project.xcconfig", "MARKETING_VERSION").get()
        // IBU data goes through the server's cache, as on iOS; straight to the IBU without a server.
        buildConfigField("String", "SERVER_URL", "\"${xcconfigSetting("Project.xcconfig", "BIATHLON_SERVER_URL").get()}\"")
        // Linked from Settings, hidden while empty.
        buildConfigField("String", "PRIVACY_POLICY_URL", "\"${xcconfigSetting("Biathlon.xcconfig", "BIATHLON_PRIVACY_POLICY_URL").get()}\"")
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    // The app's languages, as on iOS: English, French and German.
    androidResources {
        localeFilters += listOf("en", "fr", "de")
        generateLocaleConfig = true
    }
    // BiathlonKit's fixtures, shared with the iOS app and the server.
    sourceSets.getByName("test").resources.directories += "../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures"
    testOptions {
        // Compose tests run on the JVM with Robolectric, with no emulator.
        unitTests.isIncludeAndroidResources = true
        // The JDK internals Robolectric needs on Java 17 and later, from its getting-started guide.
        unitTests.all {
            it.jvmArgs(
                "--add-opens=java.base/java.lang=ALL-UNNAMED",
                "--add-opens=java.base/java.util=ALL-UNNAMED",
                "--add-opens=java.base/java.io=ALL-UNNAMED",
                "--add-opens=java.base/java.net=ALL-UNNAMED",
                "--add-opens=java.base/java.security=ALL-UNNAMED",
                "--add-opens=java.base/java.text=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
                "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
                "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
            )
        }
    }
    lint {
        warningsAsErrors = true
        // Version updates come from Dependabot, not from a failing build.
        disable += listOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
    }
}

/**
 * Android string resources from the String Catalog of the iOS app, which the server's alerts
 * read too: one set of texts and translations for every platform. Each key becomes a resource
 * name, `Updated at %@` becoming `updated_at_arg`, and a plural catalog entry a `<plurals>`.
 */
@CacheableTask
abstract class GenerateCatalogStrings : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val catalog: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        @Suppress("UNCHECKED_CAST")
        val json = JsonSlurper().parse(catalog.get().asFile) as Map<String, Any?>
        val source = json["sourceLanguage"] as String

        @Suppress("UNCHECKED_CAST")
        val entries = (json["strings"] as Map<String, Map<String, Any?>>).toSortedMap()
        val names = entries.keys.groupBy(::resourceName)
        names.filterValues { it.size > 1 }.keys.firstOrNull()?.let { error("Catalog keys sharing the name $it: ${names[it]}") }

        outputDirectory.get().asFile.deleteRecursively()
        for ((language, folder) in LANGUAGES) {
            val resources = entries.mapNotNull { (key, entry) ->
                @Suppress("UNCHECKED_CAST")
                val localization = (entry["localizations"] as Map<String, Map<String, Any?>>?)?.get(language)
                resource(resourceName(key), localization ?: if (language == source) mapOf("stringUnit" to mapOf("value" to key)) else null)
            }
            val file = outputDirectory.get().dir(folder).file("catalog.xml").asFile
            file.parentFile.mkdirs()
            file.writeText(resources.joinToString("\n", "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n", "\n</resources>\n"))
        }
    }

    /** A string, or plurals, for one language; `null` where the catalog has no translation. */
    private fun resource(name: String, localization: Map<String, Any?>?): String? {
        if (localization == null) return null
        @Suppress("UNCHECKED_CAST")
        val plural = (localization["variations"] as Map<String, Map<String, Map<String, Map<String, String>>>>?)?.get("plural")
        if (plural != null) {
            val items = plural.map { (quantity, variation) -> "        <item quantity=\"$quantity\">${value(variation.getValue("stringUnit").getValue("value"))}</item>" }
            return items.joinToString("\n", "    <plurals name=\"$name\">\n", "\n    </plurals>")
        }
        @Suppress("UNCHECKED_CAST")
        val unit = localization["stringUnit"] as Map<String, String>
        return "    <string name=\"$name\">${value(unit.getValue("value"))}</string>"
    }

    /** Apple's placeholders (`%@`, `%lld`, `%1$@`) as Android's, each numbered, and Android's escapes. */
    private fun value(text: String): String {
        var position = 0
        val formatted = PLACEHOLDER.replace(text) { match ->
            position += 1
            val index = match.groupValues[1].ifEmpty { "$position" }
            "%$index$" + if (match.groupValues[2] == "@") "s" else "d"
        }
        check('%' !in PLACEHOLDER.replace(text, "")) { "Unsupported % in the catalog: $text" }
        return formatted
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("\\", "\\\\").replace("'", "\\'").replace("\"", "\\\"").replace("\n", "\\n")
            .replace(Regex("^([@?])"), "\\\\$1")
    }

    private fun resourceName(key: String): String =
        PLACEHOLDER.replace(key.lowercase(), " arg ").replace(Regex("[^a-z0-9]+"), "_").trim('_')

    private companion object {
        /** The app's languages and their resource folders; the catalog's source language is the default. */
        val LANGUAGES = mapOf("en" to "values", "fr" to "values-fr", "de" to "values-de")
        val PLACEHOLDER = Regex("""%(?:(\d+)\$)?(@|lld|d)""")
    }
}

val catalogStrings = tasks.register<GenerateCatalogStrings>("generateCatalogStrings") {
    catalog = layout.projectDirectory.file("../../Shared/Localizable.xcstrings")
    outputDirectory = layout.buildDirectory.dir("generated/res/catalog")
}

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(catalogStrings, GenerateCatalogStrings::outputDirectory)
    }
}

kotlin {
    compilerOptions {
        allWarningsAsErrors = true
    }
}

dependencies {
    implementation(project(":kit"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.material3.navigation.suite)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.viewmodel.navigation3)
    implementation(libs.navigation3.runtime)
    implementation(libs.navigation3.ui)
    // Athletes' photos, with OkHttp as the IBU client.
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    // The fictional World Cup the screens are tested on.
    testImplementation(testFixtures(project(":kit")))
    testImplementation(libs.ktor.client.mock)
    debugImplementation(libs.compose.ui.test.manifest)
}
