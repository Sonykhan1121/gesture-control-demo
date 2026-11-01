package com.sonykhan.gesture_demo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val recognitionWorker = Executors.newSingleThreadExecutor()
    private var handRecognizer: HandGestureRecognizer? = null
    private var channel: MethodChannel? = null
    private var faceTracker: FaceTracker? = null
    private var faceChannel: MethodChannel? = null
    private var appInfoChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appInfoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lazivoo/app_info")
        appInfoChannel!!.setMethodCallHandler { call, result ->
            if (call.method == "getVersion") {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(packageName, 0)
                @Suppress("DEPRECATION")
                val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                result.success(mapOf("version" to (info.versionName ?: ""), "buildNumber" to build.toString()))
            } else {
                result.notImplemented()
            }
        }
        faceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lazivoo/face_tracking")
        faceChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> recognitionWorker.execute {
                    try {
                        val tracker = faceTracker ?: FaceTracker(applicationContext)
                            .also { faceTracker = it }
                        @Suppress("UNCHECKED_CAST")
                        val observation = tracker.recognize(call.arguments as Map<String, Any>)
                        runOnUiThread { result.success(observation) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("FACE_TRACKING_FAILED", error.message, null) }
                    }
                }
                "close" -> recognitionWorker.execute {
                    faceTracker?.close()
                    faceTracker = null
                    runOnUiThread { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hand_gesture/recognizer")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> recognitionWorker.execute {
                    try {
                        val recognizer = handRecognizer ?: HandGestureRecognizer(applicationContext)
                            .also { handRecognizer = it }
                        @Suppress("UNCHECKED_CAST")
                        val observation = recognizer.recognize(call.arguments as Map<String, Any>)
                        runOnUiThread { result.success(observation) }
                    } catch (error: Exception) {
                        android.util.Log.e("LazivooHand", "Hand recognition failed", error)
                        runOnUiThread { result.error("HAND_RECOGNITION_FAILED", error.message, null) }
                    }
                }
                "close" -> recognitionWorker.execute {
                    handRecognizer?.close()
                    handRecognizer = null
                    runOnUiThread { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appInfoChannel?.setMethodCallHandler(null)
        appInfoChannel = null
        channel?.setMethodCallHandler(null)
        channel = null
        faceChannel?.setMethodCallHandler(null)
        faceChannel = null
        recognitionWorker.execute {
            handRecognizer?.close()
            handRecognizer = null
            faceTracker?.close()
            faceTracker = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        recognitionWorker.shutdown()
    }
}
