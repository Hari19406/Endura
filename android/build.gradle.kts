plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}
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
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

// The `health` package (pinned to 3.0.6 by a share_plus/win32 version
// conflict — see pubspec.yaml) pulls in the abandoned `device_info` 2.0.3
// plugin, which predates AGP's namespace requirement and has no
// android.namespace set. Rather than patch the plugin (which pub_cache
// would overwrite), inject the namespace from its legacy Groovy `group`
// value at configuration time — the standard workaround for this AGP 8
// error class with old, unmaintained Flutter plugins.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension && android.namespace == null) {
            android.namespace = project.group.toString()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
