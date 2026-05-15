import CarPlay
import Flutter
import Foundation

// MethodChannel bridge between the CarPlay scene and the Flutter
// engine. Direction:
//   native → dart: invoke `pttPressed` / `pttReleased` / `requestSnapshot`
//   dart → native: `updateConvoyState({memberCount, proximityActive})`
//     to keep the CarPlay map template's status header in sync.
//
// The channel name and method strings are mirrored in
// `app/lib/core/carplay/carplay_bridge.dart` — keep them in lock-step.
final class CarPlayBridge {
  static let channelName = "crewlink/carplay"

  private let channel: FlutterMethodChannel
  weak var coordinator: CarPlayCoordinator?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: CarPlayBridge.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func pttPressed() {
    channel.invokeMethod("pttPressed", arguments: nil)
  }

  func pttReleased() {
    channel.invokeMethod("pttReleased", arguments: nil)
  }

  private func handle(
    call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
    switch call.method {
    case "updateConvoyState":
      guard
        let args = call.arguments as? [String: Any],
        let count = args["memberCount"] as? Int
      else {
        result(
          FlutterError(
            code: "BAD_ARGS", message: "memberCount required", details: nil))
        return
      }
      let proximityActive = (args["proximityActive"] as? Bool) ?? false
      coordinator?.updateState(
        memberCount: count, proximityActive: proximityActive)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
