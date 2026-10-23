package com.petalquest.core.data;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import java.util.List;

@Dao
public interface FamilyDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE) void putCache(FamilyCacheEntry entry);
    @Query("SELECT * FROM family_cache WHERE userId=:user AND endpointId=:endpoint AND kind=:kind AND recordId=:id")
    FamilyCacheEntry cache(String user, String endpoint, String kind, String id);
    @Query("DELETE FROM family_cache WHERE userId=:user AND endpointId=:endpoint") void clearCache(String user, String endpoint);
    @Insert(onConflict = OnConflictStrategy.ABORT) void enqueue(PendingOperation operation);
    @Query("SELECT * FROM pending_operations WHERE userId=:user AND endpointId=:endpoint ORDER BY createdAtEpochMillis, requestId")
    List<PendingOperation> pending(String user, String endpoint);
    @Query("UPDATE pending_operations SET status='sent_needs_reconcile', lastAttemptEpochMillis=:now WHERE userId=:user AND endpointId=:endpoint AND requestId=:id AND status='queued'")
    int markDispatched(String user, String endpoint, String id, long now);
    @Query("DELETE FROM pending_operations WHERE userId=:user AND endpointId=:endpoint AND requestId=:id AND status='sent_needs_reconcile'")
    int acknowledge(String user, String endpoint, String id);
    @Query("UPDATE pending_operations SET status=:status WHERE userId=:user AND endpointId=:endpoint AND requestId=:id")
    int setStatus(String user, String endpoint, String id, String status);
    @Query("UPDATE pending_operations SET status='queued' WHERE userId=:user AND endpointId=:endpoint AND requestId=:id AND status LIKE 'needs_review_%'")
    int reviewForExplicitRetry(String user, String endpoint, String id);
    @Query("DELETE FROM pending_operations WHERE userId=:user AND endpointId=:endpoint") void clearQueue(String user, String endpoint);
}
