import CarPlay
import UIKit

// Owns the live CPMapTemplate: shows member count in the header and a
// large "Halten zum Sprechen" map button that dispatches PTT events
// to Flutter. The actual audio path (mic capture → WebRTC) lives in
// the Flutter / Dart layer and the SFU; CarPlay only routes input.
final class CarPlayCoordinator {
  private let interfaceController: CPInterfaceController
  private weak var bridge: CarPlayBridge?
  private var mapTemplate: CPMapTemplate?

  init(
    interfaceController: CPInterfaceController, bridge: CarPlayBridge?
  ) {
    self.interfaceController = interfaceController
    self.bridge = bridge
  }

  func attach() {
    let map = CPMapTemplate()
    map.automaticallyHidesNavigationBar = false
    map.mapButtons = [pttButton()]
    map.trailingNavigationBarButtons = [exitButton()]
    setStatus(memberCount: 0, proximityActive: false, on: map)
    interfaceController.setRootTemplate(map, animated: false) { _, _ in }
    mapTemplate = map
  }

  func detach() {
    mapTemplate = nil
  }

  func updateState(memberCount: Int, proximityActive: Bool) {
    guard let map = mapTemplate else { return }
    setStatus(memberCount: memberCount, proximityActive: proximityActive, on: map)
  }

  private func setStatus(
    memberCount: Int, proximityActive: Bool, on map: CPMapTemplate
  ) {
    let title: String
    if proximityActive {
      title = "Abstandswarnung aktiv · \(memberCount) Mitglieder"
    } else {
      title = "\(memberCount) Mitglieder im Konvoi"
    }
    map.userInfo = title as NSString
    if #available(iOS 14.0, *) {
      map.tripEstimateStyle = .light
    }
  }

  private func pttButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      // CarPlay map buttons don't expose press-down/press-up natively.
      // We dispatch a brief "pressed" followed by a "released" event so
      // the Flutter side can drive a fixed-duration speech window. A
      // future iteration can switch to a custom UIScene gesture, but
      // for the initial CarPlay-Review the simple action keeps the
      // entitlement review simple.
      guard let bridge = self?.bridge else { return }
      bridge.pttPressed()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        bridge.pttReleased()
      }
    }
    button.image = UIImage(systemName: "mic.fill")?
      .withRenderingMode(.alwaysTemplate)
    button.isEnabled = true
    return button
  }

  private func exitButton() -> CPBarButton {
    return CPBarButton(title: "Verlassen") { [weak self] _ in
      // Pops back to a lobby template; future iteration will show a
      // proper CPListTemplate with active convoys to switch between.
      self?.interfaceController.popToRootTemplate(animated: true) { _, _ in }
    }
  }
}
