import CarPlay
import UIKit

// Apple's CarPlay scene delegate. The session is created by iOS when
// the user plugs into a CarPlay head unit (or starts the Xcode CarPlay
// simulator). We hand the controller off to a coordinator that owns
// the map template + the bridge to Flutter.
final class CarPlaySceneDelegate: UIResponder,
  CPTemplateApplicationSceneDelegate
{
  private var coordinator: CarPlayCoordinator?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    let bridge = AppDelegate.shared.carPlayBridge
    let coordinator = CarPlayCoordinator(
      interfaceController: interfaceController, bridge: bridge)
    bridge?.coordinator = coordinator
    coordinator.attach()
    self.coordinator = coordinator
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    coordinator?.detach()
    coordinator = nil
  }
}
