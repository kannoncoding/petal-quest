package com.petalquest.core.sync

import kotlinx.coroutines.*
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Foreground invalidations only. Received database records are never applied locally. */
internal class FamilyRealtime(private val runtime: FamilySync) {
 private val client=OkHttpClient.Builder().pingInterval(25,TimeUnit.SECONDS).build()
 private var job: Job?=null
 @Volatile private var socket: WebSocket?=null
 fun start() { close(); job=runtime.scope.launch {
  var attempt=0
  while(isActive) {
   try {
    val (session,member)=runtime.authorize()
    val closed=CompletableDeferred<Unit>()
    val url=(runtime.config.url+"/realtime/v1/websocket").replaceFirst("https://","wss://")
    val request=Request.Builder().url(url.toHttpUrlCompat(runtime.config.publicKey)).build()
    var reference=0
    fun frame(topic: String,event: String,payload: JSONObject)=JSONObject().put("topic",topic).put("event",event).put("payload",payload).put("ref",(++reference).toString()).toString()
    val topic="realtime:family-${member.familyId}"
    val ws=client.newWebSocket(request,object: WebSocketListener() {
     override fun onOpen(webSocket: WebSocket,response: Response) {
      if(!runtime.current(session)) { webSocket.close(1000,"Session changed"); return }
      // INSERT/UPDATE only: DELETE replication cannot provide row-level authorization guarantees.
      val changes=JSONArray()
      for(event in listOf("INSERT","UPDATE")) changes.put(JSONObject().put("event",event).put("schema","public").put("table","family_notices").put("filter","recipient_user_id=eq.${session.userId}"))
      for(table in listOf("vacation_policy_versions","school_items","school_change_requests","task_occurrences","submissions","submission_reviews","day_results","reward_requests","extra_outcome_requests","day_appeals","assigned_routine_versions","parent_actions")) {
       for(event in listOf("INSERT","UPDATE")) changes.put(JSONObject().put("event",event).put("schema","public").put("table",table).put("filter","family_id=eq.${member.familyId}"))
      }
      webSocket.send(frame(topic,"phx_join",JSONObject().put("access_token",session.token).put("config",JSONObject().put("postgres_changes",changes).put("broadcast",JSONObject().put("self",false)).put("presence",JSONObject().put("key","")))))
     }
     override fun onMessage(webSocket: WebSocket,text: String) {
      if(!runtime.current(session)) { webSocket.close(1000,"Session changed"); return }
      try { val message=JSONObject(text); when(message.optString("event")) {
       "postgres_changes" -> runtime.hint()
       "phx_error","phx_close" -> { webSocket.close(1000,"Rejoin"); closed.complete(Unit) }
       "phx_reply" -> if(message.optJSONObject("payload")?.optString("status")=="error") { webSocket.close(1000,"Rejected"); closed.complete(Unit) }
      } } catch(_: Exception) { }
     }
     override fun onFailure(webSocket: WebSocket,t: Throwable,response: Response?) { closed.complete(Unit) }
     override fun onClosed(webSocket: WebSocket,code: Int,reason: String) { closed.complete(Unit) }
    })
    socket=ws
    try { while(isActive && !closed.isCompleted) {
     delay(25000); check(runtime.current(session)); val active=runtime.token(session)
     ws.send(frame("phoenix","heartbeat",JSONObject()))
     ws.send(frame(topic,"access_token",JSONObject().put("access_token",active.token)))
    } } finally { ws.close(1000,"Foreground ended"); if(socket===ws) socket=null }
   } catch(e: CancellationException) { throw e } catch(_: Exception) { }
   delay((1000L shl attempt.coerceAtMost(6)).coerceAtMost(60000)); attempt++
  }
 } }
 fun close() { job?.cancel(); job=null; socket?.close(1000,"Background"); socket=null }
}
private fun String.toHttpUrlCompat(key: String): String = this+"?apikey="+java.net.URLEncoder.encode(key,"UTF-8")+"&vsn=1.0.0"
