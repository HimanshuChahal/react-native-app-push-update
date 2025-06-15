package com.apppushupdate

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class RNAppPushUpdateFirebaseService : FirebaseMessagingService() {
  override fun onMessageReceived(message: RemoteMessage) {
    Log.d("RNAppPushUpdate", "🔥 Message received from topic: ${message.from}")

    val expectedTopic = "/topics/" + getString(R.string.rn_app_push_update_fcm_update_topic)

    if (message.from == expectedTopic) {
      Log.d("RNAppPushUpdate", "✅ Received message from topic: $expectedTopic")
      RNAppPushUpdate.checkForUpdate(application)
    } else {
      Log.d("RNAppPushUpdate", "ℹ️ Message not for our topic: ${message.from}")
    }

    message.notification?.let {
      Log.d("RNAppPushUpdate", "Notification body: ${it.body}")
    }
  }

  override fun onNewToken(token: String) {
    Log.d("RNAppPushUpdate", "🎯 New FCM Token: $token")
  }
}
