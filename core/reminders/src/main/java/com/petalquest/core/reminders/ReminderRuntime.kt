package com.petalquest.core.reminders

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.room.Room
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.time.*
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Host must bind only after authenticating, and clear BEFORE signout/account/role change. */
data class ReminderOwnership(val userId: String, val familyId: String, val role: String, val sessionId: String) {
    init { require(listOf(userId, familyId, role, sessionId).all { it.isNotBlank() }) }
    internal fun key() = digest(listOf(userId, familyId, role, sessionId).joinToString("\u0000"))
}
/** Server-confirmed, date-resolved dashboard entry. No recurrence is inferred from this snapshot. */
data class AssignedReminder(
    val routineId: String, val version: String, val id: String, val title: String,
    val localDate: LocalDate, val localTimes: List<LocalTime>, val weekdays: Set<DayOfWeek>
)
data class QuietHours(val start: LocalTime, val end: LocalTime) {
    init { require(start != end) }
}
data class ReminderConfiguration(val quietHours: QuietHours?, val snoozeMinutes: Int?)
data class PersonalReminder(
    val id: String = UUID.randomUUID().toString(), val title: String, val time: LocalTime,
    val weekdays: Set<DayOfWeek> = emptySet(), val oneOffDate: LocalDate? = null,
    val zoneId: String = "America/Costa_Rica"
)
internal fun digest(value: String) = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }

class ReminderRuntime private constructor(private val context: Context) {
    private val prefs = context.getSharedPreferences("reminders_state", Context.MODE_PRIVATE)
    private val db = Room.databaseBuilder(context, ReminderDatabase::class.java, "reminders.db").build()
    private val dao get() = db.reminders()
    private val alarms get() = context.getSystemService(AlarmManager::class.java)
    private val notifications get() = NotificationManagerCompat.from(context)
    private fun owner() = prefs.getString("owner", null)
    // Serialized across receiver and foreground writes, including claim/replacement/cancellation.
    private val lock = Any()

    companion object {
        const val FAMILY_ZONE = "America/Costa_Rica"
        private const val CHANNEL = "local_reminders"
        @Volatile private var instance: ReminderRuntime? = null
        fun get(context: Context): ReminderRuntime = instance ?: synchronized(this) {
            instance ?: ReminderRuntime(context.applicationContext).also { instance = it }
        }
        suspend fun initialize(context: Context, ownership: ReminderOwnership?): ReminderRuntime = get(context).also {
            it.bindOwnership(ownership)
        }
    }

