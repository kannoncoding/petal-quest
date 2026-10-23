package com.petalquest.core.reminders

import org.junit.Assert.*
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

/** Calendar policy only; these tests do not claim Android alarm or FCM delivery. */
class CheckpointPolicyTest {
    private fun times(vararg values: String) = values.map(LocalTime::parse)

    @Test fun schoolBreakTimesMatchApprovedSchedule() {
        assertEquals(times("06:55", "08:21", "09:46", "11:26", "12:11", "13:31"), TeenCheckpointPolicy.schoolBreaks)
        assertEquals(setOf(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
            DayOfWeek.THURSDAY, DayOfWeek.FRIDAY), TeenCheckpointPolicy.schoolDays)
    }

    @Test fun incompleteSchoolItemMovesToNextBreak() {
        assertEquals(LocalDateTime.parse("2026-10-23T08:21"),
            TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-10-23T06:55"), TeenCheckpointPolicy.schoolDays))
    }

    @Test fun fridayLastBreakCarriesToMondayBeforeClasses() {
        assertEquals(LocalDateTime.parse("2026-10-26T06:55"),
            TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-10-23T13:31"), TeenCheckpointPolicy.schoolDays))
    }

    @Test fun lastSchoolDayIncludesFinalBreak() {
        assertEquals(LocalDateTime.parse("2026-11-27T13:31"),
            TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-11-27T12:11"), TeenCheckpointPolicy.schoolDays))
    }

    @Test fun noSchoolRemindersAfterLastBreakOrDuringDecember() {
        assertNull(TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-11-27T13:31"), TeenCheckpointPolicy.schoolDays))
        assertNull(TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-12-02T06:00"), TeenCheckpointPolicy.schoolDays))
        assertNull(TeenCheckpointPolicy.nextSchoolBreak(LocalDateTime.parse("2026-10-23T06:00"), emptySet()))
    }

    @Test fun normalHomeTimesMatchApprovedSchedule() {
        assertEquals(times("15:45", "16:45", "18:00", "20:00"),
            TeenCheckpointPolicy.homeTimes(LocalDate.parse("2026-10-23")))
    }

    @Test fun wednesdayShiftAppliesThroughSchoolTerm() {
        assertEquals(times("17:45", "18:45", "19:45", "20:55"),
            TeenCheckpointPolicy.homeTimes(LocalDate.parse("2026-11-25")))
    }

    @Test fun wednesdayShiftEndsWithTerm() {
        assertEquals(times("15:45", "16:45", "18:00", "20:00"),
            TeenCheckpointPolicy.homeTimes(LocalDate.parse("2026-12-02")))
    }

    @Test fun pendingMessageNamesOnlySingleItem() {
        assertNull(TeenCheckpointPolicy.pendingText(emptyList()))
        assertEquals("Fictional duty", TeenCheckpointPolicy.pendingText(listOf("Fictional duty")))
        assertEquals("Review your pending tasks", TeenCheckpointPolicy.pendingText(listOf("First", "Second")))
    }

    @Test fun parentCheckpointTimesAndWednesdayOverridesMatchDecision() {
        assertEquals(times("07:15", "16:00", "17:00", "20:00", "21:10"), ParentCheckpointPlan.slots.map { it.time })
        assertEquals(times("07:15", "18:00", "19:00", "20:00", "21:10"), ParentCheckpointPlan.slots.map { it.wednesdayTime ?: it.time })
        assertEquals(5, ParentCheckpointPlan.slots.map { it.key }.toSet().size)
    }
}
