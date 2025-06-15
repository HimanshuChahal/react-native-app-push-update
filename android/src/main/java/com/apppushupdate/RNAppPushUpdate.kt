package com.apppushupdate

import android.app.Application
import android.content.Context
import android.util.Log
import android.util.Patterns
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.*
import org.json.JSONObject
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.content.edit
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

object RNAppPushUpdate {
  private var initialized = false

  fun getJSBundleFile(application: Application): String? {
    var bundlePath: String? = null
    if (!initialized) {
      val bundleFile = File(application.filesDir, "index.android.bundle")
      if (bundleFile.exists()) {
        bundlePath = bundleFile.absolutePath
      }

      Thread {
        checkForUpdate(application)
      }.start()

      runCatching {
        if (FirebaseApp.getApps(application).isEmpty()) {
          val app = FirebaseApp.initializeApp(application)
          if (app == null) {
            Log.w("RNAppPushUpdate", "Firebase initialization failed. Is google-services.json missing?")
          }
        }
        val topic = application.getString(R.string.rn_app_push_update_fcm_update_topic)
        FirebaseMessaging.getInstance().subscribeToTopic(topic).addOnCompleteListener { task ->
          if (task.isSuccessful) {
            Log.i("RNAppPushUpdate", "Firebase: Successfully subscribed to topic: $topic")
          } else {
            Log.w("RNAppPushUpdate", "Firebase: Failed to subscribe to topic: $topic", task.exception)
          }
        }
      }.onFailure {
        Log.e("RNAppPushUpdate", "Firebase setup failed", it)
      }

      initialized = true
    }
    return bundlePath
  }

  internal fun checkForUpdate(application: Application) {
    val baseUrl = application.getString(R.string.rn_app_push_update_base_url)
    try {
      val packageInfo = application.packageManager.getPackageInfo(application.packageName, 0)
      val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo)

      val key = application.getString(R.string.rn_app_push_update_key)

      if (key == "no_key") {
        Log.e("RNAppPushUpdate", "❌ No key provided in strings.xml. Please refer the documentation.")
        return
      }

      val client = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()
      val request = Request.Builder()
        .url("${baseUrl}product/versions?key=$key&version_code=$versionCode")
        .build()

      client.newCall(request).enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          Log.e("RNAppPushUpdate", "❌ Error in fetching product versions ${e.message ?: ""}")
          e.printStackTrace()
        }

        override fun onResponse(call: Call, response: Response) {
          val body = response.body?.string()

          try {
            val json = JSONObject(body ?: "")
            val isVersionAccepted = json.optBoolean("is_version_accepted", true)
            val downloadUrl = json.optString("download_url")
            val bundleId = json.optInt("accepted_bundle_id")

            if (isVersionAccepted && downloadUrl != null && downloadUrl.isNotEmpty()) {
              val sharedPrefs = application.getSharedPreferences(application.getString(R.string.rn_app_push_update_shared_prefs), Context.MODE_PRIVATE)
              val downloadedBundleId = sharedPrefs.getInt(application.getString(R.string.rn_app_push_update_shared_prefs_bundle_id), -1)
              if (downloadedBundleId != bundleId) downloadBundleFromServer(application, downloadUrl, bundleId)
              else Log.i("RNAppPushUpdate", "Latest bundle already downloaded")
            } else {
              Log.d("RNAppPushUpdate", "No download URL received")
            }
          } catch (e: Exception) {
            Log.e("RNAppPushUpdate", "❌ Error in parsing JSON response from server")
            e.printStackTrace()
          }
        }
      })

    } catch (e: Exception) {
      Log.e("RNAppPushUpdate", "❌ Failed to check for update: ${e.message}")
    }
  }

  private fun downloadBundleFromServer(application: Application, urlStr: String, bundleId: Int) {
    if (!Patterns.WEB_URL.matcher(urlStr).matches()) {
      Log.e("RNAppPushUpdate", "❌ Invalid download URL")
      return
    }
    try {
      val client = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()
      val request = Request.Builder()
        .url(urlStr)
        .build()

      client.newCall(request).enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          Log.e("RNAppPushUpdate", "❌ Error in downloading the bundle ${e.message ?: ""}")
          e.printStackTrace()
        }

        override fun onResponse(call: Call, response: Response) {
          if (!response.isSuccessful) {
            Log.e("RNAppPushUpdate", "❌ Error in downloading the bundle, unexpected code $response")
            return
          }
          try {
            val outputFile = File(application.filesDir, "index.android.bundle")
            val outputStream = FileOutputStream(outputFile)

            val body = response.body
            if (body != null) {
              outputStream.use { out ->
                body.byteStream().use { input ->
                  input.copyTo(out)
                }
              }
              val sharedPrefs = application.getSharedPreferences(application.getString(R.string.rn_app_push_update_shared_prefs), Context.MODE_PRIVATE)
              sharedPrefs.edit {
                putInt(application.getString(R.string.rn_app_push_update_shared_prefs_bundle_id), bundleId)
              }
              Log.d("RNAppPushUpdate", "✅ File downloaded to ${outputFile.absolutePath}")
            } else {
              Log.e("RNAppPushUpdate", "❌ Received empty or corrupted file, does the bundle exist on the server?")
            }
          } catch (e: Exception) {
            Log.e("RNAppPushUpdate", "❌ Error in parsing the bundle downloaded from server")
            e.printStackTrace()
          }
        }
      })
    } catch (e: Exception) {
      Log.e("RNAppPushUpdate", "❌ Failed to download file: ${e.message}")
    }
  }
}