    suspend fun bindOwnership(ownership: ReminderOwnership?) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val next = ownership?.key()
            if (owner() != next) {
                clearLocked()
                prefs.edit().clear().putString("owner", next).commit()
            }
            if (next != null && !prefs.getBoolean("policyInitialized", false)) {
                prefs.edit().putString("quietStart", "22:00").putString("quietEnd", "07:00")
                    .putInt("snooze", 10).putBoolean("policyInitialized", true).commit()
            }
            createChannel()
            rebuildLocked()
        }
    }
    suspend fun clearOwnership() = bindOwnership(null)
    private fun clearLocked() {
        dao.all().forEach { cancel(it) }; alarms.cancel(pending("maintenance", "rebuild"))
        db.runInTransaction { dao.clear(); dao.clearRules() }
    }
    private fun requireOwner(ownership: ReminderOwnership): String = ownership.key().also {
        check(owner() == it) { "Reminder session no longer active" }
    }

    /** Full authoritative replacement for this date window; call only after dashboard sync succeeds. */
    suspend fun syncAssigned(ownership: ReminderOwnership, snapshots: List<AssignedReminder>,
        rangeStart: LocalDate, rangeEndInclusive: LocalDate) = withContext(Dispatchers.IO) {
        require(!rangeEndInclusive.isBefore(rangeStart))
        require(java.time.temporal.ChronoUnit.DAYS.between(rangeStart, rangeEndInclusive) <= 14)
        synchronized(lock) {
            val binding = requireOwner(ownership)
            val incoming = snapshots.flatMap { snapshot ->
                require(snapshot.routineId.isNotBlank() && snapshot.version.isNotBlank() && snapshot.id.isNotBlank())
                require(!snapshot.localDate.isBefore(rangeStart) && !snapshot.localDate.isAfter(rangeEndInclusive))
                if (snapshot.weekdays.isNotEmpty() && snapshot.localDate.dayOfWeek !in snapshot.weekdays) emptyList()
                else snapshot.localTimes.distinct().map { time ->
                    occurrence(binding, "assigned", "${snapshot.routineId}/${snapshot.version}/${snapshot.id}/${snapshot.localDate}/$time",
                        snapshot.title, snapshot.localDate, time, ZoneId.of(FAMILY_ZONE))
                }
            }.associateBy { it.id }
            val stale = dao.all().filter { it.source == "assigned" &&
                it.id !in incoming }
            db.runInTransaction {
                stale.forEach { dao.delete(it.id) }
                incoming.values.forEach { if (dao.get(it.id) == null) dao.put(it) }
            }
            stale.forEach { cancel(it) }
            rebuildLocked()
        }
    }

    /** Call after fetching the authoritative prior-day result. No result or sealed => cancellation. */
    suspend fun syncPreviousDayReview(ownership: ReminderOwnership, previousDate: LocalDate,
        authoritativeUnsealed: Boolean, authoritativeSealAt: Instant? = null) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val binding = requireOwner(ownership)
            val today = LocalDate.now(ZoneId.of(FAMILY_ZONE))
            require(previousDate == today.minusDays(1))
            val incoming = if (authoritativeUnsealed && ownership.role.equals("teen", ignoreCase = true))
                occurrence(binding, "review", previousDate.toString(), "Your previous-day review is available.",
                    today, LocalTime.of(17, 0), ZoneId.of(FAMILY_ZONE)).apply { routeDate = previousDate.toString() }
                else null
            val stale = dao.all().filter { it.source == "review" && it.id != incoming?.id }
            db.runInTransaction {
                stale.forEach { dao.delete(it.id) }
                if (incoming != null && dao.get(incoming.id) == null) dao.put(incoming)
            }
            stale.forEach { cancel(it); prefs.edit().remove("expires:${it.id}").commit() }
            if (incoming != null) prefs.edit().putLong("expires:${incoming.id}", authoritativeSealAt?.toEpochMilli()
                ?: today.plusDays(1).atStartOfDay(ZoneId.of(FAMILY_ZONE)).toInstant().toEpochMilli()).commit()
            rebuildLocked()
        }
    }
    suspend fun savePersonal(ownership: ReminderOwnership, reminder: PersonalReminder) = withContext(Dispatchers.IO) {
        require(reminder.title.isNotBlank() && reminder.title.length <= 160)
        require((reminder.oneOffDate != null) xor reminder.weekdays.isNotEmpty())
        ZoneId.of(reminder.zoneId)
        synchronized(lock) {
            val binding = requireOwner(ownership)
            val old = dao.all().filter { it.source == "personal:${reminder.id}" }
            val existingRule = dao.rules().firstOrNull { it.id == reminder.id && it.owner == binding }
            val sameSchedule = existingRule != null && existingRule.time == reminder.time.toString() &&
                days(existingRule.weekdays) == reminder.weekdays && existingRule.date == reminder.oneOffDate?.toString().orEmpty() &&
                existingRule.zone == reminder.zoneId
            db.runInTransaction {
                if (sameSchedule) old.forEach { it.title = reminder.title; dao.put(it) }
                else old.forEach { dao.delete(it.id) }
                dao.putRule(PersonalReminderRule().apply {
                    id = reminder.id; owner = binding; title = reminder.title; time = reminder.time.toString()
                    weekdays = reminder.weekdays.joinToString(",") { it.value.toString() }
                    date = reminder.oneOffDate?.toString().orEmpty(); zone = reminder.zoneId
                })
            }
            if (sameSchedule) old.forEach { notifications.cancel(it.id, 1) }
            else old.forEach { cancel(it) }
            rebuildLocked()
        }
    }
    suspend fun removePersonal(ownership: ReminderOwnership, id: String) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            requireOwner(ownership)
            val old = dao.all().filter { it.source == "personal:$id" }
            db.runInTransaction { dao.deleteRule(id); old.forEach { dao.delete(it.id) } }
            old.forEach { cancel(it) }
        }
    }
    suspend fun personalReminders(ownership: ReminderOwnership): List<PersonalReminder> = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val binding = requireOwner(ownership)
            dao.rules().filter { it.owner == binding }.map { r -> PersonalReminder(r.id, r.title,
                LocalTime.parse(r.time), days(r.weekdays), r.date.takeIf { it.isNotEmpty() }?.let(LocalDate::parse), r.zone) }
        }
    }
    /** Null quiet hours disables them. Null snooze removes the action until the owner configures it. */
    suspend fun configure(ownership: ReminderOwnership, quietHours: QuietHours?, snoozeMinutes: Int?) = withContext(Dispatchers.IO) {
        require(snoozeMinutes == null || snoozeMinutes in 1..120)
        synchronized(lock) {
            requireOwner(ownership)
            prefs.edit().putString("quietStart", quietHours?.start?.toString())
                .putString("quietEnd", quietHours?.end?.toString()).putInt("snooze", snoozeMinutes ?: 0)
                .putBoolean("policyInitialized", true).commit()
            rebuildLocked()
        }
    }
    /** Configuration is inert by default; enabling requires every outstanding owner decision. */
    suspend fun configureParentCheckpoints(ownership: ReminderOwnership, plan: ParentCheckpointPlan) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            requireOwner(ownership)
            require(ownership.role.equals("parent", true))
            if (plan.enabled) {
                require(plan.recipientUserIds.isNotEmpty() && plan.weekdays.isNotEmpty())
                require(!plan.suppressionPolicy.isNullOrBlank() && plan.wednesdayShiftThrough != null)
                require(plan.wednesdayShiftThrough.year == 2026)
            }
            val json = JSONObject().put("enabled", plan.enabled)
                .put("recipients", JSONArray(plan.recipientUserIds.toList()))
                .put("weekdays", JSONArray(plan.weekdays.map { it.value }))
                .put("suppression", plan.suppressionPolicy).put("shiftThrough", plan.wednesdayShiftThrough?.toString())
            prefs.edit().putString("parentPlan", json.toString()).commit()
            // A changed policy invalidates all already resolved checkpoints until host confirms fresh state.
            val stale = dao.all().filter { it.source == "checkpoint" }
            db.runInTransaction { stale.forEach { dao.delete(it.id) } }
            stale.forEach { cancel(it) }
        }
    }
    private fun parentPlanLocked(): ParentCheckpointPlan {
        val raw = prefs.getString("parentPlan", null) ?: return ParentCheckpointPlan()
        val json = JSONObject(raw)
        val recipients = json.getJSONArray("recipients")
        val weekdays = json.getJSONArray("weekdays")
        return ParentCheckpointPlan(json.optBoolean("enabled"),
            (0 until recipients.length()).map { recipients.getString(it) }.toSet(),
            (0 until weekdays.length()).map { DayOfWeek.of(weekdays.getInt(it)) }.toSet(),
            json.optString("suppression").takeIf { it.isNotBlank() && it != "null" },
            json.optString("shiftThrough").takeIf { it.isNotBlank() && it != "null" }?.let(LocalDate::parse))
    }
    suspend fun parentCheckpointPlan(ownership: ReminderOwnership): ParentCheckpointPlan = withContext(Dispatchers.IO) {
        synchronized(lock) { requireOwner(ownership); parentPlanLocked() }
    }
    /** Explicit host-confirmed date occurrences only. Never called until pending owner decisions are approved. */
    suspend fun syncConfirmedParentCheckpoints(ownership: ReminderOwnership, confirmed: List<ConfirmedParentCheckpoint>, coveredDates: Set<LocalDate>? = null) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val binding = requireOwner(ownership)
            require(ownership.role.equals("parent", true))
            val plan = parentPlanLocked()
            val incoming = if (!plan.enabled || ownership.userId !in plan.recipientUserIds) emptyList() else confirmed
                .filter { !it.suppress && it.localDate.dayOfWeek in plan.weekdays }.map { value ->
                    val slot = ParentCheckpointPlan.slots.single { it.key == value.slotKey }
                    val shifted = value.localDate.dayOfWeek == DayOfWeek.WEDNESDAY && value.localDate.year == 2026 &&
                        plan.wednesdayShiftThrough != null && value.localDate <= plan.wednesdayShiftThrough
                    val time = if (shifted) slot.wednesdayTime ?: slot.time else slot.time
                    occurrence(binding, "checkpoint", "${slot.key}/${value.localDate}/$time", slot.title,
                        value.localDate, time, ZoneId.of(FAMILY_ZONE))
                }
            val ids = incoming.map { it.id }.toSet()
            val stale = dao.all().filter { it.source == "checkpoint" && it.id !in ids && (coveredDates==null || LocalDate.parse(it.routeDate) in coveredDates) }
            db.runInTransaction {
                stale.forEach { dao.delete(it.id) }
                incoming.forEach { if (dao.get(it.id) == null) dao.put(it) }
            }
            stale.forEach { cancel(it) }
            rebuildLocked()
        }
    }
    /** Pending titles come from a confirmed daily snapshot. Empty clears that day's reminders. */
    suspend fun syncHomePendings(ownership:ReminderOwnership,date:LocalDate,titles:List<String>,times:List<LocalTime>) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val binding=requireOwner(ownership)
            require(ownership.role=="teen")
            val title=TeenCheckpointPolicy.pendingText(titles)
            val incoming=if(title==null) emptyList() else times.distinct().map { time ->
                occurrence(binding,"home_pending","$date/$time",title,date,time,ZoneId.of(FAMILY_ZONE))
            }
            val ids=incoming.map { it.id }.toSet()
            val stale=dao.all().filter { it.source=="home_pending" && (it.routeDate!=date.toString() || it.id !in ids) }
            val changedTitles=incoming.filter { next -> dao.get(next.id)?.title?.let { it!=next.title }==true }
            db.runInTransaction {
                stale.forEach { dao.delete(it.id) }
                incoming.forEach { next ->
                    val existing=dao.get(next.id)
                    if(existing==null) dao.put(next) else { existing.title=next.title;dao.put(existing) }
                }
            }
            stale.forEach { cancel(it) }
            changedTitles.forEach { notifications.cancel(it.id,1) }
            val expiry=date.plusDays(1).atStartOfDay(ZoneId.of(FAMILY_ZONE)).toInstant().toEpochMilli()
            incoming.forEach { prefs.edit().putLong("expires:${it.id}",expiry).commit() }
            rebuildLocked()
        }
    }
    /** Incomplete items recur at school breaks until completion or the last school day. */
    suspend fun syncSchoolPendings(ownership:ReminderOwnership,today:LocalDate,titles:List<String>,vacationDates:Set<LocalDate> = emptySet()) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            val binding=requireOwner(ownership)
            require(ownership.role=="teen")
            val title=TeenCheckpointPolicy.pendingText(titles)
            val incoming=if(title==null) emptyList() else (0L..45L).map { today.plusDays(it) }
                .filter { it<=TeenCheckpointPolicy.lastSchoolDay && it.dayOfWeek in TeenCheckpointPolicy.schoolDays && it !in vacationDates }
                .flatMap { date -> TeenCheckpointPolicy.schoolBreaks.map { time -> occurrence(binding,"school_pending","$date/$time",title,date,time,ZoneId.of(FAMILY_ZONE)) } }
            val ids=incoming.map { it.id }.toSet()
            val stale=dao.all().filter { it.source=="school_pending" && it.id !in ids }
            val changedTitles=incoming.filter { next -> dao.get(next.id)?.title?.let { it!=next.title }==true }
            db.runInTransaction {
                stale.forEach { dao.delete(it.id) }
                incoming.forEach { next -> val existing=dao.get(next.id);if(existing==null) dao.put(next) else { existing.title=next.title;dao.put(existing) } }
            }
            stale.forEach { cancel(it) }
            changedTitles.forEach { notifications.cancel(it.id,1) }
            val expires=TeenCheckpointPolicy.lastSchoolDay.plusDays(1).atStartOfDay(ZoneId.of(FAMILY_ZONE)).toInstant().toEpochMilli()
            incoming.forEach { prefs.edit().putLong("expires:${it.id}",expires).apply() }
            rebuildLocked()
        }
    }
    suspend fun configuration(ownership: ReminderOwnership): ReminderConfiguration = withContext(Dispatchers.IO) {
        synchronized(lock) {
            requireOwner(ownership)
            val start = prefs.getString("quietStart", null)
            val end = prefs.getString("quietEnd", null)
            ReminderConfiguration(if (start != null && end != null) QuietHours(LocalTime.parse(start), LocalTime.parse(end)) else null,
                prefs.getInt("snooze", 0).takeIf { it > 0 })
        }
    }
    fun isCurrentOwnership(ownership: ReminderOwnership, notificationOwner: String?): Boolean =
        notificationOwner != null && owner() == ownership.key() && notificationOwner == ownership.key()
    fun canNotify(): Boolean = (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context,
        Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && notifications.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 26 || context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    suspend fun rebuild() = withContext(Dispatchers.IO) { synchronized(lock) { rebuildLocked() } }
    private fun days(raw: String) = raw.split(',').filter { it.isNotEmpty() }.map { DayOfWeek.of(it.toInt()) }.toSet()
    private fun occurrence(binding: String, source: String, identity: String, title: String,
        date: LocalDate, time: LocalTime, zone: ZoneId) = ReminderOccurrence().apply {
        id = digest("$binding/$source/$identity"); owner = binding; this.source = source
        this.title = title; routeDate = date.toString(); dueAt = date.atTime(time).atZone(zone).toInstant().toEpochMilli()
    }
    private fun rebuildLocked() {
        val binding = owner() ?: return
        val now = System.currentTimeMillis()
        dao.rules().filter { it.owner == binding }.forEach { rule ->
            val zone = ZoneId.of(rule.zone)
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            val dates = if (rule.date.isNotEmpty()) listOf(LocalDate.parse(rule.date))
                else (0L..30L).map(today::plusDays).filter { it.dayOfWeek in days(rule.weekdays) }
            dates.forEach { date ->
                val row = occurrence(binding, "personal:${rule.id}", "$date/${rule.time}", rule.title, date, LocalTime.parse(rule.time), zone)
                if (dao.get(row.id) == null && row.dueAt >= now) dao.put(row)
            }
        }
        dao.all().forEach { row ->
            if (row.owner != binding) { cancel(row); return@forEach }
            if (prefs.getLong("expires:${row.id}", Long.MAX_VALUE) <= now) {
                row.dismissed = true; dao.put(row); cancel(row); return@forEach
            }
            val deliveryKey = if (row.snoozedUntil > 0) "${row.id}/snooze/${row.snoozedUntil}" else row.id
            if (!row.dismissed && dao.delivered(deliveryKey) == 0) {
                val whenAt = deliveryTime(row)
                // Do not replay missed occurrences on restart, grant, or clock correction.
                if (whenAt >= now) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenAt, pending(row.id, "deliver"))
                // Preserve an already registered, overdue inexact alarm: Android may still deliver it late.
            }
        }
        // Rolling recurrence horizon is extended even if no reminder is delivered.
        val tomorrow = Instant.ofEpochMilli(now).atZone(ZoneId.of(FAMILY_ZONE)).toLocalDate().plusDays(1)
            .atStartOfDay(ZoneId.of(FAMILY_ZONE)).toInstant().toEpochMilli()
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, tomorrow, pending("maintenance", "rebuild"))
    }
    private fun quietAdjusted(time: Long): Long {
        val start = prefs.getString("quietStart", null)?.let(LocalTime::parse) ?: return time
        val end = prefs.getString("quietEnd", null)?.let(LocalTime::parse) ?: return time
        val dateTime = Instant.ofEpochMilli(time).atZone(ZoneId.of(FAMILY_ZONE))
        val local = dateTime.toLocalTime()
        val inside = if (start < end) local >= start && local < end else local >= start || local < end
        if (!inside) return time
        val date = if (start > end && local >= start) dateTime.toLocalDate().plusDays(1) else dateTime.toLocalDate()
        return date.atTime(end).atZone(ZoneId.of(FAMILY_ZONE)).toInstant().toEpochMilli()
    }
    private fun deliveryTime(row:ReminderOccurrence):Long {
        val time=maxOf(row.dueAt,row.snoozedUntil)
        // The specifically requested pre-class 06:55 checkpoint takes precedence over 07:00 quiet end.
        val beforeClass=row.source=="school_pending" && Instant.ofEpochMilli(row.dueAt).atZone(ZoneId.of(FAMILY_ZONE)).toLocalTime()==LocalTime.of(6,55)
        return if(beforeClass) time else quietAdjusted(time)
    }
    private fun pending(id: String, action: String): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, ReminderReceiver::class.java).setAction(action)
            .setData(Uri.Builder().scheme("petalquest-reminder").authority(context.packageName).appendPath(id).appendPath(action).build()),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancelAlarm(id: String) { alarms.cancel(pending(id, "deliver")) }
    private fun cancel(row: ReminderOccurrence) { cancelAlarm(row.id); notifications.cancel(row.id, 1) }

    internal suspend fun handle(id: String, action: String) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            if (action == "rebuild") { rebuildLocked(); return@synchronized }
            val row = dao.get(id) ?: return@synchronized
            if (row.owner != owner() || row.dismissed) return@synchronized
            val now = System.currentTimeMillis()
            if (prefs.getLong("expires:${row.id}", Long.MAX_VALUE) <= now) {
                row.dismissed = true; dao.put(row); cancel(row); return@synchronized
            }
            when (action) {
                "dismiss" -> { row.dismissed = true; dao.put(row); cancel(row) }
                "snooze" -> {
                    val minutes = prefs.getInt("snooze", 0)
                    if (minutes > 0 && dao.delivered(row.id) > 0) {
                        row.snoozedUntil = now + minutes * 60_000L; dao.put(row); cancel(row); rebuildLocked()
                    }
                }
                "deliver" -> {
                    val due = deliveryTime(row)
                    if (due > now) { rebuildLocked(); return@synchronized }
                    if (!canNotify()) return@synchronized
                    val key = if (row.snoozedUntil > 0) "${row.id}/snooze/${row.snoozedUntil}" else row.id
                    // Claim before posting: at-most-once across process death and clock rollback.
                    val claim = ReminderDelivery().apply { this.id = key; deliveredAt = now }
                    if (dao.claim(claim) == -1L) return@synchronized
                    createChannel()
                    val public = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(android.R.drawable.ic_popup_reminder)
                        .setContentTitle("Petal Quest").setContentText("You have a reminder.").build()
                    val builder = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(android.R.drawable.ic_popup_reminder)
                        .setContentTitle("Petal Quest reminder").setContentText(row.title).setAutoCancel(true)
                        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPublicVersion(public)
                        .setDeleteIntent(pending(id, "dismiss"))
                        .addAction(0, "Dismiss", pending(id, "dismiss"))
                    if (prefs.getInt("snooze", 0) > 0 && row.source!="school_pending") builder.addAction(0, "Snooze", pending(id, "snooze"))
                    context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
                        launch.data = Uri.Builder().scheme("petalquest-reminder").authority(context.packageName).appendPath(id).build()
                        launch.putExtra("reminder_date", row.routeDate).putExtra("reminder_owner", row.owner)
                        builder.setContentIntent(PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    }
                    try { notifications.notify(id, 1, builder.build()) } catch (_: SecurityException) { /* revoked concurrently */ }
                    rebuildLocked()
                }
            }
        }
    }
    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, "Local reminders", NotificationManager.IMPORTANCE_DEFAULT))
    }
}
