package com.petalquest.core.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;

/** A persisted intent, never evidence of a successful remote mutation. */
@Entity(tableName = "pending_operations", primaryKeys = {"userId", "endpointId", "requestId"})
public final class PendingOperation {
    @NonNull public String userId = "";
    @NonNull public String endpointId = "";
    @NonNull public String requestId = "";
    @NonNull public String kind = "";
    @NonNull public String canonicalPayload = "{}";
    @NonNull public String status = "queued";
    public long createdAtEpochMillis;
    public long lastAttemptEpochMillis;
}
