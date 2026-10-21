package com.petalquest.core.ui

import com.petalquest.core.data.FamilyRepository
import com.petalquest.core.data.PendingOperation
import com.petalquest.core.network.FamilyService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Offline intent stays pending until an authenticated response confirms its request ID. */
class QueuedSubmissions(private val repository: FamilyRepository, private val service: FamilyService) {
 suspend fun enqueue(occurrenceId: String): PendingOperation = withContext(Dispatchers.IO) {
  repository.enqueue(FamilyRepository.OperationKind.QUEST_SUBMIT, JSONObject().put("occurrence_id",occurrenceId).toString())
 }
 suspend fun retry(operation: PendingOperation, accessToken: String): JSONObject = withContext(Dispatchers.IO) {
  require(operation.kind == FamilyRepository.OperationKind.QUEST_SUBMIT.name)
  val stored = repository.pending().firstOrNull { it.requestId == operation.requestId } ?: error("Pending submission no longer exists")
  val args = JSONObject().put("p_occurrence_id",JSONObject(stored.canonicalPayload).getString("occurrence_id")).put("p_request_id",stored.requestId)
  repository.markDispatched(stored.requestId)
  val result = service.rpc("submit_occurrence",accessToken,args)
  check(result.optString("request_id") == stored.requestId) { "Submission response could not be reconciled; it remains pending." }
  repository.acknowledgeServerResult(stored.requestId)
  result
 }
}
