import groovy.json.JsonSlurper
import java.io.ByteArrayOutputStream
import javax.inject.Inject

// BiathlonKit for Android: the Swift library built with the Swift SDK for Android, and the
// Java bindings that swift-java's jextract generates for it (android/swift).

plugins {
    alias(libs.plugins.android.library)
}

val swiftPackage = layout.projectDirectory.dir("../swift")

/** The swift-java release that SwiftPM resolved: its Java runtime library must be the same. */
val swiftJavaVersion: String = run {
    @Suppress("UNCHECKED_CAST")
    val pins = (JsonSlurper().parse(swiftPackage.file("Package.resolved").asFile) as Map<String, Any>)["pins"]
        as List<Map<String, Any>>
    val pin = pins.single { it["identity"] == "swift-java" }
    (pin["state"] as Map<*, *>)["version"] as String
}

/** The Android ABIs the app ships, with the Swift and NDK target triples that build them. */
data class SwiftAbi(val androidAbi: String, val swiftTriple: String, val ndkTriple: String)

val swiftAbis = listOf(
    SwiftAbi("arm64-v8a", "aarch64-unknown-linux-android", "aarch64-linux-android"),
    SwiftAbi("x86_64", "x86_64-unknown-linux-android", "x86_64-linux-android"),
)

android {
    namespace = "com.fouteox.biathlon.kit"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndk.get()
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.java.get())
    }
    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        consumerProguardFiles("consumer-rules.pro")
    }
}

dependencies {
    api("org.swift.swiftkit:swiftkit-core:$swiftJavaVersion")
}

/**
 * Runs jextract: the Swift thunks into android/swift, the Java sources into [javaSources].
 *
 * Trial finding: the thunks of a debug and a release build differ (IBUClient.sample is
 * DEBUG only) but SwiftPM compiles them from one directory, so a Gradle invocation builds
 * either debug or release variants, never both.
 */
abstract class GenerateSwiftBindings : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val swiftSources: ConfigurableFileCollection

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val script: RegularFileProperty

    @get:Input
    abstract val configuration: Property<String>

    @get:OutputDirectory
    abstract val thunks: DirectoryProperty

    @get:OutputDirectory
    abstract val javaSources: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun generate() {
        execOperations.exec {
            commandLine(script.get().asFile.path, javaSources.get().asFile.path, configuration.get())
        }
    }
}

/** Builds libBiathlonKit.so for one ABI, with the Swift runtime and Foundation linked statically. */
abstract class BuildSwiftLibrary : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sources: ConfigurableFileCollection

    @get:Internal
    abstract val packageDirectory: DirectoryProperty

    @get:Input
    abstract val swiftSdk: Property<String>

    @get:Input
    abstract val configuration: Property<String>

    @get:Input
    abstract val androidAbi: Property<String>

    /** The NDK's C++ runtime, which the Swift runtime links against. */
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val cppRuntime: RegularFileProperty

    @get:LocalState
    abstract val scratchDirectory: DirectoryProperty

    /** A jniLibs directory: <abi>/libBiathlonKit.so and <abi>/libc++_shared.so. */
    @get:OutputDirectory
    abstract val jniLibs: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun build() {
        val arguments = listOf(
            "swift", "build",
            "--package-path", packageDirectory.get().asFile.path,
            "--scratch-path", scratchDirectory.get().asFile.path,
            "--swift-sdk", swiftSdk.get(),
            "--configuration", configuration.get(),
            "--static-swift-stdlib",
        )
        execOperations.exec { commandLine(arguments) }
        val binPath = ByteArrayOutputStream()
        execOperations.exec {
            commandLine(arguments + "--show-bin-path")
            standardOutput = binPath
        }
        val abiDirectory = jniLibs.get().dir(androidAbi.get()).asFile
        abiDirectory.deleteRecursively()
        abiDirectory.mkdirs()
        File(binPath.toString().trim(), "libBiathlonKit.so").copyTo(File(abiDirectory, "libBiathlonKit.so"))
        cppRuntime.get().asFile.copyTo(File(abiDirectory, "libc++_shared.so"))
    }
}

androidComponents {
    val ndkDirectory = sdkComponents.ndkDirectory
    onVariants { variant ->
        val configuration = if (variant.buildType == "release") "release" else "debug"
        val variantName = variant.name.replaceFirstChar(Char::uppercase)
        val generate = tasks.register<GenerateSwiftBindings>("generateSwiftBindings$variantName") {
            swiftSources.from(
                swiftPackage.dir("Sources/BiathlonKit/Shared"),
                swiftPackage.dir("Sources/BiathlonKit/Android"),
                swiftPackage.file("swift-java.config"),
                swiftPackage.file("Package.resolved"),
            )
            script = swiftPackage.file("scripts/generate-bindings.sh")
            this.configuration = configuration
            thunks = swiftPackage.dir("Sources/BiathlonKit/Generated")
            javaSources = layout.buildDirectory.dir("generated/swift-java/${variant.name}")
        }
        variant.sources.java!!.addGeneratedSourceDirectory(generate, GenerateSwiftBindings::javaSources)
        for (abi in swiftAbis) {
            val name = "${variant.name}${abi.androidAbi.replace(Regex("[^A-Za-z0-9]"), "")}"
            val build = tasks.register<BuildSwiftLibrary>("buildSwift${name.replaceFirstChar(Char::uppercase)}") {
                sources.from(
                    generate.flatMap { it.thunks },
                    swiftPackage.dir("Sources/BiathlonKit/Shared"),
                    swiftPackage.dir("Sources/BiathlonKit/Android"),
                    swiftPackage.file("Package.swift"),
                    swiftPackage.file("Package.resolved"),
                )
                packageDirectory = swiftPackage
                swiftSdk = "${abi.swiftTriple}${libs.versions.minSdk.get()}"
                this.configuration = configuration
                androidAbi = abi.androidAbi
                cppRuntime = ndkDirectory.map { ndk ->
                    // The NDK's single prebuilt toolchain, named after the host (linux-x86_64, darwin-x86_64).
                    val host = ndk.dir("toolchains/llvm/prebuilt").asFile.listFiles()!!.single().name
                    ndk.file("toolchains/llvm/prebuilt/$host/sysroot/usr/lib/${abi.ndkTriple}/libc++_shared.so")
                }
                scratchDirectory = layout.buildDirectory.dir("swift/$name")
                jniLibs = layout.buildDirectory.dir("generated/jniLibs/$name")
            }
            variant.sources.jniLibs!!.addGeneratedSourceDirectory(build, BuildSwiftLibrary::jniLibs)
        }
    }
}
