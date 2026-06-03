import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Mehrere aeltere Flutter-Plugins (sentry_flutter, posthog_flutter, …) pinnen
// intern Kotlin language-/apiVersion 1.6. Der Kotlin-2.2-Compiler (Flutter
// 3.41.9) unterstuetzt das nicht mehr (Minimum 1.8) und bricht den Build mit
// "Language version 1.6 is no longer supported" ab. Wir heben daher fuer alle
// Subprojekte auf 1.8 an — quellkompatibel und erspart Major-Bumps jedes
// einzelnen Plugins (mit potenziellen Dart-API-Breaks).
subprojects {
    afterEvaluate {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                languageVersion.set(KotlinVersion.KOTLIN_1_8)
                apiVersion.set(KotlinVersion.KOTLIN_1_8)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
