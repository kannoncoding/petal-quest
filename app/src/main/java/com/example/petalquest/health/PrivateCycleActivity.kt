package com.example.petalquest.health

import android.app.KeyguardManager
import android.hardware.biometrics.BiometricPrompt
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.ui.platform.ComposeView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import com.example.petalquest.ui.theme.PetalQuestTheme
import com.petalquest.core.health.CycleVault
import java.text.SimpleDateFormat
import java.util.*

/** Private health UI deliberately has no family, analytics, notification or network integration. */
class PrivateCycleActivity : ComponentActivity() {
    private lateinit var vault: CycleVault
    private lateinit var privateView: ComposeView
    @Volatile private var visible = false
    private var busy by mutableStateOf(false)
    private var epoch by mutableIntStateOf(0)
    private var unlocked by mutableStateOf(false)
    private var status by mutableStateOf("")
    private var auth: CancellationSignal? = null
    private var authAttempt = 0
    private var pendingAuth = false
    private var pendingReset = false
    private var awaitingCredential = false
    private var exportTarget: Uri? = null
    private var exportReady by mutableStateOf(false)
    private val credential = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        val expected = awaitingCredential
        awaitingCredential = false
        if (expected && it.resultCode == RESULT_OK) { pendingAuth = true; if (visible) completeAuthentication() }
        else { pendingReset = false; pendingAuth = false; exportTarget = null; status = "Unlock cancelled." }
    }
    private val destination = registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) {
        exportTarget = it
        if (it != null) { if (visible) authenticate() else pendingExport = true }
    }
    private var pendingExport = false
    private var externalDeparture = false
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(null)
        window.decorView.importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        vault = CycleVault(this)
        privateView = ComposeView(this).apply { isSaveEnabled = false; importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS }
        setContentView(privateView)
    }
    override fun onStart() {
        super.onStart(); visible = true
        privateView.setContent { PetalQuestTheme { Surface(Modifier.fillMaxSize()) { key(epoch) { Screen() } } } }
        if (pendingAuth) completeAuthentication()
        if (pendingExport) { pendingExport = false; authenticate() }
    }
    override fun onStop() {
        visible = false
        privateView.disposeComposition()
        if (!(externalDeparture && awaitingCredential)) { pendingReset = false; pendingAuth = false; awaitingCredential = false }
        authAttempt++; auth?.cancel(); auth = null
        if (exportReady || !externalDeparture) { exportTarget = null; pendingExport = false }
        externalDeparture = false
        vault.lock(); unlocked = false; exportReady = false; epoch++; status = ""
        super.onStop()
    }
    override fun onSaveInstanceState(outState: Bundle) { super.onSaveInstanceState(outState); outState.clear() }
    override fun onDestroy() { auth?.cancel(); vault.lock(); exportTarget = null; super.onDestroy() }
    private fun authenticate(forReset: Boolean = false) {
        pendingReset = forReset
        pendingAuth = false
        val manager = getSystemService(KeyguardManager::class.java)
        if (!manager.isDeviceSecure) { pendingReset = false; status = "Set a phone screen lock PIN or password in Android Settings before using this private log."; exportTarget = null; return }
        try { if (!forReset) vault.prepareKey() } catch (_: Exception) { exportTarget = null; exportReady = false; pendingExport = false; pendingReset = false; status = "Private storage is unavailable. Your phone lock or key may have changed."; return }
        if (Build.VERSION.SDK_INT >= 30) {
            auth?.cancel(); auth = CancellationSignal()
            val attempt = ++authAttempt
            BiometricPrompt.Builder(this).setTitle("Unlock private log")
                .setAllowedAuthenticators(android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                .build().authenticate(auth!!, mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (visible && attempt == authAttempt) { pendingAuth = true; completeAuthentication() }
                    }
                    override fun onAuthenticationError(code: Int, message: CharSequence) { if (attempt == authAttempt) { pendingReset = false; exportTarget = null; status = "Unlock cancelled or unavailable." } }
                })
        } else {
            @Suppress("DEPRECATION")
            val intent = manager.createConfirmDeviceCredentialIntent("Unlock private log", "Confirm your phone screen lock")
            if (intent != null) { awaitingCredential = true; externalDeparture = true; credential.launch(intent) } else { pendingReset = false; exportTarget = null; status = "Phone authentication unavailable." }
        }
    }
    private fun completeAuthentication() {
        pendingAuth = false
        try {
            if (pendingReset) {
                pendingReset = false
                vault.resetConfirmed(); unlocked = false; exportTarget = null; exportReady = false; pendingExport = false; epoch++
                status = "Private log reset."
                return
            }
            vault.unlockAfterAuthentication()
            exportReady = exportTarget != null
            unlocked = true; epoch++
        } catch (_: Exception) { pendingReset = false; vault.lock(); exportTarget = null; exportReady = false; pendingExport = false; unlocked = false; status = "Unable to open or save private data. Try again, or reset this log if its key is unavailable." }
    }
    @Composable private fun Screen() {
        if (busy) { Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(24.dp)) { CircularProgressIndicator(); Text("Saving encrypted backup…") }; return }
        var refresh by remember { mutableIntStateOf(0) }
        var confirm by remember { mutableStateOf<Pair<String, () -> Unit>?>(null) }
        fun operation(action: () -> Unit) { try { action(); refresh++ } catch (_: Exception) { status = "Change could not be saved. Check dates and try again." } }
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Private cycle log", style = MaterialTheme.typography.headlineMedium)
            Text("Only on this phone. Protected by your phone lock. Anyone with an enrolled phone biometric or phone credential can unlock. No family account or XP access. Locks when you leave.")
            Button(onClick = { finish() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Close") }
            if (status.isNotBlank()) Text(status)
            if (!unlocked) {
                Button(onClick = { authenticate() }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Unlock with phone lock") }
                Text("If the private key is lost after a phone lock change, the existing data cannot be recovered. Reset deletes it permanently.")
                OutlinedButton(onClick = { confirm = "Permanently delete all private health data? This cannot be undone." to { authenticate(forReset = true) } }) { Text("Reset private log") }
            } else {
                val generation = vault.generation()
                val snapshot = remember(refresh) { try { vault.snapshot() } catch (_: Exception) { null } }
                Button(onClick = { vault.lock(); exportTarget = null; exportReady = false; pendingExport = false; unlocked = false; epoch++ }) { Text("Lock now") }
                Text("Record confirmed dates only. Gaps do not imply symptoms or flow. This log makes no predictions and provides no medical advice.")
                if (exportReady) {
                    var passphrase by remember { mutableStateOf("") }
                    var repeated by remember { mutableStateOf("") }
                    Text("Encrypt export with a separate passphrase. Keep it safe: it cannot be recovered. The destination may sync to cloud. Restore/import is planned for a future phase.")
                    OutlinedTextField(passphrase, { passphrase = it }, label = { Text("Passphrase (at least 12 characters)") }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(repeated, { repeated = it }, label = { Text("Confirm passphrase") }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false), modifier = Modifier.fillMaxWidth())
                    Button(enabled = passphrase.length >= 12 && passphrase == repeated, onClick = {
                        val target = exportTarget
                        val secret = passphrase.toCharArray(); passphrase = ""; repeated = ""
                        busy = true; exportTarget = null; exportReady = false
                        lifecycleScope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    if (!visible || target == null || generation != vault.generation()) error("Locked")
                                    val encrypted = vault.exportEncrypted(generation, secret)
                                    if (!visible || generation != vault.generation()) error("Locked")
                                    contentResolver.openOutputStream(target, "wt")?.use { it.write(encrypted.toByteArray(Charsets.UTF_8)) } ?: error("Unavailable")
                                }
                                if (visible && generation == vault.generation()) status = "Encrypted export saved. Keep your passphrase separately."
                            } catch (_: Exception) {
                                if (visible && generation == vault.generation()) status = "Export could not be saved. Choose a destination and try again."
                            } finally { secret.fill('\u0000'); busy = false }
                        }
                    }) { Text("Save encrypted export") }
                    TextButton(onClick = { passphrase = ""; repeated = ""; exportTarget = null; exportReady = false }) { Text("Cancel export") }
                }
                var selected by remember { mutableStateOf(today()) }
                MonthGrid(selected, snapshot?.periods ?: emptyList(), snapshot?.observations ?: emptyList()) { selected = it }
                PeriodEditor(selected, null) { period -> operation { vault.savePeriod(generation, period) } }
                Text("Period history", style = MaterialTheme.typography.titleLarge)
                snapshot?.periods?.sortedByDescending { it.startDate }?.forEach { period ->
                    Text("${period.startDate} – ${period.endDate ?: "ongoing"}")
                    period.endDate?.let { Text("Recorded period length: ${dayDistance(period.startDate, it) + 1} days") }
                    PeriodEditor(period.startDate, period) { operation { vault.savePeriod(generation, it) } }
                    OutlinedButton(onClick = { confirm = "Delete this period?" to { operation { vault.deletePeriod(generation, period.id) } } }) { Text("Delete period") }
                }
                snapshot?.periods?.sortedBy { it.startDate }?.zipWithNext()?.forEach { (a,b) -> Text("Start-to-start interval ${a.startDate} to ${b.startDate}: ${dayDistance(a.startDate,b.startDate)} days") }
                ObservationEditor(selected, snapshot?.observations?.firstOrNull { it.date == selected }) { operation { vault.saveObservation(generation, it) } }
                snapshot?.observations?.sortedByDescending { it.date }?.forEach { observation ->
                    Text("Daily entry: ${observation.date}")
                    Text(listOfNotNull(observation.flow, observation.consistency, observation.pain?.let { "Pain $it/10" }, observation.painLocation, observation.symptoms.joinToString(", "), observation.notes).filter { it.isNotBlank() }.joinToString(" · "))
                    OutlinedButton(onClick = { selected = observation.date }) { Text("Edit this day") }
                    OutlinedButton(onClick = { confirm = "Delete this daily entry?" to { operation { vault.deleteObservation(generation, observation.date) } } }) { Text("Delete daily entry") }
                }
                OutlinedButton(onClick = { confirm = "Export creates a passphrase-encrypted JSON backup outside this log. The destination may sync to cloud. Keep the passphrase separately; losing it makes the backup unreadable. Continue?" to { vault.lock(); unlocked = false; epoch++; externalDeparture = true; destination.launch("private-cycle-log.json") } }) { Text("Export encrypted backup") }
                OutlinedButton(onClick = { confirm = "Permanently delete all private health data? This cannot be undone." to { operation { vault.resetConfirmed(); unlocked = false; epoch++ } } }) { Text("Delete all health data") }
            }
        }
        confirm?.let { dialog -> AlertDialog(onDismissRequest = { confirm = null }, title = { Text("Confirm") }, text = { Text(dialog.first) }, confirmButton = { TextButton(onClick = { confirm = null; dialog.second() }) { Text("Continue") } }, dismissButton = { TextButton(onClick = { confirm = null }) { Text("Cancel") } }) }
    }
}
private fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getTimeZone("America/Costa_Rica") }.format(Date())
private fun parsed(value: String): Date? = try { SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false; timeZone = TimeZone.getTimeZone("UTC") }.let { if (value.matches(Regex("\\d{4}-\\d{2}-\\d{2}"))) it.parse(value) else null } } catch (_: Exception) { null }
private fun dayDistance(start: String, end: String) = ((parsed(end)!!.time - parsed(start)!!.time) / 86400000).toInt()
@Composable private fun PeriodEditor(date: String, existing: CycleVault.Period?, save: (CycleVault.Period) -> Unit) {
    var start by remember(date, existing) { mutableStateOf(existing?.startDate ?: date) }
    var end by remember(date, existing) { mutableStateOf(existing?.endDate ?: "") }
    Text(if (existing == null) "Add period" else "Edit period")
    OutlinedTextField(start, { start = it }, label = { Text("Start YYYY-MM-DD") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(end, { end = it }, label = { Text("End YYYY-MM-DD (blank = ongoing)") }, modifier = Modifier.fillMaxWidth())
    val valid = parsed(start) != null && start <= today() && (end.isBlank() || (parsed(end) != null && end >= start && end <= today()))
    Button(enabled = valid, onClick = { save(CycleVault.Period(existing?.id ?: UUID.randomUUID().toString(), start, end.ifBlank { null })) }) { Text("Save period") }
}
@Composable private fun ObservationEditor(date: String, existing: CycleVault.Observation?, save: (CycleVault.Observation) -> Unit) {
    var flow by remember(date, existing) { mutableStateOf(existing?.flow ?: "") }
    var consistency by remember(date, existing) { mutableStateOf(existing?.consistency ?: "") }
    var pain by remember(date, existing) { mutableStateOf(existing?.pain?.toString() ?: "") }
    var location by remember(date, existing) { mutableStateOf(existing?.painLocation ?: "") }
    var symptoms by remember(date, existing) { mutableStateOf(existing?.symptoms?.joinToString(", ") ?: "") }
    var notes by remember(date, existing) { mutableStateOf(existing?.notes ?: "") }
    Text("Optional daily entry: $date", style = MaterialTheme.typography.titleLarge)
    Text("All fields are optional. Leaving a day unrecorded is okay. Select past dates to make corrections.")
    Text("Flow (subjective): ${flow.ifBlank { "unrecorded" }}")
    listOf("", "spotting", "light", "moderate", "heavy").forEach { option ->
        TextButton(onClick = { flow = option }, modifier = Modifier.heightIn(min = 48.dp)) { Text(option.ifBlank { "Unrecorded" }) }
    }
    OutlinedTextField(consistency, { consistency = it }, label = { Text("Consistency (your description)") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(pain, { pain = it }, label = { Text("Pain 0–10 (optional)") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(location, { location = it }, label = { Text("Pain location") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(symptoms, { symptoms = it }, label = { Text("Symptoms (comma separated)") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(notes, { notes = it }, label = { Text("Notes") }, modifier = Modifier.fillMaxWidth())
    Button(enabled = date <= today() && (pain.isBlank() || pain.toIntOrNull() in 0..10), onClick = { save(CycleVault.Observation(date, flow.ifBlank { null }, consistency.ifBlank { null }, pain.toIntOrNull(), location.ifBlank { null }, symptoms.split(',').map { it.trim() }.filter { it.isNotBlank() }, notes.ifBlank { null })) }) { Text("Save daily entry") }
}
@Composable private fun MonthGrid(selected: String, periods: List<CycleVault.Period>, observations: List<CycleVault.Observation>, select: (String) -> Unit) {
    var month by remember { mutableStateOf(selected.substring(0,7)) }
    Text("Calendar — select a day", style = MaterialTheme.typography.titleLarge)
    Row { TextButton(onClick = { month = shiftMonth(month,-1) }) { Text("Previous month") }; TextButton(onClick = { month = shiftMonth(month,1) }) { Text("Next month") } }
    Text("$month · week starts Sunday")
    Text("P = confirmed period day; • = daily entry. Ongoing periods mark only the recorded start.")
    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { time = parsed("$month-01")!! }
    val leading = cal.get(Calendar.DAY_OF_WEEK) - 1
    val count = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
    Column(Modifier.horizontalScroll(rememberScrollState())) {
    Column(Modifier.width(336.dp)) {
    Text("Sun   Mon   Tue   Wed   Thu   Fri   Sat")
    (0 until (leading + count + 6)/7).forEach { week -> Row(Modifier.fillMaxWidth()) { (0..6).forEach { column ->
        val day = week*7+column-leading+1
        Box(Modifier.weight(1f)) { if (day in 1..count) { val value = "$month-${day.toString().padStart(2,'0')}"; TextButton(onClick = { select(value) }, modifier = Modifier.heightIn(min=48.dp), contentPadding = PaddingValues(0.dp)) { Text((if (value == selected) "[$day]" else "$day") + (if (periods.any { value >= it.startDate && value <= (it.endDate ?: it.startDate) }) "P" else "") + (if (observations.any { it.date == value }) "•" else "")) } } }
    } } }
    } }
    Text("Selected: $selected. Confirmed ranges are listed in period history below.")
}
private fun shiftMonth(month: String, delta: Int): String = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { time = parsed("$month-01")!!; add(Calendar.MONTH,delta) }.let { SimpleDateFormat("yyyy-MM", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(it.time) }
