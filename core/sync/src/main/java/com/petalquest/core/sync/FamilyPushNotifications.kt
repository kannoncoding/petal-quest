package com.petalquest.core.sync

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Push carries a navigation hint; current server membership is checked before display. */
object FamilyPushNotifications {
 internal fun clear(context:Context, invalidate:()->Unit) = synchronized(this) {
  invalidate()
  context.getSystemService(NotificationManager::class.java).cancelAll()
  context.getSharedPreferences("family-push-receipts",Context.MODE_PRIVATE).edit().clear().commit()
 }
 suspend fun receive(context: Context, data: Map<String,String>) = withContext(Dispatchers.IO) {
  try {
   val runtime=FamilySync.get() ?: return@withContext
   if(Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) return@withContext
   val (session,member)=runtime.authorize()
   val hint=FamilyNotificationGate.parse(data,session,member) ?: return@withContext
   if(!runtime.current(session)) return@withContext
   runtime.hint()
   val key=session.generation+":"+hint.eventId
   val receipts=context.getSharedPreferences("family-push-receipts",Context.MODE_PRIVATE)
   synchronized(this@FamilyPushNotifications) {
    if(receipts.contains(key) || !runtime.current(session) || runtime.currentMembership()!=member || runtime.deliveryBlocked()) return@synchronized
    val manager=context.getSystemService(NotificationManager::class.java)
    // A burst updates one current family notice; every event still has its own receipt.
    val notificationTag="family-update:${member.familyId}:${member.role}"
    manager.activeNotifications.filter { it.id==2 && it.tag!=notificationTag }.forEach { manager.cancel(it.tag,it.id) }
    if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel("family_updates","Family updates",NotificationManager.IMPORTANCE_DEFAULT))
    val intent=context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return@synchronized
    intent.data=Uri.parse("petalquest://family/"+hint.eventId)
    intent.putExtra("family_id",hint.familyId).putExtra("family_teen",hint.teenId).putExtra("family_destination",hint.destination).putExtra("family_date",hint.localDate).putExtra("family_session",session.generation)
    val open=PendingIntent.getActivity(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val notice=NotificationCompat.Builder(context,"family_updates").setSmallIcon(android.R.drawable.ic_dialog_info)
     .setContentTitle(if(member.role=="parent") "Petal Quest Parent" else "Petal Quest").setContentText("Open Petal Quest to see a family update.")
     .setOnlyAlertOnce(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setContentIntent(open).setAutoCancel(true).build()
    manager.notify(notificationTag,2,notice)
    val edit=receipts.edit()
    val now=System.currentTimeMillis()
    receipts.all.forEach { (k,v)-> if(v is Long && now-v>7L*24*60*60*1000) edit.remove(k) }
    edit.putLong(key,now).apply()
   }
  } catch (_: Exception) { /* Refresh on resume recovers unavailable or missed push hints. */ }
 }
}
