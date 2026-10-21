package com.petalquest.parent

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.firebase.messaging.FirebaseMessaging
import com.petalquest.core.data.LocalData
import com.petalquest.core.data.Session
import com.petalquest.core.model.ServiceConfig
import com.petalquest.core.network.FamilyService
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal fun parentConfig() = ServiceConfig(BuildConfig.SERVICE_URL, BuildConfig.SERVICE_PUBLIC_KEY, BuildConfig.BUILD_TYPE)
internal fun pushOptIn(context: Context) = File(context.noBackupFilesDir, "parent_push_enabled").isFile
internal fun notificationPermission(context: Context) = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

/** Tokens remain in RAM; the service owns token persistence. SessionStore protects account switches. */
internal suspend fun registerParentPush(context: Context, suppliedToken: String? = null) = withContext(Dispatchers.IO) {
 val config = parentConfig()
 check(config.available && pushOptIn(context) && notificationPermission(context))
 val data = LocalData.getInstance(context)
 val initial = data.sessionStore().read() ?: error("Sign in to enable parent notifications.")
 check(initial.endpointId == config.url)
 val service = FamilyService(config)
 var session = initial
 if (session.expiresAtEpochSeconds <= System.currentTimeMillis()/1000 + 60) {
  val fresh = service.refresh(session.refreshToken)
  val replacement = Session(fresh.userId, config.url, fresh.accessToken, fresh.refreshToken, fresh.expiresAtEpochSeconds)
  check(data.sessionStore().refreshIfCurrent(session, replacement))
  session = data.sessionStore().read() ?: error("Sign in again.")
 }
 val memberships = service.memberships(session.token, session.userId).filter { it.active && it.role == "parent" && it.userId == session.userId }
 check(memberships.size == 1) { "An active parent family membership is required." }
 val token = suppliedToken ?: suspendCancellableCoroutine<String> { continuation ->
  FirebaseMessaging.getInstance().token.addOnSuccessListener { if (continuation.isActive) continuation.resume(it) }
   .addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
 }
 val active = data.sessionStore().read()
 check(active != null && active.userId == session.userId && active.endpointId == session.endpointId && active.generation == session.generation)
 service.rpc("register_device", session.token, JSONObject().put("p_family_id", memberships.single().familyId).put("p_push_token", token))
}

@Composable
fun ParentPushSetup(modifier: Modifier = Modifier) {
 val context = LocalContext.current
 val scope = rememberCoroutineScope()
 var message by remember { mutableStateOf("Enable generic parent check-in notifications on this device.") }
 var busy by remember { mutableStateOf(false) }
 fun register() {
  if (busy) return
  busy = true
  scope.launch {
   try {
    withContext(Dispatchers.IO) { File(context.noBackupFilesDir, "parent_push_enabled").writeText("enabled") }
    FirebaseMessaging.getInstance().isAutoInitEnabled = true
    registerParentPush(context)
    message = "Parent notifications enabled on this device."
   } catch (e: CancellationException) { throw e }
   catch (_: Exception) { message = "Sign in with an active parent account, then retry enabling notifications." }
   finally { busy = false }
  }
 }
 val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
  if (allowed) register() else message = "Notifications are disabled. You can enable them in app settings."
 }
 DisposableEffect(context) {
  val lifecycle = (context as? ComponentActivity)?.lifecycle
  val observer = LifecycleEventObserver { _, event ->
   if (event == Lifecycle.Event.ON_RESUME && pushOptIn(context) && notificationPermission(context)) register()
  }
  lifecycle?.addObserver(observer)
  onDispose { lifecycle?.removeObserver(observer) }
 }
 ElevatedCard(modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
  Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
   Text("Parent notifications", style = MaterialTheme.typography.titleSmall)
   Text(message, style = MaterialTheme.typography.bodySmall)
   Button(enabled = !busy && parentConfig().available, onClick = {
    if (Build.VERSION.SDK_INT >= 33 && !notificationPermission(context)) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else register()
   }) { Text(if (busy) "Connecting…" else "Enable / retry notifications") }
  }
 }
}
