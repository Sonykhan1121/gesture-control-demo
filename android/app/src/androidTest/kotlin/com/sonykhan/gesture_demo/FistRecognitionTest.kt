package com.sonykhan.gesture_demo

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.io.File

/** Official MediaPipe real-photo fixtures. Exercises the actual YUV bridge. */
@RunWith(AndroidJUnit4::class)
class FistRecognitionTest {
    private fun image(name: String): Bitmap {
        val context = InstrumentationRegistry.getInstrumentation().context
        return context.assets.open(name).use { BitmapFactory.decodeStream(it) }
    }

    private fun input(bitmap: Bitmap, rotation: Int = 0, mirror: Boolean = false): Map<String, Any> {
        val w = bitmap.width; val h = bitmap.height
        require(w % 2 == 0 && h % 2 == 0)
        val stride = w + 8 // Test row padding and interleaved chroma pixel stride.
        val yPlane = ByteArray(stride * h)
        val uPlane = ByteArray(stride * h / 2)
        val vPlane = ByteArray(stride * h / 2)
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        for (y in 0 until h) for (x in 0 until w) {
            val rgb = pixels[y*w+x]
            val r = (rgb shr 16) and 255; val g = (rgb shr 8) and 255; val b = rgb and 255
            yPlane[y*stride+x] = (((66*r+129*g+25*b+128) shr 8)+16).coerceIn(0,255).toByte()
            if (x % 2 == 0 && y % 2 == 0) {
                var rr=0; var gg=0; var bb=0
                for (dy in 0..1) for (dx in 0..1) {
                    val p = pixels[(y+dy)*w+x+dx]
                    rr += (p shr 16) and 255; gg += (p shr 8) and 255; bb += p and 255
                }
                rr/=4; gg/=4; bb/=4
                uPlane[(y/2)*stride+x] = (((-38*rr-74*gg+112*bb+128) shr 8)+128).coerceIn(0,255).toByte()
                vPlane[(y/2)*stride+x] = (((112*rr-94*gg-18*bb+128) shr 8)+128).coerceIn(0,255).toByte()
            }
        }
        return mapOf("width" to w, "height" to h, "rotation" to rotation, "mirror" to mirror,
            "planes" to listOf(
                mapOf("bytes" to yPlane,"rowStride" to stride,"pixelStride" to 1),
                mapOf("bytes" to uPlane,"rowStride" to stride,"pixelStride" to 2),
                mapOf("bytes" to vPlane,"rowStride" to stride,"pixelStride" to 2)))
    }

    private fun run(name: String, rotation: Int = 0, mirror: Boolean = false, subjectRotation: Int = 0, subjectMirror: Boolean = false): Map<String, Any> {
        val source = image(name)
        // Some fixtures have odd dimensions; crop only the final edge pixel.
        var bitmap = Bitmap.createBitmap(source,0,0,source.width and -2,source.height and -2)
        if (rotation != 0) bitmap = Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,
            Matrix().apply { postRotate(-rotation.toFloat()) }, false)
        if (subjectMirror) bitmap = Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,
            Matrix().apply { postScale(-1f,1f) }, false)
        if (subjectRotation != 0) bitmap = Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,
            Matrix().apply { postRotate(subjectRotation.toFloat()) }, false)
        val recognizer = HandGestureRecognizer(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            val result = recognizer.recognize(input(bitmap,rotation,mirror))
            Log.i("FistRecognitionTest", "$name rotation=$rotation mirror=$mirror gesture=${result["gesture"]} score=${result["fistScore"]} points=${(result["points"] as List<*>).size}")
            return result
        } finally {
            recognizer.close()
            bitmap.recycle()
            if (source !== bitmap) source.recycle()
        }
    }

    @Test fun realFistIsRecognizedWithLandmarks() {
        val result = run("fist.jpg")
        assertEquals("Closed_Fist", result["gesture"])
        assertTrue((result["fistScore"] as Double) >= .75)
        assertEquals(21, (result["points"] as List<*>).size)
    }
    @Test fun openHandIsNotAcceptedAsFist() {
        val result = run("right_hands.jpg")
        assertEquals(21, (result["points"] as List<*>).size)
        assertTrue((result["fistScore"] as Double) < .75)
    }
    @Test fun noHandProducesNoLandmarksOrFistScore() {
        val result = run("cat.jpg")
        assertEquals(0, (result["points"] as List<*>).size)
        assertEquals(0.0, result["fistScore"] as Double, .0001)
    }
    @Test fun rotatedMirroredCameraFrameStillRecognizesFist() {
        val result = run("fist.jpg",90,true)
        assertEquals("Closed_Fist", result["gesture"])
        assertTrue((result["fistScore"] as Double) >= .75)
        assertEquals(21, (result["points"] as List<*>).size)
    }

    @Test fun mirroredPhotosExposeRealScoresForOtherTutorialGestures() {
        val samples = linkedMapOf<String, Any>()
        for ((name, category) in listOf("fist.jpg" to "Closed_Fist", "pointing_up.jpg" to "Pointing_Up",
            "thumb_up.jpg" to "Thumb_Up", "victory.jpg" to "Victory")) {
            val result = run(name, mirror = true)
            samples[name] = result
            val scores = result["scores"] as Map<*, *>
            assertEquals(21, (result["points"] as List<*>).size)
            assertEquals(category, result["gesture"])
            assertTrue("$name: $scores", (scores[category] as? Double ?: 0.0) >= .5)
        }
        samples["left_pointing_up.jpg"] = run("pointing_up.jpg", mirror = true, subjectMirror = true)
        samples["right_hands.jpg"] = run("right_hands.jpg", mirror = true)
        samples["cat.jpg"] = run("cat.jpg", mirror = true)
        // Test-only fixture observations, never user camera frames.
        File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir,
            "tutorial-pose-fixtures.json").writeText(JSONObject(samples).toString())
    }

    @Test fun physicalHandIdentityCanBeResolvedAcrossCameraMirroring() {
        for (name in listOf("fist.jpg", "pointing_up.jpg")) {
            for (mirror in listOf(false, true)) {
                val result = run(name, rotation = 90, mirror = mirror)
                // Official photos contain a right hand. Tasks Vision 0.10.32
                // swaps its image-space label when camera mirroring is applied.
                assertEquals(if (mirror) "Left" else "Right", result["hand"])
                assertEquals(mirror, result["mirrored"])
                assertTrue((result["handScore"] as Double) >= .8)
            }
        }
        val left = run("pointing_up.jpg", mirror = true, subjectMirror = true)
        assertEquals("Right", left["hand"])
        assertEquals(true, left["mirrored"])
        assertTrue((left["handScore"] as Double) >= .8)
        val empty = run("cat.jpg", mirror = true)
        assertEquals("", empty["hand"])
        assertEquals(0.0, empty["handScore"] as Double, .0001)
    }

    @Test fun upsideDownThumbIsNotAcceptedAsThumbUp() {
        val result = run("thumb_up.jpg", mirror = true, subjectRotation = 180)
        val scores = result["scores"] as Map<*, *>
        assertTrue("$scores", (scores["Thumb_Up"] as? Double ?: 0.0) < .8)
        assertEquals("Thumb_Down", result["gesture"])
        assertTrue("$scores", (scores["Thumb_Down"] as? Double ?: 0.0) >= .5)
    }
}
