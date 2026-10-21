package com.example.petalquest.health

import android.content.Context
import android.util.AtomicFile
import com.example.petalquest.BuildConfig
import com.petalquest.core.data.LocalData
import com.petalquest.core.data.Session
import com.petalquest.core.health.CycleVault
import com.petalquest.core.model.Membership
import com.petalquest.core.model.ServiceConfig
import com.petalquest.core.network.FamilyService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.Locale

/** Only installation identity, enrollment and wipe receipts are persisted here, never journal content. */
class TeenHealthSync private constructor(context: Context) {
    private val app = context.applicationContext
    private val data = LocalData.getInstance(app)
    private val vault = CycleVault.getInstance(app)
    private val config = ServiceConfig(BuildConfig.SERVICE_URL, BuildConfig.SERVICE_PUBLIC_KEY, BuildConfig.BUILD_TYPE)
    private val service = FamilyService(config)
    private val mutex = Mutex()
    @Volatile private var replacementSessionGeneration: String? = null
    var onInvalidated: ((String) -> Unit)? = null
    private val file = AtomicFile(File(app.noBackupFilesDir, "health_control.json"))
    private fun load(): JSONObject {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return JSONObject().put("installation", UUID.randomUUID().toString()).put("receipts", JSONArray())
        return JSONObject(String(file.readFully(), Charsets.UTF_8)).also {
            UUID.fromString(it.getString("installation")); it.getJSONArray("receipts")
        }
    }
    private fun persist(state: JSONObject) {
        val output = file.startWrite()
        try { output.write(state.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output) }
        catch (error: Exception) { file.failWrite(output); throw error }
    }
    private fun active(expected: Session): Boolean {
        val current = data.sessionStore().read() ?: return false
        return current.generation == expected.generation && current.userId == expected.userId && current.endpointId == expected.endpointId
    }
    private suspend fun session(): Session {
        val current = data.sessionStore().read() ?: error("No session")
        check(current.endpointId == Session.normalizeEndpoint(config.url))
        if (current.expiresAtEpochSeconds > System.currentTimeMillis()/1000 + 60) return current
        val refreshed = service.refresh(current.refreshToken)
        val replacement = Session(refreshed.userId, current.endpointId, refreshed.accessToken, refreshed.refreshToken, refreshed.expiresAtEpochSeconds)
        check(data.sessionStore().refreshIfCurrent(current, replacement))
        return data.sessionStore().read() ?: error("Session changed")
    }
    private fun matches(binding: JSONObject, session: Session) = binding.getString("endpoint") == session.endpointId && binding.getString("user") == session.userId
    private fun args(state: JSONObject, binding: JSONObject) = JSONObject().put("p_installation_id", state.getString("installation")).put("p_enrollment_generation", binding.getString("generation"))
    private fun receipts(state: JSONObject) = state.getJSONArray("receipts")
    private fun unresolved(state: JSONObject): Boolean = (0 until receipts(state).length()).any { !receipts(state).getJSONObject(it).optBoolean("acknowledged") }
    private suspend fun finishLocalDeletion(state: JSONObject, onWiped: suspend () -> Unit) {
        val binding = state.optJSONObject("binding") ?: return
        val entries = receipts(state)
        for (index in 0 until entries.length()) {
            val receipt = entries.getJSONObject(index)
            if (receipt.getString("state") != "applying") continue
            check(receipt.getString("generation") == binding.getString("generation"))
            // Tombstone was durably committed before this irreversible operation.
            vault.resetConfirmed()
            withContext(Dispatchers.Main) { onInvalidated?.invoke("A parent requested deletion of this device’s health log."); onWiped() }
            receipt.put("state", "done"); persist(state)
        }
    }
    /** Always complete a previously claimed local deletion, even offline, before any unlock. */
    suspend fun beforeUnlock(acceptReplacement: Boolean = false): String? = withContext(Dispatchers.IO) { mutex.withLock {
        val state = load(); persist(state)
        finishLocalDeletion(state) {}
        accessCheck(state, acceptReplacement)
    } }
    private suspend fun accessCheck(state: JSONObject, acceptReplacement: Boolean): String? {
        val binding = state.optJSONObject("binding") ?: return null
        if (unresolved(state) || binding.has("next_generation")) return "A parent deletion is finishing. Reconnect this family session before opening a new journal."
        val current = data.sessionStore().read() ?: return "Restore the previous family session to open this device’s health log."
        if (matches(binding, current)) return null
        if (acceptReplacement && current.endpointId == binding.getString("endpoint")) {
            val authenticated = session()
            val membership = service.memberships(authenticated.token, authenticated.userId).firstOrNull { it.active && it.role == "teen" && it.familyId == binding.getString("family") && it.actorId == binding.getString("actor") }
            if (membership != null && active(authenticated)) { replacementSessionGeneration = authenticated.generation; return null }
        }
        return "This journal belongs to a different family profile. Restore its previous identity, or explicitly verify a replacement session for the same Teen."
    }
    suspend fun unlockAuthenticated(acceptReplacement: Boolean, foreground: () -> Boolean): Long = withContext(Dispatchers.IO) { mutex.withLock {
        val state = load(); persist(state); finishLocalDeletion(state) {}
        check(accessCheck(state, acceptReplacement) == null && foreground())
        vault.unlockAfterAuthentication()
    } }

