// The app's models and its clients, in plain Kotlin as BiathlonKit is in Swift: tested on the
// JVM against the same fixtures, with no Android device.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.android.lint)
}

kotlin {
    compilerOptions {
        allWarningsAsErrors = true
    }
}

// BiathlonKit's fixtures, shared with the iOS app and the server.
sourceSets.test {
    resources.srcDir("../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures")
}

tasks.test {
    useJUnitPlatform()
}

lint {
    warningsAsErrors = true
    // Version updates come from Dependabot, not from a failing build.
    disable += listOf("GradleDependency", "NewerVersionAvailable")
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    api(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
    testImplementation(libs.ktor.client.mock)
    testImplementation(libs.kotlinx.coroutines.test)
}
