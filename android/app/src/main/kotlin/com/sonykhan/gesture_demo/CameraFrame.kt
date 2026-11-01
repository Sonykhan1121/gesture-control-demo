package com.sonykhan.gesture_demo

import android.graphics.Bitmap
import android.graphics.Matrix

/** Shared YUV420 stride-aware conversion. Caller owns/recycles the bitmap. */
internal object CameraFrame {
    @Suppress("UNCHECKED_CAST")
    fun upright(arguments: Map<String, Any>): Bitmap {
        val width = (arguments["width"] as Number).toInt()
        val height = (arguments["height"] as Number).toInt()
        require(width > 0 && height > 0 && width <= 1920 && height <= 1920)
        val planes = arguments["planes"] as List<Map<String, Any>>
        require(planes.size == 3) { "YUV420 camera frames required" }
        val bytes = planes.map { it["bytes"] as ByteArray }
        val row = planes.map { (it["rowStride"] as Number).toInt() }
        val pixel = planes.map { (it["pixelStride"] as Number).toInt() }
        val argb = IntArray(width * height)
        for (y in 0 until height) for (x in 0 until width) {
            val yy = (bytes[0][y * row[0] + x * pixel[0]].toInt() and 255) - 16
            val u = (bytes[1][(y / 2) * row[1] + (x / 2) * pixel[1]].toInt() and 255) - 128
            val v = (bytes[2][(y / 2) * row[2] + (x / 2) * pixel[2]].toInt() and 255) - 128
            val c = 298 * yy.coerceAtLeast(0)
            val r = ((c + 409 * v + 128) shr 8).coerceIn(0, 255)
            val g = ((c - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
            val b = ((c + 516 * u + 128) shr 8).coerceIn(0, 255)
            argb[y * width + x] = (255 shl 24) or (r shl 16) or (g shl 8) or b
        }
        val raw = Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
        val matrix = Matrix().apply {
            postRotate((arguments["rotation"] as Number).toFloat())
            if (arguments["mirror"] == true) postScale(-1f, 1f)
        }
        val upright = Bitmap.createBitmap(raw, 0, 0, width, height, matrix, false)
        if (upright !== raw) raw.recycle()
        return upright
    }
}
