import Flutter
import UIKit

// We replace the auto-generated implicit-engine setup with an explicit
// FlutterEngine. Reason: the CarPlay scene needs to talk to the same
// Flutter engine that powers the phone UI (so a MethodChannel-based
// bridge can deliver events to the same Dart isolate). An explicit
// pre-warmed engine is the canonical Flutter add-to-app pattern that
// composes cleanly with multiple UIScenes.
@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "crew-link-main")

  static var shared: AppDelegate {
    UIApplication.shared.delegate as! AppDelegate
  }

  var carPlayBridge: CarPlayBridge?
  var pttAudioChannel: PttAudioChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    carPlayBridge   = CarPlayBridge(messenger: flutterEngine.binaryMessenger)
    pttAudioChannel = PttAudioChannel(messenger: flutterEngine.binaryMessenger)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if connectingSceneSession.role == UISceneSession.Role(
      rawValue: "CPTemplateApplicationSceneSessionRoleApplication"
    ) {
      let config = UISceneConfiguration(
        name: "CarPlay", sessionRole: connectingSceneSession.role)
      config.delegateClass = CarPlaySceneDelegate.self
      return config
    }
    let config = UISceneConfiguration(
      name: "Default", sessionRole: connectingSceneSession.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
}
