package com.petalquest.core.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;

@Entity(tableName = "family_cache", primaryKeys = {"userId", "endpointId", "kind", "recordId"})
public final class FamilyCacheEntry {
    @NonNull public String userId = "";
    @NonNull public String endpointId = "";
    @NonNull public String kind = "";
    @NonNull public String recordId = "";
    @NonNull public String canonicalPayload = "{}";
    public long fetchedAtEpochMillis;
}
