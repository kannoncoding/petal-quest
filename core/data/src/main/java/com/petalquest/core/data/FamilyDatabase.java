package com.petalquest.core.data;

import androidx.room.Database;
import androidx.room.RoomDatabase;

@Database(entities = {FamilyCacheEntry.class, PendingOperation.class}, version = 1, exportSchema = true)
public abstract class FamilyDatabase extends RoomDatabase {
    public abstract FamilyDao familyDao();
}
