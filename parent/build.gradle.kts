plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.petalquest.parent"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "petalquest.parent"
        minSdk = 24
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
 initWith(getByName("debug")); applicationIdSuffix = ".staging"; matchingFallbacks += "debug"
 }
        release {
            optimization {
                enable = true
                packageScope = setOf("androidx.**", "kotlin.**", "kotlinx.**")
            }
        }
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

apply(from = rootProject.file("service-config.gradle.kts"))
@Suppress("UNCHECKED_CAST")
val serviceSettings = extra["publicServiceSettings"] as Map<String, Pair<String, String>>
android.buildTypes.configureEach {
 val (url, key) = serviceSettings[name] ?: ("" to "")
 buildConfigField("String", "SERVICE_URL", groovy.json.JsonOutput.toJson(url))
 buildConfigField("String", "SERVICE_PUBLIC_KEY", groovy.json.JsonOutput.toJson(key))
}
androidComponents { beforeVariants(selector().withBuildType("staging")) { it.enable = rootProject.file("../Configuration/Supabase/staging.local.json").isFile && rootProject.file("../Configuration/Firebase/Staging/google-services.json").isFile } }
dependencies {
 implementation(project(":core:sync"))
 implementation(project(":core:reminders"))
 coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
 implementation(project(":core:ui"))
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
