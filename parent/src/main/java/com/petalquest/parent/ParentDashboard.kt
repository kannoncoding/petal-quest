package com.petalquest.parent

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.petalquest.core.data.*
import com.petalquest.core.model.Membership
import com.petalquest.core.network.FamilyService
import com.petalquest.core.network.FamilyServiceRejected
import com.petalquest.core.ui.FamilyForegroundRefresh
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import org.json.*
import java.util.Calendar
import java.util.TimeZone
import java.text.SimpleDateFormat
import java.util.Locale

import java.util.UUID

private fun JSONObject.rows(key: String): List<JSONObject> = optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } } ?: emptyList()
private fun JSONObject.words(key: String, fallback: String = "—") = optString(key).takeUnless { it.isBlank() || it=="null" } ?: fallback
private data class ParentAction(val title: String, val rpc: String, val args: JSONObject)

@Composable
fun ParentDashboard(member: Membership, session: Session, service: FamilyService, localData: LocalData, token: suspend () -> String) {
 val scope=rememberCoroutineScope()
 val context=LocalContext.current
 val repository=remember(session.generation) { localData.family(session.userId,session.endpointId) }
 // Scoped preferences keep unresolved action identities across process restarts without credentials.
 val receipts=remember(session.generation) { context.getSharedPreferences("parent-actions-"+session.generation,0) }
 var dashboard by remember { mutableStateOf(JSONObject()) }
 var teen by remember { mutableStateOf("") }
 var date by remember { mutableStateOf(ParentDate.today().toString()) }
 var period by remember { mutableStateOf("Day") }
 var section by remember { mutableStateOf("Review") }
 var busy by remember { mutableStateOf(false) }
 var stale by remember { mutableStateOf(true) }
 var resumeRefreshPending by remember { mutableStateOf(false) }
 var message by remember { mutableStateOf("") }
 var decisionError by remember { mutableStateOf<String?>(null) }
 var note by remember { mutableStateOf("") }
 var cashAmount by remember { mutableStateOf("") }
 var confirmation by remember { mutableStateOf<List<ParentAction>?>(null) }
 var unresolved by remember { mutableStateOf<List<ParentAction>>(emptyList()) }
 var blockedCount by remember { mutableStateOf(0) }
 LaunchedEffect(session.generation,member) {
  val activity=context as? MainActivity
  val intent=activity?.intent
  if(intent?.data?.scheme !in setOf("petalquest","petalquest-reminder")) return@LaunchedEffect
  val currentAccess=withContext(Dispatchers.IO) { runCatching {
   service.memberships(token(),session.userId).any { it.active && it.userId==member.userId && it.familyId==member.familyId && it.actorId==member.actorId && it.role=="parent" } && localData.sessionStore().read()?.generation==session.generation
  }.getOrDefault(false) }
  if(!currentAccess) return@LaunchedEffect
  val bridge=(activity?.application as? PetalApplication)?.reminders
  val reminderAllowed=withContext(Dispatchers.IO) { bridge?.ownershipFor(member)?.let { bridge.runtime.isCurrentOwnership(it,intent?.getStringExtra("reminder_owner")) }==true }
  val familyAllowed=intent?.getStringExtra("family_session")==session.generation && intent.getStringExtra("family_id")==member.familyId
  val target=if(reminderAllowed) intent?.getStringExtra("reminder_date") else if(familyAllowed) intent?.getStringExtra("family_date") else null
  if(target!=null && runCatching { ParentDate.parse(target) }.isSuccess) { date=target;period="Day" }
  if(familyAllowed) {
   intent?.getStringExtra("family_teen")?.let { if(runCatching { java.util.UUID.fromString(it) }.isSuccess) teen=it }
   section=when(intent?.getStringExtra("family_destination")) { "results"->"History";"school"->"School";else->"Review" }
  }
 }
 LaunchedEffect(session.generation) { com.petalquest.core.sync.FamilySync.get()?.refreshes?.collect { stale=true;resumeRefreshPending=true } }
 LaunchedEffect(session.generation) { receipts.getString("unresolved-actions",null)?.let { saved -> val a=JSONArray(saved);unresolved=(0 until a.length()).map { val row=a.getJSONObject(it);ParentAction(row.getString("title"),row.getString("rpc"),row.getJSONObject("args")) } } }
 val cacheKey="parent:"+member.familyId+":"+teen+":"+date+":"+period
 suspend fun reload() {
  stale=true
  withContext(Dispatchers.IO) {
   val a=JSONArray(receipts.getString("unresolved-actions","[]")); unresolved=(0 until a.length()).map { val row=a.getJSONObject(it);ParentAction(row.getString("title"),row.getString("rpc"),row.getJSONObject("args")) }
   blockedCount=com.petalquest.core.sync.FamilySync.get()?.parentBlockedActions(session.generation)?.size ?: 0
  }
  val selected=ParentDate.parse(date)
  val from=when(period) { "Week" -> selected.minusDays((selected.sundayDay).toLong()); "Month" -> selected.withDayOfMonth(1); else -> selected }
  val to=when(period) { "Week" -> from.plusDays(6); "Month" -> from.plusMonths(1).minusDays(1); else -> from }
  val result=service.rpc("get_parent_dashboard",token(),JSONObject().put("p_family_id",member.familyId).put("p_teen_id",teen.takeIf { it.isNotBlank() } ?: JSONObject.NULL).put("p_from",from.toString()).put("p_to",to.toString()))
  check(result.optString("family_id")==member.familyId) { "Family selection changed. Refresh family access." }
  withContext(Dispatchers.IO) { repository.cacheRemoteSnapshot(FamilyRepository.CacheKind.REVIEWS,cacheKey,result.toString()) }
  dashboard=result; stale=false
  com.petalquest.core.sync.FamilySync.get()?.acceptRoutineSnapshot(member,JSONObject(result.toString()).put("_reminder_from",from.toString()).put("_reminder_to",to.toString()))
 }
 fun refresh() { if(busy) return; busy=true; scope.launch { try { reload();message="Updated from family service." } catch(e: CancellationException) { throw e } catch(e: Exception) { stale=true;message="Could not refresh. Saved information is read only. Try again when connected." } finally { busy=false } } }
 FamilyForegroundRefresh(onBackground={stale=true},onReturn={stale=true;resumeRefreshPending=true})
 LaunchedEffect(resumeRefreshPending,busy) {
  if(resumeRefreshPending && !busy) { resumeRefreshPending=false;refresh() }
 }
 LaunchedEffect(cacheKey) {
  stale=true;dashboard=JSONObject();note="";cashAmount="";confirmation=null;busy=true
  try {
   withContext(Dispatchers.IO) { repository.cached(FamilyRepository.CacheKind.REVIEWS,cacheKey)?.canonicalPayload }?.let { dashboard=JSONObject(it) }
   reload()
  } catch(e: CancellationException) { throw e } catch(e: Exception) { stale=true;message="Could not refresh. Saved information is read only. Check the date and connection." } finally { busy=false }
 }
 fun propose(title: String,rpc: String,args: JSONObject) { confirmation=listOf(ParentAction(title,rpc,args)) }
 fun parentLabel(user: String): String { val parents=dashboard.rows("memberships").filter { it.words("role")=="parent" };val index=parents.indexOfFirst { it.words("user_id")==user };return if(user==session.userId) "You" else if(index>=0) "Parent ${index+1}" else "Parent" }
 fun versionLabel(id: String): String { val row=dashboard.rows("rule_versions").firstOrNull { it.words("id")==id };return row?.let { "Rule effective "+it.words("effective_from",it.words("created_at","original schedule")) } ?: "Original saved rule" }
 val selectedTeen=teen.ifBlank { dashboard.words("teen_id","") }
 fun outcomeTitle(row: JSONObject): String { val catalogue=dashboard.optJSONObject("outcome_catalogue");val items=(catalogue?.rows("cash").orEmpty()+catalogue?.rows("privileges").orEmpty()+dashboard.rows("achievements"));return row.optJSONObject("catalogue_snapshot")?.words("title","")?.takeIf { it.isNotBlank() } ?: items.firstOrNull { it.words("id")==row.words("outcome_key") }?.words("title", "Family outcome") ?: "Family outcome" }
 Text("Family dashboard",style=MaterialTheme.typography.titleLarge)
 dashboard.optJSONObject("balance")?.let { balance -> Text("${balance.words("earned_xp","0")} earned XP · ${balance.words("available_coins","0")} available coins");if(balance.optLong("available_coins")<0) Text("Coin debt: new earnings repay this balance. Reward approval is blocked until it is repaid.") }
 Text(if(stale || resumeRefreshPending) "Saved information · reconnect and refresh before making decisions" else "Current family information · server checks each decision")
 OutlinedButton(enabled=!busy,onClick={refresh()}) { Text("Refresh dashboard") }
 if(message.isNotBlank()) Text(message)
 if(blockedCount>0) Text("$blockedCount saved decision(s) need review after a service rejection. Refresh and review the saved decision.")
 dashboard.rows("actors").filter { it.words("role")=="teen" }.forEachIndexed { index,row ->
  OutlinedButton(enabled=!busy && unresolved.isEmpty(),onClick={teen=row.words("actor_id",row.words("id",""))}) { Text("Teen ${index+1}"+(if(selectedTeen==row.words("actor_id",row.words("id",""))) " · selected" else "")) }
 }
 OutlinedTextField(date,{date=it},label={Text("History date (YYYY-MM-DD)")},singleLine=true,enabled=!busy && unresolved.isEmpty())
 Row { listOf("Day","Week","Month").forEach { label -> TextButton(enabled=!busy && unresolved.isEmpty(),onClick={period=label}) { Text(label) } } }
 Row(Modifier.horizontalScroll(rememberScrollState())) { listOf("Review","School","Vacation","Adjust","History","Edit","Access").forEach { label -> TextButton(onClick={section=label}) { Text(label) } } }
 if(unresolved.isNotEmpty()) { Text("An earlier decision needs confirmation from the service. Retry the saved decision before entering another.");OutlinedButton(enabled=!busy && !stale,onClick={confirmation=unresolved}) { Text("Review and retry saved decision") } }
 val enabled=!busy && !stale && !resumeRefreshPending && selectedTeen.isNotBlank() && unresolved.isEmpty()
 if(section=="School") com.petalquest.core.ui.SchoolChecklistScreen(member,selectedTeen,session,service,token)
 if(section=="Vacation") com.petalquest.core.ui.VacationModeControls(dashboard,enabled,service,token,::propose)
 if(section=="Review") {
  Text("Submission decisions",style=MaterialTheme.typography.titleMedium)
  Text("Points shown on duties are contributions. Earned XP and coins are confirmed when a day is published.")
  OutlinedTextField(note,{note=it},label={Text("Decision note")})
  val pending=dashboard.rows("tasks").filter { task -> task.words("status")=="pending" && task.words("submission_id","").isNotBlank() && dashboard.rows("occurrence_corrections").none { it.words("occurrence_id")==task.words("id") } }
  fun review(row: JSONObject,outcome: String)=ParentAction("${outcome.replaceFirstChar { it.uppercase() }}: ${row.words("title_snapshot","Duty")} · ${row.words("local_date")}","review_submission_checked",JSONObject().put("p_expected_version",row.optInt("review_version")).put("p_submission_id",row.getString("submission_id")).put("p_outcome",outcome).put("p_review_note",note.trim()))
  pending.forEach { row ->
   Text(row.words("title_snapshot","Duty"),style=MaterialTheme.typography.titleSmall)
   Text("Original day: ${row.words("local_date")} · ${row.words("points_snapshot",row.words("points"))} points · due ${row.words("due_at","Not specified")}")
   Text("Submitted ${row.words("submitted_at")} · ${if(row.optBoolean("is_late")) "Late submission" else "Original submission recorded"}")
   Text(versionLabel(row.words("rule_version_id")))
   Text("Previous note: ${row.words("review_note","None")}")
   Row { listOf("approved" to "Approve","returned" to "Return","rejected" to "Reject").forEach { (outcome,label) -> TextButton(enabled=enabled,onClick={confirmation=listOf(review(row,outcome))}) { Text(label) } } }
  }
  if(pending.isEmpty()) Text("No pending submissions in this range.")
  OutlinedButton(enabled=enabled && pending.isNotEmpty(),onClick={confirmation=pending.map { review(it,"approved") }}) { Text("Review approval of all ${pending.size} pending submissions") }
  val selectedSummary=dashboard.rows("day_summaries").firstOrNull { it.words("local_date")==date }
  val publicationPreview=selectedSummary?.optJSONObject("preview")
  if(period=="Day" && selectedSummary?.words("status")=="pending" && publicationPreview!=null) {
   Text("Not finalized · service preview for $date",style=MaterialTheme.typography.titleSmall)
   Text("Actual ${publicationPreview.words("actual_score")} · protected ${publicationPreview.words("protected_score")} · remaining virtual ${publicationPreview.words("virtual_remaining")}")
   Text("Expected XP ${publicationPreview.words("earned_xp")} · expected coins ${publicationPreview.words("coins_earned")}")
   Text("Deduction points ${publicationPreview.words("deduction_points","0")} · approved bonus points before deductions ${publicationPreview.words("converted_points","0")}")
  }
  Button(enabled=enabled && period=="Day" && pending.isEmpty() && publicationPreview!=null,onClick={propose("Publish result for $date. Unsubmitted duties contribute zero.\nService preview · actual ${publicationPreview?.words("actual_score")} · protected ${publicationPreview?.words("protected_score")} · expected XP ${publicationPreview?.words("earned_xp")} · expected coins ${publicationPreview?.words("coins_earned")}.\nThe service checks the latest result before publication.","finalize_complete_day",JSONObject().put("p_teen_id",selectedTeen).put("p_local_date",date))}) { Text("Publish this day's result") }
  Text("Resolve pending submissions before publishing. Sealed days cannot change.")
  Text("Duties and approved bonuses supply actual points. Deductions reduce points before XP is calculated; they are not a flat coin charge. Remaining virtual points protect the result without earning XP or coins.")
  Text("Fixed deductions",style=MaterialTheme.typography.titleMedium)
  listOf("dirty-lunchbag" to "Dirty lunchbag · 5", "torn-clothes" to "Torn clothes · 20", "instructions" to "Instructions not followed · 6", "shower-items" to "Shower items forgotten · 4", "messy-items" to "Messy items · 5").forEach { (key,label) ->
   OutlinedButton(enabled=enabled && period=="Day",onClick={propose("Enter $label for $date", "enter_deduction",JSONObject().put("p_teen_id",selectedTeen).put("p_local_date",date).put("p_deduction_key",key).put("p_entry_id",UUID.randomUUID().toString()))}) { Text(label) }
  }
  Text("Reward requests",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("reward_requests").forEach { row ->
   Text("${row.words("title_snapshot",row.words("title","Reward"))} · ${row.words("coin_cost",row.words("price_snapshot"))} coins · ${row.words("status")}")
   val choices=when(row.words("status")) { "requested" -> listOf("approved" to "Approve and debit", "cancelled" to "Decline request"); "approved" -> listOf("fulfilled" to "Mark fulfilled", "cancelled" to "Cancel and refund"); else -> emptyList() }
   choices.forEach { (outcome,label) -> OutlinedButton(enabled=enabled,onClick={propose(label,"review_reward_request",JSONObject().put("p_reward_request_id",row.getString("id")).put("p_outcome",outcome).put("p_note",note.trim()))}) { Text(label) } }
  }
  Text("Cash, achievement and privilege requests",style=MaterialTheme.typography.titleMedium)
  Text("Cash guidance: ₡500 per point above 95. Confirm the actual amount and reason; recording does not transfer money.")
  OutlinedTextField(cashAmount,{cashAmount=it},label={Text("Confirmed cash amount in whole colones")})
  dashboard.rows("extra_outcome_requests").forEach { row ->
   Text("${row.words("kind").replaceFirstChar { it.uppercase() }} · ${outcomeTitle(row)} · ${row.words("target_date")} · ${row.words("status")}")
   Text(row.words("reason","No reason supplied"))
   row.optJSONObject("catalogue_snapshot")?.let { snapshot -> Text(snapshot.words("description",""));if(row.words("kind")=="achievement") Text("Catalogue award: ${snapshot.words("xp",snapshot.words("XP"))} XP · confirmed once by a parent") }
   if(row.words("status")=="requested") Row { listOf("confirmed" to "Confirm", "declined" to "Decline").forEach { (outcome,label) -> TextButton(enabled=enabled && (outcome!="confirmed" || row.words("kind")!="cash" || ((cashAmount.toIntOrNull() ?: -1)>=0 && note.isNotBlank())),onClick={ if(outcome=="confirmed" && row.words("kind")=="cash") propose("Confirm ₡$cashAmount · "+outcomeTitle(row)+" · "+row.words("target_date"),"confirm_cash_outcome",JSONObject().put("p_outcome_request_id",row.getString("id")).put("p_cash_amount",cashAmount.toInt()).put("p_note",note.trim())) else propose(label+" · "+outcomeTitle(row)+" · "+row.words("target_date"),"review_extra_outcome",JSONObject().put("p_outcome_request_id",row.getString("id")).put("p_outcome",outcome).put("p_note",note.trim())) }) { Text(label) } } }
  }
 }
 if(section=="Adjust") ParentAdjustments(dashboard,date,selectedTeen,enabled) { title,rpc,args -> propose(title,rpc,args) }
 if(section=="History") {
  dashboard.rows("day_summaries").forEach { row ->
   Text("${row.words("local_date")} · ${row.words("status")}",style=MaterialTheme.typography.titleMedium)
   if(row.words("status")=="pending") {
    Text("Not finalized · result awaiting publication")
    row.optJSONObject("preview")?.let { preview ->
     Text("Service preview: actual ${preview.words("actual_score")} · protected ${preview.words("protected_score")} · expected XP ${preview.words("earned_xp")} · expected coins ${preview.words("coins_earned")}")
     Text("Remaining virtual ${preview.words("virtual_remaining")} · deduction points ${preview.words("deduction_points","0")} · approved bonus points before deductions ${preview.words("converted_points","0")}")
    }
   } else {
    Text("Actual ${row.words("actual_score")} · virtual ${row.words("virtual_remaining","0")} · protected ${row.words("protected_score")}")
    Text("Earned XP ${row.words("earned_xp")} · coins ${row.words("coins_earned")} · approved bonus points before deductions ${row.words("converted_points","0")}")
    Text(row.words("performance_icon","")+" "+row.words("performance_label",""))
   }
   Text("Published ${row.words("first_published_at")} · seals ${row.words("effective_seal_at")} · revision ${row.words("revision")}")
  }
  dashboard.rows("tasks").forEach { row -> Text("${row.words("local_date")} · ${row.words("title_snapshot","Duty")} · ${row.words("points_snapshot",row.words("points"))} points · ${row.words("status")}");Text(versionLabel(row.words("rule_version_id")));Text("Review note: ${row.words("review_note","None")}") }
  Text("Corrections and bonus history",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("occurrence_corrections").forEach { row ->
   val task=dashboard.rows("tasks").firstOrNull { it.words("id")==row.words("occurrence_id") }
   Text("${task?.words("local_date",date) ?: date} · ${task?.words("title_snapshot","Duty") ?: "Duty"} · ${row.words("outcome")} · ${parentLabel(row.words("parent_user_id"))} · ${row.words("created_at")}")
   Text(row.words("reason","No reason recorded"))
  }
  dashboard.rows("bonus_activities").forEach { row -> Text("${row.words("description")} · ${row.words("status")} · ${row.words("points_snapshot")} points") }
  dashboard.rows("reflection_notes").forEach { row -> Text("Parent reflection · ${row.words("local_date")}");Text(row.words("text","")) }
  Text("Review audit",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("review_history").forEach { row -> Text("${parentLabel(row.words("parent_user_id"))} · ${row.words("created_at",row.words("reviewed_at"))} · ${row.words("outcome",row.words("status"))} · ${row.words("review_note",row.words("note","No note"))}") }
  Text("Deductions",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("deductions").forEach { row -> Text("${row.words("local_date")} · ${row.words("points",row.words("magnitude"))} points · ${row.words("created_at")}") }
  Text("Wallet history",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("wallet_events").forEach { row -> Text("${row.words("local_date",row.words("created_at"))} · XP ${row.words("earned_xp_delta","0")} · coins ${row.words("coin_delta","0")}") }
  Text("Parent decisions",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("parent_actions").forEach { row -> Text("${parentLabel(row.words("parent_user_id"))} · ${row.words("created_at")} · ${row.words("outcome")} · ${row.words("note","No note")}") }
  Text("Result appeals",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("day_appeals").forEach { row -> Text("${row.words("local_date")} · ${row.words("status")} · ${row.words("reason")}") }
 }
 if(section=="Edit") {
  ParentRoutineEditor(dashboard,selectedTeen,enabled) { title,rpc,args -> propose(title,rpc,args.put("p_family_id",member.familyId)) }
  ParentCatalogueEditor(dashboard,enabled) { title,rpc,args -> propose(title,rpc,args.put("p_family_id",member.familyId)) }
 }
 if(section=="Access") {
  Text("Family and device access",style=MaterialTheme.typography.titleMedium)
  dashboard.rows("memberships").forEachIndexed { index,row ->
   Text("Member ${index+1} · ${row.words("role")} · ${if(row.optBoolean("active")) "Active" else "Revoked"}")
   if(row.words("user_id")!=session.userId && row.optBoolean("active")) OutlinedButton(enabled=!busy && !stale,onClick={propose("Revoke access for member ${index+1}","revoke_membership",JSONObject().put("p_family_id",member.familyId).put("p_user_id",row.getString("user_id")))}) { Text("Revoke family access") }
  }
  Text("Registered devices: ${dashboard.rows("devices").size}")
  dashboard.rows("devices").forEachIndexed { index,row -> Text("Device ${index+1} · last registered ${row.words("updated_at")}") }
  OutlinedButton(enabled=enabled,onClick={propose("Replace this teen's device pairing. Existing teen access will be revoked.","issue_teen_replacement",JSONObject().put("p_family_id",member.familyId).put("p_actor_id",selectedTeen))}) { Text("Replace teen device") }
 }
 if(busy) CircularProgressIndicator()
 confirmation?.let { actions -> AlertDialog(onDismissRequest={if(!busy) confirmation=null},title={Text("Confirm family decision")},text={Column(Modifier.heightIn(max=420.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) { Text("${actions.size} action(s). Decisions are recorded by the service.");actions.forEach { Text(it.title) };Text("Note: ${note.ifBlank { "None" }}") }},confirmButton={TextButton(enabled=!busy,onClick={
  busy=true;scope.launch {
   var completed=0
   try {
    unresolved=actions
    fun saveUnresolved() { val saved=JSONArray();unresolved.forEach { a -> saved.put(JSONObject().put("title",a.title).put("rpc",a.rpc).put("args",a.args)) };check(receipts.edit().putString("unresolved-actions",saved.toString()).commit()) }
    saveUnresolved()
    actions.forEach { action ->
     val identity=action.rpc+":"+action.args.toString()
     val operationId=receipts.getString(identity,null) ?: UUID.randomUUID().toString().also { check(receipts.edit().putString(identity,it).commit()) { "Could not save retry identity" } }
     val args=JSONObject(action.args.toString())
     if(action.rpc !in setOf("revoke_membership","issue_teen_replacement")) args.put("p_request_id",operationId)
     val result=service.rpc(action.rpc,token(),args)
     if(action.rpc !in setOf("revoke_membership","issue_teen_replacement")) check(result.optString("request_id")==operationId) { "Response identity not confirmed. Saved decision retained." };receipts.edit().remove(identity).remove("blocked:"+operationId).commit();completed++;unresolved=unresolved.drop(1);saveUnresolved()
     if(action.rpc=="issue_teen_replacement") message="Replacement code: "+result.words("code")+" · expires "+result.words("expires_at")
    }
    if(message.startsWith("Replacement code:").not()) message="$completed action(s) confirmed by the service."
   } catch(e: CancellationException) { throw e } catch(e: Exception) { if(e is FamilyServiceRejected && e.statusCode in 400..499 && e.statusCode!=408 && e.statusCode!=429) { unresolved.firstOrNull()?.let { a -> receipts.getString(a.rpc+":"+a.args.toString(),null)?.let { id -> receipts.edit().putInt("blocked:"+id,e.statusCode).commit() } } };message="$completed action(s) confirmed. "+(e.message ?: "No further change confirmed.")+" Refresh before trying again.";decisionError=message }
   finally { com.petalquest.core.sync.FamilySync.get()?.kick();confirmation=null;try { reload() } catch(e: Exception) { stale=true };busy=false }
  }
 }) { Text("Confirm ${actions.size} action(s)") }},dismissButton={TextButton(enabled=!busy,onClick={confirmation=null}) { Text("Keep reviewing") }}) }
 if(confirmation==null) decisionError?.let { error -> AlertDialog(onDismissRequest={decisionError=null},title={Text("Decision not fully confirmed")},text={Text(error)},confirmButton={TextButton(onClick={decisionError=null}) { Text("OK") }}) }
}

@Composable
private fun ParentCatalogueEditor(data: JSONObject, enabled: Boolean, propose: (String,String,JSONObject)->Unit) {
 var kind by remember { mutableStateOf("task") }
 var selected by remember { mutableStateOf<JSONObject?>(null) }
 var drafts by remember(data) { mutableStateOf<Map<String,JSONObject>>(emptyMap()) }
 var added by remember(data) { mutableStateOf<List<JSONObject>>(emptyList()) }
 var title by remember { mutableStateOf("") };var points by remember { mutableStateOf("") }
 var effective by remember { mutableStateOf("") };var due by remember { mutableStateOf("") };var weekdays by remember { mutableStateOf("") }
 var available by remember { mutableStateOf(true) };var error by remember { mutableStateOf("") }
 LaunchedEffect(data) { selected=null;title="";points="";due="";weekdays="";error="" }
 fun key(row: JSONObject)=row.words("catalogue_key",row.words("id"))
 fun payload(row: JSONObject): JSONObject = drafts[key(row)] ?: JSONObject().put("catalogue_key",key(row)).put("title",row.words("title")).put("points",row.optInt("points")).put("local_due_time",row.words("local_due_time","").takeIf { it.isNotBlank() } ?: JSONObject.NULL).put("weekdays",row.optJSONArray("weekdays") ?: JSONArray()).put("enabled",row.optBoolean("enabled",true))
 Text("Schedule a future catalogue version",style=MaterialTheme.typography.titleMedium)
 Text("Existing submissions and sealed history keep their original rules. Changes must start after today in Costa Rica.")
 Row { listOf("task","reward").forEach { value -> TextButton(onClick={kind=value;selected=null}) { Text(if(value=="task") "Duties and rules" else "Rewards") } } }
 val rows=if(kind=="reward") data.rows("reward_catalogue") else data.rows("task_definitions")+added
 if(kind=="task") OutlinedButton(enabled=enabled,onClick={ val row=JSONObject().put("catalogue_key","parent-duty-"+UUID.randomUUID().toString()).put("title","New duty").put("points",0).put("weekdays",JSONArray(listOf(0,1,2,3,4,5,6))).put("enabled",true);added=added+row;selected=row;title="New duty";points="0";due="";weekdays="0,1,2,3,4,5,6";available=true }) { Text("Add duty") }
 rows.forEach { row -> OutlinedButton(onClick={selected=row;val source=if(kind=="task") payload(row) else row;title=source.words("title");points=source.words(if(kind=="reward") "coinCost" else "points","");due=source.words("local_due_time","");weekdays=source.optJSONArray("weekdays")?.let { a -> (0 until a.length()).joinToString(",") { a.getInt(it).toString() } } ?: "";available=if(kind=="reward") row.words("sourceStatus")=="Available" else source.optBoolean("enabled",true)}) { Text((drafts[key(row)]?.words("title") ?: row.words("title","Duty"))+(if(drafts.containsKey(key(row))) " · edited" else "")) } }
 OutlinedTextField(effective,{effective=it},label={Text("Effective date (YYYY-MM-DD)")})
 selected?.let { row ->
  OutlinedTextField(title,{title=it},label={Text("Title")})
  OutlinedTextField(points,{points=it},label={Text(if(kind=="reward") "Coin price" else "Duty points")})
  if(kind!="reward") { OutlinedTextField(due,{due=it},label={Text("Deadline HH:mm · leave empty if unspecified")});OutlinedTextField(weekdays,{weekdays=it},label={Text("Repeat days: Sunday 0 through Saturday 6, comma separated")}) }
  Row { Text(if(kind=="reward") "Available" else "Enabled"); Switch(available,{available=it}) }
  Button(enabled=enabled,onClick={
   try {
    require(title.isNotBlank());require((points.toIntOrNull() ?: -1)>=0)
    val edited=JSONObject().put("title",title.trim())
    if(kind=="reward") {
     require(ParentDate.parse(effective)>ParentDate.parse(data.words("server_local_date")))
     edited.put("coinCost",points.toInt()).put("sourceStatus",if(available) "Available" else "Unavailable").put("type",row.words("type","reward")).put("tier",row.words("tier",""))
     val prior=data.rows("catalogue_versions").maxByOrNull { it.words("created_at","")+it.words("id","") }
     propose("Save reward version effective $effective","save_catalogue_version",JSONObject().put("p_kind","reward").put("p_catalogue_key",key(row)).put("p_effective_from",effective).put("p_expected_version",prior?.words("id") ?: JSONObject.NULL).put("p_payload",edited))
    } else {
     require(due.isBlank() || Regex("([01][0-9]|2[0-3]):[0-5][0-9]").matches(due));val days=weekdays.split(',').map { it.trim().toInt() };require(days.isNotEmpty() && days.all { it in 0..6 })
     edited.put("catalogue_key",key(row)).put("points",points.toInt()).put("local_due_time",due.takeIf { it.isNotBlank() } ?: JSONObject.NULL).put("weekdays",JSONArray(days.distinct())).put("enabled",available)
     drafts=drafts+(key(row) to edited)
    }
    error=""
   } catch(e: Exception) { error="Check the title, amount, future date, deadline and repeat days." }
  }) { Text(if(kind=="reward") "Review future reward version" else "Apply to duty draft") }
 }
 if(kind=="task" && rows.isNotEmpty()) {
  val all=rows.map { payload(it) }
  val totals=(0..6).map { day -> all.filter { task -> task.optBoolean("enabled") && task.optJSONArray("weekdays")?.let { days -> (0 until days.length()).any { days.optInt(it)==day } }==true }.sumOf { it.optInt("points") } }
  Text("Draft daily totals",style=MaterialTheme.typography.titleSmall)
  Text(listOf("Sun","Mon","Tue","Wed","Thu","Fri","Sat").mapIndexed { i,label -> "$label ${totals[i]}" }.joinToString(" · "))
  Text("Each day must total 100 points. Apply each edited duty to the draft, then save the complete schedule together.")
  Button(enabled=enabled && drafts.isNotEmpty() && totals.all { it==100 },onClick={try {
   require(ParentDate.parse(effective)>ParentDate.parse(data.words("server_local_date")))
   val latest=data.rows("catalogue_versions").maxByOrNull { it.words("created_at","")+it.words("id","") }
   val preview=all.joinToString("\n") { task -> val days=task.optJSONArray("weekdays");val labels=listOf("Sun","Mon","Tue","Wed","Thu","Fri","Sat");val repeats=if(days==null) "" else (0 until days.length()).joinToString(", ") { labels[days.getInt(it)] };"${task.words("title")} · ${task.optInt("points")} points · $repeats · due ${task.words("local_due_time","unspecified")} · ${if(task.optBoolean("enabled")) "enabled" else "archived"}" }
   propose("Save complete duty schedule effective $effective. All seven days total 100 points.\n$preview","save_task_catalogue",JSONObject().put("p_effective_from",effective).put("p_tasks",JSONArray(all)).put("p_expected_version",latest?.words("id") ?: JSONObject.NULL))
   error=""
  } catch(e: Exception) { error="Choose a future effective date." }}) { Text("Review complete future schedule") }
 }
 if(error.isNotBlank()) Text(error)
}
@Composable
private fun ParentAdjustments(data: JSONObject,date: String,teen: String,enabled: Boolean,propose: (String,String,JSONObject)->Unit) {
 var reason by remember(data) { mutableStateOf("") }
 var description by remember(data) { mutableStateOf("") }
 val savedNote=data.rows("reflection_notes").firstOrNull { it.words("local_date")==date }
 var reflection by remember(data,date) { mutableStateOf(savedNote?.words("text","") ?: "") }
 fun revision(day: String)=data.rows("day_summaries").firstOrNull { it.words("local_date")==day }?.let { it.optInt("edit_revision",it.optInt("revision",0)) } ?: 0
 fun originalDay(id: String)=data.rows("tasks").firstOrNull { it.words("id")==id }?.words("local_date",date) ?: date
 Text("Corrections and excused work",style=MaterialTheme.typography.titleMedium)
 Text("Use a reason for every correction. The service checks the current result revision and seal time. Excused points protect the result without earning XP or coins.")
 OutlinedTextField(reason,{reason=it.take(2000)},label={Text("Reason for this decision")})
 val ready=enabled && reason.isNotBlank()
 data.rows("tasks").forEach { row ->
  Text("${row.words("local_date")} · ${row.words("title_snapshot","Duty")} · ${row.words("status")}",style=MaterialTheme.typography.titleSmall)
  val args=JSONObject().put("p_occurrence_id",row.getString("id")).put("p_expected_revision",revision(row.words("local_date"))).put("p_reason",reason.trim())
  Row { listOf("approved" to "Credit", "rejected" to "Remove credit", "excused" to "Excuse").forEach { (outcome,label) -> TextButton(enabled=ready,onClick={propose("$label · ${row.words("title_snapshot","Duty")} · ${row.words("local_date")} · reason: $reason","correct_occurrence",JSONObject(args.toString()).put("p_outcome",outcome))}) { Text(label) } } }
 }
 Text("Offer conversion bonus work",style=MaterialTheme.typography.titleMedium)
 Text("Bonus work can convert excused virtual points into actual points. It must be completed and approved before the original day seals. Conversion days do not receive the perfect-day doubling bonus.")
 OutlinedTextField(description,{description=it.take(2000)},label={Text("Bonus work to complete")})
 data.rows("tasks").filter { task -> data.rows("occurrence_corrections").lastOrNull { it.words("occurrence_id")==task.words("id") }?.words("outcome")=="excused" && data.rows("bonus_activities").none { it.words("occurrence_id")==task.words("id") } }.forEach { row ->
  OutlinedButton(enabled=enabled && description.isNotBlank(),onClick={propose("Offer bonus for ${row.words("title_snapshot","Duty")} · ${row.words("local_date")} · $description","offer_bonus",JSONObject().put("p_occurrence_id",row.getString("id")).put("p_description",description.trim()).put("p_expected_revision",revision(row.words("local_date"))))}) { Text("Offer bonus · "+row.words("title_snapshot","Duty")) }
 }
 data.rows("bonus_activities").forEach { row ->
  val day=row.words("local_date",originalDay(row.words("occurrence_id")))
  Text("$day · ${row.words("description")} · ${row.words("points_snapshot")} points · ${row.words("status")}")
  if(row.words("status") in listOf("submitted","pending","offered","returned")) Row { listOf("approved" to "Approve", "returned" to "Return", "cancelled" to "Cancel").forEach { (outcome,label) -> TextButton(enabled=ready && (outcome=="cancelled" || row.words("status")=="submitted"),onClick={propose("$label bonus for $day · ${row.words("description")} · reason: $reason","review_bonus",JSONObject().put("p_bonus_id",row.getString("id")).put("p_outcome",outcome).put("p_expected_revision",revision(day)).put("p_reason",reason.trim()))}) { Text(label) } } }
 }
 Text("Reverse a deduction",style=MaterialTheme.typography.titleMedium)
 data.rows("deductions").filter { entry -> data.rows("deduction_reversals").none { it.words("entry_id")==entry.words("id") } && !entry.optBoolean("reversed") && entry.isNull("reversed_at") }.forEach { row ->
  OutlinedButton(enabled=ready,onClick={propose("Reverse ${row.words("points",row.words("magnitude"))}-point deduction · ${row.words("local_date")} · reason: $reason","reverse_deduction",JSONObject().put("p_entry_id",row.getString("id")).put("p_expected_revision",revision(row.words("local_date"))).put("p_reason",reason.trim()))}) { Text("Reverse deduction · ${row.words("local_date")} · ${row.words("points",row.words("magnitude"))} points") }
 }
 Text("Resolve an appeal",style=MaterialTheme.typography.titleMedium)
 Text("Apply any justified correction above first. Resolving the appeal records your decision; it does not enter an arbitrary score.")
 data.rows("day_appeals").filter { it.words("status")=="requested" }.forEach { row ->
  Text("${row.words("local_date")} · ${row.words("reason")}")
  Row { listOf("approved" to "Accept appeal", "rejected" to "Decline appeal").forEach { (outcome,label) -> TextButton(enabled=ready,onClick={propose("$label · ${row.words("local_date")} · reason: $reason","resolve_day_appeal",JSONObject().put("p_appeal_id",row.getString("id")).put("p_outcome",outcome).put("p_expected_revision",revision(row.words("local_date"))).put("p_reason",reason.trim()))}) { Text(label) } } }
 }
 Text("Parent reflection note · $date",style=MaterialTheme.typography.titleMedium)
 Text("The teen can read this note. Parents can edit it; it does not change points or private health information.")
 OutlinedTextField(reflection,{reflection=it.take(4000)},label={Text("Family reflection note")})
 Button(enabled=enabled,onClick={propose("Save shared reflection note for $date: $reflection","save_reflection_note",JSONObject().put("p_teen_id",teen).put("p_local_date",date).put("p_text",reflection.trim()).put("p_expected_version",savedNote?.optInt("version",0) ?: 0))}) { Text("Review reflection note") }
}
internal class ParentDate private constructor(private val value: Calendar): Comparable<ParentDate> {
 val sundayDay: Int get()=value.get(Calendar.DAY_OF_WEEK)-1
 fun plusDays(days: Long)=copy().apply { value.add(Calendar.DAY_OF_MONTH,days.toInt()) }
 fun minusDays(days: Long)=plusDays(-days)
 fun plusMonths(months: Long)=copy().apply { value.add(Calendar.MONTH,months.toInt()) }
 fun withDayOfMonth(day: Int)=copy().apply { value.set(Calendar.DAY_OF_MONTH,day) }
 private fun copy()=ParentDate(value.clone() as Calendar)
 override fun compareTo(other: ParentDate)=value.timeInMillis.compareTo(other.value.timeInMillis)
 override fun toString()=format().format(value.time)
 companion object {
  private fun format()=SimpleDateFormat("yyyy-MM-dd",Locale.US).apply { timeZone=TimeZone.getTimeZone("America/Costa_Rica");isLenient=false }
  fun parse(text: String): ParentDate { require(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(text));return ParentDate(Calendar.getInstance(TimeZone.getTimeZone("America/Costa_Rica")).apply { time=format().parse(text)!! }) }
  fun today()=parse(format().format(java.util.Date()))
 }
}
