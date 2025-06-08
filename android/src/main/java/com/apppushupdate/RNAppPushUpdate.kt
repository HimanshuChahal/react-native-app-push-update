package com.apppushupdate

import android.app.Application
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.io.InputStream

object RNAppPushUpdate {
  private var initialized = false

  fun getJSBundleFile(application: Application): String? {
    var bundlePath: String? = null
    if (!initialized) {
      val bundleFile = File(application.filesDir, "index.android.bundle")
      if (bundleFile.exists()) {
        bundlePath = bundleFile.absolutePath
      }
      initialized = true

      Thread {
        downloadBundleFromServer(application)
      }.start()
    }
    return bundlePath
  }

  fun downloadBundleFromServer(application: Application) {
    val urlStr = "https://yourserver.com/download"

    try {
      val url = URL(urlStr)
      val connection = url.openConnection() as HttpURLConnection
      connection.requestMethod = "GET"
      connection.connectTimeout = 10000
      connection.readTimeout = 10000

      val responseCode = connection.responseCode
      if (responseCode != HttpURLConnection.HTTP_OK) {
        Log.e("Download", "Server returned HTTP $responseCode")
        return
      }

      val inputStream: InputStream = connection.inputStream

      val outputFile = File(application.filesDir, "index.android.bundle")
      val outputStream = FileOutputStream(outputFile)

      inputStream.use { input ->
        outputStream.use { output ->
          input.copyTo(output)
        }
      }

      Log.d("Download", "✅ File downloaded to ${outputFile.absolutePath}")
    } catch (e: Exception) {
      Log.e("Download", "❌ Failed to download file: ${e.message}")
    }
  }
}