    /** Fresh OS authentication authorizes control enrollment without opening the health key. */
    suspend fun enrollControlsAuthenticated(foreground: () -> Boolean): String = withContext(Dispatchers.IO) { mutex.withLock {
        check(foreground())
        val state = load(); persist(state)
        check(!unresolved(state))
        val current = session()
        val memberships = service.memberships(current.token, current.userId).filter { it.active && it.role == "teen" }
        val previous = state.optJSONObject("binding")
        val membership = if (previous == null) memberships.single() else memberships.single {
            it.familyId == previous.getString("family") && it.actorId == previous.getString("actor")
        }
        if (previous != null) check(previous.getString("endpoint") == current.endpointId)
        check(foreground() && active(current))
        val binding = previous ?: JSONObject().put("generation", UUID.randomUUID().toString()).put("consent", 0)
        if (previous != null && previous.getString("user") != current.userId) {
            binding.put("next_generation", binding.optString("next_generation").ifBlank { UUID.randomUUID().toString() })
        }
        binding.put("endpoint", current.endpointId).put("user", current.userId).put("actor", membership.actorId).put("family", membership.familyId).put("controlConsent", 1)
        state.put("binding", binding); persist(state)
        check(foreground() && active(current))
        register(state, binding, current)
        "Parent device controls enabled for Teen device ${code(state.getString("installation"))}. Period date sharing is a separate action after health unlock."
    } }

