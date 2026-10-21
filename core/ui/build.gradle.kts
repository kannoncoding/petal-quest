plugins { alias(libs.plugins.android.library) ; alias(libs.plugins.kotlin.compose) }
android { namespace = "com.petalquest.core.ui"; compileSdk = 37
 defaultConfig { minSdk = 24 }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_11; targetCompatibility = JavaVersion.VERSION_11 }
 buildFeatures { compose = true }
}
dependencies {
 api(project(":core:network"))
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
 api(project(":core:data")); implementation(platform(libs.androidx.compose.bom)); implementation(libs.androidx.compose.material3); implementation(libs.androidx.compose.ui); implementation(libs.androidx.activity.compose)
}