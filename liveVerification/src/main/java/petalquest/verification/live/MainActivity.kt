package petalquest.verification.live

import android.app.Activity
import android.os.Bundle
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.text.InputType
import android.view.WindowManager
import android.widget.*
import com.petalquest.core.data.*
import com.petalquest.core.model.ServiceConfig
import com.petalquest.core.network.FamilyService
import com.petalquest.core.ui.QueuedSubmissions
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.time.*
import java.util.UUID

/** Dedicated QA sandbox: no access to parent/teen app storage, Firebase, or credentials. */
class MainActivity : Activity() {
 companion object { private val processRun = UUID.randomUUID().toString() }
 private val scope = MainScope()
 private lateinit var local: LocalData
 private lateinit var output: TextView
 private lateinit var password: EditText
 private lateinit var layout: LinearLayout
 private val config by lazy { ServiceConfig(BuildConfig.SERVICE_URL, BuildConfig.SERVICE_PUBLIC_KEY, BuildConfig.BUILD_TYPE) }
 private val service by lazy { requireDevelopment(); FamilyService(config) }
 private val prefs by lazy { getSharedPreferences("qa-evidence", MODE_PRIVATE) }
 override fun onCreate(state: Bundle?) {
  super.onCreate(state)
  window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
  local = LocalData.getInstance(this)
  layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24,24,24,24) }
  val scroll = ScrollView(this); scroll.addView(layout); setContentView(scroll)
  text("Phase 6 • Live offline QA\nFictional account: qa-parent-c@example.com\nUses its own app storage and an additional anonymous QA teen. Internet access is enabled. No Firebase. Password stays in memory only.")
  password = EditText(this).apply { hint = "QA parent C password"; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; isSaveEnabled = false; importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO }
  layout.addView(password)
  button("1. Prepare online / resume QA teen") {
   val secret = withContext(Dispatchers.Main) { password.text.toString().also { password.text.clear() } }
   prepare(secret)
  }
  button("2. Internet OFF → queue locally") {
   check(!online()) { "Disable Wi-Fi and mobile data first." }
   val repository = repo(); val snapshot = repository.cached(FamilyRepository.CacheKind.QUESTS,"offline-target") ?: error("Prepare online first.")
   val occurrence = JSONObject(snapshot.canonicalPayload)
   check(Instant.parse(occurrence.getString("due_at")).isAfter(Instant.now())) { "Prepared deadline passed. Prepare again online." }
   check(repository.pending().isEmpty() && prefs.getString("request", null) == null) { "Existing probe exists; inspect or send it first." }
   val pending = QueuedSubmissions(repository, service).enqueue(occurrence.getString("id"))
   prefs.edit().putString("request",pending.requestId).putString("occurrence",occurrence.getString("id")).putString("queuedProcess",processRun).putBoolean("restartVerified",false).commit()
   "QUEUED OFFLINE\nRequest: ${pending.requestId}\nPending: ${repository.pending().size}\nNow close the app from recent apps or force stop, then relaunch while offline."
  }
  button("3. After restart → verify saved queue") {
   check(!online()) { "Keep internet disabled for restart verification." }
   check(prefs.getString("queuedProcess", "") != processRun) { "Restart the app process before this step. Force stop from Android app settings, then reopen." }
   val request = prefs.getString("request", null) ?: error("No queued probe.")
   val operation = repo().pending().single { it.requestId == request }
   check(JSONObject(operation.canonicalPayload).getString("occurrence_id") == prefs.getString("occurrence", ""))
   prefs.edit().putBoolean("restartVerified",true).commit()
   "RESTART VERIFIED OFFLINE\nSame request: $request\nPending: ${repo().pending().size}\nReconnect internet, then send."
  }
  button("4. Internet ON → send with real adapter") {
   check(online()) { "Reconnect internet first." }
   check(prefs.getBoolean("restartVerified",false)) { "Verify the queue after restarting first." }
   val session = activeSession(); val repository = repo()
   val request = prefs.getString("request", null) ?: error("No queued probe.")
   val operation = repository.pending().single { it.requestId == request }
   val receipt = QueuedSubmissions(repository,service).retry(operation,session.token)
   check(receipt.getString("request_id") == request && receipt.getString("occurrence_id") == prefs.getString("occurrence", ""))
   repository.cacheRemoteSnapshot(FamilyRepository.CacheKind.REVIEWS,"offline-receipt",receipt.toString())
   check(repository.pending().none { it.requestId == request })
   "EXACT RECEIPT ACKNOWLEDGED\nRequest: $request\nSubmission: ${receipt.getString("id")}\nPending: ${repository.pending().size}\nRun replay to confirm one server submission."
  }
  button("5. Replay same request → server count") {
   check(online()) { "Reconnect internet first." }
   val session = activeSession(); val repository = repo()
   val receipt = JSONObject(repository.cached(FamilyRepository.CacheKind.REVIEWS,"offline-receipt")?.canonicalPayload ?: error("Send first."))
   val replay = service.rpc("submit_occurrence",session.token,JSONObject().put("p_occurrence_id",receipt.getString("occurrence_id")).put("p_request_id",receipt.getString("request_id")))
   check(replay.getString("request_id") == receipt.getString("request_id") && replay.getString("id") == receipt.getString("id"))
   val rows = JSONArray(read("/rest/v1/submissions?select=id&occurrence_id=eq.${receipt.getString("occurrence_id")}",session.token))
   check(rows.length() == 1 && rows.getJSONObject(0).getString("id") == receipt.getString("id")) { "Server count does not confirm exactly one matching submission." }
   prefs.edit().putBoolean("replayVerified",true).commit()
   "LIVE OFFLINE PROBE PASSED\nSame request and submission on replay.\nServer submissions for occurrence: 1\nLocal pending: ${repository.pending().size}\nRequest: ${receipt.getString("request_id")}\nSubmission: ${receipt.getString("id")}"
  }
  button("Inspect local state (no network)") {
   val session = local.sessionStore().read()
   if(session == null) "No saved QA teen. Prepare online." else "Saved encrypted QA teen session.\nPending: ${repo().pending().size}\nRequest: ${prefs.getString("request", "none")}\nRestart verified: ${prefs.getBoolean("restartVerified",false)}\nInternet available: ${online()}"
  }
  button("Show sanitized JSON evidence") {
   val session=local.sessionStore().read()
   val repository=if(session == null) null else repo()
   val receipt=repository?.cached(FamilyRepository.CacheKind.REVIEWS,"offline-receipt")?.canonicalPayload?.let { JSONObject(it) }
   JSONObject().put("app","petalquest.verification.live").put("request_id",prefs.getString("request",null) ?: JSONObject.NULL)
    .put("submission_id",receipt?.optString("id") ?: JSONObject.NULL).put("restart_verified",prefs.getBoolean("restartVerified",false))
    .put("pending_count",repository?.pending()?.size ?: 0).put("replay_single_submission_verified",prefs.getBoolean("replayVerified",false)).toString(2)
  }
  output = TextView(this).apply { setTextIsSelectable(true); text = "Loading saved local state…" }; layout.addView(output)
  if(config.url != "https://hijtwgugzzpjjkuutyfy.supabase.co" || !config.publicKey.startsWith("sb_publishable_")) {
   (0 until layout.childCount).map { layout.getChildAt(it) }.filterIsInstance<Button>().forEach { it.isEnabled=false }
   output.text="BLOCKED: Live QA requires development configuration only."; return
  }
  scope.launch { output.text = withContext(Dispatchers.IO) {
   try { if(local.sessionStore().read() == null) "Ready. Enter QA parent C password for initial preparation."
    else "Saved encrypted QA teen restored. Pending: ${repo().pending().size}\nRequest: ${prefs.getString("request","none")}\nUse step 3 while offline to verify the saved queue after restart."
   } catch(e: Exception) { "BLOCKED: ${safeError(e)}" }
  } }
 }
 private fun text(value: String) { layout.addView(TextView(this).apply { text=value }) }
 private fun button(label: String, action: suspend () -> String) {
  layout.addView(Button(this).apply { text=label; setOnClickListener {
   val buttons = (0 until this@MainActivity.layout.childCount).map { this@MainActivity.layout.getChildAt(it) }.filterIsInstance<Button>()
   buttons.forEach { it.isEnabled=false }; output.text="Working…"
   scope.launch { try { output.text=withContext(Dispatchers.IO) { action() } } catch(e: CancellationException) { throw e } catch(e: Exception) { output.text="BLOCKED: ${safeError(e)}\nNo successful verification claimed. Pending requests remain available for retry." } finally { buttons.forEach { it.isEnabled=true } } }
  } })
 }
 private fun safeError(e: Exception): String = when(e) {
  is java.io.IOException -> "Network unavailable or interrupted."
  else -> e.message?.takeIf { !it.contains("token",true) && !it.contains("password",true) && it.length < 240 } ?: "QA step could not complete."
 }
 private fun online(): Boolean {
  val cm = getSystemService(ConnectivityManager::class.java)
  return cm.activeNetwork?.let { cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } == true
 }
 private fun repo(): FamilyRepository { val s=local.sessionStore().read() ?: error("Prepare online first."); return local.family(s.userId,s.endpointId) }
 private suspend fun activeSession(): Session {
  var s=local.sessionStore().read() ?: error("Prepare online first.")
  if(s.isExpired) { val fresh=service.refresh(s.refreshToken); s=Session(fresh.userId,config.url,fresh.accessToken,fresh.refreshToken,fresh.expiresAtEpochSeconds); local.activate(s) }
  return s
 }
 private suspend fun prepare(secret: String): String {
  requireDevelopment(); check(online()) { "Internet is required to prepare." }; check(config.available) { "Service configuration missing." }
  check(prefs.getString("request",null) == null && (local.sessionStore().read() == null || repo().pending().isEmpty())) { "A probe already exists. Continue its verification steps; preparation cannot replace it." }
  if(local.sessionStore().read() == null) {
   check(secret.isNotBlank()) { "Enter QA parent C credentials locally." }
   val parent = service.signIn("qa-parent-c@example.com",secret)
   try {
   val memberships = service.memberships(parent.accessToken,parent.userId)
   val family = if(memberships.isEmpty()) service.rpc("create_family",parent.accessToken,JSONObject().put("p_name","QA P6 Offline ${System.currentTimeMillis()}")).getString("family_id") else {
    check(memberships.size == 1 && memberships.single().role == "parent" && memberships.single().familyName.startsWith("QA P6 ")) { "Parent C must be unpaired or belong only to a QA P6 family." }
    memberships.single().familyId
   }
   val code=service.rpc("issue_teen_pairing",parent.accessToken,JSONObject().put("p_family_id",family)).getString("code")
   val teen=service.anonymousSignIn()
   service.rpc("redeem_teen_pairing",teen.accessToken,JSONObject().put("p_code",code))
   local.activate(Session(teen.userId,config.url,teen.accessToken,teen.refreshToken,teen.expiresAtEpochSeconds))
   } finally { withContext(NonCancellable + Dispatchers.IO) { logoutParent(parent.accessToken) } }
  }
  val teen=activeSession()
  val memberships=service.memberships(teen.token,teen.userId)
  check(memberships.size == 1 && memberships.single().role == "teen" && memberships.single().familyName.startsWith("QA P6 ")) { "Saved teen is not in a QA P6 family." }
  val membership=memberships.single()
  val today=LocalDate.now(ZoneId.of("America/Costa_Rica")).toString()
  val result=service.rpc("reconcile_occurrences",teen.token,JSONObject().put("p_family_id",membership.familyId).put("p_teen_id",membership.actorId).put("p_from_date",today).put("p_to_date",today))
  val rows=result.getJSONArray("occurrences")
  val future=(0 until rows.length()).map { rows.getJSONObject(it) }.filter { !it.isNull("due_at") && Instant.parse(it.getString("due_at")).isAfter(Instant.now().plusSeconds(300)) }.maxByOrNull { Instant.parse(it.getString("due_at")) }
   ?: error("No known deadline at least five minutes in the future today. Retry on the next eligible day; unresolved deadlines stay blocked.")
  repo().cacheRemoteSnapshot(FamilyRepository.CacheKind.QUESTS,"offline-target",future.toString())
  return "PREPARED ONLINE\nQA family: ${membership.familyName}\nOccurrence: ${future.getString("id")}\nKnown deadline: ${future.getString("due_at")}\nCatalogue is provisioned by the server when a family is created.\nDisable Wi-Fi AND mobile data, then queue locally."
 }
 /** Read only, authenticated server query for exact-count evidence; never logs bodies or credentials. */
 private fun requireDevelopment() {
  check(config.url == "https://hijtwgugzzpjjkuutyfy.supabase.co" && config.publicKey.startsWith("sb_publishable_")) { "Live QA requires the development service only." }
 }
 private fun logoutParent(token: String) {
  requireDevelopment()
  val c=URL(config.url+"/auth/v1/logout?scope=local").openConnection() as HttpURLConnection
  try { c.requestMethod="POST"; c.connectTimeout=15000; c.readTimeout=20000; c.instanceFollowRedirects=false; c.setRequestProperty("apikey",config.publicKey); c.setRequestProperty("Authorization","Bearer $token"); check(c.responseCode in 200..299) { "Temporary QA parent session cleanup was not confirmed." } } finally { c.disconnect() }
 }
 private fun read(path: String, token: String): String {
  requireDevelopment()
  val c=URL(config.url+path).openConnection() as HttpURLConnection
  try { c.connectTimeout=15000; c.readTimeout=20000; c.instanceFollowRedirects=false; c.setRequestProperty("apikey",config.publicKey); c.setRequestProperty("Authorization","Bearer $token")
   check(c.responseCode in 200..299) { "Server verification query rejected (HTTP ${c.responseCode})." }
   return c.inputStream.bufferedReader().use { it.readText() }
  } finally { c.disconnect() }
 }
 override fun onDestroy() { scope.cancel(); super.onDestroy() }
}




