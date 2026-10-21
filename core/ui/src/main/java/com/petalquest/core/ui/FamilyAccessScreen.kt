package com.petalquest.core.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.petalquest.core.model.*
import com.petalquest.core.network.FamilyService
import com.petalquest.core.data.LocalData
import com.petalquest.core.data.Session
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Composable
fun FamilyAccessScreen(isParent: Boolean, config: ServiceConfig, localData: LocalData, modifier: Modifier = Modifier) {
 val scope = rememberCoroutineScope()
 val context = LocalContext.current
 val service = remember(config) { FamilyService(config) }
 var live by remember { mutableStateOf(false) }
 var session by remember { mutableStateOf<Session?>(null) }
 var sessionLoaded by remember { mutableStateOf(false) }
 var requiresReset by remember { mutableStateOf(false) }
 var memberships by remember { mutableStateOf(emptyList<Membership>()) }
 var email by remember { mutableStateOf("") }; var password by remember { mutableStateOf("") }
 var code by remember { mutableStateOf("") }; var familyName by remember { mutableStateOf("") }
 var selectedFamily by remember { mutableStateOf("") }
 var message by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
 var issuedCode by remember { mutableStateOf("") }
 suspend fun save(auth: AuthSession) { val next=Session(auth.userId,config.url,auth.accessToken,auth.refreshToken,auth.expiresAtEpochSeconds); withContext(Dispatchers.IO) { localData.activate(next) }; session=next }
 fun action(block: suspend () -> Unit) { if(busy) return; busy=true; issuedCode=""; scope.launch { message=""; try { block() } catch(e: CancellationException) { throw e } catch(e: Exception) { message=e.message ?: "Request failed. No change confirmed." } finally { busy=false } } }
 suspend fun token(): String {
  val current = session ?: error("Sign in first")
  if(current.expiresAtEpochSeconds <= System.currentTimeMillis()/1000+60) { save(service.refresh(current.refreshToken)) }
  return session!!.token
 }
 suspend fun reload() { memberships=service.memberships(token(),session!!.userId).filter { it.userId == session!!.userId && it.active }; if(selectedFamily !in memberships.map { it.familyId }) selectedFamily=memberships.firstOrNull()?.familyId.orEmpty() }
 LaunchedEffect(localData) {
  try { session = withContext(Dispatchers.IO) { localData.sessionStore().read()?.takeIf { it.endpointId == config.url } } }
  catch(e: CancellationException) { throw e } catch(e: Exception) { requiresReset=true; message="Stored session could not be opened. Reset local family access to sign in again." }
  finally { sessionLoaded=true }
 }
 Column(modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
  Text(if(isParent) "Petal Quest · Parent" else "Petal Quest · Teen",style=MaterialTheme.typography.headlineSmall)
  Text(if(live) "LIVE · " + config.environment else "DEMO · offline preview")
  Text(if(live) "Family permissions come from your verified server membership." else "Explore the family setup flow. No family changes are sent in demo mode.")
  Row { Text("Use live service"); Switch(checked=live,onCheckedChange={ live=it; message=""; issuedCode="" },enabled=config.available && !busy && sessionLoaded && !requiresReset) }
  if(requiresReset) OutlinedButton(enabled=!busy,onClick={action { withContext(Dispatchers.IO) { localData.resetLocalFamilyAndSession() };session=null;memberships=emptyList();requiresReset=false;message="Local family access reset. Private health data retained." }}) { Text("Reset local family access") }
  if(!config.available) Text("Live access is disabled: this build has no local public service configuration.")
  if(!live) {
   Text(if(isParent) "Parents sign in, create a family, and share expiring invitation or teen pairing codes." else "Ask your parent for a teen pairing code. Live pairing requires anonymous sign-in to be enabled by the project administrator.")
  } else if(session==null) {
   if(isParent) {
    OutlinedTextField(email,{email=it},label={Text("Email")},singleLine=true)
    OutlinedTextField(password,{password=it},label={Text("Password")},visualTransformation=PasswordVisualTransformation(),singleLine=true)
    Button(enabled=!busy && email.isNotBlank() && password.isNotBlank(),onClick={action { try { save(service.signIn(email.trim(),password)); reload() } finally { password="" } }}) {Text("Sign in")}
    Text("Use your provisioned parent account. Account registration and email confirmation are managed separately.")
   } else {
    OutlinedTextField(code,{code=it},label={Text("Parent's pairing code")},singleLine=true)
    Button(enabled=!busy && code.isNotBlank(),onClick={action { save(service.anonymousSignIn()); val result=service.rpc("redeem_teen_pairing",token(),JSONObject().put("p_code",code.trim())); reload(); check(memberships.any { it.familyId==result.getString("family_id") && it.role=="teen" }) { "Membership could not be verified. Refresh family access." }; code=""; message="Connected. Membership loaded from service." }}) {Text("Connect to family")}
    Text("Anonymous authentication must be enabled by the project administrator.")
   }
  } else {
   Text("Signed in")
   Button(enabled=!busy,onClick={action { reload() }}) {Text("Refresh family access")}
   memberships.forEach { membership ->
    OutlinedButton(enabled=!busy,onClick={selectedFamily=membership.familyId}) {Text((if(selectedFamily==membership.familyId) "✓ " else "") + membership.familyName + " · " + membership.role)}
   }
   if(memberships.isEmpty()) Text("No family membership yet.")
   if(isParent) {
    OutlinedTextField(familyName,{familyName=it},label={Text("Family name")})
    Button(enabled=!busy && familyName.isNotBlank(),onClick={action { service.rpc("create_family",token(),JSONObject().put("p_name",familyName.trim())); reload(); message="Family created." }}) {Text("Create family")}
    OutlinedTextField(code,{code=it},label={Text("Parent invitation code")})
    Button(enabled=!busy && code.isNotBlank(),onClick={action { val result=service.rpc("accept_parent_invite",token(),JSONObject().put("p_code",code.trim()));reload();check(memberships.any { it.familyId==result.getString("family_id") && it.role=="parent" }) { "Membership could not be verified. Refresh family access." };code="";message="Invitation accepted." }}) {Text("Accept parent invitation")}
    if(memberships.any { it.familyId==selectedFamily && it.role=="parent" }) {
     key(selectedFamily, session!!.userId, config.url) { ParentHealthControls(service, selectedFamily, { token() }, !busy) }
     listOf("Invite parent" to "issue_parent_invite", "Pair teen" to "issue_teen_pairing").forEach { (label,rpc) ->
      Button(enabled=!busy,onClick={action { val result=service.rpc(rpc,token(),JSONObject().put("p_family_id",selectedFamily));issuedCode=result.getString("code");message="Code expires: " + result.getString("expires_at") }}) {Text(label)}
     }
    }
   } else if(memberships.isEmpty()) {
    OutlinedTextField(code,{code=it},label={Text("Parent's pairing code")})
    Button(enabled=!busy && code.isNotBlank(),onClick={action {val result=service.rpc("redeem_teen_pairing",token(),JSONObject().put("p_code",code.trim()));reload();check(memberships.any { it.familyId==result.getString("family_id") && it.role=="teen" }) { "Membership could not be verified. Refresh family access." };code="";message="Connected."}}) {Text("Connect to family")}
   }
   OutlinedButton(enabled=!busy,onClick={action { withContext(Dispatchers.IO) { localData.logout() }; session=null;memberships=emptyList();selectedFamily="";code="";password="";message="Signed out. Local family session cleared." }}) {Text("Sign out and clear local session")}
  }
  if(busy) CircularProgressIndicator()
  if(live && issuedCode.isNotBlank()) {
   Text("Share this code only with the intended family member.")
   Text(issuedCode)
   OutlinedButton(onClick={
    val clip=ClipData.newPlainText("Petal Quest family access code",issuedCode)
    clip.description.extras=PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE",true) }
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
   }) { Text("Copy code") }
  }
  if(message.isNotBlank()) Text(message)
 }
}
