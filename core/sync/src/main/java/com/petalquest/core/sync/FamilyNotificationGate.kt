package com.petalquest.core.sync

import com.petalquest.core.model.Membership
import com.petalquest.core.data.Session

/** A hint can select a destination only after current authenticated access has been checked. */
object FamilyNotificationGate {
 data class Hint(val eventId: String,val destination: String,val familyId: String,val teenId: String?,val localDate: String?)
 fun parse(data: Map<String,String>,session: Session?,membership: Membership?,nowEpoch: Long=System.currentTimeMillis()/1000): Hint? {
  if(session==null || membership==null || !membership.active || membership.userId!=session.userId) return null
  if(data["kind"]!="family_update" || data["recipient_user_id"]!=session.userId || data["family_id"]!=membership.familyId) return null
  val expiry=data["expires_at_epoch"]?.toLongOrNull() ?: return null
  if(expiry<=nowEpoch || data["destination"] !in setOf("review","today","results","rewards","routines","school")) return null
  val event=data["event_id"] ?: return null
  try { java.util.UUID.fromString(event) } catch(_: Exception) { return null }
  val teen=data["teen_id"]?.takeIf { it.isNotBlank() }
  if(membership.role=="teen" && teen!=null && teen!=membership.actorId) return null
  val date=data["local_date"]?.takeIf { it.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) }
  return Hint(event,data.getValue("destination"),membership.familyId,teen,date)
 }
}
