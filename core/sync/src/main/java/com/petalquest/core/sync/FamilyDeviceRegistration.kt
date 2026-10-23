package com.petalquest.core.sync

import android.util.AtomicFile
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Token and installation state live under no_backup, never in family snapshots. */
class FamilyDeviceRegistration internal constructor(private val runtime: FamilySync) {
 private val mutex=Mutex()
 private fun notificationsAllowed(): Boolean {
  if(android.os.Build.VERSION.SDK_INT>=33 && runtime.context.checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=android.content.pm.PackageManager.PERMISSION_GRANTED) return false
  return File(runtime.context.noBackupFilesDir,"family_push_enabled").exists() || (runtime.role=="parent" && File(runtime.context.noBackupFilesDir,"parent_push_enabled").exists())
 }
 private val file=AtomicFile(File(runtime.context.noBackupFilesDir,"family-device.json"))
 private fun read(): JSONObject = synchronized(this) { if(file.baseFile.exists()) JSONObject(String(file.readFully(),Charsets.UTF_8)) else JSONObject().put("installation",UUID.randomUUID().toString()).also { save(it) } }
 private fun save(state: JSONObject) { val stream=file.startWrite(); try { stream.write(state.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) } catch(e: Exception) { file.failWrite(stream); throw e } }
 fun updateToken(token: String) { require(token.isNotBlank()); runtime.scope.launch { try { registerToken(token) } catch(_: Exception) { }; runtime.kick() } }
 /** Explicit enable waits for the family-registration receipt, not just Firebase token retrieval. */
 suspend fun registerToken(token:String) = withContext(Dispatchers.IO) { mutex.withLock {
  require(token.isNotBlank())
  synchronized(this@FamilyDeviceRegistration) {
   val state=read()
   if(state.optString("token")!=token) { state.put("token",token).remove("bound");save(state) }
  }
  check(notificationsAllowed()) { "Notifications are disabled on this device." }
  reconcileLocked()
 } }
 internal suspend fun reconcile() = mutex.withLock {
  if(!notificationsAllowed()) return@withLock
  reconcileLocked()
 }
 private suspend fun reconcileLocked() {
  val (session,member)=runtime.authorize()
  val state=read(); val token=state.optString("token"); if(token.isBlank()) return
  val binding=session.generation+":"+member.familyId+":"+member.actorId+":"+token
  if(state.optString("bound")==binding) return
  val requestId=UUID.nameUUIDFromBytes(binding.toByteArray(Charsets.UTF_8)).toString()
  check(runtime.current(session))
  val result=runtime.service.rpc("register_family_device",session.token,JSONObject().put("p_installation_id",state.getString("installation")).put("p_token",token).put("p_app",runtime.role).put("p_request_id",requestId))
  check(runtime.current(session)); check(result.optString("request_id")==requestId)
  synchronized(this) { val latest=read(); if(latest.optString("token")==token && runtime.current(session)) { latest.put("bound",binding); save(latest) } }
 }
 internal suspend fun unregister() = mutex.withLock {
  try {
   val s=runtime.local.sessionStore().read() ?: return@withLock
   val active=runtime.token(s); val state=read(); val id=UUID.randomUUID().toString()
   check(runtime.current(s))
   runtime.service.rpc("unregister_family_device",active.token,JSONObject().put("p_installation_id",state.getString("installation")).put("p_request_id",id))
  } finally { synchronized(this) { val state=read(); state.remove("bound"); save(state) } }
 }
}
