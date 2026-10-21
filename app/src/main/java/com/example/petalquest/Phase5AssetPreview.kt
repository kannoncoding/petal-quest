package com.example.petalquest

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.ImageView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay

/** Manual visual review only. Entry point is confined to the debug branch. */
@Composable
internal fun Phase5AssetPreview(lifecycle: Lifecycle, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var reducedMotion by remember { mutableStateOf(false) }
    var systemMotion by remember { mutableStateOf(false) }
    var resumed by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    var playing by remember { mutableStateOf(false) }
    var frame by remember { mutableIntStateOf(0) }
    var sequence by remember { mutableStateOf("idle") }
    val frames = remember {
        mapOf(
            "idle" to intArrayOf(R.drawable.pq_dog_idle_00, R.drawable.pq_dog_idle_01, R.drawable.pq_dog_idle_02, R.drawable.pq_dog_idle_03, R.drawable.pq_dog_idle_04, R.drawable.pq_dog_idle_05, R.drawable.pq_dog_idle_06, R.drawable.pq_dog_idle_07, R.drawable.pq_dog_idle_08, R.drawable.pq_dog_idle_09, R.drawable.pq_dog_idle_10, R.drawable.pq_dog_idle_11),
            "celebrate" to intArrayOf(R.drawable.pq_dog_celebrate_00, R.drawable.pq_dog_celebrate_01, R.drawable.pq_dog_celebrate_02, R.drawable.pq_dog_celebrate_03, R.drawable.pq_dog_celebrate_04, R.drawable.pq_dog_celebrate_05, R.drawable.pq_dog_celebrate_06, R.drawable.pq_dog_celebrate_07),
            "reminder" to intArrayOf(R.drawable.pq_dog_reminder_00, R.drawable.pq_dog_reminder_01, R.drawable.pq_dog_reminder_02, R.drawable.pq_dog_reminder_03, R.drawable.pq_dog_reminder_04, R.drawable.pq_dog_reminder_05, R.drawable.pq_dog_reminder_06, R.drawable.pq_dog_reminder_07)
        )
    }
    DisposableEffect(lifecycle, context) {
        fun readScale() {
            systemMotion = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
            if (!systemMotion) { playing = false; frame = 0 }
        }
        val scaleObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) = readScale()
        }
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) { resumed = true; readScale() }
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP || event == Lifecycle.Event.ON_DESTROY) {
                resumed = false; playing = false; frame = 0
            }
        }
        readScale()
        lifecycle.addObserver(observer)
        context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, scaleObserver)
        onDispose {
            lifecycle.removeObserver(observer)
            context.contentResolver.unregisterContentObserver(scaleObserver)
        }
    }
    val animate = playing && resumed && systemMotion && !reducedMotion
    LaunchedEffect(animate, sequence) {
        frame = 0
        if (animate) {
            val interval = when (sequence) { "idle" -> 200L; "celebrate" -> 125L; else -> 250L }
            while (true) {
                delay(interval)
                val next = frame + 1
                if (next >= frames.getValue(sequence).size && sequence != "idle") {
                    playing = false
                    frame = 0
                    break
                }
                frame = next % frames.getValue(sequence).size
            }
        }
    }
    BackHandler(onBack = onBack)
    val resource = if (animate) frames.getValue(sequence)[frame] else R.drawable.pq_dog_static
    Column(modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Phase 5 · Asset visual review", style = MaterialTheme.typography.headlineSmall)
        OutlinedButton(onClick = onBack) { Text("Back to Phase 2 setup") }
        Text("Static by default. Play loops idle; celebration and reminder run once, then return to static. Leaving this screen or backgrounding the app stops playback; returning requires Play again.")
        Text("Mascot · 64dp and 128dp · fixed full canvas, nearest neighbor")
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            for (size in listOf(64, 128)) {
                Image(bitmap = ImageBitmap.imageResource(resource), contentDescription = "Dog visual review at ${size}dp", modifier = Modifier.size(size.dp), filterQuality = FilterQuality.None)
            }
        }
        Text("Sequence: $sequence · frame ${if (animate) frame + 1 else 0} / ${frames.getValue(sequence).size}")
        for (name in listOf("idle", "celebrate", "reminder")) {
            OutlinedButton(onClick = { playing = false; frame = 0; sequence = name }) { Text("Select $name") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = { frame = 0; playing = true }, enabled = !reducedMotion && systemMotion && resumed && !playing) { Text("Play") }
            OutlinedButton(onClick = { playing = false; frame = 0 }) { Text("Stop") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Switch(checked = reducedMotion, onCheckedChange = { reducedMotion = it; playing = false; frame = 0 })
            Text("Reduced motion · static mascot")
        }
        Text(if (systemMotion) "System animation setting permits playback." else "System animations are disabled; static mascot is shown.")
        Text("Launcher artwork · 48dp / 72dp · teen then parent")
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            LauncherSample(R.mipmap.petal_quest_teen_launcher, 48, "Teen launcher")
            LauncherSample(R.mipmap.petal_quest_teen_launcher, 72, "Teen launcher enlarged")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            LauncherSample(R.mipmap.ic_parent_launcher, 48, "Parent launcher")
            LauncherSample(R.mipmap.ic_parent_launcher, 72, "Parent launcher enlarged")
        }
        Text("Notification alpha masks · 24dp · teen then parent")
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Icon(painterResource(R.drawable.ic_petal_quest_teen_notification), "Teen notification mask", Modifier.size(24.dp))
            Icon(painterResource(R.drawable.ic_parent_notification), "Parent notification mask", Modifier.size(24.dp))
        }
        Text("These samples support visual review. Launcher masks, themed icons, status bar rendering and notification delivery still require device checks.")
    }
}

@Composable
private fun LauncherSample(resource: Int, size: Int, description: String) {
    AndroidView(factory = { context -> ImageView(context).apply { contentDescription = description; scaleType = ImageView.ScaleType.FIT_CENTER; setImageResource(resource) } }, modifier = Modifier.size(size.dp))
}

