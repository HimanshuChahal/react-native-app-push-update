package com.apppushupdate

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Patterns
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.*
import org.json.JSONObject
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.content.edit
import com.facebook.react.ReactActivity
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import java.lang.ref.WeakReference

object RNAppPushUpdate {
  private var initialized = false
  private var activityRef: WeakReference<Activity>? = null
  private var presentUpdateHeader = true

  fun getJSBundleFile(application: Application, presentUpdateHeader: Boolean = true): String? {
    var bundlePath: String? = null
    this.presentUpdateHeader = presentUpdateHeader
    try {
      if (!initialized) {
        registerActivityLifecycleEvents(application)
        val bundleFile = File(application.filesDir, "index.android.bundle")
        if (bundleFile.exists() && bundleFile.length() < 50_000) {
          val packageInfo = application.packageManager.getPackageInfo(application.packageName, 0)
          val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo)
          val sharedPrefs = application.getSharedPreferences(
            application.getString(R.string.rn_app_push_update_shared_prefs),
            Context.MODE_PRIVATE
          )
          val downloadedBundleVersionCode = sharedPrefs.getLong(
            application.getString(R.string.rn_app_push_update_shared_prefs_version_code),
            -1
          )
          if (downloadedBundleVersionCode == versionCode) {
            bundlePath = bundleFile.absolutePath
          } else {
            Log.w("RNAppPushUpdate", "Downloaded bundle is for versionCode: $downloadedBundleVersionCode, current versionCode: $versionCode. Deleting this bundle.")
            if (bundleFile.delete()) {
              Log.d("RNAppPushUpdate", "✅ Bundle file deleted.")
              sharedPrefs.edit {
                remove(application.getString(R.string.rn_app_push_update_shared_prefs_bundle_id))
                remove(application.getString(R.string.rn_app_push_update_shared_prefs_patch_id))
                remove(application.getString(R.string.rn_app_push_update_shared_prefs_version_code))
              }
            } else {
              Log.w("RNAppPushUpdate", "⚠️ Failed to delete bundle file.")
            }
          }
        }

        Thread {
          checkForUpdate(application)
        }.start()

        runCatching {
          if (FirebaseApp.getApps(application).isEmpty()) {
            val app = FirebaseApp.initializeApp(application)
            if (app == null) {
              Log.w(
                "RNAppPushUpdate",
                "Firebase initialization failed. Is google-services.json missing?"
              )
            }
          }
          val topic = application.getString(R.string.rn_app_push_update_fcm_update_topic)
          FirebaseMessaging.getInstance().subscribeToTopic(topic).addOnCompleteListener { task ->
            if (task.isSuccessful) {
              Log.i("RNAppPushUpdate", "Firebase: Successfully subscribed to topic: $topic")
            } else {
              Log.w(
                "RNAppPushUpdate",
                "Firebase: Failed to subscribe to topic: $topic",
                task.exception
              )
            }
          }
        }.onFailure {
          Log.e("RNAppPushUpdate", "Firebase setup failed", it)
        }

        initialized = true
      }
    } catch (e: Exception) {
      e.printStackTrace()
      Log.e("RNAppPushUpdate", "❌ Failed to fetch the bundle ${e.message}")
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
            val json = JSONObject(body ?: "{}")
            val bundleUrl = json.optString("bundle_url")
            val bundleId = json.optInt("bundle_id")
            val patchUrl = json.optString("patch_url")
            val patchId = json.optInt("patch_id")

            if (bundleUrl != null && bundleUrl.isNotEmpty()) {
              val sharedPrefs = application.getSharedPreferences(application.getString(R.string.rn_app_push_update_shared_prefs), Context.MODE_PRIVATE)
              val downloadedBundleId = sharedPrefs.getInt(application.getString(R.string.rn_app_push_update_shared_prefs_bundle_id), -1)
              val downloadedPatchId = sharedPrefs.getInt(application.getString(R.string.rn_app_push_update_shared_prefs_patch_id), -1)
              if (downloadedBundleId != bundleId) downloadBundleFromServer(application, bundleUrl, bundleId, patchUrl, patchId, versionCode)
              else if (patchUrl != null && patchUrl.isNotEmpty() && downloadedPatchId != patchId) downloadPatchFromServer(application, patchUrl, patchId)
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

  private fun downloadBundleFromServer(application: Application, urlStr: String, bundleId: Int, patchUrl: String, patchId: Int, versionCode: Long) {
    if (!Patterns.WEB_URL.matcher(urlStr).matches()) {
      Log.e("RNAppPushUpdate", "❌ Invalid download URL")
      return
    }
    try {
      val client = OkHttpClient.Builder()
        .callTimeout(60, TimeUnit.SECONDS)
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
                putLong(application.getString(R.string.rn_app_push_update_shared_prefs_version_code), versionCode)
              }
              Log.d("RNAppPushUpdate", "✅ File downloaded to ${outputFile.absolutePath}")
              if (patchUrl.isNotEmpty() && patchId > 0) downloadPatchFromServer(application, patchUrl, patchId)
              else if (presentUpdateHeader) showUpdateHeader()
            } else {
              Log.e("RNAppPushUpdate", "❌ Received empty or corrupted file, does the bundle exist on the server?")
            }
          } catch (e: Exception) {
            Log.e("RNAppPushUpdate", "❌ Error in parsing the bundle downloaded from server")
            e.printStackTrace()
            val bundleFile = File(application.filesDir, "index.android.bundle")
            if (bundleFile.exists()) {
              if(bundleFile.delete()) {
                val sharedPrefs = application.getSharedPreferences(
                  application.getString(R.string.rn_app_push_update_shared_prefs),
                  Context.MODE_PRIVATE
                )
                sharedPrefs.edit {
                  remove(application.getString(R.string.rn_app_push_update_shared_prefs_bundle_id))
                  remove(application.getString(R.string.rn_app_push_update_shared_prefs_version_code))
                }
              }
            }
          }
        }
      })
    } catch (e: Exception) {
      Log.e("RNAppPushUpdate", "❌ Failed to download file: ${e.message}")
    }
  }

  private fun downloadPatchFromServer(application: Application, patchUrl: String, patchId: Int) {
    if (!Patterns.WEB_URL.matcher(patchUrl).matches()) {
      Log.e("RNAppPushUpdate", "❌ Invalid patch download URL")
      return
    }
    try {
      val client = OkHttpClient.Builder()
        .callTimeout(30, TimeUnit.SECONDS)
        .build()
      val request = Request.Builder()
        .url(patchUrl)
        .build()

      client.newCall(request).enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          Log.e("RNAppPushUpdate", "❌ Error in downloading the patch ${e.message ?: ""}")
          e.printStackTrace()
        }

        override fun onResponse(call: Call, response: Response) {
          if (!response.isSuccessful) {
            Log.e("RNAppPushUpdate", "❌ Error in downloading the patch, unexpected code $response")
            return
          }
          try {
            val outputFile = File(application.filesDir, "bundle.patch")
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
                putInt(application.getString(R.string.rn_app_push_update_shared_prefs_patch_id), patchId)
              }
              val oldPath = File(application.filesDir, "index.android.bundle")
              val patchPath = File(application.filesDir, "bundle.patch")
              val outputPath = File(application.filesDir, "new_index.android.bundle")
              val patchResult = NativeBridge.applyPatch(oldPath.absolutePath, patchPath.absolutePath, outputPath.absolutePath)
              if (patchResult == 0) {
                if (oldPath.exists()) oldPath.delete()
                val rename = outputPath.renameTo(oldPath)
                if (!rename) throw Exception("Unable to rename the patched bundle")
                if (presentUpdateHeader) showUpdateHeader()
              } else {
                throw Exception("Apply patch failed")
              }
            } else {
              Log.e("RNAppPushUpdate", "❌ Received empty or corrupted file, does the patch exist on the server?")
            }
          } catch (e: Exception) {
            Log.e("RNAppPushUpdate", "❌ Error in parsing the patch downloaded from the server")
            e.printStackTrace()
            val patchFile = File(application.filesDir, "bundle.patch")
            if (patchFile.exists()) {
              if(patchFile.delete()) {
                val sharedPrefs = application.getSharedPreferences(
                  application.getString(R.string.rn_app_push_update_shared_prefs),
                  Context.MODE_PRIVATE
                )
                sharedPrefs.edit {
                  remove(application.getString(R.string.rn_app_push_update_shared_prefs_patch_id))
                }
              }
            }
          } finally {
            val patchFile = File(application.filesDir, "bundle.patch")
            if (patchFile.exists()) patchFile.delete()
          }
        }

      })
    } catch (e: Exception) {
      Log.e("RNAppPushUpdate", "❌ Failed to download the patch file: ${e.message}")
    }
  }

  private fun registerActivityLifecycleEvents(application: Application) {
    application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
      override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

      override fun onActivityStarted(activity: Activity) {}

      override fun onActivityResumed(activity: Activity) {
        activityRef = WeakReference(activity)
      }
      override fun onActivityPaused(activity: Activity) {}
      override fun onActivityStopped(activity: Activity) {}
      override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
      override fun onActivityDestroyed(activity: Activity) {}
    })
  }

  private fun showUpdateHeader() {
    val handler = Handler(Looper.getMainLooper())
    var attempts = 0
    val poll = object : Runnable {
      override fun run() {
        val activity = activityRef?.get()
        if (activity == null) {
          if (++attempts < 30) {
            handler.postDelayed(this, 1000)
          }
          return
        }
        if (activity is ReactActivity) {
          val content = activity.findViewById<ViewGroup>(android.R.id.content)
          val inflater = LayoutInflater.from(activity)
          val header = inflater.inflate(R.layout.update_header, content, false)

          header.findViewById<Button>(R.id.updateButton).setOnClickListener {
            restartApp(activity)
          }
          header.findViewById<LinearLayout>(R.id.native_header).setOnClickListener {
            restartApp(activity)
          }
          val alreadyAdded = (0 until content.childCount).any {
            content.getChildAt(it)?.tag == "rn_app_push_update_header"
          }
          if (!alreadyAdded) {
            val insertIndex = 1.coerceAtMost(content.childCount)
            content.addView(
              header,
              insertIndex,
              ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                header.layoutParams?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT
              )
            )
          }
        }
      }
    }
    handler.post(poll)
  }

  private fun restartApp(activity: Activity) {
    val context = activity.applicationContext
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
    if (intent != null) {
      intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or
        Intent.FLAG_ACTIVITY_NEW_TASK or
        Intent.FLAG_ACTIVITY_CLEAR_TASK)
      context.startActivity(intent)
      Runtime.getRuntime().exit(0)
    } else {
      Log.e("RNAppPushUpdate", "Unable to restart app — launch intent is null")
    }
  }
}

