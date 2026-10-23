package com.petalquest.core.reminders

import java.time.LocalTime
import java.time.LocalDateTime
import java.time.DayOfWeek
import java.time.LocalDate

/** School items are a separate checklist; these times never award points or fail a duty. */
object TeenCheckpointPolicy {
 val lastSchoolDay:LocalDate=LocalDate.of(2026,11,27)
 val schoolDays:Set<DayOfWeek> = setOf(DayOfWeek.MONDAY,DayOfWeek.TUESDAY,DayOfWeek.WEDNESDAY,DayOfWeek.THURSDAY,DayOfWeek.FRIDAY)
 val schoolBreaks = listOf("06:55", "08:21", "09:46", "11:26", "12:11", "13:31").map(LocalTime::parse)
 val homeTimes = listOf("15:45", "16:45", "18:00", "20:00").map(LocalTime::parse)
 val wednesdayHomeTimes = listOf("17:45", "18:45", "19:45", "20:55").map(LocalTime::parse)
 fun homeTimes(date:LocalDate)=if(date.dayOfWeek==DayOfWeek.WEDNESDAY && date<=lastSchoolDay) wednesdayHomeTimes else homeTimes
 /** Carry an incomplete school item to its next permitted break; no arbitrary ten-minute snooze. */
 fun nextSchoolBreak(after:LocalDateTime,schoolDays:Set<DayOfWeek>):LocalDateTime? {
  if(schoolDays.isEmpty()) return null
  return (0L..7L).asSequence().map { after.toLocalDate().plusDays(it) }
   .filter { it<=lastSchoolDay && it.dayOfWeek in schoolDays }.flatMap { date -> schoolBreaks.asSequence().map { date.atTime(it) } }
   .firstOrNull { it>after }
 }
 fun pendingText(titles: List<String>): String? = when(titles.size) {
  0 -> null
  1 -> titles.single()
  else -> "Review your pending tasks"
 }
}
