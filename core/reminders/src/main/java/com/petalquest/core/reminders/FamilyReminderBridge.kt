package com.petalquest.core.reminders

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import com.petalquest.core.data.LocalData
import com.petalquest.core.model.Membership
import com.petalquest.core.sync.FamilySync
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.time.*

/** Receives only successful authenticated dashboard snapshots, never push-envelope schedules. */
class FamilyReminderBridge private constructor(private val sync: FamilySync, private val local: LocalData) {
    val runtime = ReminderRuntime.get(sync.context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    @Volatile private var activeOwnership: ReminderOwnership? = null
    private val ownershipState = MutableStateFlow<ReminderOwnership?>(null)
    val ownershipChanges = ownershipState.asStateFlow()
    companion object {
        fun install(sync: FamilySync, local: LocalData): FamilyReminderBridge = FamilyReminderBridge(sync, local).also { bridge ->
            sync.setOwnershipSink { _, membership ->
                val next = membership?.let(bridge::ownerFromSession)
                bridge.activeOwnership = next
                if (bridge.ownershipState.value != next) bridge.ownershipState.value = null
                bridge.mutex.withLock {
                    bridge.runtime.bindOwnership(next)
                    bridge.ownershipState.value = next
                }
            }
            sync.setRoutineSink { membership, dashboard ->
                // Ownership is rechecked inside the serialized worker before persistence.
                val expected = bridge.ownershipFor(membership)
                bridge.scope.launch {
                    bridge.mutex.withLock {
                        if (expected != null && expected == bridge.ownershipFor(membership)) {
                            try { bridge.accept(expected, membership, dashboard) }
                            catch (cancel: CancellationException) { throw cancel }
                            catch (_: Exception) { /* Failed or incomplete snapshot leaves existing schedules intact. */ }
                        }
                    }
                }
            }
        }
    }
    /** Stable generation, endpoint, family, user and host role all contribute to the binding. */
    fun ownershipFor(membership: Membership): ReminderOwnership? = ownerFromSession(membership)
        ?.takeIf { it == activeOwnership && sync.currentMembership() == membership }
    private fun ownerFromSession(membership: Membership): ReminderOwnership? {
        val session = local.sessionStore().read() ?: return null
        if (!membership.active || membership.userId != session.userId || membership.role != sync.role) return null
        return ReminderOwnership(session.userId, membership.familyId, membership.role, "${session.endpointId}/${session.generation}")
    }
    private suspend fun accept(ownership: ReminderOwnership, membership: Membership, dashboard: JSONObject) {
        if(membership.role=="parent") { acceptParent(ownership,membership,dashboard); return }
        if (membership.role != "teen" || dashboard.optString("family_id") != membership.familyId ||
            dashboard.optString("teen_id") != membership.actorId) return
        val serverDate = dashboard.optString("server_local_date").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: return
        dashboard.optJSONObject("school_checklist")?.let { school ->
            if(school.optString("family_id")==membership.familyId && school.optString("teen_id")==membership.actorId) {
                val items=school.getJSONArray("items")
                val session=local.sessionStore().read()
                val saved=session?.let { sync.context.getSharedPreferences("school-actions-${it.generation}",android.content.Context.MODE_PRIVATE) }
                val pending=saved?.getString("pending",null)?.let { JSONObject(it) }
                val locallyCompleted=if(saved?.getBoolean("blocked",false)==false && pending?.optString("p_action")=="complete") pending.optString("p_item_id") else null
                val titles=if(dashboard.optJSONObject("vacation")?.optBoolean("active")==true || !school.optBoolean("school_active")) emptyList() else
                    (0 until items.length()).map { items.getJSONObject(it) }.filter { !it.optBoolean("completed") && !it.optBoolean("removed") && it.optString("id")!=locallyCompleted }.map { it.getString("title") }
                val vacationDates=(0L..45L).map { serverDate.plusDays(it) }.filter { vacationOn(dashboard,it) }.toSet()
                runtime.syncSchoolPendings(ownership,serverDate,titles,vacationDates)
            }
        }
        if(dashboard.has("tasks") && dashboard.has("day_summaries")) {
            val tasks=dashboard.getJSONArray("tasks")
            val summaries=dashboard.getJSONArray("day_summaries")
            val todayResult=(0 until summaries.length()).map { summaries.getJSONObject(it) }.firstOrNull { it.optString("local_date")==serverDate.toString() }
            if(todayResult!=null) {
                val session=local.sessionStore().read()
                val queued=if(session==null) emptySet() else local.family(session.userId,session.endpointId).pending()
                    .filter { it.kind=="QUEST_SUBMIT" && !it.status.startsWith("needs_review") }.map { JSONObject(it.canonicalPayload).optString("occurrence_id") }.toSet()
                val titles=if(todayResult.optString("status") in setOf("finalized","sealed")) emptyList() else
                    (0 until tasks.length()).map { tasks.getJSONObject(it) }.filter {
                        it.optString("local_date")==serverDate.toString() && it.optString("status") in setOf("open","returned") && it.optString("id") !in queued
                    }.map { it.optString("title_snapshot",it.optString("title","Pending task")) }
                runtime.syncHomePendings(ownership,serverDate,titles,TeenCheckpointPolicy.homeTimes(serverDate))
            }
        }
        val from = dashboard.optString("_reminder_from").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: return
        val to = dashboard.optString("_reminder_to").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: return
        val end = serverDate.plusDays(13)
        if (from > serverDate || to < end) return // Never replace 14-day schedules using a partial UI fetch.
        if (!dashboard.has("assigned_routines")) return
        val rows = dashboard.getJSONArray("assigned_routines")
        val snapshots = (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            check(row.getString("family_id") == membership.familyId && row.getString("teen_id") == membership.actorId)
            val date = LocalDate.parse(row.getString("local_date"))
            val times = row.getJSONArray("local_times")
            val days = row.getJSONArray("weekdays")
            AssignedReminder(row.getString("routine_id"), row.get("version").toString(), row.getString("id"), row.getString("title"), date,
                (0 until times.length()).map { LocalTime.parse(times.getString(it)) },
                (0 until days.length()).map { DayOfWeek.of(if (days.getInt(it) == 0) 7 else days.getInt(it)) }.toSet())
        }.filter { it.localDate >= serverDate && it.localDate <= end }
        runtime.bindOwnership(ownership)
        runtime.syncAssigned(ownership, snapshots, serverDate, end)
        val yesterday = serverDate.minusDays(1)
        if (from <= yesterday && to >= yesterday && dashboard.has("day_summaries")) {
            val summaries = dashboard.getJSONArray("day_summaries")
            val prior = (0 until summaries.length()).map { summaries.getJSONObject(it) }
                .firstOrNull { it.optString("local_date") == yesterday.toString() }
            val seal = prior?.optString("effective_seal_at")?.takeIf { it.isNotBlank() && it != "null" }?.let(Instant::parse)
            val unsealed = prior != null && prior.optString("status") == "finalized" &&
                !prior.isNull("first_published_at") && seal != null && seal.isAfter(Instant.now())
            runtime.syncPreviousDayReview(ownership, yesterday, unsealed, seal)
        }
    }
    private suspend fun acceptParent(ownership: ReminderOwnership, membership: Membership, dashboard: JSONObject) {
        if(dashboard.optString("family_id")!=membership.familyId || !dashboard.has("day_summaries")) return
        val today=dashboard.optString("server_local_date").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: return
        val rows=dashboard.getJSONArray("day_summaries")
        val summaries=(0 until rows.length()).map { rows.getJSONObject(it) }.toMutableList()
        // A successfully read, bounded date range also confirms absence of a published result.
        // The Teen need not open the app before a Parent receives a finalization reminder.
        val from=dashboard.optString("_reminder_from").takeIf { it.isNotBlank() }?.let(LocalDate::parse)
        val to=dashboard.optString("_reminder_to").takeIf { it.isNotBlank() }?.let(LocalDate::parse)
        if(from!=null && to!=null && dashboard.optString("teen_id").let { it.isNotBlank() && it!="null" }) {
            (0L..13L).map { today.plusDays(it) }.filter { it>=from && it<=to }.forEach { date ->
                if(summaries.none { it.optString("local_date")==date.toString() }) summaries.add(JSONObject().put("local_date",date.toString()).put("status","pending").put("first_published_at",JSONObject.NULL))
            }
        }
        val plan=ParentCheckpointPlan(enabled=true,recipientUserIds=setOf(ownership.userId),
            weekdays=DayOfWeek.values().toSet(),suppressionPolicy="after_finalization",
            wednesdayShiftThrough=TeenCheckpointPolicy.lastSchoolDay)
        if(runtime.parentCheckpointPlan(ownership)!=plan) runtime.configureParentCheckpoints(ownership,plan)
        // Resolve only dates actually covered by the authoritative response, never missing/future guesses.
        val confirmed=summaries.filter { LocalDate.parse(it.getString("local_date"))>=today }.flatMap { day ->
            val date=LocalDate.parse(day.getString("local_date"))
            val finalized=day.optString("status") in setOf("finalized","sealed") || !day.isNull("first_published_at")
            ParentCheckpointPlan.slots.map { ConfirmedParentCheckpoint(it.key,date,finalized || it.key=="morning" && (date>TeenCheckpointPolicy.lastSchoolDay || vacationOn(dashboard,date))) }
        }
        val covered=summaries.map { LocalDate.parse(it.getString("local_date")) }.filter { it>=today }.toSet()
        if(covered.isNotEmpty()) runtime.syncConfirmedParentCheckpoints(ownership,confirmed,covered)
    }
    private fun vacationOn(dashboard:JSONObject,date:LocalDate):Boolean {
        val rows=dashboard.optJSONObject("vacation")?.optJSONArray("schedule")
        val baseline=LocalDate.of(2026,11,28)
        val changes=rows?.let { a -> (0 until a.length()).map { a.getJSONObject(it) }.filter {
            LocalDate.parse(it.getString("effective_from"))<=date && (date<baseline || LocalDate.parse(it.getString("effective_from"))>=baseline)
        }.sortedWith(compareBy<JSONObject> { it.getString("effective_from") }.thenBy { it.getString("created_at") }.thenBy { it.getString("id") }) }.orEmpty()
        return changes.lastOrNull()?.getBoolean("enabled") ?: (date>=baseline)
    }
}

/** Insert into either authenticated dashboard. Settings opens in a bounded modal, avoiding nested scrolls. */
@Composable
fun Phase10ReminderPanel(bridge: FamilyReminderBridge, membership: Membership,
    onRequestNotificationPermission: () -> Unit) {
    var show by remember(membership) { mutableStateOf(false) }
    val binding by bridge.ownershipChanges.collectAsState()
    var ownership by remember(bridge, membership) { mutableStateOf<ReminderOwnership?>(null) }
    LaunchedEffect(bridge, membership, binding) {
        ownership = withContext(Dispatchers.IO) { bridge.ownershipFor(membership) }
    }
    val currentOwnership = ownership?.takeIf { it == binding }
    if (currentOwnership != null) {
        TextButton(onClick = { show = true }) { Text("Local reminders") }
        if (show) Dialog(onDismissRequest = { show = false }) {
            Surface(Modifier.fillMaxWidth().fillMaxHeight(0.9f)) {
                Column {
                    TextButton(onClick = { show = false }) { Text("Close") }
                    ReminderSettingsScreen(bridge.runtime, currentOwnership, onRequestNotificationPermission, Modifier.weight(1f))
                }
            }
        }
    }
}


/** Host-independent permission/settings launcher. Permission is requested only after the button is tapped. */
@Composable
fun Phase10ReminderPanel(bridge: FamilyReminderBridge, membership: Membership) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var asked by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        scope.launch { bridge.runtime.rebuild() }
    }
    val settings = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        scope.launch { bridge.runtime.rebuild() }
    }
    Phase10ReminderPanel(bridge, membership) {
        if (Build.VERSION.SDK_INT >= 33 && !asked && ContextCompat.checkSelfPermission(context,
                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            asked = true
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
            settings.launch(intent)
        }
    }
}
