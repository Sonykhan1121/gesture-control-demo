import MediaPipeTasksVision

/// Same model, options and output schema as the Android bridge. All matching,
/// selected-hand enforcement and hold timing remain in shared Dart code.
final class HandGestureRecognizer {
  private var recognizer: GestureRecognizer?
  private var lastTimestamp = 0

  private func detector() throws -> GestureRecognizer {
    if let recognizer { return recognizer }
    let options = GestureRecognizerOptions()
    options.baseOptions.modelAssetPath = try VisionModels.path("gesture_recognizer", extension: "task")
    options.runningMode = .video
    options.numHands = 1
    options.minHandDetectionConfidence = 0.6
    options.minHandPresenceConfidence = 0.6
    options.minTrackingConfidence = 0.5
    let result = try GestureRecognizer(options: options)
    recognizer = result
    return result
  }

  func recognize(_ frame: CameraFrame) throws -> [String: Any] {
    lastTimestamp = max(Int(ProcessInfo.processInfo.systemUptime * 1000), lastTimestamp + 1)
    let result = try detector().recognize(
      videoFrame: MPImage(uiImage: frame.image), timestampInMilliseconds: lastTimestamp)
    let categories = result.gestures.first ?? []
    var scores: [String: Double] = [:]
    for category in categories {
      if let name = category.categoryName { scores[name] = Double(category.score) }
    }
    let best = categories.max { $0.score < $1.score }
    let hand = result.handedness.first?.first
    return [
      "points": (result.landmarks.first ?? []).map { [Double($0.x), Double($0.y), Double($0.z)] },
      "worldPoints": (result.worldLandmarks.first ?? []).map { [Double($0.x), Double($0.y), Double($0.z)] },
      "width": frame.width, "height": frame.height,
      "fistScore": scores["Closed_Fist"] ?? 0,
      "scores": scores,
      "gesture": best?.categoryName ?? "None",
      "hand": hand?.categoryName ?? "",
      "handScore": Double(hand?.score ?? 0),
      "mirrored": frame.mirrored,
    ]
  }

  func close() { recognizer = nil }
}
