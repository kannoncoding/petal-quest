package com.petalquest.core.network

import com.petalquest.core.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

class FamilyServiceRejected(val statusCode: Int, message: String): IllegalStateException(message)
class FamilyService(private val config: ServiceConfig) {
 @Volatile private var contractAccepted = false
 private suspend fun requireContract(token: String) {
  if (!contractAccepted) {
   val version = JSONObject(request("/rest/v1/rpc/get_contract_version",token,JSONObject()))
   check(version.optInt("api_contract_version",-1) == API_CONTRACT_VERSION) { "The family service needs a compatible update before this app can connect." }
   contractAccepted = true
  }
 }
 private suspend fun request(path: String, token: String?, payload: JSONObject? = null): String = withContext(Dispatchers.IO) {
  check(config.available) { "Live service is not configured for this build." }
  val endpoint = URI(config.url + path)
  check(endpoint.scheme == "https" && endpoint.host != null) { "HTTPS required" }
  val connection = endpoint.toURL().openConnection() as HttpURLConnection
  try {
   connection.connectTimeout = 15000; connection.readTimeout = 20000
   connection.instanceFollowRedirects = false
   connection.setRequestProperty("apikey", config.publicKey)
   if (token != null) connection.setRequestProperty("Authorization", "Bearer " + token)
   connection.setRequestProperty("Content-Type", "application/json")
   if (payload != null) { connection.requestMethod = "POST"; connection.doOutput = true
    connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
   }
   val status = connection.responseCode
   if (status !in 200..299) {
    val detail=connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
    val code=try { JSONObject(detail).optString("message") } catch(e: Exception) { "" }
    val known=when(code) {
     "negative_correction_debt_policy_required" -> "This correction could not be completed. Refresh the current balance and try again."
     "stale_routine_refresh_required", "stale_note_refresh_required", "stale_day_revision_refresh_required", "stale_review_refresh_required", "stale_catalogue_refresh_required", "stale_revision_refresh_required", "version_conflict", "outcome_already_resolved" -> "Another decision changed this item. Refresh and review its latest state."
     "day_sealed", "result_sealed", "sealed_day", "appeal_expired", "day_seal_reached" -> "This day has sealed. Its result can no longer change."
     "insufficient_coins", "insufficient_balance" -> "There are not enough available coins for this approval."
     "invalid_history_range" -> "Enter a valid history date."
     "future_effective_date_required", "effective_date_must_be_future" -> "Choose an effective date after today in Costa Rica."
     "pending_reviews_require_resolution", "pending_reviews_exist", "pending_submissions_require_review" -> "Resolve all pending submissions before publishing this day."
     "explicit_cash_amount_and_reason_required", "cash_amount_and_note_required", "reason_required", "note_required" -> "Enter the required amount and reason before confirming."
     "day_taskset_must_total_100", "catalogue_day_must_total_100:0", "catalogue_day_must_total_100:1", "catalogue_day_must_total_100:2", "catalogue_day_must_total_100:3", "catalogue_day_must_total_100:4", "catalogue_day_must_total_100:5", "catalogue_day_must_total_100:6", "daily_total_must_be_100", "catalogue_daily_total_must_be_100", "invalid_catalogue_total" -> "The enabled duties must total 100 points on every day."
     "approved_appeal_requires_corrected_revision" -> "Apply the justified correction first, then accept the appeal against the updated result."
     "submitted_bonus_required" -> "The teen must submit completed bonus work before you review it."
     "excused_occurrence_required" -> "Bonus work is available only for an excused duty."
     "bonus_already_resolved", "appeal_already_resolved", "deduction_already_reversed" -> "This item was already resolved. Refresh to see the latest decision."
     "approved_bonus_correction_unavailable" -> "This duty has an approved bonus conversion and cannot be changed through an ordinary correction."
     "invalid_due_time", "invalid_deadline" -> "Enter a deadline in HH:mm format."
     "bonus_window_closed", "bonus_deadline_passed" -> "The time allowed for this bonus has ended."
     else -> null
    }
    throw FamilyServiceRejected(status,known ?: when(status) {
    401 -> "Session expired or credentials rejected. Sign in again."
    403 -> "Your account cannot perform this action."
    404 -> "Family service setup is not complete yet."
    409 -> "This action conflicts with the current family state."
    429 -> "Too many attempts. Wait and try again."
    else -> "Service rejected the request (HTTP " + status + "). No change confirmed."
   })
   }
   connection.inputStream.bufferedReader().use { it.readText() }
  } finally { connection.disconnect() }
 }
 private fun session(json: JSONObject): AuthSession {
  check(json.has("access_token")) { "Authentication did not return a session. Check confirmation requirements." }
  return AuthSession(json.getJSONObject("user").getString("id"), json.getString("access_token"), json.getString("refresh_token"), System.currentTimeMillis()/1000 + json.optLong("expires_in",3600))
 }
 suspend fun signIn(email: String, password: String) = session(JSONObject(request("/auth/v1/token?grant_type=password",null,JSONObject().put("email",email).put("password",password))))
 suspend fun recoverPassword(email: String) { request("/auth/v1/recover",null,JSONObject().put("email",email)) }
 suspend fun anonymousSignIn() = session(JSONObject(request("/auth/v1/signup",null,JSONObject())))
 suspend fun refresh(refreshToken: String) = session(JSONObject(request("/auth/v1/token?grant_type=refresh_token",null,JSONObject().put("refresh_token",refreshToken))))
 suspend fun memberships(token: String, userId: String): List<Membership> {
  requireContract(token)
  java.util.UUID.fromString(userId)
  val items = JSONArray(request("/rest/v1/memberships?select=family_id,user_id,role,actor_id,active,family:families(name)&active=eq.true&user_id=eq." + userId,token))
  return (0 until items.length()).map { val row=items.getJSONObject(it); Membership(row.getString("family_id"),row.getString("user_id"),row.getString("role"),row.getString("actor_id"),row.getBoolean("active"),row.optJSONObject("family")?.optString("name")?.takeIf { it.isNotBlank() } ?: "Your family") }
 }
 suspend fun rpc(name: String, token: String, args: JSONObject): JSONObject {
  requireContract(token)
  require(name in setOf("get_vacation_preview","set_vacation_schedule","end_vacation_mode","list_school_items","school_item_action","register_family_device","unregister_family_device","list_family_notices","create_family","issue_parent_invite","issue_teen_pairing","accept_parent_invite","redeem_teen_pairing","create_occurrence","reconcile_occurrences","submit_occurrence","approve_submission","revoke_membership","issue_teen_replacement","register_device",
   "save_assigned_routine", "correct_occurrence", "offer_bonus", "submit_bonus", "review_bonus", "reverse_deduction", "save_reflection_note", "save_task_catalogue", "confirm_cash_outcome", "review_submission_checked", "get_parent_dashboard", "review_submission", "finalize_complete_day", "enter_deduction", "review_extra_outcome", "review_reward_request", "approve_reward_request", "save_catalogue_version", "resolve_day_appeal", "get_teen_dashboard", "materialize_teen_tasks", "request_reward", "cancel_reward_request", "request_extra_outcome", "request_day_appeal",
   "register_health_installation", "list_health_installations", "request_wipe", "list_pending_wipes", "claim_wipe", "acknowledge_wipe",
   "upsert_period_range", "delete_period_range", "list_period_ranges", "submit_high_pain_checkin", "list_parent_checkins", "get_checkin_policy"))
  val result = JSONObject(request("/rest/v1/rpc/" + name,token,args))
  if(result.has("error")) throw IllegalStateException(when(result.optString("error")) {
   "rate_limited" -> "Too many code attempts. Wait and try again."
   else -> "Code or family action was rejected. Check the code and your family access."
  })
  if(name == "accept_parent_invite" || name == "redeem_teen_pairing") {
   check(result.optString("family_id").isNotBlank() && result.optString("actor_id").isNotBlank() && result.optString("role") == if(name == "accept_parent_invite") "parent" else "teen") { "Membership response was incomplete. Refresh family access." }
  }
  return result
 }
 data class HealthInstallation(val installationId: String, val enrollmentGeneration: String, val wipeStatus: String?)
 data class PeriodRange(val installationId: String, val recordId: String, val startDate: String, val endDate: String?)
 suspend fun healthInstallations(token: String, familyId: String): List<HealthInstallation> {
  java.util.UUID.fromString(familyId)
  val items = rpc("list_health_installations", token, JSONObject()).getJSONArray("installations")
  return (0 until items.length()).map { items.getJSONObject(it) }.filter { it.getString("family_id") == familyId }.map {
   HealthInstallation(it.getString("installation_id"), it.getString("enrollment_generation"), it.optString("latest_wipe_status").takeIf { value -> value.isNotBlank() && value != "null" })
  }
 }
 suspend fun periodRanges(token: String, familyId: String): List<PeriodRange> {
  java.util.UUID.fromString(familyId)
  val items = rpc("list_period_ranges", token, JSONObject().put("p_family_id", familyId)).getJSONArray("period_ranges")
  return (0 until items.length()).map { items.getJSONObject(it) }.map {
   PeriodRange(it.getString("installation_id"), it.getString("record_id"), it.getString("start_date"), if (it.isNull("end_date")) null else it.getString("end_date"))
  }
 }
 suspend fun requestHealthWipe(token: String, installationId: String, enrollmentGeneration: String, requestId: String): JSONObject {
  java.util.UUID.fromString(installationId); java.util.UUID.fromString(enrollmentGeneration); java.util.UUID.fromString(requestId)
  return rpc("request_wipe", token, JSONObject().put("p_installation_id", installationId).put("p_enrollment_generation", enrollmentGeneration).put("p_request_id", requestId))
 }

}
