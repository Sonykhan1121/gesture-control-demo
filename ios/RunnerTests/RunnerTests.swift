import Flutter
import UIKit
import XCTest
@testable import Runner

/// Public MediaPipe reference photos and synthetic pixels, never user captures.
final class RunnerTests: XCTestCase {
  private func arguments(width: Int, height: Int, stride: Int, bytes: Data,
                          mirrored: Bool = false) -> [String: Any] {
    ["width": width, "height": height, "format": "bgra8888", "alreadyUpright": true,
     "rotation": 0, "mirror": mirrored,
     "planes": [["bytes": FlutterStandardTypedData(bytes: bytes), "rowStride": stride, "pixelStride": 4]]]
  }

  private func photo(_ name: String, mirrored: Bool = false) throws -> CameraFrame {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
    let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    let stride = image.width * 4 + 16
    var bytes = Data(count: stride * image.height)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
        width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: stride,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
          CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
      if mirrored {
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return try CameraFrame(arguments: arguments(width: image.width, height: image.height,
      stride: stride, bytes: bytes, mirrored: mirrored))
  }

  func testBGRAKeepsPaddedRowsAndDoesNotRotateOrMirrorAgain() throws {
    var pixels = Data(count: 16 * 3)
    for row in 0..<3 {
      for col in 0..<2 {
        let offset = row * 16 + col * 4
        pixels[offset] = UInt8(10 + row)
        pixels[offset + 1] = UInt8(20 + col)
        pixels[offset + 2] = UInt8(row * 2 + col)
        pixels[offset + 3] = 255
      }
    }
    let frame = try CameraFrame(arguments: arguments(width: 2, height: 3, stride: 16,
      bytes: pixels, mirrored: true))
    let cg = try XCTUnwrap(frame.image.cgImage)
    XCTAssertEqual(cg.width, 2)
    XCTAssertEqual(cg.height, 3)
    XCTAssertEqual(cg.bytesPerRow, 16)
    XCTAssertTrue(frame.mirrored)
    XCTAssertEqual(frame.image.imageOrientation, .up)
    let decoded = try XCTUnwrap(cg.dataProvider?.data) as Data
    XCTAssertEqual(decoded, pixels, "Already upright, mirrored pixels must remain unchanged")
  }

  func testInvalidFramesFailBeforeInference() throws {
    let valid = arguments(width: 2, height: 3, stride: 16, bytes: Data(count: 48))
    for (key, value) in [("width", 0 as Any), ("height", 3000 as Any),
                         ("alreadyUpright", false as Any), ("rotation", 90 as Any),
                         ("format", "yuv420" as Any), ("planes", [] as Any)] {
      var bad = valid; bad[key] = value
      XCTAssertThrowsError(try CameraFrame(arguments: bad), key)
    }
    XCTAssertThrowsError(try CameraFrame(arguments: arguments(width: 2, height: 3,
      stride: 16, bytes: Data(count: 47))))
    XCTAssertThrowsError(try CameraFrame(arguments: arguments(width: 2, height: 3,
      stride: 4, bytes: Data(count: 48))))
  }

  func testFistBothImageHandsAndCloseReopen() throws {
    let recognizer = HandGestureRecognizer()
    for mirrored in [false, true] {
      recognizer.close()
      let result = try recognizer.recognize(photo("fist", mirrored: mirrored))
      XCTAssertEqual(result["gesture"] as? String, "Closed_Fist")
      XCTAssertGreaterThan(try XCTUnwrap(result["fistScore"] as? Double), 0.65)
      XCTAssertEqual((result["points"] as? [[Double]])?.count, 21)
      XCTAssertEqual((result["worldPoints"] as? [[Double]])?.count, 21)
      XCTAssertEqual(result["mirrored"] as? Bool, mirrored)
      XCTAssertEqual(result["hand"] as? String, mirrored ? "Left" : "Right")
    }
    recognizer.close()
    XCTAssertEqual(try recognizer.recognize(photo("fist"))["gesture"] as? String, "Closed_Fist")
    recognizer.close()
  }

  func testOpenPalmAndMissingHandDoNotBecomeFist() throws {
    let recognizer = HandGestureRecognizer()
    let open = try recognizer.recognize(photo("right_hands"))
    XCTAssertEqual((open["points"] as? [[Double]])?.count, 21)
    XCTAssertLessThan(try XCTUnwrap(open["fistScore"] as? Double), 0.45)
    recognizer.close()
    let absent = try recognizer.recognize(photo("cat"))
    XCTAssertEqual((absent["points"] as? [[Double]])?.count, 0)
    XCTAssertEqual(absent["fistScore"] as? Double, 0)
    recognizer.close()
  }

  func testFaceProvidesExpressionsAndRecoversAfterClose() throws {
    let tracker = FaceTracker()
    for mirrored in [false, true] {
      tracker.close()
      let face = try tracker.recognize(photo("portrait", mirrored: mirrored))
      XCTAssertEqual(face["detected"] as? Bool, true)
      XCTAssertEqual(face["blinkValid"] as? Bool, true)
      XCTAssertEqual(face["mouthValid"] as? Bool, true)
      XCTAssertEqual(face["mouthSmileValid"] as? Bool, true)
      XCTAssertEqual((face["mouthLandmarks"] as? [[Double]])?.count, 8)
      XCTAssertEqual((face["eyeLandmarks"] as? [[Double]])?.count, 8)
      for key in ["x", "y", "faceHeight", "confidence", "blinkScreenLeft", "blinkScreenRight", "mouthOpen", "mouthSmile"] {
        let value = try XCTUnwrap(face[key] as? Double, key)
        XCTAssertTrue(value.isFinite && value >= 0 && value <= 1, key)
      }
      let rawLeft = try XCTUnwrap(face["eyeBlinkNativeLeft"] as? Double)
      let rawRight = try XCTUnwrap(face["eyeBlinkNativeRight"] as? Double)
      let fromRight = try XCTUnwrap(face["screenLeftFromRight"] as? Bool)
      XCTAssertEqual(face["blinkScreenLeft"] as? Double, fromRight ? rawRight : rawLeft)
      XCTAssertEqual(face["blinkScreenRight"] as? Double, fromRight ? rawLeft : rawRight)
    }
    let blank = try CameraFrame(arguments: arguments(width: 320, height: 240,
      stride: 1280, bytes: Data(repeating: 255, count: 1280 * 240)))
    XCTAssertEqual(try tracker.recognize(blank)["detected"] as? Bool, false)
    tracker.close()
  }
}
