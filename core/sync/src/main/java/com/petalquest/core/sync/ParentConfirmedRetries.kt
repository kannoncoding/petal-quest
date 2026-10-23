package com.petalquest.core.sync

import android.content.Context
import com.petalquest.core.data.Session
import com.petalquest.core.network.FamilyServiceRejected
import org.json.JSONArray
import org.json.JSONObject

/** Reads only user-confirmed unresolved actions with a previously committed request identity. */
internal class ParentConfirmedRetries(private val runtime: FamilySync) {
 private val allowed=setOf("set_vacation_schedule","end_vacation_mode","finalize_complete_day","enter_deduction","review_reward_request","confirm_cash_outcome","review_extra_outcome","correct_occurrence","offer_bonus","review_bonus","reverse_deduction","resolve_day_appeal","save_reflection_note","save_catalogue_version","save_task_catalogue","save_assigned_routine","review_submission_checked")
 suspend fun drain(expected: Session): Boolean {
  val prefs=runtime.context.getSharedPreferences("parent-actions-${expected.generation}",Context.MODE_PRIVATE)
  val saved=prefs.getString("unresolved-actions",null) ?: return false
  val rows=JSONArray(saved); var retry=false
  for(i in 0 until rows.length()) {
   check(runtime.current(expected))
   val row=rows.getJSONObject(i); val rpc=row.getString("rpc"); val args=row.getJSONObject("args")
   if(rpc !in allowed) return retry
   val validKeys=setOf("p_start_date","p_end_date","p_effective_from","p_family_id","p_teen_id","p_local_date","p_deduction_key","p_entry_id","p_reward_request_id","p_outcome","p_note","p_outcome_request_id","p_cash_amount","p_occurrence_id","p_expected_revision","p_reason","p_description","p_bonus_id","p_appeal_id","p_text","p_expected_version","p_kind","p_catalogue_key","p_effective_from","p_payload","p_tasks","p_submission_id","p_review_note","p_routine_id","p_title","p_instructions","p_enabled","p_weekdays","p_local_due_time","p_rule_version_id","p_local_times","p_active")
   if(args.keys().asSequence().any { it !in validKeys }) return retry
   // Keys originate from the already-confirmed Parent UI. Never create a retry ID here.
   val identity=rpc+":"+args.toString()
   val id=prefs.getString(identity,null) ?: return retry
   if(prefs.contains("blocked:$id")) return retry
   try {
    java.util.UUID.fromString(id)
    val token=runtime.token(expected); check(runtime.current(expected))
    val result=runtime.service.rpc(rpc,token.token,JSONObject(args.toString()).put("p_request_id",id))
    check(runtime.current(expected))
    if(result.optString("request_id")!=id) return true
    synchronized(runtime) {
     check(runtime.current(expected))
     // Merge against latest preferences so a concurrent UI confirmation is never overwritten.
     val latest=JSONArray(prefs.getString("unresolved-actions","[]")); val remaining=JSONArray()
     for(j in 0 until latest.length()) { val candidate=latest.getJSONObject(j)
      if(candidate.getString("rpc")+":"+candidate.getJSONObject("args").toString()!=identity) remaining.put(candidate)
     }
     check(prefs.edit().putString("unresolved-actions",remaining.toString()).remove(identity).commit())
    }
    runtime.hint()
   } catch(e: FamilyServiceRejected) {
    check(runtime.current(expected))
    if(e.statusCode==401) runtime.token(expected,true)
    if(e.statusCode in 400..499 && e.statusCode !in setOf(401,408,429)) { prefs.edit().putInt("blocked:$id",e.statusCode).commit(); runtime.hint(); return false } else return true
   }
  }
  return retry
 }
}
