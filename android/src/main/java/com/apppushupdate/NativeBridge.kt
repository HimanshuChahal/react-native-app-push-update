package com.apppushupdate

object NativeBridge {
  init {
    System.loadLibrary("native-lib")
  }

  external fun applyPatch(oldPath: String, patchPath: String, outputPath: String): Int
}
