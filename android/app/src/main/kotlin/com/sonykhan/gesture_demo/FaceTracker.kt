package com.sonykhan.gesture_demo

import android.content.Context
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker

/** Face position and expressions: no identification, recordings or saved frames. */
internal class FaceTracker(private val context: Context) {
    private var detector: FaceDetector? = null
    private var blinkDetector: FaceLandmarker? = null
    private var lastTimestamp = 0L

    private fun detector(): FaceDetector = detector ?: FaceDetector.createFromOptions(
        context,
        FaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(BaseOptions.builder()
                .setModelAssetPath("blaze_face_short_range.tflite").build())
            .setRunningMode(RunningMode.VIDEO)
            .setMinDetectionConfidence(0.6f)
            .build()
    ).also { detector = it }

    private fun blinkDetector(): FaceLandmarker = blinkDetector ?: FaceLandmarker.createFromOptions(
        context,
        FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder()
                .setModelAssetPath("face_landmarker.task").build())
            .setRunningMode(RunningMode.VIDEO)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.6f)
            .setMinFacePresenceConfidence(0.6f)
            .setMinTrackingConfidence(0.5f)
            .setOutputFaceBlendshapes(true)
            .build()
    ).also { blinkDetector = it }

    fun recognize(arguments: Map<String, Any>): Map<String, Any> {
        val bitmap = CameraFrame.upright(arguments)
        val image = BitmapImageBuilder(bitmap).build()
        try {
            lastTimestamp = maxOf(SystemClock.uptimeMillis(), lastTimestamp + 1)
            // The largest face is normally the person nearest the selfie camera.
            val face = detector().detectForVideo(image, lastTimestamp).detections()
                .filter { it.boundingBox().width() > 0 && it.boundingBox().height() > 0 }
                .maxByOrNull { it.boundingBox().width() * it.boundingBox().height() }
                ?: return mapOf("detected" to false)
            val bounds = face.boundingBox()
            val blinkResult = blinkDetector().detectForVideo(image, lastTimestamp)
            val landmarks = blinkResult.faceLandmarks().firstOrNull()
            // Associate expressions with the selected face, not a bystander's.
            val nose = landmarks?.getOrNull(1)
            val sameFace = nose != null && bounds.contains(nose.x() * bitmap.width, nose.y() * bitmap.height)
            val blendshapes = if (sameFace) {
                blinkResult.faceBlendshapes().orElse(emptyList()).firstOrNull().orEmpty()
                    .associate { it.categoryName() to it.score().toDouble() }
            } else emptyMap()
            // Official lip/eye topology: corners, inner gap, outer lips, eye scale.
            val mouthIndices = listOf(61, 291, 13, 14, 0, 17, 33, 263)
            val mouthGeometryValid = sameFace && landmarks != null && landmarks.size > 291
            val mouthPoints = if (mouthGeometryValid) mouthIndices.map { index ->
                listOf(landmarks!![index].x().toDouble(), landmarks[index].y().toDouble())
            } else emptyList()
            val eyeIndices = listOf(33, 133, 159, 145, 263, 362, 386, 374)
            val eyeDebugValid = sameFace && landmarks != null && landmarks.size > 386 &&
                blendshapes.containsKey("eyeBlinkLeft") && blendshapes.containsKey("eyeBlinkRight")
            val eyePoints = if (eyeDebugValid) eyeIndices.map { index ->
                listOf(landmarks!![index].x().toDouble(), landmarks[index].y().toDouble())
            } else emptyList()
            val screenLeftFromRight = landmarks != null && landmarks.size > 263 &&
                landmarks[33].x() < landmarks[263].x()
            return mapOf(
                "detected" to true,
                "eyeDebugValid" to eyeDebugValid,
                "eyeLandmarks" to eyePoints,
                "eyeBlinkNativeLeft" to (blendshapes["eyeBlinkLeft"] ?: 0.0),
                "eyeBlinkNativeRight" to (blendshapes["eyeBlinkRight"] ?: 0.0),
                "screenLeftFromRight" to screenLeftFromRight,
                "blinkValid" to (sameFace && landmarks != null && landmarks.size > 263 &&
                    blendshapes.containsKey("eyeBlinkLeft") && blendshapes.containsKey("eyeBlinkRight")),
                // Same associated face and inference as the eyes. Missing
                // expression output must not leave a talking mouth frozen open.
                "mouthValid" to (sameFace && blendshapes.containsKey("jawOpen")),
                "mouthOpen" to (blendshapes["jawOpen"] ?: 0.0),
                "mouthGeometryValid" to mouthGeometryValid,
                "mouthLandmarks" to mouthPoints,
                "mouthSmileValid" to (sameFace && blendshapes.containsKey("mouthSmileLeft") &&
                    blendshapes.containsKey("mouthSmileRight")),
                "mouthSmile" to (((blendshapes["mouthSmileLeft"] ?: 0.0) +
                    (blendshapes["mouthSmileRight"] ?: 0.0)) / 2.0),
                "x" to (bounds.centerX() / bitmap.width).toDouble().coerceIn(0.0, 1.0),
                "y" to (bounds.centerY() / bitmap.height).toDouble().coerceIn(0.0, 1.0),
                "faceHeight" to (bounds.height() / bitmap.height).toDouble().coerceIn(0.01, 1.0),
                "width" to bitmap.width,
                "height" to bitmap.height,
                // Blendshape names are subject-relative. Map by the actual
                // landmark X ordering in the already mirrored camera image.
                "blinkScreenLeft" to if (screenLeftFromRight) {
                    blendshapes["eyeBlinkRight"] ?: 0.0
                } else blendshapes["eyeBlinkLeft"] ?: 0.0,
                "blinkScreenRight" to if (screenLeftFromRight) {
                    blendshapes["eyeBlinkLeft"] ?: 0.0
                } else blendshapes["eyeBlinkRight"] ?: 0.0,
                "confidence" to (face.categories().maxOfOrNull { it.score() } ?: 0f).toDouble()
            )
        } finally {
            image.close()
            bitmap.recycle()
        }
    }

    fun close() {
        detector?.close()
        detector = null
        blinkDetector?.close()
        blinkDetector = null
    }
}
