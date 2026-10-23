package com.petalquest.core.reminders;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** Each row is a date-resolved occurrence, never a server task mutation. */
@Entity(tableName = "reminder_occurrences")
public class ReminderOccurrence {
    @PrimaryKey @NonNull public String id = "";
    @NonNull public String owner = "";
    @NonNull public String source = "personal";
    @NonNull public String title = "";
    @NonNull public String routeDate = "";
    public long dueAt;
    public long snoozedUntil;
    public boolean dismissed;
}
