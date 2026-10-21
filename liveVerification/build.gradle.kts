plugins { alias(libs.plugins.android.application) }
android {
 namespace = "petalquest.verification.live"
 compileSdk = 37
 defaultConfig { applicationId = "petalquest.verification.live"; minSdk = 26; targetSdk = 37; versionCode = 1; versionName = "1.0" }
 buildTypes { create("staging") { initWith(getByName("debug")); matchingFallbacks += "debug" } }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_11; targetCompatibility = JavaVersion.VERSION_11 }
 buildFeatures { buildConfig = true }
}
apply(from = rootProject.file("service-config.gradle.kts"))
@Suppress("UNCHECKED_CAST")
val publicSettings = extra["publicServiceSettings"] as Map<String, Pair<String, String>>
android.buildTypes.configureEach {
 val (url, key) = publicSettings[name] ?: ("" to "")
 buildConfigField("String", "SERVICE_URL", groovy.json.JsonOutput.toJson(url))
 buildConfigField("String", "SERVICE_PUBLIC_KEY", groovy.json.JsonOutput.toJson(key))
}
dependencies { implementation(project(":core:ui")); implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2") }
