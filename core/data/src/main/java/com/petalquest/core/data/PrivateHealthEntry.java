package com.petalquest.core.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;

/** Reserved Phase 7 schema. No repository or public data entry API exists. */
@Entity(tableName = "private_health", primaryKeys = {"userId", "endpointId", "recordId"})
public final class PrivateHealthEntry {
    @NonNull public String userId = "";
    @NonNull public String endpointId = "";
    @NonNull public String recordId = "";
    @NonNull public byte[] encryptedPayload = new byte[0];
}
