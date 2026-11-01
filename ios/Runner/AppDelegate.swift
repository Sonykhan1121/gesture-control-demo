import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appInfoChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LazivooAppInfo") {
      let channel = FlutterMethodChannel(name: "lazivoo/app_info", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "getVersion" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result([
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
          "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        ])
      }
      appInfoChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LazivooVision") {
      VisionPlugin.register(with: registrar)
    }
  }
}
