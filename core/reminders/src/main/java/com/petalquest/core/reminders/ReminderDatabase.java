package com.petalquest.core.reminders;
import androidx.room.Database;
import androidx.room.RoomDatabase;
@Database(entities = {ReminderOccurrence.class, ReminderDelivery.class, PersonalReminderRule.class}, version = 1, exportSchema = false)
public abstract class ReminderDatabase extends RoomDatabase {
    public abstract ReminderDao reminders();
}
