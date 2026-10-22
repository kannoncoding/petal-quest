package com.petalquest.parent

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.petalquest.core.model.ServiceConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

/** Recovery credentials are transient, never a persisted family session. */
private class RecoveryClient(private val config: ServiceConfig) {
    private suspend fun call(path: String, method: String, payload: JSONObject?, bearer: String? = null): JSONObject = withContext(Dispatchers.IO) {
        check(config.available) { "Recovery is not configured for this app." }
        require(path in setOf("recover", "verify", "user", "logout?scope=local"))
        val uri = URI(config.url.trimEnd('/') + "/auth/v1/" + path)
        check(uri.scheme == "https" && uri.host != null)
        val connection = uri.toURL().openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15000
            connection.readTimeout = 20000
            connection.instanceFollowRedirects = false
            connection.requestMethod = method
            connection.setRequestProperty("apikey", config.publicKey)
            connection.setRequestProperty("Content-Type", "application/json")
            bearer?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            if (payload != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
            }
            when (connection.responseCode) {
                in 200..299 -> connection.inputStream.bufferedReader().use { it.readText() }.let { if (it.isBlank()) JSONObject() else JSONObject(it) }
                429 -> error("Please wait before requesting another recovery code.")
                else -> error("Recovery could not be completed. Check the code, password requirements and connection, then try again.")
            }
        } finally { connection.disconnect() }
    }

    suspend fun send(email: String) { call("recover", "POST", JSONObject().put("email", email)) }

    suspend fun verify(email: String, code: String): String {
        val result = call("verify", "POST", JSONObject().put("email", email).put("token", code).put("type", "recovery"))
        val user = result.getJSONObject("user")
        check(user.optString("email").equals(email, ignoreCase = true) && !user.optBoolean("is_anonymous")) { "Recovery identity could not be verified." }
        return result.getString("access_token").also { check(it.isNotBlank()) }
    }

    suspend fun update(accessToken: String, password: String) {
        call("user", "PUT", JSONObject().put("password", password), accessToken)
        // Revoke this transient recovery session; its tokens never enter SessionStore.
        try { call("logout?scope=local", "POST", JSONObject(), accessToken) }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { /* Password update already succeeded; discard transient credentials. */ }
    }
}

@Composable
internal fun PasswordRecoveryPanel(config: ServiceConfig) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val lifecycle = (context as? ComponentActivity)?.lifecycle
    val client = remember(config) { RecoveryClient(config) }
    var expanded by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var access by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var epoch by remember { mutableIntStateOf(0) }
    var foreground by remember { mutableStateOf(lifecycle?.currentState?.isAtLeast(Lifecycle.State.STARTED) == true) }

    fun clearSensitive() { code = ""; password = ""; confirm = ""; access = null; epoch++ }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) foreground = true
            if (event == Lifecycle.Event.ON_STOP) { foreground = false; clearSensitive() }
        }
        lifecycle?.addObserver(observer)
        onDispose { lifecycle?.removeObserver(observer); clearSensitive() }
    }
    fun action(block: suspend (Int) -> Unit) {
        if (busy || !foreground) return
        val attempt = epoch
        busy = true
        scope.launch {
            try { message = ""; block(attempt) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (foreground && epoch == attempt) message = e.message ?: "Recovery could not be completed." }
            finally { busy = false }
        }
    }

    TextButton(enabled = !busy, onClick = { expanded = !expanded; clearSensitive(); message = "" }) { Text(if (expanded) "Close password recovery" else "Forgot password?") }
    if (!expanded) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Recover your Parent account", style = MaterialTheme.typography.titleMedium)
        Text("Enter your account email, then the code from its recovery email. Return here after reading the email. Codes and passwords are cleared when you leave this app.")
        OutlinedTextField(email, { email = it; sent = false; clearSensitive() }, label = { Text("Account email") }, enabled = !busy && access == null, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email))
        if (access == null) {
            OutlinedButton(enabled = !busy && email.trim().contains('@'), onClick = {
                val target = email.trim()
                action { attempt ->
                    // Retain only the nonsecret intent if the owner opens their mail app.
                    sent = true
                    client.send(target)
                    if (foreground && epoch == attempt) { sent = true; message = "If this account can receive recovery email, a code has been sent. Check your inbox and spam folder." }
                }
            }) { Text("Email recovery code") }
            if (sent) {
                OutlinedTextField(code, { code = it.filter { digit -> digit in '0'..'9' }.take(10) }, label = { Text("Recovery code") }, enabled = !busy, singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
                Button(enabled = !busy && code.length in 6..10, onClick = {
                    val target = email.trim(); val entered = code
                    action { attempt ->
                        val verified = client.verify(target, entered)
                        if (foreground && epoch == attempt) { access = verified; code = ""; message = "Code verified. Choose a new password." }
                    }
                }) { Text("Verify code") }
            }
        } else {
            OutlinedTextField(password, { password = it }, label = { Text("New password (at least 12 characters)") }, singleLine = true, enabled = !busy, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            OutlinedTextField(confirm, { confirm = it }, label = { Text("Confirm new password") }, singleLine = true, enabled = !busy, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            Button(enabled = !busy && password.length >= 12 && password == confirm, onClick = {
                val credential = access ?: return@Button; val chosen = password
                action { attempt ->
                    client.update(credential, chosen)
                    if (foreground && epoch == attempt) { clearSensitive(); sent = false; message = "Password updated. Sign in above using your new password." }
                }
            }) { Text("Save new password") }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (message.isNotBlank()) Text(message)
    }
}
