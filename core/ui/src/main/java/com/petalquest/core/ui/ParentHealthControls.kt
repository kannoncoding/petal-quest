package com.petalquest.core.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.petalquest.core.network.FamilyService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.util.UUID
import org.json.JSONObject

/** Parent access is server-authorized. This module has no private vault dependency. */
@Composable
fun ParentHealthControls(service: FamilyService, familyId: String, token: suspend () -> String, enabled: Boolean) {
    val scope = rememberCoroutineScope()
    var installations by remember { mutableStateOf(emptyList<FamilyService.HealthInstallation>()) }
    var checkinDates by remember { mutableStateOf(emptyList<String>()) }
    var ranges by remember { mutableStateOf(emptyList<FamilyService.PeriodRange>()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<FamilyService.HealthInstallation?>(null) }
    var typed by remember { mutableStateOf("") }
    // A lost response must retry the same command, never enqueue a second deletion.
    val requestIds = rememberSaveable { HashMap<String, String>() }
    val requested = remember { mutableStateMapOf<String, Boolean>() }
    fun refresh() {
        if (busy || !enabled) return
        busy = true
        scope.launch {
            try {
                val access = token()
                val nextInstallations = service.healthInstallations(access, familyId)
                val nextRanges = service.periodRanges(access, familyId)
                val checkins = service.rpc("list_parent_checkins", access, JSONObject()).getJSONArray("checkins")
                val nextCheckins = (0 until checkins.length()).map { checkins.getJSONObject(it).getString("local_date") }.filter { it.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) }.distinct().sortedDescending()
                nextInstallations.filter { it.wipeStatus == "expired" }.forEach { requestIds.remove(it.installationId + ":" + it.enrollmentGeneration) }
                installations = nextInstallations; ranges = nextRanges; checkinDates = nextCheckins
                message = "Device status refreshed."
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { installations = emptyList(); ranges = emptyList(); checkinDates = emptyList(); message = "Health controls could not be loaded. Check your family access and try again." }
            finally { busy = false }
        }
    }
    Text("Teen device health controls", style = MaterialTheme.typography.titleLarge)
    Text("Parents can view period date ranges and generic check-in dates when configured. Daily descriptions, symptoms, notes and numerical pain scores stay on the Teen device. A remote deletion is irreversible and requires the device to reconnect.")
    OutlinedButton(enabled = enabled && !busy, onClick = { refresh() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Refresh device status and period dates") }
    installations.forEachIndexed { index, installation ->
        Text("Teen device ${installation.installationId.replace("-", "").takeLast(6).uppercase()}", style = MaterialTheme.typography.titleMedium)
        Text(when (installation.wipeStatus) { "done" -> "Last deletion request completed."; "expired" -> "Deletion request expired. Request again for this device."; "claimed" -> "Device accepted deletion; waiting for completion."; "requested" -> "Deletion requested. Device must reconnect before the request expires (30 days)."; else -> if (requested[installation.installationId] == true) "Deletion requested; refresh for status." else "No current deletion request reported." })
        ranges.filter { it.installationId == installation.installationId }.forEach { range ->
            Text("Period: ${range.startDate} – ${range.endDate ?: "ongoing"}")
        }
        OutlinedButton(enabled = enabled && !busy, onClick = { selected = installation; typed = "" }, modifier = Modifier.heightIn(min = 48.dp)) { Text(if (requestIds.containsKey(installation.installationId + ":" + installation.enrollmentGeneration)) "Retry device deletion request" else "Delete this device’s health log remotely") }
    }
    checkinDates.forEach { Text("Please check in · $it") }
    if (busy) CircularProgressIndicator()
    if (message.isNotBlank()) Text(message)
    selected?.let { installation ->
        val installationId = installation.installationId
        val requestKey = installationId + ":" + installation.enrollmentGeneration
        AlertDialog(onDismissRequest = { if (!busy) { selected = null; typed = "" } },
            title = { Text("Permanently delete Teen device " + installationId.replace("-", "").takeLast(6).uppercase() + " health log?") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("All private health records on this Teen device and its shared period date ranges are queued for irreversible deletion. The device must reconnect before the request expires (30 days). This cannot be undone. Existing exported backups are not deleted. Type DELETE to confirm.")
                OutlinedTextField(typed, { typed = it }, label = { Text("Type DELETE") }, singleLine = true, enabled = !busy)
            } },
            confirmButton = { TextButton(enabled = enabled && !busy && typed == "DELETE", onClick = {
                val requestId = requestIds.getOrPut(requestKey) { UUID.randomUUID().toString() }
                busy = true; typed = ""; selected = null
                scope.launch {
                    try {
                        service.requestHealthWipe(token(), installationId, installation.enrollmentGeneration, requestId)
                        requested[installationId] = true
                        message = "Deletion request accepted. The Teen device must reconnect before the request expires (30 days). Refresh for status."
                    } catch (e: CancellationException) { throw e }
                    catch (_: Exception) { message = "Deletion was not confirmed. Retry uses the same request identifier; refresh status before assuming it failed." }
                    finally { busy = false }
                }
            }) { Text("Request permanent deletion") } },
            dismissButton = { TextButton(enabled = !busy, onClick = { selected = null; typed = "" }) { Text("Cancel") } })
    }
}
