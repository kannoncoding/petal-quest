package com.example.petalquest

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.petalquest.core.sync.FamilySync
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.CancellationException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.io.File

@Composable
fun TeenPushSetup() {
 val context=LocalContext.current
 val scope=rememberCoroutineScope()
 var message by remember { mutableStateOf("Family updates") }
 var busy by remember { mutableStateOf(false) }
 fun enable() {
  if(busy) return
  busy=true
  scope.launch {
   try {
    withContext(Dispatchers.IO) { File(context.noBackupFilesDir,"family_push_enabled").writeText("enabled") }
    FirebaseMessaging.getInstance().isAutoInitEnabled=true
    val token=suspendCancellableCoroutine<String> { continuation ->
     FirebaseMessaging.getInstance().token.addOnSuccessListener { if(continuation.isActive) continuation.resume(it) }
      .addOnFailureListener { if(continuation.isActive) continuation.resumeWithException(it) }
    }
    val registration=FamilySync.get()?.registration ?: error("Family notifications unavailable")
    registration.registerToken(token)
    message="Family notifications enabled."
   } catch(e:CancellationException) { throw e }
   catch(_:Exception) { message="Could not confirm family notifications. Refresh family access and retry when online." }
   finally { busy=false;FamilySync.get()?.kick() }
  }
 }
 val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { if(it) enable() else message="Notifications are disabled in phone settings." }
 TextButton(enabled=!busy,onClick={
  if(Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else enable()
 }) { Text(if(busy) "Connecting family notifications…" else message+" · Enable / retry") }
}
