package com.petalquest.core.reminders

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime

/** Approved daily Parent times; authenticated snapshot resolution supplies recipients and suppression. */
data class ParentCheckpointSlot(val key: String, val title: String, val time: LocalTime,
    val wednesdayTime: LocalTime? = null)

data class ParentCheckpointPlan(
    val enabled: Boolean = false,
    val recipientUserIds: Set<String> = emptySet(),
    val weekdays: Set<DayOfWeek> = emptySet(),
    val suppressionPolicy: String? = null,
    val wednesdayShiftThrough: LocalDate? = null
) {
    companion object {
        val slots = listOf(
            ParentCheckpointSlot("morning", "Morning after high-school drop", LocalTime.of(7, 15)),
            ParentCheckpointSlot("first_tasks", "First tasks completion", LocalTime.of(16, 0), LocalTime.of(18, 0)),
            ParentCheckpointSlot("more_tasks", "More tasks completion plus attitude", LocalTime.of(17, 0), LocalTime.of(19, 0)),
            ParentCheckpointSlot("all_tasks", "All tasks completion", LocalTime.of(20, 0)),
            ParentCheckpointSlot("finalize", "Finalize day review", LocalTime.of(21, 10))
        )
    }
}

/** Host resolves confirmed suppression against authoritative state; no task changes happen here. */
data class ConfirmedParentCheckpoint(val slotKey: String, val localDate: LocalDate, val suppress: Boolean)
