pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
        // swift-java does not publish its Java runtime library yet: it is built from the
        // swift-java checkout that SwiftPM resolves and published locally (see android/README.md).
        mavenLocal {
            content { includeGroup("org.swift.swiftkit") }
        }
    }
}

rootProject.name = "Biathlon"
include(":kit", ":app")
