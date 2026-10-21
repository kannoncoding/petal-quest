package com.petalquest.core.network

import com.petalquest.core.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

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
   if (status !in 200..299) throw IllegalStateException(when(status) {
    401 -> "Session expired or credentials rejected. Sign in again."
    403 -> "Your account cannot perform this action."
    404 -> "Family service setup is not complete yet."
    409 -> "This action conflicts with the current family state."
    429 -> "Too many attempts. Wait and try again."
    else -> "Service rejected the request (HTTP " + status + "). No change confirmed."
   })
   connection.inputStream.bufferedReader().use { it.readText() }
  } finally { connection.disconnect() }
 }
 private fun session(json: JSONObject): AuthSession {
  check(json.has("access_token")) { "Authentication did not return a session. Check confirmation requirements." }
  return AuthSession(json.getJSONObject("user").getString("id"), json.getString("access_token"), json.getString("refresh_token"), System.currentTimeMillis()/1000 + json.optLong("expires_in",3600))
 }
 suspend fun signIn(email: String, password: String) = session(JSONObject(request("/auth/v1/token?grant_type=password",null,JSONObject().put("email",email).put("password",password))))
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
  require(name in setOf("create_family","issue_parent_invite","issue_teen_pairing","accept_parent_invite","redeem_teen_pairing","create_occurrence","reconcile_occurrences","submit_occurrence","approve_submission","revoke_membership","issue_teen_replacement","register_device",
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
