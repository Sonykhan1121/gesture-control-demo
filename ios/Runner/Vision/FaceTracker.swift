import MediaPipeTasksVision

/// Position, eye coefficients and lip geometry use the same face association
/// and model outputs as Android. No frames or landmarks are persisted here.
final class FaceTracker {
  private var detector: FaceDetector?
  private var landmarker: FaceLandmarker?
  private var lastTimestamp = 0

  private func faceDetector() throws -> FaceDetector {
    if let detector { return detector }
    let options = FaceDetectorOptions()
    options.baseOptions.modelAssetPath = try VisionModels.path("blaze_face_short_range", extension: "tflite")
    options.runningMode = .video
    options.minDetectionConfidence = 0.6
    let result = try FaceDetector(options: options)
    detector = result
    return result
  }

  private func faceLandmarker() throws -> FaceLandmarker {
    if let landmarker { return landmarker }
    let options = FaceLandmarkerOptions()
    options.baseOptions.modelAssetPath = try VisionModels.path("face_landmarker", extension: "task")
    options.runningMode = .video
    options.numFaces = 1
    options.minFaceDetectionConfidence = 0.6
    options.minFacePresenceConfidence = 0.6
    options.minTrackingConfidence = 0.5
    options.outputFaceBlendshapes = true
    let result = try FaceLandmarker(options: options)
    landmarker = result
    return result
  }

  func recognize(_ frame: CameraFrame) throws -> [String: Any] {
    lastTimestamp = max(Int(ProcessInfo.processInfo.systemUptime * 1000), lastTimestamp + 1)
    let image = try MPImage(uiImage: frame.image)
    let faces = try faceDetector().detect(videoFrame: image, timestampInMilliseconds: lastTimestamp)
    guard let face = faces.detections.filter({ $0.boundingBox.width > 0 && $0.boundingBox.height > 0 })
      .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
    else { return ["detected": false] }
    let bounds = face.boundingBox
    let expressions = try faceLandmarker().detect(videoFrame: image, timestampInMilliseconds: lastTimestamp)
    let landmarks = expressions.faceLandmarks.first ?? []
    let sameFace = landmarks.count > 1 && bounds.contains(CGPoint(
      x: Double(landmarks[1].x) * Double(frame.width),
      y: Double(landmarks[1].y) * Double(frame.height)))
    var coefficients: [String: Double] = [:]
    if sameFace {
      for category in expressions.faceBlendshapes.first?.categories ?? [] {
        if let name = category.categoryName { coefficients[name] = Double(category.score) }
      }
    }
    let mouthValid = sameFace && landmarks.count > 291
    let blinkValid = sameFace && landmarks.count > 263 &&
      coefficients["eyeBlinkLeft"] != nil && coefficients["eyeBlinkRight"] != nil
    let eyeValid = blinkValid && landmarks.count > 386
    let screenLeftFromRight = landmarks.count > 263 && landmarks[33].x < landmarks[263].x
    func points(_ indices: [Int], valid: Bool) -> [[Double]] {
      valid ? indices.map { [Double(landmarks[$0].x), Double(landmarks[$0].y)] } : []
    }
    func score(_ key: String) -> Double { coefficients[key] ?? 0 }
    return [
      "detected": true,
      "x": min(1, max(0, Double(bounds.midX) / Double(frame.width))),
      "y": min(1, max(0, Double(bounds.midY) / Double(frame.height))),
      "faceHeight": min(1, max(0.01, Double(bounds.height) / Double(frame.height))),
      "width": frame.width, "height": frame.height,
      "confidence": Double(face.categories.map { $0.score }.max() ?? 0),
      "blinkValid": blinkValid,
      "blinkScreenLeft": score(screenLeftFromRight ? "eyeBlinkRight" : "eyeBlinkLeft"),
      "blinkScreenRight": score(screenLeftFromRight ? "eyeBlinkLeft" : "eyeBlinkRight"),
      "mouthValid": sameFace && coefficients["jawOpen"] != nil,
      "mouthOpen": score("jawOpen"),
      "mouthGeometryValid": mouthValid,
      "mouthLandmarks": points([61, 291, 13, 14, 0, 17, 33, 263], valid: mouthValid),
      "mouthSmileValid": sameFace && coefficients["mouthSmileLeft"] != nil && coefficients["mouthSmileRight"] != nil,
      "mouthSmile": (score("mouthSmileLeft") + score("mouthSmileRight")) / 2,
      "eyeDebugValid": eyeValid,
      "eyeLandmarks": points([33, 133, 159, 145, 263, 362, 386, 374], valid: eyeValid),
      "eyeBlinkNativeLeft": score("eyeBlinkLeft"),
      "eyeBlinkNativeRight": score("eyeBlinkRight"),
      "screenLeftFromRight": screenLeftFromRight,
    ]
  }

  func close() {
    detector = nil
    landmarker = nil
  }
}
