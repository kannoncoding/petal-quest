package com.example.petalquest

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.petalquest.core.data.*
import com.petalquest.core.model.Membership
import com.petalquest.core.network.FamilyService
import com.petalquest.core.ui.QueuedSubmissions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

private fun JSONArray.rows() = (0 until length()).map { getJSONObject(it) }
private fun JSONObject.rows(key: String) = optJSONArray(key)?.rows().orEmpty()
private fun JSONObject.value(key: String, fallback: String = "—") = optString(key).takeUnless { it.isBlank() || it == "null" } ?: fallback
private val familyZone = TimeZone.getTimeZone("America/Costa_Rica")
private fun dateText(calendar: Calendar) = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone=familyZone }.format(calendar.time)
private fun dueDate(value:String):java.util.Date? = runCatching {
 SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX",Locale.US).parse(value.replace(Regex("\\.\\d+"),""))
}.getOrNull()
private fun dueLabel(value:String):String = dueDate(value)?.let { SimpleDateFormat("h:mm a",Locale.US).apply { timeZone=familyZone }.format(it) } ?: "time not specified"

/** Family-only server facts. Local intent never supplies scores or balances. */
@Composable
internal fun TeenQuestScreen(member: Membership, session: Session, service: FamilyService, token: suspend () -> String, localData: LocalData) {
 val scope=rememberCoroutineScope()
 val repository=remember(member.familyId,session.userId,session.endpointId,session.generation) { localData.family(session.userId,session.endpointId) }
 val submissions=remember(repository,service) { QueuedSubmissions(repository,service) }
 var snapshot by remember { mutableStateOf<JSONObject?>(null) }
 var pending by remember { mutableStateOf(emptyList<PendingOperation>()) }
 var busy by remember { mutableStateOf(false) }
 var message by remember { mutableStateOf("") }
 var stale by remember { mutableStateOf(false) }
 var page by remember { mutableStateOf("Quests") }
 var range by remember { mutableStateOf("Week") }
 var anchor by remember { mutableStateOf(dateText(Calendar.getInstance(familyZone))) }
 var selectedDay by remember { mutableStateOf("") }
 var weekly by remember { mutableStateOf(false) }
 var celebration by remember { mutableStateOf(0) }
 var outcomeDate by remember { mutableStateOf(dateText(Calendar.getInstance(familyZone))) }
 var outcomeReason by remember { mutableStateOf("") }
 var appealReason by remember { mutableStateOf("") }
 fun bounds(): Pair<String,String> {
  val cal=Calendar.getInstance(familyZone).apply { time=SimpleDateFormat("yyyy-MM-dd",Locale.US).apply { timeZone=familyZone }.parse(anchor)!! }
  when(range) { "Week" -> cal.add(Calendar.DATE,-(cal.get(Calendar.DAY_OF_WEEK)-Calendar.SUNDAY)); "Month" -> cal.set(Calendar.DAY_OF_MONTH,1) }
  val from=dateText(cal)
  when(range) { "Week" -> cal.add(Calendar.DATE,6); "Month" -> cal.set(Calendar.DAY_OF_MONTH,cal.getActualMaximum(Calendar.DAY_OF_MONTH)) }
  return from to dateText(cal)
 }
 suspend fun load() {
  val (from,to)=bounds()
  val remote=service.rpc("get_teen_dashboard",token(),JSONObject().put("p_from",from).put("p_to",to))
  check(remote.value("family_id")==member.familyId && remote.value("teen_id")==member.actorId) { "Family access changed. Reconnect to your family." }
  var newlyApproved=false
  withContext(Dispatchers.IO) {
   remote.rows("tasks").forEach { task ->
    val marker=member.familyId+":approval:"+task.value("id")
    val previous=repository.cached(FamilyRepository.CacheKind.REVIEWS,marker)?.let { JSONObject(it.canonicalPayload) }
    if(previous!=null && previous.value("status")!="approved" && task.value("status")=="approved") newlyApproved=true
    repository.cacheRemoteSnapshot(FamilyRepository.CacheKind.REVIEWS,marker,JSONObject().put("status",task.value("status")).toString())
   }
  }
  if(newlyApproved) celebration++
  snapshot=remote;stale=false
  withContext(Dispatchers.IO) { repository.cacheRemoteSnapshot(FamilyRepository.CacheKind.QUESTS,member.familyId+":"+from+":"+to,remote.toString()); pending=repository.pending() }
 }
 fun action(block:suspend () -> Unit) { if(!busy) { busy=true;scope.launch { try { message="";block() } catch(e:CancellationException) { throw e } catch(e:Exception) { message=e.message ?: "No change confirmed. Retry when connected." } finally { try { pending=withContext(Dispatchers.IO) { repository.pending() } } catch(e:CancellationException) { throw e } catch(_:Exception) { pending=emptyList();snapshot=null };busy=false } } } }
 suspend fun dispatch(op:PendingOperation) {
  if(op.kind==FamilyRepository.OperationKind.QUEST_SUBMIT.name) { submissions.retry(op,token());return }
  val payload=JSONObject(op.canonicalPayload)
  if(op.kind==FamilyRepository.OperationKind.BONUS_SUBMIT.name) {
   withContext(Dispatchers.IO) { repository.markDispatched(op.requestId) }
   val result=service.rpc("submit_bonus",token(),JSONObject().put("p_bonus_id",payload.getString("bonus_id")).put("p_request_id",op.requestId))
   check(result.value("request_id")==op.requestId) { "Bonus response not reconciled. Completion remains pending send." }
   withContext(Dispatchers.IO) { repository.acknowledgeServerResult(op.requestId) };return
  }
  if(op.kind==FamilyRepository.OperationKind.DAY_APPEAL_REQUEST.name) {
   withContext(Dispatchers.IO) { repository.markDispatched(op.requestId) }
   val result=service.rpc("request_day_appeal",token(),JSONObject().put("p_request_id",op.requestId).put("p_local_date",payload.getString("local_date")).put("p_reason",payload.getString("reason")))
   check(result.value("request_id")==op.requestId) { "Appeal response not reconciled. Request remains pending send." }
   withContext(Dispatchers.IO) { repository.acknowledgeServerResult(op.requestId) }
   return
  }
  if(op.kind==FamilyRepository.OperationKind.EXTRA_OUTCOME_REQUEST.name) {
   withContext(Dispatchers.IO) { repository.markDispatched(op.requestId) }
   val args=JSONObject().put("p_request_id",op.requestId)
   listOf("kind","outcome_key","target_date","reason").forEach { args.put("p_"+it,payload.getString(it)) }
   val result=service.rpc("request_extra_outcome",token(),args)
   check(result.value("request_id")==op.requestId) { "Response not reconciled. Request remains pending send." }
   withContext(Dispatchers.IO) { repository.acknowledgeServerResult(op.requestId) }
   return
  }
  val cancel=op.kind==FamilyRepository.OperationKind.REWARD_CANCEL.name
  check(cancel || op.kind==FamilyRepository.OperationKind.REWARD_REQUEST.name)
  withContext(Dispatchers.IO) { repository.markDispatched(op.requestId) }
  val result=service.rpc(if(cancel) "cancel_reward_request" else "request_reward",token(),JSONObject().put("p_request_id",op.requestId).put(if(cancel) "p_reward_request_id" else "p_reward_key",payload.getString(if(cancel) "reward_request_id" else "reward_id")))
  check(result.value("request_id")==op.requestId) { "Response not reconciled. Request remains pending send." }
  withContext(Dispatchers.IO) { repository.acknowledgeServerResult(op.requestId) }
 }
 LaunchedEffect(anchor,range) {
  val (from,to)=bounds()
  snapshot=withContext(Dispatchers.IO) { pending=repository.pending(); repository.cached(FamilyRepository.CacheKind.QUESTS,member.familyId+":"+from+":"+to)?.let { JSONObject(it.canonicalPayload) } }; stale=snapshot!=null
  action { service.rpc("materialize_teen_tasks",token(),JSONObject());load() }
 }
 Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
  Text("Your garden",style=MaterialTheme.typography.headlineMedium)
  Text("Costa Rica time · weeks start Sunday")
  Row { listOf("Quests","Rewards","History").forEach { tab -> TextButton(enabled=!busy,onClick={page=tab;if(tab=="Quests") { range="Week";anchor=dateText(Calendar.getInstance(familyZone)) }}) { Text(if(tab==page) "• $tab" else tab) } } }
  if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
  if(stale) Text("Saved server snapshot · refresh to check current status")
  OutlinedButton(enabled=!busy,onClick={action { load() }}) { Text("Refresh confirmed results") }
  if(message.isNotBlank()) Text(message)
  ConfirmedMascot(celebration)
  snapshot?.optJSONObject("balance")?.let { balance ->
   Text("${balance.value("available_coins")} available coins · ${balance.value("earned_xp")} earned XP",style=MaterialTheme.typography.titleMedium)
   Text("Coin rank: ${balance.value("coin_rank",snapshot!!.value("coin_rank","Awaiting confirmed rank"))}")
   Text("Requests are free. Coins are charged once when a parent approves. Spending can change your coin rank; earned XP history stays.")
   if(balance.optLong("available_coins")<0) Text("Your coin balance has debt from a corrected result. New earnings repay it. Reward approvals pause until the debt is repaid.")
  }
  if(pending.isNotEmpty()) {
   Text("Pending send · ${pending.size}",style=MaterialTheme.typography.titleMedium)
   Text("Saved on this device. These requests have no confirmed review or earnings yet.")
   pending.forEach { op ->
    val payload=JSONObject(op.canonicalPayload)
    val subject=when(op.kind) {
     "QUEST_SUBMIT" -> snapshot?.rows("tasks")?.firstOrNull { it.value("id")==payload.value("occurrence_id") }?.value("title_snapshot") ?: "Task completion"
     "EXTRA_OUTCOME_REQUEST" -> "${payload.value("kind")} · ${payload.value("target_date")}"
     "REWARD_CANCEL" -> "Reward cancellation"
     "BONUS_SUBMIT" -> "Bonus completion"
     "DAY_APPEAL_REQUEST" -> "Result appeal · ${payload.value("local_date")}"
     else -> "Reward request"
    }
    Text(subject)
    OutlinedButton(enabled=!busy,onClick={action { dispatch(op);load() }}) { Text("Retry this request") }
   }
  }
  val data=snapshot
  if(data==null) Text("Connect to load your tasks and confirmed rewards.")
  else when(page) {
   "Quests" -> {
    Row { Text("Weekly view");Switch(weekly,{weekly=it},enabled=!busy) }
    Text(if(weekly) "Tasks this Sunday–Saturday" else "Tasks today",style=MaterialTheme.typography.titleLarge)
    val today=if(!stale) data.value("server_local_date",dateText(Calendar.getInstance(familyZone))) else dateText(Calendar.getInstance(familyZone))
    val tasks=data.rows("tasks").filter { weekly || it.value("local_date")==today }
    if(tasks.isEmpty()) Text("No task occurrences in this view. Refresh to check availability.")
    tasks.forEach { task ->
     val id=task.value("id",task.value("occurrence_id")); val queued=pending.any { it.kind=="QUEST_SUBMIT" && JSONObject(it.canonicalPayload).value("occurrence_id")==id }
     Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
      Text(task.value("title_snapshot",task.value("title")),style=MaterialTheme.typography.titleMedium)
      Text("${task.value("local_date")} · ${task.value("points_snapshot")} points · due ${dueLabel(task.value("due_at"))}")
      if(dueDate(task.value("due_at"))?.before(java.util.Date())==true && task.value("status") in listOf("open","returned")) Text("Past due time · a parent decides credit after review")
      val correction=data.rows("occurrence_corrections").lastOrNull { it.value("occurrence_id")==id }
      val status=correction?.value("outcome") ?: task.value("status","open")
      if(correction!=null) Text("Parent correction: ${correction.value("reason","")}")
      Text(if(queued) "Pending send · saved locally" else when(status) { "pending","submitted","pending_review" -> "Awaiting parent review · received by server"; "approved" -> "Approved · earnings confirmed only on day finalization"; "excused" -> "Excused · virtual points protect the result without earning XP or coins"; "open" -> "Ready to complete"; else -> status.replace('_',' ') })
      listOf("review_note","review_notes","decision_note").forEach { field -> if(task.has(field) && !task.isNull(field)) Text("Review: ${task.value(field)}") }
      if(!task.optBoolean("submission_ready",true)) Text(when(task.value("readiness_reason")) {
       "sealed","day_sealed","result_sealed" -> "This day's result is sealed. It can no longer be changed."
       "unresolved_schedule" -> "Your family needs to confirm the schedule before this task can be submitted."
       else -> "This task cannot be submitted in its current state. Refresh to check the latest result."
      })
      if(status in listOf("open","returned")) Button(enabled=!busy && !queued && task.optBoolean("submission_ready",true),onClick={action {
       val op=submissions.enqueue(id);pending=withContext(Dispatchers.IO) { repository.pending() };dispatch(op);load()
      }}) { Text(if(status=="returned") "Resubmit for review" else "Mark completed") }
     } }
    }
    Text("Bonus work",style=MaterialTheme.typography.titleMedium)
    data.rows("bonus_activities").forEach { bonus ->
     val id=bonus.value("id")
     val original=data.rows("tasks").firstOrNull { it.value("id")==bonus.value("occurrence_id") }
     val sealed=data.rows("day_summaries").firstOrNull { it.value("local_date")==bonus.value("local_date",original?.value("local_date") ?: "") }?.value("status")=="sealed" || original?.optBoolean("submission_ready",true)==false
     val queued=pending.any { it.kind=="BONUS_SUBMIT" && JSONObject(it.canonicalPayload).value("bonus_id")==id }
     Text("${bonus.value("local_date",original?.value("local_date") ?: "Original day")} · ${bonus.value("description")} · ${bonus.value("points_snapshot")} points · ${bonus.value("status")}")
     if(bonus.value("status") in listOf("offered","returned")) Button(enabled=!busy && !queued && !sealed,onClick={action {
      val op=withContext(Dispatchers.IO) { repository.pending().firstOrNull { it.kind=="BONUS_SUBMIT" && JSONObject(it.canonicalPayload).value("bonus_id")==id } ?: repository.enqueue(FamilyRepository.OperationKind.BONUS_SUBMIT,JSONObject().put("bonus_id",id).toString()) }
      dispatch(op);load()
     }}) { Text(if(queued) "Bonus completion pending send" else if(sealed) "Original day sealed" else "Mark bonus completed") }
    }
    Text("Bonus completion requires parent review before the original day seals. It converts virtual protection into actual points; conversion days do not receive perfect-day doubling.")
    data.rows("reflection_notes").filter { weekly || it.value("local_date")==today }.forEach { reflection -> Text("Parent reflection · ${reflection.value("local_date")}",style=MaterialTheme.typography.titleSmall);Text(reflection.value("text","")) }
    Text("Completion is a request for review. Parent review and finalized daily earnings are separate.")
   }
   "Rewards" -> {
    Text("Reward shop",style=MaterialTheme.typography.titleLarge)
    data.rows("reward_catalogue").forEach { reward ->
     val id=reward.value("id");val queued=pending.any { it.kind=="REWARD_REQUEST" && JSONObject(it.canonicalPayload).value("reward_id")==id }
     Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp)) {
      Text(reward.value("title"),style=MaterialTheme.typography.titleMedium)
      Text("${reward.value("coinCost",reward.value("coin_cost"))} coins · ${reward.value("type")} · ${reward.value("tier")}")
      Text(reward.value("sourceStatus",reward.value("status","Available")))
      Button(enabled=!busy && !queued && reward.value("sourceStatus","Available").equals("Available",true),onClick={action {
       val op=withContext(Dispatchers.IO) { repository.enqueue(FamilyRepository.OperationKind.REWARD_REQUEST,JSONObject().put("reward_id",id).toString()) };dispatch(op);load()
      }}) { Text(if(queued) "Pending send" else "Request reward · free") }
     } }
    }
    Text("Your reward requests",style=MaterialTheme.typography.titleLarge)
    data.rows("reward_requests").forEach { request ->
     Text("${request.value("title_snapshot",request.value("reward_key"))} · ${request.value("status")} · saved price ${request.value("coin_cost_snapshot",request.value("price_snapshot"))}")
     if(request.value("status") in listOf("requested","pending")) OutlinedButton(enabled=!busy,onClick={action {
      val id=request.getString("id")
      val op=withContext(Dispatchers.IO) { repository.pending().firstOrNull { it.kind=="REWARD_CANCEL" && JSONObject(it.canonicalPayload).value("reward_request_id")==id } ?: repository.enqueue(FamilyRepository.OperationKind.REWARD_CANCEL,JSONObject().put("reward_request_id",id).toString()) };dispatch(op);load()
     }}) { Text("Cancel request · free before approval") }
    }
    Text("Achievements",style=MaterialTheme.typography.titleLarge)
    Text("Ask a parent to confirm an achievement, cash recommendation or privilege. A request does not grant coins, cash or access.")
    Text("Cash and privilege entries are catalogue references. This form does not calculate an amount from a daily score; a parent confirms eligibility and any amount. The history icon separately uses protected score.")
    OutlinedTextField(outcomeDate,{outcomeDate=it},label={Text("Request date · YYYY-MM-DD")},singleLine=true)
    OutlinedTextField(outcomeReason,{outcomeReason=it.take(1000)},label={Text("Reason for parent review · optional")})
    val outcomes=data.rows("achievements").map { "achievement" to it } +
     data.optJSONObject("outcome_catalogue")?.rows("cash").orEmpty().map { "cash" to it } +
     data.optJSONObject("outcome_catalogue")?.rows("privileges").orEmpty().map { "privilege" to it }
    outcomes.forEach { (kind,item) ->
     val id=item.value("id")
     val queued=pending.any { it.kind=="EXTRA_OUTCOME_REQUEST" && JSONObject(it.canonicalPayload).let { payload -> payload.value("outcome_key")==id && payload.value("target_date")==outcomeDate } }
     Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp)) {
      Text(item.value("title"),style=MaterialTheme.typography.titleMedium)
      if(kind=="achievement") Text("${item.value("xp")} XP · ${item.value("sourceCondition")}") else Text(item.value("description"))
      Button(enabled=!busy && !queued && outcomeDate.matches(Regex("\\d{4}-\\d{2}-\\d{2}")),onClick={action {
       val op=withContext(Dispatchers.IO) { repository.enqueue(FamilyRepository.OperationKind.EXTRA_OUTCOME_REQUEST,JSONObject().put("kind",kind).put("outcome_key",id).put("target_date",outcomeDate).put("reason",outcomeReason.trim()).toString()) }
       dispatch(op);load()
      }}) { Text(if(queued) "Pending send" else "Request parent confirmation") }
     } }
    }
    Text("Your confirmation requests",style=MaterialTheme.typography.titleMedium)
    data.rows("extra_outcome_requests").forEach { request ->
     val title=outcomes.firstOrNull { it.second.value("id")==request.value("outcome_key") }?.second?.value("title") ?: request.value("kind")
     Text("$title · ${request.value("target_date")} · ${request.value("status")}\n${request.value("reason","")}")
    }
    Text("Tracker guidance",style=MaterialTheme.typography.titleLarge)
    Text("Benefits, cash guidance and consequences below are tracker references. A parent confirms benefits and records any cash amount manually. Actual-score earnings and conversion rules apply.")
    data.optJSONObject("tracker_rules")?.rows("rules")?.filter { it.value("sheet").contains("Accountability") }?.forEach { sheet ->
     val values=sheet.optJSONArray("values") ?: JSONArray()
     for(index in 0 until values.length()) {
      val row=values.optJSONArray(index) ?: continue
      val cells=(0 until row.length()).mapNotNull { cell -> if(row.isNull(cell)) null else row.optString(cell).takeIf { it.isNotBlank() } }
      if(cells.isNotEmpty()) Text(cells.joinToString(" · "))
     }
    }
    Text("Coin rank uses available coins. Tracker rank catalogue: Base, Silver, Gold, Ruby, Sapphire, Emerald, Diamond. Rank thresholds await confirmed service policy when no rank is supplied.")
   }
   else -> {
    Text("Performance history",style=MaterialTheme.typography.titleLarge)
    Row { listOf("Day","Week","Month").forEach { unit -> TextButton(enabled=!busy,onClick={range=unit;selectedDay=""}) { Text(if(range==unit) "• $unit" else unit) } } }
    Row {
     TextButton(enabled=!busy,onClick={ val cal=Calendar.getInstance(familyZone).apply { time=SimpleDateFormat("yyyy-MM-dd",Locale.US).apply { timeZone=familyZone }.parse(anchor)!! };cal.add(if(range=="Month") Calendar.MONTH else Calendar.DATE,if(range=="Week") -7 else -1);anchor=dateText(cal);selectedDay="" }) { Text("Previous") }
     TextButton(enabled=!busy,onClick={anchor=dateText(Calendar.getInstance(familyZone));selectedDay=""}) { Text("Today") }
     TextButton(enabled=!busy,onClick={ val cal=Calendar.getInstance(familyZone).apply { time=SimpleDateFormat("yyyy-MM-dd",Locale.US).apply { timeZone=familyZone }.parse(anchor)!! };cal.add(if(range=="Month") Calendar.MONTH else Calendar.DATE,if(range=="Week") 7 else 1);anchor=dateText(cal);selectedDay="" }) { Text("Next") }
    }
    Text("${bounds().first} — ${bounds().second}")
    val days=data.rows("day_summaries")
    if(days.isEmpty()) Text("No confirmed results in this period. Missing days are not bad days.")
    days.forEach { day ->
     val status=day.value("status","pending")
     OutlinedButton(onClick={selectedDay=day.value("local_date")}) { Text("${day.value("local_date")} · ${if(status=="pending") "Pending result" else day.value("performance_icon")+" "+day.value("performance_label")} · $status") }
     if(selectedDay==day.value("local_date")) {
      Text("Actual ${day.value("actual_score")} · virtual protection ${day.value("virtual_remaining")} · protected score ${day.value("protected_score")}")
      Text("Earned ${day.value("earned_xp")} XP · ${day.value("coins_earned")} coins · seals ${day.value("effective_seal_at")}")
      Text("Below 85 actual points earns zero. Converted virtual points never receive perfect-day doubling. The daily icon uses protected score.")
      Text("Approved bonus points before deductions: ${day.value("converted_points",day.value("converted_score"))} · deduction points ${day.value("deduction_points")}")
      Text("Deductions reduce points before XP is calculated. Actual points can earn XP; remaining virtual points protect the result without earning XP or coins.")
      day.rows("conversion_history").forEach { Text("Approved bonus points before deductions: ${it.value("points")} · ${it.value("created_at")}") }
      data.rows("tasks").filter { it.value("local_date")==selectedDay }.forEach { Text("${it.value("title_snapshot",it.value("title"))} · ${it.value("status")} · ${it.value("review_note","")}") }
      data.rows("reflection_notes").filter { it.value("local_date")==selectedDay }.forEach { reflection -> Text("Parent reflection",style=MaterialTheme.typography.titleSmall);Text(reflection.value("text","")) }
      val dayTaskIds=data.rows("tasks").filter { it.value("local_date")==selectedDay }.map { it.value("id") }.toSet()
      data.rows("occurrence_corrections").filter { it.value("occurrence_id") in dayTaskIds }.forEach { correction -> Text("Correction · ${correction.value("outcome")} · ${correction.value("created_at")}\n${correction.value("reason","")}") }
      data.rows("bonus_activities").filter { it.value("occurrence_id") in dayTaskIds }.forEach { bonus -> Text("Bonus · ${bonus.value("description")} · ${bonus.value("status")} · ${bonus.value("points_snapshot")} points") }
      val submissionsForDay=data.rows("tasks").filter { it.value("local_date")==selectedDay }.map { it.value("submission_id") }.toSet()
      data.rows("review_history").filter { it.value("submission_id") in submissionsForDay }.forEach { review ->
       Text("Review · ${review.value("outcome")} · ${review.value("reviewed_at")}\n${review.value("review_note","")}")
      }
      (data.rows("deductions")+day.rows("deductions")).filter { it.value("local_date",selectedDay)==selectedDay }.forEach { Text("Deduction: ${it.value("title",it.value("deduction_key"))} · ${it.value("points")} points · ${it.value("created_at")}") }
      val appeals=data.rows("day_appeals").filter { it.value("local_date")==selectedDay }
      appeals.forEach { appeal -> Text("Appeal · ${appeal.value("status")}\n${appeal.value("reason")}\nDeadline: ${appeal.value("effective_seal_at")}") }
      val queued=pending.any { it.kind=="DAY_APPEAL_REQUEST" && JSONObject(it.canonicalPayload).value("local_date")==selectedDay }
      if(status=="finalized" && appeals.isEmpty()) {
       OutlinedTextField(appealReason,{appealReason=it.take(1000)},label={Text("Why should this result be reviewed?")})
       Button(enabled=!busy && !queued && appealReason.isNotBlank(),onClick={action {
        val op=withContext(Dispatchers.IO) { repository.enqueue(FamilyRepository.OperationKind.DAY_APPEAL_REQUEST,JSONObject().put("local_date",selectedDay).put("reason",appealReason.trim()).toString()) }
        dispatch(op);appealReason="";load()
       }}) { Text(if(queued) "Appeal pending send" else "Ask parent to review result") }
       Text("Appeals must reach the service before sealing. Unresolved appeals expire when the day seals. Asking for review does not change XP or coins.")
      }
     }
    }
   }
  }
  snapshot?.optJSONObject("readiness")?.let { readiness ->
   Text("Availability",style=MaterialTheme.typography.titleMedium)
   val notices=mapOf(
    "qualification_policy_required" to "A parent must confirm achievement qualifications; requests do not grant an award.",
    "effective_date_policy_required" to "Past task generation needs an agreed start date; recorded history remains available."
   )
   readiness.keys().forEach { key -> notices[readiness.value(key)]?.let { Text(it) } }
  }
 }
}
