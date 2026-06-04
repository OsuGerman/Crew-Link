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
  private var pttMapButton: CPMapButton?
  // PTT is modelled as a toggle: CPMapButton exposes no press-down/press-up,
  // so the old fixed 0.4 s window capped speech at ~0.4 s. Tap once to open
  // the mic, tap again to close it.
  private var pttActive = false

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
    interfaceController.setRootTemplate(map, animated: false) { success, error in
      if let error = error {
        NSLog("[CarPlay] setRootTemplate failed: %@", error.localizedDescription)
      } else if !success {
        NSLog("[CarPlay] setRootTemplate returned success=false")
      }
    }
    mapTemplate = map
  }

  func detach() {
    // Avoid a stuck-open mic if CarPlay disconnects mid-transmission.
    if pttActive {
      pttActive = false
      bridge?.pttReleased()
    }
    pttMapButton = nil
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
      // CPMapButton has no press-down/press-up, so PTT is a toggle: first tap
      // opens the mic, second tap closes it. The Dart side maps pttPressed →
      // startTransmitting and pttReleased → stopTransmitting unchanged.
      guard let self, let bridge = self.bridge else { return }
      self.pttActive.toggle()
      if self.pttActive {
        bridge.pttPressed()
      } else {
        bridge.pttReleased()
      }
      self.updatePttButtonImage()
    }
    pttMapButton = button
    updatePttButtonImage()
    button.isEnabled = true
    return button
  }

  private func updatePttButtonImage() {
    let symbol = pttActive ? "mic.circle.fill" : "mic.fill"
    pttMapButton?.image = UIImage(systemName: symbol)?
      .withRenderingMode(.alwaysTemplate)
  }

  private func exitButton() -> CPBarButton {
    return CPBarButton(title: "Verlassen") { [weak self] _ in
      // Pops back to a lobby template; future iteration will show a
      // proper CPListTemplate with active convoys to switch between.
      self?.interfaceController.popToRootTemplate(animated: true) { _, _ in }
    }
  }
}
