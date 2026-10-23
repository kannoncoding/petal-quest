package com.petalquest.core.reminders;
import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;
@Entity(tableName = "personal_reminder_rules")
public class PersonalReminderRule {
    @PrimaryKey @NonNull public String id = "";
    @NonNull public String owner = "";
    @NonNull public String title = "";
    @NonNull public String time = "";
    @NonNull public String weekdays = "";
    @NonNull public String date = "";
    @NonNull public String zone = "America/Costa_Rica";
}
