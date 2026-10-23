package com.example.petalquest

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.petalquest.core.sync.FamilySync
import com.petalquest.core.sync.FamilyPushNotifications
import kotlinx.coroutines.runBlocking

class TeenMessagingService : FirebaseMessagingService() {
 override fun onNewToken(token:String) { FamilySync.get()?.registration?.updateToken(token) }
 override fun onMessageReceived(message:RemoteMessage) {
  if(message.notification==null && message.data["kind"]=="family_update") runBlocking { FamilyPushNotifications.receive(this@TeenMessagingService,message.data) }
 }
}
