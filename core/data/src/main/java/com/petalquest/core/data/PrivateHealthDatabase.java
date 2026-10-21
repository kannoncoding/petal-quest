package com.petalquest.core.data;

import androidx.room.Database;
import androidx.room.RoomDatabase;

/** Deliberately has no DAO/access API until encrypted health storage is implemented. */
@Database(entities = {PrivateHealthEntry.class}, version = 1, exportSchema = true)
public abstract class PrivateHealthDatabase extends RoomDatabase { }
