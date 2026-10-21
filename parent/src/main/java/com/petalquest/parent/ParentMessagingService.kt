package com.petalquest.parent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.AtomicFile
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.petalquest.core.data.LocalData
import kotlinx.coroutines.*
import org.json.JSONArray
import java.io.File
import java.security.MessageDigest
import java.util.UUID

class ParentMessagingService : FirebaseMessagingService() {
 override fun onNewToken(token: String) {
  // Rebind rotated tokens only for the explicitly opted-in, current parent session.
  CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
   try { registerParentPush(applicationContext, token) } catch (_: Exception) { /* Foreground retry; no token logging. */ }
  }
 }
 override fun onMessageReceived(message: RemoteMessage) {
  try {
   val data = message.data
   if (message.notification != null || data["kind"] != "parent_checkin" || !pushOptIn(this) || !notificationPermission(this)) return
   val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
    timeZone = java.util.TimeZone.getTimeZone("America/Costa_Rica")
   }.format(java.util.Date())
   val expiresAt = data["expires_at_epoch"]?.toLongOrNull() ?: return
   if (data["local_date"] != today || System.currentTimeMillis()/1000 >= expiresAt) return
   val body = data["checkin_text"]?.takeIf { it == "High pain levels today - please check in" } ?: return
   val recipient = UUID.fromString(data["recipient_user_id"]).toString()
   val event = UUID.fromString(data["event_id"]).toString()
   val config = parentConfig()
   if (!config.available) return
   val store = LocalData.getInstance(this).sessionStore()
   val session = store.read() ?: return
   if (session.userId != recipient || session.endpointId != config.url) return
   val key = MessageDigest.getInstance("SHA-256").digest((config.url + "|" + recipient + "|" + event).toByteArray()).joinToString("") { "%02x".format(it) }
   synchronized(receiptLock) {
    val receipts = AtomicFile(File(noBackupFilesDir, "parent_push_receipts.json"))
    val known = if (receipts.baseFile.exists() || File(receipts.baseFile.path + ".bak").exists()) JSONArray(String(receipts.readFully(), Charsets.UTF_8)) else JSONArray()
    if ((0 until known.length()).any { known.getString(it) == key }) return
    val current = store.read() ?: return
    if (current.userId != recipient || current.endpointId != config.url || current.generation != session.generation) return
    val retained = JSONArray()
    for (index in 0 until known.length()) retained.put(known.getString(index))
    retained.put(key)
    val output = receipts.startWrite()
    try { output.write(retained.toString().toByteArray()); receipts.finishWrite(output) }
    catch (e: Exception) { receipts.failWrite(output); return }
    val manager = getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Parent check-ins", NotificationManager.IMPORTANCE_DEFAULT).apply { lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE })
    val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val notification = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info)
     .setContentTitle("Petal Quest").setContentText(body).setContentIntent(open).setAutoCancel(true)
     .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
    manager.notify(key, 1, notification)
   }
  } catch (_: Exception) { /* Malformed, stale, or unavailable credentials fail closed. */ }
 }
 companion object { private val receiptLock = Any(); private const val CHANNEL = "parent_checkins" }
}
