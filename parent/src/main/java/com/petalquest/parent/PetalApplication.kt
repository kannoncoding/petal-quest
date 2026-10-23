package com.petalquest.parent

import android.app.Application
import com.petalquest.core.data.LocalData
import com.petalquest.core.sync.FamilySync

class PetalApplication : Application() {
 lateinit var reminders: com.petalquest.core.reminders.FamilyReminderBridge
  private set
 override fun onCreate() {
  super.onCreate()
  val local=LocalData.getInstance(this)
  val sync=FamilySync.install(this, parentConfig(), local, "parent")
  reminders=com.petalquest.core.reminders.FamilyReminderBridge.install(sync,local)
 }
}
