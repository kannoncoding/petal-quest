package com.petalquest.core.reminders;
import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;
@Entity(tableName = "reminder_delivery")
public class ReminderDelivery {
    @PrimaryKey @NonNull public String id = "";
    public long deliveredAt;
}
