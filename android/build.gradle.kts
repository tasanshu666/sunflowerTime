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

// 统一抬高 Android 插件模块的 compileSdk。
// 原因：部分 Flutter 插件（如 sqlcipher_flutter_libs 0.5.7）在自身 build.gradle 里
// 硬编码 compileSdkVersion 28，而 AGP 编译含 Java 9+ 源码的模块要求 compileSdk >= 30，
// 直接导致 assembleDebug 失败（"set compileSdkVersion to 30 or above"）。
// 插件位于 pub 缓存、不可改，故在根工程对全部 Android 模块统一覆盖。
//
// ⚠️ 位置很重要：本块必须放在下面 `evaluationDependsOn(":app")` 之前，
// 否则会报 "Cannot run Project.afterEvaluate(Action) when the project is already evaluated"。
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            androidExt.withGroovyBuilder {
                try {
                    "compileSdkVersion"(35)
                } catch (_: Throwable) {
                    "compileSdk"(35)
                }
            }
            println("[sunfocus] forced compileSdk=35 for ${project.name}")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
