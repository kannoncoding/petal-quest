package com.petalquest.parent

import androidx.compose.foundation.layout.Row
import androidx.compose.material3.*
import androidx.compose.runtime.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

private fun JSONObject.routineRows(key: String): List<JSONObject> = optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getJSONObject(it) } }.orEmpty()
private fun JSONObject.routineValues(key: String) = optJSONArray(key)?.let { a -> (0 until a.length()).joinToString(",") { a.get(it).toString() } } ?: ""

@Composable
internal fun ParentRoutineEditor(data: JSONObject,teen: String,enabled: Boolean,propose: (String,String,JSONObject)->Unit) {
 val versions=data.routineRows("assigned_routine_versions")
 val latest=versions.groupBy { it.getString("routine_id") }.values.map { rows -> rows.maxBy { it.getInt("version") } }
 fun author(row: JSONObject): String {
  val index=data.routineRows("memberships").filter { it.optString("role")=="parent" }.indexOfFirst { it.optString("user_id")==row.optString("created_by") }
  return if(index>=0) "Parent ${index+1}" else "Parent"
 }
 var selected by remember(teen) { mutableStateOf<JSONObject?>(null) }
 var title by remember(teen) { mutableStateOf("") }
 var times by remember(teen) { mutableStateOf("") }
 var days by remember(teen) { mutableStateOf("") }
 var effective by remember(teen) { mutableStateOf("") }
 var active by remember(teen) { mutableStateOf(true) }
 var error by remember(teen) { mutableStateOf("") }
 fun load(row: JSONObject) {
  selected=row;title=row.optString("title","");times=row.routineValues("local_times");days=row.routineValues("weekdays")
  active=row.optBoolean("active",true);effective="";error=""
 }
 Text("Assigned routines",style=MaterialTheme.typography.titleMedium)
 Text("Routines give no points and need no approval. Times use Costa Rica local time. Sunday is 0; Saturday is 6. Changes start after today.")
 if(!data.has("assigned_routine_versions")) Text("Routine service upgrade required. Refresh after setup.")
 data.routineRows("assigned_routines").forEach { row -> Text("${row.optString("local_date")} · ${row.optString("title")} · ${row.routineValues("local_times")}") }
 latest.forEach { row ->
  Text("${row.optString("title")} · version ${row.optInt("version")} · effective ${row.optString("effective_from")} · ${if(row.optBoolean("active")) "Active" else "Archived"}")
  OutlinedButton(enabled=enabled,onClick={load(row)}) { Text("Edit routine or schedule archive") }
 }
 if(versions.isNotEmpty()) {
  Text("Saved routine versions",style=MaterialTheme.typography.titleSmall)
  versions.forEach { row -> Text("${row.optString("title")} · v${row.optInt("version")} · effective ${row.optString("effective_from")} · ${row.routineValues("local_times")} · days ${row.routineValues("weekdays")} · ${if(row.optBoolean("active")) "Active" else "Archived"} · ${author(row)} · saved ${row.optString("created_at")}") }
 }
 OutlinedButton(enabled=enabled && data.has("assigned_routine_versions"),onClick={load(JSONObject().put("routine_id",UUID.randomUUID().toString()))}) { Text("Add assigned routine") }
 selected?.let { row ->
  OutlinedTextField(title,{title=it.take(200)},label={Text("Routine title")},enabled=enabled)
  OutlinedTextField(times,{times=it},label={Text("Local times HH:mm, comma separated")},enabled=enabled)
  OutlinedTextField(days,{days=it},label={Text("Weekdays 0–6, comma separated")},enabled=enabled)
  OutlinedTextField(effective,{effective=it},label={Text("Future effective date YYYY-MM-DD")},enabled=enabled)
  Row { Text("Active from effective date");Switch(active,{active=it},enabled=enabled) }
  Button(enabled=enabled,onClick={try {
   require(title.isNotBlank())
   val schedule=times.split(',').map { it.trim() }.distinct().sorted()
   require(schedule.size in 1..24 && schedule.all { Regex("([01][0-9]|2[0-3]):[0-5][0-9]").matches(it) })
   val weekdays=days.split(',').map { it.trim().toInt() }.distinct().sorted();require(weekdays.isNotEmpty() && weekdays.all { it in 0..6 })
   val start=ParentDate.parse(effective);require(start>ParentDate.parse(data.getString("server_local_date")))
   if(row.has("effective_from")) require(start>=ParentDate.parse(row.getString("effective_from")))
   val current=latest.firstOrNull { it.getString("routine_id")==row.getString("routine_id") }
   require(current?.optString("id")==row.optString("id").takeIf { it.isNotEmpty() })
   propose("${if(active) "Save" else "Archive"} routine: $title · effective $effective · ${schedule.joinToString(", ")} Costa Rica · weekdays ${weekdays.joinToString(", ")}","save_assigned_routine",JSONObject().put("p_teen_id",teen).put("p_routine_id",row.getString("routine_id")).put("p_expected_version",row.opt("id") ?: JSONObject.NULL).put("p_effective_from",effective).put("p_title",title.trim()).put("p_local_times",JSONArray(schedule)).put("p_weekdays",JSONArray(weekdays)).put("p_active",active))
   error=""
  } catch(e: Exception) { error="Check title, times, weekdays and future date. Refresh and reselect if this version changed." }}) { Text("Review routine change") }
 }
 if(error.isNotBlank()) Text(error)
}
