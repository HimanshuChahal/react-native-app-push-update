package com.apppushupdate

import android.content.Context
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.module.annotations.ReactModule

@ReactModule(name = AppPushUpdateModule.NAME)
class AppPushUpdateModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  @ReactMethod
  fun getPushUpdateVersion(promise: Promise) {
    try {
      val prefs = reactApplicationContext.getSharedPreferences(reactApplicationContext.getString(R.string.rn_app_push_update_shared_prefs), Context.MODE_PRIVATE)
      val version = prefs.getInt(reactApplicationContext.getString(R.string.rn_app_push_update_shared_prefs_bundle_id), -1)
      promise.resolve(version)
    } catch (e: Exception) {
      promise.reject("ERROR", e.message)
    }
  }

  companion object {
    const val NAME = "RNAppPushUpdate"
  }
}
