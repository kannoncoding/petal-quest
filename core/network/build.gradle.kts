plugins { alias(libs.plugins.android.library)  }
android { namespace = "com.petalquest.core.network"; compileSdk = 37
 defaultConfig { minSdk = 24 }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_11; targetCompatibility = JavaVersion.VERSION_11 }
 
}
dependencies {
 api(project(":core:model"))
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
 
}