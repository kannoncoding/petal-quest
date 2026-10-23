plugins { alias(libs.plugins.android.library) }
android {
 namespace = "com.petalquest.core.sync"; compileSdk = 37
 defaultConfig { minSdk = 24 }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_11; targetCompatibility = JavaVersion.VERSION_11 }
}
dependencies {
 implementation("androidx.core:core-ktx:1.10.1")
 api(project(":core:data")); api(project(":core:network"))
 implementation("androidx.work:work-runtime-ktx:2.10.5")
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
 implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
