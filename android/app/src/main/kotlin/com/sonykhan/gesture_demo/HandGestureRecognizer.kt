package com.sonykhan.gesture_demo

import android.content.Context
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult

/** Called on a single worker thread; neither frames nor landmarks are saved. */
class HandGestureRecognizer(private val context: Context) {
    private var recognizer: GestureRecognizer? = null
    private var lastTimestamp = 0L

    private fun detector(): GestureRecognizer {
        return recognizer ?: GestureRecognizer.createFromOptions(
            context,
            GestureRecognizer.GestureRecognizerOptions.builder()
                .setBaseOptions(BaseOptions.builder()
                    .setModelAssetPath("gesture_recognizer.task").build())
                .setRunningMode(RunningMode.VIDEO)
                .setNumHands(1)
                .setMinHandDetectionConfidence(0.6f)
                .setMinHandPresenceConfidence(0.6f)
                .setMinTrackingConfidence(0.5f)
                .build()
        ).also { recognizer = it }
    }

    @Suppress("UNCHECKED_CAST")
    fun recognize(arguments: Map<String, Any>): Map<String, Any> {
        val upright = CameraFrame.upright(arguments)
        val image = BitmapImageBuilder(upright).build()
        try {
            lastTimestamp = maxOf(SystemClock.uptimeMillis(), lastTimestamp + 1)
            val result = detector().recognizeForVideo(image, lastTimestamp)
            return serialize(result, upright.width, upright.height, arguments["mirror"] == true)
        } finally {
            image.close()
            upright.recycle()
        }
    }

    private fun serialize(result: GestureRecognizerResult, width: Int, height: Int, mirrored: Boolean): Map<String, Any> {
        val landmarks = result.landmarks().firstOrNull().orEmpty()
        val worldLandmarks = result.worldLandmarks().firstOrNull().orEmpty()
        val categories = result.gestures().firstOrNull().orEmpty()
        val best = categories.maxByOrNull { it.score() }
        val fistScore = categories.firstOrNull { it.categoryName() == "Closed_Fist" }?.score() ?: 0f
        val handedness = result.handedness().firstOrNull()?.firstOrNull()
        return mapOf(
            "points" to landmarks.map { listOf(it.x().toDouble(), it.y().toDouble(), it.z().toDouble()) },
            "worldPoints" to worldLandmarks.map { listOf(it.x().toDouble(), it.y().toDouble(), it.z().toDouble()) },
            "width" to width, "height" to height,
            "fistScore" to fistScore.toDouble(),
            "scores" to categories.associate { it.categoryName() to it.score().toDouble() },
            "gesture" to (best?.categoryName() ?: "None"),
            "hand" to (handedness?.categoryName() ?: ""),
            "handScore" to (handedness?.score()?.toDouble() ?: 0.0),
            "mirrored" to mirrored
        )
    }

    fun close() {
        recognizer?.close()
        recognizer = null
    }
}
