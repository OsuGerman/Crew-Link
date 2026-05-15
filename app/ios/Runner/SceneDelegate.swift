import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let engine = AppDelegate.shared.flutterEngine
    let controller = FlutterViewController(
      engine: engine, nibName: nil, bundle: nil)
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = controller
    self.window = window
    window.makeKeyAndVisible()
  }
}
