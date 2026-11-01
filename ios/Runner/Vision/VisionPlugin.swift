import Flutter

/// Engine-owned bridge. Inference and close share one serial worker, so a new
/// session cannot race teardown of an older model. Flutter owns the camera.
final class VisionPlugin: NSObject, FlutterPlugin {
  private let worker = DispatchQueue(label: "lazivoo.vision", qos: .userInitiated)
  private var hand: HandGestureRecognizer?
  private var face: FaceTracker?
  private let handChannel: FlutterMethodChannel
  private let faceChannel: FlutterMethodChannel

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = VisionPlugin(messenger: registrar.messenger())
    registrar.publish(plugin)
  }

  private init(messenger: FlutterBinaryMessenger) {
    handChannel = FlutterMethodChannel(name: "hand_gesture/recognizer", binaryMessenger: messenger)
    faceChannel = FlutterMethodChannel(name: "lazivoo/face_tracking", binaryMessenger: messenger)
    super.init()
    handChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, faceMode: false, result: result)
    }
    faceChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, faceMode: true, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, faceMode: Bool, result: @escaping FlutterResult) {
    guard call.method == "recognize" || call.method == "close" else {
      result(FlutterMethodNotImplemented)
      return
    }
    worker.async {
      autoreleasepool {
        do {
          if call.method == "close" {
            if faceMode { self.face?.close(); self.face = nil }
            else { self.hand?.close(); self.hand = nil }
            DispatchQueue.main.async { result(nil) }
            return
          }
          guard let arguments = call.arguments as? [String: Any] else {
            throw VisionError.invalidFrame("Missing arguments")
          }
          let frame = try CameraFrame(arguments: arguments)
          let observation: [String: Any]
          if faceMode {
            let tracker = self.face ?? FaceTracker()
            self.face = tracker
            observation = try tracker.recognize(frame)
          } else {
            let tracker = self.hand ?? HandGestureRecognizer()
            self.hand = tracker
            observation = try tracker.recognize(frame)
          }
          DispatchQueue.main.async { result(observation) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: faceMode ? "FACE_TRACKING_FAILED" : "HAND_RECOGNITION_FAILED",
              message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    handChannel.setMethodCallHandler(nil)
    faceChannel.setMethodCallHandler(nil)
    worker.async {
      self.hand?.close(); self.hand = nil
      self.face?.close(); self.face = nil
    }
  }
}
