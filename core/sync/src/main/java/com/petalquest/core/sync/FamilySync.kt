package com.petalquest.core.sync

import android.content.Context
import androidx.work.*
import com.petalquest.core.data.*
import com.petalquest.core.model.*
import com.petalquest.core.network.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Install from Application.onCreate so WorkManager can restore persisted work after process death. */
class FamilySync private constructor(val context: Context, val config: ServiceConfig, val local: LocalData, val role: String) {
 companion object {
  @Volatile private var instance: FamilySync? = null
  fun install(context: Context, config: ServiceConfig, local: LocalData, role: String): FamilySync {
   require(role in setOf("parent", "teen"))
   return synchronized(this) { instance ?: FamilySync(context.applicationContext, config, local, role).also { instance=it; it.kick() } }
  }
  fun get(): FamilySync? = instance
 }
 internal val scope = CoroutineScope(SupervisorJob()+Dispatchers.IO)
 internal val service=FamilyService(config)
 private val signals=MutableSharedFlow<Unit>(extraBufferCapacity=1)
 val refreshes=signals.asSharedFlow()
 private var debounce: Job?=null
 @Volatile internal var foreground=false
 @Volatile private var member: Membership?=null
 @Volatile private var endingSession=false
 internal fun deliveryBlocked()=endingSession
 private val realtime=FamilyRealtime(this)
 val registration=FamilyDeviceRegistration(this)
 @Volatile private var routineSink: ((Membership,JSONObject)->Unit)?=null
 @Volatile private var ownershipSink: (suspend (Session?,Membership?)->Unit)?=null
 @Volatile private var reminderSnapshot:Triple<String,Membership,JSONObject>?=null
 fun setOwnershipSink(sink: suspend (Session?,Membership?)->Unit) { ownershipSink=sink }
 fun currentMembership(): Membership? = member
 fun currentSession(): Session? = local.sessionStore().read()
 fun setRoutineSink(sink: (Membership,JSONObject)->Unit) { routineSink=sink }
 /** Authoritative dashboard supplied by UI or a foreground refresh; never accepts push data. */
 fun acceptRoutineSnapshot(membership: Membership, dashboard: JSONObject) {
  if(member==membership) {
   if(dashboard.has("_reminder_from")) local.sessionStore().read()?.let { reminderSnapshot=Triple(it.generation,membership,JSONObject(dashboard.toString())) }
   routineSink?.invoke(membership,dashboard)
  }
 }
 fun acceptSchoolSnapshot(membership:Membership,school:JSONObject) {
  scope.launch {
   val s=local.sessionStore().read() ?: return@launch
   val previous=reminderSnapshot ?: return@launch
   if(previous.first!=s.generation || previous.second!=membership || member!=membership || school.optString("family_id")!=membership.familyId) return@launch
   if(role=="teen" && school.optString("teen_id")!=membership.actorId) return@launch
   val merged=JSONObject(previous.third.toString()).put("school_checklist",school)
   acceptRoutineSnapshot(membership,merged)
  }
 }
 fun parentBlockedActions(generation: String): Map<String,Int> = context.getSharedPreferences("parent-actions-$generation",Context.MODE_PRIVATE).all
  .filterKeys { it.startsWith("blocked:") }.mapValues { (it.value as? Int) ?: 400 }
 fun bind(membership: Membership) { require(membership.active && membership.role==role); endingSession=false; member=membership; kick() }
 internal fun hint() { synchronized(this) { debounce?.cancel(); debounce=scope.launch { delay(350); signals.emit(Unit) } } }
 fun onForeground() { foreground=true; scope.launch { try { val (s,m)=authorize(); if(foreground) realtime.start(); registration.reconcile();
  refreshReminderSnapshot(); hint(); kick() } catch(e: CancellationException) { throw e } catch (e: Exception) { realtime.close(); if(e is FamilyAccessDenied || e is FamilyServiceRejected && e.statusCode in setOf(401,403)) { FamilyPushNotifications.clear(context) { member=null }; ownershipSink?.invoke(null,null) }; hint() } } }
 fun onBackground() { foreground=false; realtime.close() }
 /** Worker/foreground refresh uses authorized facts; cached push data never supplies schedules. */
 suspend fun refreshReminderSnapshot() {
  if(routineSink==null) return
  val (s,m)=authorize()
  val calendar=java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("America/Costa_Rica"))
  val format=java.text.SimpleDateFormat("yyyy-MM-dd",java.util.Locale.ROOT).also { it.timeZone=calendar.timeZone }
  calendar.add(java.util.Calendar.DAY_OF_MONTH,-1)
  val from=format.format(calendar.time);calendar.add(java.util.Calendar.DAY_OF_MONTH,14)
  val to=format.format(calendar.time)
  val args=JSONObject().put("p_from",from).put("p_to",to)
  if(role=="parent") args.put("p_family_id",m.familyId).put("p_teen_id",JSONObject.NULL)
  val data=service.rpc(if(role=="parent") "get_parent_dashboard" else "get_teen_dashboard",s.token,args)
   .put("_reminder_from",from).put("_reminder_to",to)
  try {
   val teen=if(role=="teen") m.actorId else data.optString("teen_id")
   if(teen.isNotBlank()) data.put("school_checklist",service.rpc("list_school_items",s.token,JSONObject().put("p_family_id",m.familyId).put("p_teen_id",teen)))
  } catch(e:CancellationException) { throw e } catch(_:Exception) { /* Keep the existing school schedule if its refresh is unavailable. */ }
  if(current(s)) acceptRoutineSnapshot(m,data)
 }
 fun kick() { scope.launch { val s=local.sessionStore().read() ?: return@launch
  if(s.endpointId!=Session.normalizeEndpoint(config.url)) return@launch
  reminderSnapshot?.takeIf { it.first==s.generation && it.second==member }?.let { routineSink?.invoke(it.second,it.third) }
  val data=workDataOf("user" to s.userId,"endpoint" to s.endpointId,"generation" to s.generation)
  val request=OneTimeWorkRequestBuilder<FamilySyncWorker>().setInputData(data).addTag("family-sync")
   .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
   .setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build()
  WorkManager.getInstance(context).enqueueUniqueWork("family-sync-${s.generation}",ExistingWorkPolicy.KEEP,request)
  // A bounded periodic safety pass covers an enqueue racing a running KEEP worker's final read.
  val recovery=PeriodicWorkRequestBuilder<FamilySyncWorker>(15,TimeUnit.MINUTES).setInputData(data).addTag("family-sync")
   .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
   .setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build()
  WorkManager.getInstance(context).enqueueUniquePeriodicWork("family-sync-recovery-${s.generation}",ExistingPeriodicWorkPolicy.KEEP,recovery)
 } }
 internal fun current(expected: Session): Boolean { val s=local.sessionStore().read(); return s!=null && s.userId==expected.userId && s.endpointId==expected.endpointId && s.generation==expected.generation }
 internal suspend fun token(expected: Session, force: Boolean=false): Session {
  check(current(expected)) { "Session changed" }
  if(!force && !expected.isExpired && expected.expiresAtEpochSeconds>System.currentTimeMillis()/1000+60) return expected
  val fresh=service.refresh(expected.refreshToken)
  check(current(expected))
  val replacement=Session(fresh.userId,expected.endpointId,fresh.accessToken,fresh.refreshToken,fresh.expiresAtEpochSeconds)
  check(local.sessionStore().refreshIfCurrent(expected,replacement))
  return local.sessionStore().read()!!.also { check(current(expected)) }
 }
 internal suspend fun authorize(): Pair<Session,Membership> {
  check(!endingSession) { "Signed out" }
  val initial=local.sessionStore().read() ?: error("Signed out")
  check(initial.endpointId==Session.normalizeEndpoint(config.url))
  val s=token(initial)
  val memberships=service.memberships(s.token,s.userId)
  check(current(initial) && !endingSession)
  val selected=member
  val candidates=memberships.filter { it.active && it.role==role && (selected==null || it.familyId==selected.familyId && it.actorId==selected.actorId) }
  if(candidates.isEmpty()) { realtime.close(); FamilyPushNotifications.clear(context) { member=null }; ownershipSink?.invoke(null,null); throw FamilyAccessDenied() }
  val match=candidates.singleOrNull() ?: error("Select current family access")
  member=match; ownershipSink?.invoke(s,match); return s to match
 }
 suspend fun logout() { withContext(Dispatchers.IO) {
  foreground=false; realtime.close()
  FamilyPushNotifications.clear(context) { endingSession=true; member=null;reminderSnapshot=null }
  WorkManager.getInstance(context).cancelAllWorkByTag("family-sync")
  try { ownershipSink?.invoke(null,null); registration.unregister() } catch (_: Exception) { } finally { local.logout(); hint() }
 } }
 internal suspend fun drain(expected: Session): Boolean {
  val (s,_)=authorize(); check(current(expected))
  val repository=local.family(s.userId,s.endpointId)
  var retry=false
  for(op in repository.pending()) {
   if(op.status.startsWith("needs_review")) continue
   val payload=JSONObject(op.canonicalPayload)
   val args=JSONObject().put("p_request_id",op.requestId)
   val rpc=when(op.kind) {
    "QUEST_SUBMIT" -> { args.put("p_occurrence_id",payload.getString("occurrence_id")); "submit_occurrence" }
    "BONUS_SUBMIT" -> { args.put("p_bonus_id",payload.getString("bonus_id")); "submit_bonus" }
    "REWARD_REQUEST" -> { args.put("p_reward_key",payload.getString("reward_id")); "request_reward" }
    "REWARD_CANCEL" -> { args.put("p_reward_request_id",payload.getString("reward_request_id")); "cancel_reward_request" }
    "DAY_APPEAL_REQUEST" -> { listOf("local_date","reason").forEach { args.put("p_$it",payload.get(it)) }; "request_day_appeal" }
    "EXTRA_OUTCOME_REQUEST" -> { listOf("kind","outcome_key","target_date","reason").forEach { args.put("p_$it",payload.get(it)) }; "request_extra_outcome" }
    else -> continue
   }
   try {
    val active=token(local.sessionStore().read()!!.also { check(current(expected)) })
    check(current(expected)); repository.markDispatched(op.requestId)
    val result=service.rpc(rpc,active.token,args)
    check(current(expected))
    if(result.optString("request_id")==op.requestId) { repository.acknowledgeServerResult(op.requestId); hint() } else retry=true
   } catch(e: FamilyServiceRejected) {
    check(current(expected))
    if(e.statusCode==401) token(local.sessionStore().read()!!.also { check(current(expected)) },true)
    if(e.statusCode in 400..499 && e.statusCode !in setOf(401,408,429)) { repository.blockAutomaticRetry(op.requestId,e.statusCode); hint() } else retry=true
   }
  }
  if(role=="parent") retry=ParentConfirmedRetries(this).drain(expected) || retry
  val school=context.getSharedPreferences("school-actions-${expected.generation}",Context.MODE_PRIVATE)
  val saved=school.getString("pending",null)
  if(saved!=null && !school.getBoolean("blocked",false)) {
   val args=JSONObject(saved)
   val keys=setOf("p_family_id","p_teen_id","p_item_id","p_action","p_title","p_expected_version","p_request_id","p_change_id")
   if(args.keys().asSequence().toSet()==keys) try {
    val active=token(local.sessionStore().read()!!.also { check(current(expected)) })
    val result=service.rpc("school_item_action",active.token,args)
    check(current(expected))
    if(result.optString("request_id")==args.optString("p_request_id")) {
     synchronized(school) { if(school.getString("pending",null)==saved) school.edit().remove("pending").remove("blocked").commit() };hint()
    } else retry=true
   } catch(e:FamilyServiceRejected) {
    check(current(expected))
    if(e.statusCode in 400..499 && e.statusCode !in setOf(401,408,429)) { school.edit().putBoolean("blocked",true).commit();hint() } else retry=true
   }
  }
  registration.reconcile(); refreshReminderSnapshot(); return retry
 }
}

private class FamilyAccessDenied: IllegalStateException("Current family access is unavailable")

class FamilySyncWorker(context: Context, params: WorkerParameters): CoroutineWorker(context,params) {
 override suspend fun doWork(): Result {
  val runtime=FamilySync.get() ?: return Result.retry()
  return try {
   val s=runtime.local.sessionStore().read() ?: return Result.success()
   if(s.userId!=inputData.getString("user") || s.endpointId!=inputData.getString("endpoint") || s.generation!=inputData.getString("generation")) return Result.success()
   if(runtime.drain(s)) Result.retry() else Result.success()
  } catch(e: CancellationException) { throw e } catch(_: Exception) { Result.retry() }
 }
}
