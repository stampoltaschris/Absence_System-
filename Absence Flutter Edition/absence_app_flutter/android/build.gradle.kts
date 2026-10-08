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

// FORCE compileSdk 36 σε όλα τα plugins (file_picker, lifecycle κ.λπ.)
subprojects {
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                useVersion("8.9.0")
            }
        }
    }
    
    plugins.whenPluginAdded {
        if (this is com.android.build.gradle.AppPlugin) {
            project.extensions.getByType(com.android.build.gradle.AppExtension::class.java).apply {
                compileSdkVersion(36)
            }
        }
        if (this is com.android.build.gradle.LibraryPlugin) {
            project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java).apply {
                compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}