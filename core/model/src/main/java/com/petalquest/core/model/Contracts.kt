package com.petalquest.core.model

data class ServiceConfig(val url: String, val publicKey: String, val environment: String) {
 val available: Boolean get() = url.startsWith("https://") && publicKey.isNotBlank()
}
class AuthSession(val userId: String, val accessToken: String, val refreshToken: String, val expiresAtEpochSeconds: Long)
data class Membership(val familyId: String, val userId: String, val role: String, val actorId: String, val active: Boolean, val familyName: String = "Your family")
data class FamilyCode(val code: String, val expiresAt: String)
data class MutationReceipt(val requestId: String, val resourceId: String)

data class TaskOccurrence(val id: String, val familyId: String, val definitionId: String, val teenActorId: String, val ruleVersionId: String, val localDate: String, val pointsSnapshot: Int, val dueAt: String?)
data class Submission(val id: String, val occurrenceId: String, val requestId: String, val status: String)
data class Approval(val decisionId: String, val submissionId: String, val status: String, val contributionPoints: Int, val spendableXp: Int = 0)

const val API_CONTRACT_VERSION = 1
data class SubmitOccurrenceCommand(val occurrenceId: String, val requestId: String)
data class ApproveSubmissionCommand(val submissionId: String, val requestId: String)
