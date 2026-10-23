package com.petalquest.core.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.petalquest.core.model.Membership
import com.petalquest.core.data.Session
import com.petalquest.core.network.FamilyService
import com.petalquest.core.network.FamilyServiceRejected
import com.petalquest.core.sync.FamilySync
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import org.json.*
import java.util.UUID

/** Non-scoring school checklist. Parent approvals apply to Teen edits/removal, never completion. */
@Composable
fun SchoolChecklistScreen(member:Membership,teenId:String,session:Session,service:FamilyService,token:suspend()->String) {
 val context=LocalContext.current
 val prefs=remember(session.generation) { context.getSharedPreferences("school-actions-${session.generation}",Context.MODE_PRIVATE) }
 val scope=rememberCoroutineScope()
 var data by remember(teenId) { mutableStateOf<JSONObject?>(null) }
 var busy by remember { mutableStateOf(false) }
 var stale by remember { mutableStateOf(true) }
 var message by remember { mutableStateOf("") }
 var editing by remember { mutableStateOf<JSONObject?>(null) }
 var title by remember { mutableStateOf("") }
 var showEditor by remember { mutableStateOf(false) }
 var pending by remember { mutableStateOf<String?>(prefs.getString("pending",null)) }
 fun rows(key:String):List<JSONObject> = data?.optJSONArray(key)?.let { a->(0 until a.length()).map { a.getJSONObject(it) } }.orEmpty()
 suspend fun load() {
  val result=service.rpc("list_school_items",token(),JSONObject().put("p_family_id",member.familyId).put("p_teen_id",teenId))
  check(result.getString("family_id")==member.familyId && result.getString("teen_id")==teenId)
  data=result;stale=false;pending=prefs.getString("pending",null)
  FamilySync.get()?.acceptSchoolSnapshot(member,result)
 }
 fun run(block:suspend()->Unit) { if(busy) return;busy=true;scope.launch {
  try { block();message="" } catch(e:CancellationException) { throw e } catch(e:Exception) { stale=true;message=e.message ?: "Could not confirm. Refresh or retry when online." } finally { busy=false;FamilySync.get()?.kick() }
 } }
 suspend fun send(args:JSONObject) {
  val saved=args.toString()
  check(prefs.getString("pending",null).let { it==null || it==saved }) { "Resolve the saved request before starting another." }
  withContext(Dispatchers.IO) { check(prefs.edit().putString("pending",saved).commit()) }
  pending=saved
  try {
   val result=service.rpc("school_item_action",token(),args)
   check(result.optString("request_id")==args.getString("p_request_id"))
   withContext(Dispatchers.IO) { synchronized(prefs) { if(prefs.getString("pending",null)==saved) prefs.edit().remove("pending").remove("blocked").commit() } }
   pending=null;load()
  } catch(e:FamilyServiceRejected) {
   if(e.statusCode in 400..499 && e.statusCode !in setOf(401,408,429)) prefs.edit().putBoolean("blocked",true).commit()
   throw e
  }
 }
 fun args(item:JSONObject?,action:String,text:String?=null,change:JSONObject?=null)=JSONObject()
  .put("p_family_id",member.familyId).put("p_teen_id",teenId).put("p_item_id",item?.getString("id") ?: UUID.randomUUID().toString())
  .put("p_action",action).put("p_title",text ?: JSONObject.NULL).put("p_expected_version",item?.getInt("version") ?: JSONObject.NULL)
  .put("p_request_id",UUID.randomUUID().toString()).put("p_change_id",change?.getString("id") ?: JSONObject.NULL)
 LaunchedEffect(teenId) { if(teenId.isNotBlank()) run { load() } }
 LaunchedEffect(session.generation,teenId) { FamilySync.get()?.refreshes?.collect { if(!busy && teenId.isNotBlank()) run { load() } } }
 Text("At school",style=MaterialTheme.typography.headlineSmall)
 Text("Talk to a teacher, deliver a permission slip or follow up on an activity. This checklist has no XP.")
 Text("Weekdays · 06:55, 08:21, 09:46, 11:26, 12:11 and 13:31 · through November 27")
 if(teenId.isBlank()) { Text("Select a Teen to view school items.");return }
 if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
 if(stale) Text("Refresh to check the current school checklist.")
 if(message.isNotBlank()) Text(message)
 TextButton(enabled=!busy,onClick={run { load() }}) { Text("Refresh school items") }
 if(pending!=null) {
  Text("A saved school request needs confirmation. It will retry when connected.")
  TextButton(enabled=!busy,onClick={run { send(JSONObject(pending!!)) }}) { Text("Retry saved request") }
  if(prefs.getBoolean("blocked",false)) TextButton(enabled=!busy,onClick={prefs.edit().remove("pending").remove("blocked").apply();pending=null}) { Text("Dismiss rejected request") }
 }
 val enabled=!busy && !stale && pending==null && data?.optBoolean("school_active")==true
 val canReview=!busy && !stale && pending==null
 if(data?.optBoolean("school_active")==false) Text("School reminders ended November 27. Recorded items remain available.")
 Button(enabled=enabled,onClick={editing=null;title="";showEditor=true}) { Text("Add school item") }
 val items=rows("items").filter { !it.optBoolean("removed") }
 if(items.none { !it.optBoolean("completed") }) Text("No pending school items.")
 items.sortedBy { it.optBoolean("completed") }.forEach { item ->
  val changes=rows("changes").filter { it.optString("item_id")==item.getString("id") && it.optString("status")=="pending" }
  Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
   Text(item.getString("title"),style=MaterialTheme.typography.titleMedium)
   Text(if(item.optBoolean("completed")) "Completed" else "Pending · reminders continue at the next school break")
   if(!item.optBoolean("completed")) Button(enabled=enabled,onClick={run { send(args(item,"complete")) }}) { Text("Mark completed") }
   Row {
    TextButton(enabled=enabled && changes.isEmpty(),onClick={editing=item;title=item.getString("title");showEditor=true}) { Text(if(member.role=="parent") "Edit" else "Request edit") }
    TextButton(enabled=enabled && changes.isEmpty(),onClick={run { send(args(item,"remove")) }}) { Text(if(member.role=="parent") "Remove" else "Request removal") }
   }
   changes.forEach { change ->
    Text(if(change.optString("action")=="remove") "Removal awaiting Parent approval" else "Edit awaiting Parent approval: ${change.optString("proposed_title")}")
    if(member.role=="parent") Row {
     TextButton(enabled=canReview,onClick={run { send(args(item,"approve",change=change)) }}) { Text("Approve change") }
     TextButton(enabled=canReview,onClick={run { send(args(item,"reject",change=change)) }}) { Text("Keep original") }
    }
   }
  } }
 }
 if(showEditor) AlertDialog(onDismissRequest={if(!busy) showEditor=false},title={Text(if(editing==null) "New school item" else "Edit school item")},text={Column {
  OutlinedTextField(title,{title=it.take(200)},label={Text("What needs to be done?")})
  if(editing!=null && member.role=="teen") Text("The original stays in place until a Parent approves this change.")
 }},confirmButton={TextButton(enabled=enabled && title.isNotBlank(),onClick={val operation=args(editing,if(editing==null) "create" else "edit",title.trim());showEditor=false;run { send(operation) }}) { Text(if(editing!=null && member.role=="teen") "Request change" else "Save") }},dismissButton={TextButton(onClick={showEditor=false}) { Text("Cancel") }})
}
