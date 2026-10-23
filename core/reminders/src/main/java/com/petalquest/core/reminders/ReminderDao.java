package com.petalquest.core.reminders;
import androidx.room.*;
import java.util.List;
@Dao
public interface ReminderDao {
    @Query("SELECT * FROM personal_reminder_rules") List<PersonalReminderRule> rules();
    @Insert(onConflict = OnConflictStrategy.REPLACE) void putRule(PersonalReminderRule row);
    @Query("DELETE FROM personal_reminder_rules WHERE id = :id") void deleteRule(String id);
    @Query("DELETE FROM personal_reminder_rules") void clearRules();
    @Query("SELECT * FROM reminder_occurrences") List<ReminderOccurrence> all();
    @Query("SELECT * FROM reminder_occurrences WHERE id = :id LIMIT 1") ReminderOccurrence get(String id);
    @Insert(onConflict = OnConflictStrategy.REPLACE) void put(ReminderOccurrence row);
    @Query("DELETE FROM reminder_occurrences WHERE id = :id") void delete(String id);
    @Query("DELETE FROM reminder_occurrences") void clear();
    @Insert(onConflict = OnConflictStrategy.IGNORE) long claim(ReminderDelivery row);
    @Query("SELECT COUNT(*) FROM reminder_delivery WHERE id = :id") int delivered(String id);
}