    /** Explicit informed consent, after phone authentication; never enroll from startup polling. */
    suspend fun enroll(): String = withContext(Dispatchers.IO) { mutex.withLock {
        check(vault.isUnlocked)
        val token = vault.generation()
        val state = load(); persist(state); finishLocalDeletion(state) {}
        check(!unresolved(state))
        val current = session()
        val memberships = service.memberships(current.token, current.userId).filter { it.active && it.role == "teen" }
        val previous = state.optJSONObject("binding")
        val membership: Membership = if (previous == null) memberships.single() else memberships.single { it.familyId == previous.getString("family") && it.actorId == previous.getString("actor") }
        check(active(current) && vault.isUnlocked && vault.generation() == token)
        if (previous != null) check(previous.getString("endpoint") == current.endpointId)
        val binding = if (previous == null) JSONObject().put("generation", UUID.randomUUID().toString()) else previous
        if (previous != null && previous.getString("user") != current.userId) binding.put("next_generation", binding.optString("next_generation").ifBlank { UUID.randomUUID().toString() })
        binding.put("endpoint", current.endpointId).put("user", current.userId).put("actor", membership.actorId).put("family", membership.familyId).put("consent", 1).put("controlConsent", 1)
        state.put("binding", binding); persist(state)
        register(state, binding, current)
        syncRanges(state, binding, current)
        "Family date sharing enabled. Device ${code(state.getString("installation"))}."
    } }
    private suspend fun register(state: JSONObject, binding: JSONObject, current: Session) {
        check(active(current))
        val desired = binding.optString("next_generation").ifBlank { binding.getString("generation") }
        service.rpc("register_health_installation", current.token, JSONObject().put("p_installation_id", state.getString("installation")).put("p_enrollment_generation", desired))
        check(active(current))
        if (binding.has("next_generation")) { binding.put("generation", desired); binding.remove("next_generation") }
        persist(state)
    }
    /** Foreground polling uses only an existing matching enrollment; no enrollment or health upload at startup. */
    suspend fun poll(onWiped: suspend () -> Unit = {}) = withContext(Dispatchers.IO) { mutex.withLock {
        val state = load(); finishLocalDeletion(state, onWiped)
        val binding = state.optJSONObject("binding") ?: return@withLock
        val local = data.sessionStore().read()
        if (local == null || !matches(binding, local)) {
            if ((local == null || replacementSessionGeneration != local.generation) && vault.isUnlocked) {
                vault.lock()
                withContext(Dispatchers.Main) { onInvalidated?.invoke("This journal belongs to a different family profile. Restore its previous family session.") }
            }
            return@withLock
        }
        val current = session()
        if (!active(current)) return@withLock
        val entries = receipts(state)
        for (index in 0 until entries.length()) {
            val receipt = entries.getJSONObject(index)
            if (receipt.getString("state") != "done" || receipt.optBoolean("acknowledged")) continue
            check(receipt.getString("generation") == binding.getString("generation"))
            val response = service.rpc("acknowledge_wipe", current.token, args(state,binding).put("p_command_id",receipt.getString("command")))
            check(response.getString("status") == "done" && active(current))
            receipt.put("acknowledged",true)
            binding.put("next_generation", UUID.randomUUID().toString()); persist(state)
        }
        if (binding.has("next_generation")) register(state,binding,current)
        val commands = service.rpc("list_pending_wipes", current.token, args(state,binding)).getJSONArray("commands")
        for (index in 0 until commands.length()) {
            check(active(current))
            val command = commands.getJSONObject(index).getString("command_id")
            if ((0 until entries.length()).any { entries.getJSONObject(it).getString("command") == command }) continue
            val response = service.rpc("claim_wipe", current.token, args(state,binding).put("p_command_id",command))
            if (response.optString("status") != "claimed") continue
            check(active(current) && response.getString("enrollment_generation") == binding.getString("generation"))
            val receipt = JSONObject().put("command",command).put("generation",binding.getString("generation")).put("state","applying").put("acknowledged",false)
            entries.put(receipt); persist(state)
            finishLocalDeletion(state,onWiped)
            val acknowledged = service.rpc("acknowledge_wipe",current.token,args(state,binding).put("p_command_id",command))
            check(acknowledged.getString("status") == "done" && active(current))
            receipt.put("acknowledged",true); binding.put("next_generation",UUID.randomUUID().toString()); persist(state)
            register(state,binding,current)
            break
        }
        if (!unresolved(state) && binding.optInt("consent") == 1 && vault.isUnlocked) syncRanges(state,binding,current)
    } }
    private suspend fun syncRanges(state: JSONObject, binding: JSONObject, current: Session) {
        if (binding.optInt("consent") != 1 || !vault.isUnlocked || !active(current)) return
        val generation = vault.generation()
        // Extract only permitted fields; do not retain daily free text across network calls.
        val (periods, checkinDates) = vault.snapshot().let { snapshot ->
            snapshot.periods to snapshot.observations.filter { (it.pain ?: 0) >= 7 }.map { it.date }
        }
        val remote = service.periodRanges(current.token,binding.getString("family")).filter { it.installationId == state.getString("installation") }
        // Remove stale/changed ranges first: their old spans must not block the
        // validated replacement snapshot through the server overlap guard.
        for (period in remote.filter { remotePeriod ->
            val localPeriod = periods.firstOrNull { it.id == remotePeriod.recordId }
            localPeriod == null || localPeriod.startDate != remotePeriod.startDate || localPeriod.endDate != remotePeriod.endDate
        }) {
            check(active(current) && vault.isUnlocked && vault.generation() == generation)
            service.rpc("delete_period_range",current.token,args(state,binding).put("p_record_id",period.recordId))
        }
        for (period in periods) {
            check(active(current) && vault.isUnlocked && vault.generation() == generation)
            service.rpc("upsert_period_range", current.token, args(state,binding).put("p_record_id",period.id).put("p_start_date",period.startDate).put("p_end_date",period.endDate ?: JSONObject.NULL))
        }
        if (checkinDates.isEmpty()) return
        val policy = service.rpc("get_checkin_policy", current.token, JSONObject())
        if (!policy.optBoolean("enabled", false)) return
        val allowedDates = checkinDates.filter { date ->
            date <= policy.getString("server_today") &&
                (policy.optBoolean("include_backdated", false) || date == policy.getString("server_today"))
        }
        for (date in allowedDates) {
            check(active(current) && vault.isUnlocked && vault.generation() == generation)
            val eventId = UUID.nameUUIDFromBytes(("parent-checkin|" + state.getString("installation") + "|" + binding.getString("generation") + "|" + date).toByteArray(Charsets.UTF_8)).toString()
            // The server alone applies the configured eligible-date policy. The payload
            // contains no score, symptoms, description, note or other journal value.
            service.rpc("submit_high_pain_checkin", current.token, args(state,binding).put("p_local_date",date).put("p_event_id",eventId))
            // policy_not_configured is intentionally not represented as alert success.
        }
    }
    suspend fun deviceCode(): String = withContext(Dispatchers.IO) { mutex.withLock { val state=load(); persist(state); code(state.getString("installation")) } }
    companion object {
        @Volatile private var instance: TeenHealthSync? = null
        fun getInstance(context: Context): TeenHealthSync = instance ?: synchronized(this) { instance ?: TeenHealthSync(context).also { instance = it } }
        fun code(id: String) = id.replace("-", "").takeLast(6).uppercase(Locale.US)
    }
}
