package com.petalquest.core.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.petalquest.core.network.FamilyService
import kotlinx.coroutines.*
import org.json.*

@Composable
fun VacationModeControls(data:JSONObject,enabled:Boolean,service:FamilyService,token:suspend()->String,
 propose:(String,String,JSONObject)->Unit) {
 val scope=rememberCoroutineScope()
 var start by remember { mutableStateOf("2026-11-28") }
 var end by remember { mutableStateOf("") }
 var schoolFrom by remember { mutableStateOf("") }
 var preview by remember { mutableStateOf<JSONObject?>(null) }
 var message by remember { mutableStateOf("") }
 var loading by remember { mutableStateOf(false) }
 val policy=data.optJSONObject("vacation")
 val family=data.optString("family_id")
 val expected=policy?.optString("latest_version")?.takeUnless { it.isBlank() || it=="null" } ?: JSONObject.NULL
 Text("Vacation mode",style=MaterialTheme.typography.headlineSmall)
 Text(if(policy?.optBoolean("active")==true) "Vacation mode is active." else "Vacation mode starts automatically November 28, 2026.")
 Text("School reminders end after Friday, November 27. Vacation duties keep a daily maximum of 100 and the same 90-point passing threshold.")
 Text("Lunchbag + shower + room becomes shower + room. Homework/study is removed. Next-day preparation becomes room clean up.")
 Text("Removed points are shared proportionally among eligible remaining duties. Water plants, drink water, research, draw/dance, closet/shoes, declutter and Hikari Shop keep their points.")
 Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
  Text("Schedule a vacation",style=MaterialTheme.typography.titleMedium)
  OutlinedTextField(start,{start=it;preview=null},label={Text("First vacation day · YYYY-MM-DD")})
  OutlinedTextField(end,{end=it},label={Text("Last vacation day · optional")})
  Text("Schedule changes start after today. Existing day records retain their original rules.")
  OutlinedButton(enabled=enabled && !loading,onClick={loading=true;scope.launch {
   try { preview=service.rpc("get_vacation_preview",token(),JSONObject().put("p_family_id",family).put("p_date",start));message="" }
   catch(e:CancellationException) { throw e } catch(_:Exception) { message="Enter a valid preview date and try again when connected." } finally { loading=false }
  }}) { Text("Preview vacation duties") }
  preview?.let { result ->
   Text("${result.optString("local_date")} · maximum ${result.optInt("maximum")} points",style=MaterialTheme.typography.titleMedium)
   result.optJSONArray("tasks")?.let { tasks -> for(i in 0 until tasks.length()) { val task=tasks.getJSONObject(i);Text("${task.getString("title")} · ${task.getInt("points")} points") } }
  }
  Button(enabled=enabled && preview!=null,onClick={
   propose("Schedule vacation from $start"+(if(end.isBlank()) " until a Parent ends it." else " through $end.")+" Existing records are preserved.","set_vacation_schedule",
    JSONObject().put("p_family_id",family).put("p_start_date",start).put("p_end_date",end.takeIf { it.isNotBlank() } ?: JSONObject.NULL).put("p_expected_version",expected))
  }) { Text("Review vacation schedule") }
 } }
 Spacer(Modifier.height(12.dp))
 Text("Return to school duties",style=MaterialTheme.typography.titleMedium)
 OutlinedTextField(schoolFrom,{schoolFrom=it},label={Text("School duties resume · YYYY-MM-DD")})
 Text("This restores the ordinary duty catalogue. A new school-term reminder calendar must be confirmed separately.")
 OutlinedButton(enabled=enabled && schoolFrom.isNotBlank(),onClick={propose("Restore school duties from $schoolFrom. Existing records are preserved.","end_vacation_mode",JSONObject().put("p_family_id",family).put("p_effective_from",schoolFrom).put("p_expected_version",expected))}) { Text("Review return date") }
 if(message.isNotBlank()) Text(message)
 policy?.optJSONArray("schedule")?.let { rows -> if(rows.length()>0) { Text("Scheduled changes",style=MaterialTheme.typography.titleMedium);for(i in 0 until rows.length()) { val row=rows.getJSONObject(i);Text("${row.optString("effective_from")} · ${if(row.optBoolean("enabled")) "Vacation" else "School duties"}") } } }
}
