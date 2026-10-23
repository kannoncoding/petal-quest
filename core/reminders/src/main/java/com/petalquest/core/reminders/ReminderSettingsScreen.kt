package com.petalquest.core.reminders

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import java.time.*
import java.util.UUID

/** Host owns permission launcher and supplies an already authenticated ownership binding. */
@Composable
fun ReminderSettingsScreen(runtime: ReminderRuntime, ownership: ReminderOwnership,
    onRequestNotificationPermission: () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var rows by remember(ownership) { mutableStateOf(emptyList<PersonalReminder>()) }
    var editingId by remember(ownership) { mutableStateOf<String?>(null) }
    var title by remember(ownership) { mutableStateOf("") }
    var time by remember(ownership) { mutableStateOf("") }
    var date by remember(ownership) { mutableStateOf("") }
    var zone by remember(ownership) { mutableStateOf(ReminderRuntime.FAMILY_ZONE) }
    var weekdays by remember(ownership) { mutableStateOf(emptySet<DayOfWeek>()) }
    var quietStart by remember(ownership) { mutableStateOf("") }
    var quietEnd by remember(ownership) { mutableStateOf("") }
    var snooze by remember(ownership) { mutableStateOf("") }
    var message by remember(ownership) { mutableStateOf("") }
    LaunchedEffect(ownership) {
        try {
            rows = runtime.personalReminders(ownership)
            val configuration = runtime.configuration(ownership)
            quietStart = configuration.quietHours?.start?.toString().orEmpty()
            quietEnd = configuration.quietHours?.end?.toString().orEmpty()
            snooze = configuration.snoozeMinutes?.toString().orEmpty()
        } catch (cancel: kotlinx.coroutines.CancellationException) { throw cancel }
        catch (_: IllegalStateException) { rows = emptyList() }
    }
    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Reminders", style = MaterialTheme.typography.headlineMedium)
        Text("Reminders stay on this device. Delivery may be delayed by Android. Snooze and dismiss only affect this notification.")
        Button(onClick = onRequestNotificationPermission) { Text("Notification permission and settings") }
        Text("Personal reminders", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Reminder title") })
        OutlinedTextField(value = time, onValueChange = { time = it }, label = { Text("Time (HH:mm)") })
        OutlinedTextField(value = date, onValueChange = { date = it }, label = { Text("One-off date (YYYY-MM-DD), or choose weekdays") })
        DayOfWeek.values().toList().chunked(4).forEach { days ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                days.forEach { day ->
                    FilterChip(selected = day in weekdays,
                        onClick = { weekdays = if (day in weekdays) weekdays - day else weekdays + day },
                        label = { Text(day.name.take(3).lowercase().replaceFirstChar { it.uppercase() }) })
                }
            }
        }
        OutlinedTextField(value = zone, onValueChange = { zone = it }, label = { Text("Time zone (IANA name)") })
        Text("Family schedules use America/Costa_Rica. This time zone applies to your personal reminder.")
        Button(onClick = {
            scope.launch {
                try {
                    runtime.savePersonal(ownership, PersonalReminder(id = editingId ?: UUID.randomUUID().toString(), title = title.trim(), time = LocalTime.parse(time),
                        weekdays = weekdays, oneOffDate = date.takeIf { it.isNotBlank() }?.let(LocalDate::parse), zoneId = zone))
                    rows = runtime.personalReminders(ownership); editingId = null; title = ""; time = ""; date = ""
                    weekdays = emptySet(); zone = ReminderRuntime.FAMILY_ZONE; message = "Reminder saved locally."
                } catch (_: Exception) { message = "Enter a title, valid time and zone, and either one date or selected weekdays." }
            }
        }) { Text(if (editingId == null) "Create personal reminder" else "Save changes") }
        if (editingId != null) TextButton(onClick = {
            editingId = null; title = ""; time = ""; date = ""; weekdays = emptySet(); zone = ReminderRuntime.FAMILY_ZONE
        }) { Text("Cancel editing") }
        Text(message)
        rows.forEach { row ->
            Column(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(vertical = 8.dp)) {
                    Text(row.title)
                    Text("${row.time} · ${row.oneOffDate ?: row.weekdays.joinToString()} · ${row.zoneId}")
                    TextButton(onClick = {
                        editingId = row.id; title = row.title; time = row.time.toString()
                        date = row.oneOffDate?.toString().orEmpty(); weekdays = row.weekdays; zone = row.zoneId
                    }) { Text("Edit") }
                    TextButton(onClick = { scope.launch {
                        runtime.removePersonal(ownership, row.id); rows = runtime.personalReminders(ownership)
                        if (editingId == row.id) { editingId = null; title = ""; time = ""; date = ""; weekdays = emptySet() }
                    } }) { Text("Delete") }
                }
            }
        }
        Text("Local delivery preferences", style = MaterialTheme.typography.titleLarge)
        Text("Leave both quiet fields blank to disable quiet hours. Quiet hours use Costa Rica time. Leave snooze blank to disable its action.")
        OutlinedTextField(quietStart, { quietStart = it }, label = { Text("Quiet start (HH:mm)") })
        OutlinedTextField(quietEnd, { quietEnd = it }, label = { Text("Quiet end (HH:mm)") })
        OutlinedTextField(snooze, { snooze = it }, label = { Text("Snooze minutes (1–120)") })
        Button(onClick = { scope.launch {
            try {
                val quiet = if (quietStart.isBlank() && quietEnd.isBlank()) null
                    else QuietHours(LocalTime.parse(quietStart), LocalTime.parse(quietEnd))
                runtime.configure(ownership, quiet, snooze.takeIf { it.isNotBlank() }?.toInt())
                message = "Local delivery preferences saved."
            } catch (_: Exception) { message = "Enter valid quiet times and snooze minutes, or leave them blank." }
        } }) { Text("Save delivery preferences") }

    }
}
