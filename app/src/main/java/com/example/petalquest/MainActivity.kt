package com.example.petalquest

import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveable
import kotlinx.coroutines.delay
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.example.petalquest.ui.theme.PetalQuestTheme

class MainActivity : ComponentActivity() {
    private val localData by lazy { com.petalquest.core.data.LocalData.getInstance(this) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.rgb(16, 21, 32)),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.rgb(16, 21, 32))
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Reveal the activity's full-size branding as soon as its first frame is ready.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        setContent {
            PetalQuestTheme {
                var showingBrand by rememberSaveable { mutableStateOf(true) }
                LaunchedEffect(Unit) {
                    delay(1200L)
                    showingBrand = false
                }
                LaunchedEffect(showingBrand) {
                    if (!showingBrand) this@MainActivity.enableEdgeToEdge()
                }
                if (showingBrand) {
                    BrandLaunchScreen()
                } else {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    var showFamily by remember { mutableStateOf(false) }
                    if (showFamily || !BuildConfig.DEBUG) {
                        Column(modifier = Modifier.padding(innerPadding)) {
                            OutlinedButton(onClick = { startActivity(android.content.Intent(this@MainActivity, com.example.petalquest.health.PrivateCycleActivity::class.java)) }) { Text("Private cycle log") }
                            if (BuildConfig.DEBUG) OutlinedButton(onClick = { showFamily = false }) { Text("Back to development previews") }
                            com.petalquest.core.ui.FamilyAccessScreen(false, com.petalquest.core.model.ServiceConfig(BuildConfig.SERVICE_URL, BuildConfig.SERVICE_PUBLIC_KEY, BuildConfig.BUILD_TYPE), localData)
                        }
                    } else if (BuildConfig.DEBUG) {
                        var showAssets by remember { mutableStateOf(false) }
                        if (showAssets) {
                            Phase5AssetPreview(lifecycle = this@MainActivity.lifecycle, onBack = { showAssets = false }, modifier = Modifier.padding(innerPadding))
                        } else {
                            Column(modifier = Modifier.padding(innerPadding)) {
                                OutlinedButton(onClick = { startActivity(android.content.Intent(this@MainActivity, com.example.petalquest.health.PrivateCycleActivity::class.java)) }) { Text("Private cycle log") }
                                OutlinedButton(onClick = { showFamily = true }) { Text("Family service access") }
                                OutlinedButton(onClick = { showAssets = true }) { Text("Phase 5 asset visual review") }
                                Phase2SetupScreen(modifier = Modifier.weight(1f))
                            }
                        }
                    } else {
                        Greeting(name = "Android", modifier = Modifier.padding(innerPadding))
                    }
                }
                }
            }
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello $name!",
        modifier = modifier
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    PetalQuestTheme {
        Greeting("Android")
    }
}
