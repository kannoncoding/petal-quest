package com.petalquest.core.data;

import java.util.List;
import java.util.UUID;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import org.json.JSONObject;
import org.json.JSONArray;
import org.json.JSONException;

/** Local family data only. No network client or health reference exists in this class. */
public final class FamilyRepository {
    public enum CacheKind { FAMILY, QUESTS, REWARDS, REVIEWS, REMINDERS }
    public enum OperationKind { QUEST_CREATE, QUEST_UPDATE, QUEST_SUBMIT, REMINDER_SAVE, APPEAL_SUBMIT, REWARD_REQUEST, REWARD_CANCEL, EXTRA_OUTCOME_REQUEST, DAY_APPEAL_REQUEST, BONUS_SUBMIT }
    private final FamilyDatabase database;
    private final SessionStore sessions;
    private final String user;
    private final String endpoint;
    private final String generation;

    FamilyRepository(FamilyDatabase database, SessionStore sessions, String user, String endpoint) {
        this.database = database; this.sessions = sessions; this.user = user; this.endpoint = endpoint;
        synchronized (LocalData.LOCK) {
            Session active = sessions.read();
            if (active == null || !user.equals(active.userId) || !endpoint.equals(active.endpointId))
                throw new IllegalStateException("An active matching session is required");
            generation = active.generation;
        }
    }

    private void requireActive() {
        Session active = sessions.read();
        if (active == null || !user.equals(active.userId) || !endpoint.equals(active.endpointId) || !generation.equals(active.generation))
            throw new IllegalStateException("Family data belongs to a different or signed-out session");
    }

    /** Only remote-confirmed snapshots belong here; this method does not calculate awards or approvals. */
    public void cacheRemoteSnapshot(CacheKind kind, String recordId, String json) {
        synchronized (LocalData.LOCK) {
            requireActive();
            FamilyCacheEntry entry = new FamilyCacheEntry();
            entry.userId=user; entry.endpointId=endpoint; entry.kind=kind.name();
            entry.recordId=Session.required(recordId,"recordId"); entry.canonicalPayload=CanonicalJson.object(json);
            entry.fetchedAtEpochMillis=System.currentTimeMillis();
            database.familyDao().putCache(entry);
        }
    }

    public FamilyCacheEntry cached(CacheKind kind, String recordId) {
        synchronized (LocalData.LOCK) {
            requireActive();
            return database.familyDao().cache(user,endpoint,kind.name(),Session.required(recordId,"recordId"));
        }
    }

    /** Persist once; reuse the returned requestId and stored canonicalPayload for every retry. */
    public PendingOperation enqueue(OperationKind kind, String json) {
        synchronized (LocalData.LOCK) {
            requireActive();
            PendingOperation operation = new PendingOperation();
            operation.userId=user; operation.endpointId=endpoint; operation.requestId=UUID.randomUUID().toString();
            operation.kind=kind.name(); operation.canonicalPayload=familyOperationPayload(kind, json);
            operation.createdAtEpochMillis=System.currentTimeMillis();
            database.familyDao().enqueue(operation);
            return operation;
        }
    }

    /** Strict family fields; opaque nested blobs and unrelated/credential/health keys are rejected. */
    private static String familyOperationPayload(OperationKind kind, String json) {
        String[] allowed;
        switch (kind) {
            case QUEST_CREATE: allowed=new String[]{"title","description","assigned_user_id","due_at","repeat_rule"}; break;
            case QUEST_UPDATE: allowed=new String[]{"quest_id","title","description","due_at","repeat_rule"}; break;
            case QUEST_SUBMIT: allowed=new String[]{"occurrence_id"}; break;
            case REMINDER_SAVE: allowed=new String[]{"reminder_id","title","scheduled_at","repeat_rule"}; break;
            case APPEAL_SUBMIT: allowed=new String[]{"quest_id","reason"}; break;
            case REWARD_REQUEST: allowed=new String[]{"reward_id"}; break;
            case REWARD_CANCEL: allowed=new String[]{"reward_request_id"}; break;
            case EXTRA_OUTCOME_REQUEST: allowed=new String[]{"kind","outcome_key","target_date","reason"}; break;
            case DAY_APPEAL_REQUEST: allowed=new String[]{"local_date","reason"}; break;
            case BONUS_SUBMIT: allowed=new String[]{"bonus_id"}; break;
            default: throw new IllegalArgumentException("Unsupported family operation");
        }
        Set<String> fields=new HashSet<>(Arrays.asList(allowed));
        try {
            JSONObject payload=new JSONObject(json);
            Iterator<String> keys=payload.keys();
            while (keys.hasNext()) {
                String key=keys.next(); Object value=payload.get(key);
                if (!fields.contains(key) || value instanceof JSONObject || value instanceof JSONArray)
                    throw new IllegalArgumentException("Unsupported family operation field");
            }
            return CanonicalJson.object(json);
        } catch (JSONException e) { throw new IllegalArgumentException("Expected family operation JSON", e); }
    }

    public List<PendingOperation> pending() {
        synchronized (LocalData.LOCK) { requireActive(); return database.familyDao().pending(user,endpoint); }
    }

    /** Call BEFORE attempting network dispatch. A timeout stays unresolved and must be reconciled. */
    public boolean markDispatched(String requestId) {
        synchronized (LocalData.LOCK) {
            requireActive();
            return database.familyDao().markDispatched(user,endpoint,Session.required(requestId,"requestId"),System.currentTimeMillis()) == 1;
        }
    }

    /** Call ONLY after authenticated server reconciliation confirms this exact request ID. */
    public boolean acknowledgeServerResult(String requestId) {
        synchronized (LocalData.LOCK) {
            requireActive();
            return database.familyDao().acknowledge(user,endpoint,Session.required(requestId,"requestId")) == 1;
        }
    }
}
