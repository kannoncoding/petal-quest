package com.example.petalquest

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PersistableBundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

/** Development-only connection check, reachable only when BuildConfig.DEBUG is true. */
@Composable
internal fun Phase2SetupScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var status by remember { mutableStateOf("Ready for the phone notification check.") }
    var token by remember { mutableStateOf<String?>(null) }
    var requestingToken by remember { mutableStateOf(false) }
    var notificationEnabled by remember {
        mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
    }
    val permissionRequest = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        notificationEnabled = granted
        status = if (granted) "Notification permission granted." else "Notifications are disabled. You can enable them in Android settings."
    }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel("phase2_test", "Development test", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Petal Quest · Development check", style = MaterialTheme.typography.headlineSmall)
        Text("Firebase project: ${FirebaseApp.getInstance().options.projectId}")
        Text("App: ${context.packageName}")
        Text(if (notificationEnabled) "Notifications are enabled." else "Notifications need permission.")
        Button(
            onClick = {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    permissionRequest.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    notificationEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
                    status = if (notificationEnabled) "Notification permission is ready." else "Enable notifications in Android settings."
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Enable test notifications") }
        Button(
            onClick = {
                requestingToken = true
                status = "Contacting Firebase…"
                // The documented Firebase console test dialog still accepts a registration token.
                // Keep this compatibility path confined to the development-only setup screen.
                @Suppress("DEPRECATION")
                val tokenRequest = FirebaseMessaging.getInstance().token
                tokenRequest.addOnCompleteListener { task ->
                    requestingToken = false
                    if (task.isSuccessful) {
                        token = task.result
                        status = "Device test token ready. Copy it into Firebase’s test-message dialog."
                    } else {
                        token = null
                        status = "Could not obtain a token. Check internet access and Google Play services, then retry."
                    }
                }
            },
            enabled = !requestingToken,
            modifier = Modifier.fillMaxWidth()
        ) { Text(if (requestingToken) "Connecting…" else "Get device test token") }
        OutlinedButton(
            onClick = {
                token?.let { value ->
                    val clip = ClipData.newPlainText("Firebase development test token", value)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        }
                    }
                    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                    status = "Token copied. Send a test from Petal Quest Dev, then put this app in the background."
                }
            },
            enabled = token != null,
            modifier = Modifier.fillMaxWidth()
        ) { Text("Copy device test token") }
        Text(status)
        Text("After sending the Firebase test, confirm the notification actually appears on this phone. Sending alone does not prove delivery.")
        Text("This screen is a development check. The family apps are built in later phases.", style = MaterialTheme.typography.bodySmall)
    }
}
