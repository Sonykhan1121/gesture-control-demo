import Flutter
import UIKit

enum VisionError: LocalizedError {
  case invalidFrame(String)
  case missingModel(String)

  var errorDescription: String? {
    switch self {
    case .invalidFrame(let reason): return "Invalid camera frame: \(reason)"
    case .missingModel(let name): return "Bundled recognition model missing: \(name)"
    }
  }
}

/// camera_avfoundation supplies upright BGRA pixels, mirrored for the front
/// camera. Do not apply Android sensor rotation or mirror these a second time.
struct CameraFrame {
  let image: UIImage
  let width: Int
  let height: Int
  let mirrored: Bool

  init(arguments: [String: Any]) throws {
    guard let width = arguments["width"] as? Int,
      let height = arguments["height"] as? Int,
      (1...1920).contains(width), (1...1920).contains(height),
      arguments["format"] as? String == "bgra8888",
      arguments["alreadyUpright"] as? Bool == true,
      arguments["rotation"] as? Int == 0,
      let planes = arguments["planes"] as? [[String: Any]], planes.count == 1,
      let bytes = planes[0]["bytes"] as? FlutterStandardTypedData,
      let stride = planes[0]["rowStride"] as? Int,
      stride >= width * 4, stride <= 1920 * 8,
      bytes.data.count >= stride * height
    else { throw VisionError.invalidFrame("Expected complete upright BGRA8888 plane") }

    guard let provider = CGDataProvider(data: bytes.data as CFData),
      let cgImage = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue:
          CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent)
    else { throw VisionError.invalidFrame("Cannot decode BGRA pixels") }
    self.width = width
    self.height = height
    self.mirrored = arguments["mirror"] as? Bool ?? false
    self.image = UIImage(cgImage: cgImage)
  }
}

enum VisionModels {
  static func path(_ name: String, extension ext: String) throws -> String {
    guard let path = Bundle.main.path(forResource: name, ofType: ext) else {
      throw VisionError.missingModel("\(name).\(ext)")
    }
    return path
  }
}
