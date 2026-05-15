import AVFoundation
import Flutter

/// Platform-channel handler for microphone capture, Opus encoding, and playback.
///
/// Channels:
///   crewlink/ptt         (MethodChannel)  — startRecording / stopRecording /
///                                           playFrame / stopPlayback
///   crewlink/ptt/frames  (EventChannel)   — encoded frames as byte arrays
///   crewlink/ptt/session (EventChannel)   — AVAudioSession lifecycle events
///                                           (interruptions, BT route changes)
///
/// Record path:
///   AVAudioEngine inputNode
///     → resample → 48 kHz float32 mono
///     → 960-sample accumulator (20 ms boundary)
///     → Opus encoder (iOS 16+) or raw int16 PCM fallback
///     → FlutterStandardTypedData → EventSink → Dart frames stream
///
/// Playback path (received WebRTC frames routed back from Dart):
///   Dart playFrame(Uint8List) → MethodChannel
///     → Opus decode (iOS 16+) or int16 PCM fallback
///     → AVAudioPlayerNode → engine mainMixerNode → speaker
///
/// Audio session policy:
///   Category:  playAndRecord  Mode: voiceChat
///   Options:   allowBluetooth · allowBluetoothA2DP · defaultToSpeaker · duckOthers
///   Interruptions (phone calls): recording is stopped automatically and a
///     `interruptionBegan` event is forwarded to Dart so the UI can update.
final class PttAudioChannel: NSObject {
  static let methodChannelName  = "crewlink/ptt"
  static let eventChannelName   = "crewlink/ptt/frames"
  static let sessionChannelName = "crewlink/ptt/session"

  private let engine       = AVAudioEngine()
  private var eventSink:    FlutterEventSink?

  // MARK: Session event forwarding
  private let sessionHandler = _SessionStreamHandler()
  private var interruptionObserver: NSObjectProtocol?
  private var routeObserver:        NSObjectProtocol?

  // MARK: Encode (record) state
  private var isRecording   = false
  private var pcmConverter:  AVAudioConverter?  // hw → 48 kHz float32
  private var opusEncoder:   AVAudioConverter?  // float32 → Opus
  private var mono48Format:  AVAudioFormat?
  private var opusEncFmt:    AVAudioFormat?
  private let opusFrameSize = 960
  private var accumulator:   [Float] = []

  // MARK: Decode (playback) state
  private var playerNode:    AVAudioPlayerNode?
  private var opusDecoder:   AVAudioConverter?  // Opus → float32
  private var opusDecFmt:    AVAudioFormat?     // input format for decoder
  private var playbackFmt:   AVAudioFormat?     // float32 48 kHz mono

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: Self.methodChannelName,
                         binaryMessenger: messenger)
      .setMethodCallHandler(handleMethod)
    FlutterEventChannel(name: Self.eventChannelName,
                        binaryMessenger: messenger)
      .setStreamHandler(self)
    FlutterEventChannel(name: Self.sessionChannelName,
                        binaryMessenger: messenger)
      .setStreamHandler(sessionHandler)
    registerSessionObservers()
  }

  deinit {
    removeSessionObservers()
  }

  private func handleMethod(_ call: FlutterMethodCall,
                             result: @escaping FlutterResult) {
    switch call.method {
    case "startRecording":
      startRecording(result: result)
    case "stopRecording":
      stopRecording()
      result(nil)
    case "playFrame":
      guard let typedData = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS",
                            message: "Expected FlutterStandardTypedData",
                            details: nil))
        return
      }
      playFrame(typedData.data)
      result(nil)
    case "stopPlayback":
      stopPlayback()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - AVAudioSession setup

  /// Shared session options used for both record and playback paths.
  /// duckOthers: lower other apps' audio while PTT is active.
  /// allowBluetoothA2DP: enable high-quality BT headphones for playback.
  private func activateSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat,
                             options: [.allowBluetooth, .allowBluetoothA2DP,
                                       .defaultToSpeaker, .duckOthers])
    try session.setActive(true)
  }

  // MARK: - Session observers

  private func registerSessionObservers() {
    let nc = NotificationCenter.default

    interruptionObserver = nc.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil, queue: .main
    ) { [weak self] note in self?.handleInterruption(note) }

    routeObserver = nc.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil, queue: .main
    ) { [weak self] note in self?.handleRouteChange(note) }
  }

  private func removeSessionObservers() {
    if let obs = interruptionObserver {
      NotificationCenter.default.removeObserver(obs)
    }
    if let obs = routeObserver {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  private func handleInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    switch type {
    case .began:
      // Phone call or other interruption started: stop capture immediately.
      if isRecording { stopRecording() }
      sessionHandler.sink?(["type": "interruptionBegan"])

    case .ended:
      var shouldResume = false
      if let optValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
        shouldResume = AVAudioSession.InterruptionOptions(rawValue: optValue)
          .contains(.shouldResume)
      }
      sessionHandler.sink?(["type": "interruptionEnded",
                             "shouldResume": shouldResume])

    @unknown default:
      break
    }
  }

  private func handleRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
          let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else { return }

    switch reason {
    case .newDeviceAvailable:
      let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
      if outputs.contains(where: { isBluetooth($0.portType) }) {
        sessionHandler.sink?(["type": "bluetoothConnected"])
      }

    case .oldDeviceUnavailable:
      let prev = info[AVAudioSessionRouteChangePreviousRouteKey]
        as? AVAudioSessionRouteDescription
      if let prev, prev.outputs.contains(where: { isBluetooth($0.portType) }) {
        sessionHandler.sink?(["type": "bluetoothDisconnected"])
      }

    default:
      break
    }
  }

  private func isBluetooth(_ port: AVAudioSession.Port) -> Bool {
    port == .bluetoothHFP || port == .bluetoothA2DP || port == .bluetoothLE
  }

  // MARK: - Recording

  private func startRecording(result: @escaping FlutterResult) {
    do {
      try activateSession()
    } catch {
      result(FlutterError(code: "SESSION_ERROR",
                          message: error.localizedDescription,
                          details: nil))
      return
    }

    let inputNode = engine.inputNode
    let hwFmt     = inputNode.outputFormat(forBus: 0)
    let mono48    = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 48_000,
                                   channels: 1,
                                   interleaved: false)!
    mono48Format = mono48
    pcmConverter = AVAudioConverter(from: hwFmt, to: mono48)

    if #available(iOS 16.0, *),
       let opusFmt = AVAudioFormat(settings: [
         AVFormatIDKey:         kAudioFormatOpus as AnyObject,
         AVSampleRateKey:       48_000.0,
         AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey:   24_000,
       ]),
       let conv = AVAudioConverter(from: mono48, to: opusFmt) {
      opusEncFmt  = opusFmt
      opusEncoder = conv
    }

    let tapFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: hwFmt.sampleRate,
                                channels: 1,
                                interleaved: false)!
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: tapFmt) {
      [weak self] buf, _ in self?.processTap(buf)
    }

    do {
      try engine.start()
      isRecording = true
      result(nil)
    } catch {
      inputNode.removeTap(onBus: 0)
      result(FlutterError(code: "ENGINE_ERROR",
                          message: error.localizedDescription,
                          details: nil))
    }
  }

  private func stopRecording() {
    guard isRecording else { return }
    isRecording = false
    engine.inputNode.removeTap(onBus: 0)
    accumulator.removeAll()
    // Keep engine alive if playback is active; otherwise tear it down.
    if playerNode == nil {
      engine.stop()
      try? AVAudioSession.sharedInstance()
        .setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  // MARK: - Tap → Encode

  private func processTap(_ buffer: AVAudioPCMBuffer) {
    guard let conv = pcmConverter, let mono48 = mono48Format else { return }

    let ratio    = 48_000.0 / buffer.format.sampleRate
    let outCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
    guard let mono = AVAudioPCMBuffer(pcmFormat: mono48,
                                       frameCapacity: outCount) else { return }
    var convertErr: NSError?
    conv.convert(to: mono, error: &convertErr) { _, sp in
      sp.pointee = .haveData; return buffer
    }
    guard convertErr == nil,
          let ptr = mono.floatChannelData?[0] else { return }

    accumulator.append(
      contentsOf: UnsafeBufferPointer(start: ptr, count: Int(mono.frameLength)))

    while accumulator.count >= opusFrameSize {
      let chunk = Array(accumulator.prefix(opusFrameSize))
      accumulator.removeFirst(opusFrameSize)
      encodeAndSend(samples: chunk)
    }
  }

  private func encodeAndSend(samples: [Float]) {
    guard let sink = eventSink else { return }

    if #available(iOS 16.0, *),
       let conv    = opusEncoder,
       let opusFmt = opusEncFmt,
       let mono48  = mono48Format {
      guard let srcBuf = AVAudioPCMBuffer(
        pcmFormat: mono48,
        frameCapacity: AVAudioFrameCount(opusFrameSize))
      else { sendPcm(samples: samples, sink: sink); return }

      srcBuf.frameLength = AVAudioFrameCount(opusFrameSize)
      samples.withUnsafeBufferPointer {
        srcBuf.floatChannelData![0]
          .initialize(from: $0.baseAddress!, count: opusFrameSize)
      }

      let dstBuf = AVAudioCompressedBuffer(format: opusFmt,
                                            packetCapacity: 1,
                                            maximumPacketSize: 1_275)
      var encErr: NSError?
      let status = conv.convert(to: dstBuf, error: &encErr) { _, sp in
        sp.pointee = .haveData; return srcBuf
      }
      if status != .error, encErr == nil, dstBuf.byteLength > 0 {
        let bytes = Data(bytes: dstBuf.data, count: Int(dstBuf.byteLength))
        DispatchQueue.main.async {
          sink(FlutterStandardTypedData(bytes: bytes))
        }
        return
      }
    }
    sendPcm(samples: samples, sink: sink)
  }

  private func sendPcm(samples: [Float], sink: FlutterEventSink) {
    let int16 = samples.map {
      Int16(clamping: Int(($0 * 32_767).rounded(.toNearestOrAwayFromZero)))
    }
    let data = int16.withUnsafeBufferPointer { Data(buffer: $0) }
    DispatchQueue.main.async { sink(FlutterStandardTypedData(bytes: data)) }
  }

  // MARK: - Playback

  private func ensurePlaybackEngine() throws {
    guard playerNode == nil else { return }

    if !engine.isRunning {
      try activateSession()
    }

    let mono48 = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 48_000,
                                channels: 1,
                                interleaved: false)!
    playbackFmt = mono48

    if #available(iOS 16.0, *),
       let opusFmt = AVAudioFormat(settings: [
         AVFormatIDKey:         kAudioFormatOpus as AnyObject,
         AVSampleRateKey:       48_000.0,
         AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey:   24_000,
       ]),
       let conv = AVAudioConverter(from: opusFmt, to: mono48) {
      opusDecoder = conv
      opusDecFmt  = opusFmt
    }

    let node = AVAudioPlayerNode()
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: mono48)
    playerNode = node

    if !engine.isRunning {
      try engine.start()
    }
    node.play()
  }

  private func playFrame(_ data: Data) {
    try? ensurePlaybackEngine()
    guard let node = playerNode, let outFmt = playbackFmt else { return }

    var pcmBuffer: AVAudioPCMBuffer?

    // Try Opus decode (iOS 16+)
    if #available(iOS 16.0, *),
       let conv    = opusDecoder,
       let opusFmt = opusDecFmt,
       let dstBuf  = AVAudioPCMBuffer(pcmFormat: outFmt,
                                       frameCapacity: AVAudioFrameCount(opusFrameSize)) {
      let srcBuf = AVAudioCompressedBuffer(
        format: opusFmt,
        packetCapacity: 1,
        maximumPacketSize: data.count
      )
      data.withUnsafeBytes { raw in
        srcBuf.data.copyMemory(from: raw.baseAddress!, byteCount: data.count)
      }
      srcBuf.byteLength = UInt32(data.count)
      srcBuf.packetDescriptions![0] = AudioStreamPacketDescription(
        mStartOffset: 0,
        mVariableFramesInPacket: 0,
        mDataByteSize: UInt32(data.count)
      )
      srcBuf.packetCount = 1

      var decErr: NSError?
      conv.convert(to: dstBuf, error: &decErr) { _, sp in
        sp.pointee = .haveData; return srcBuf
      }
      if decErr == nil, dstBuf.frameLength > 0 {
        pcmBuffer = dstBuf
      }
    }

    // Fallback: int16 PCM (960 samples = 1 920 bytes)
    if pcmBuffer == nil {
      let sampleCount = data.count / 2
      guard sampleCount > 0,
            let buf = AVAudioPCMBuffer(pcmFormat: outFmt,
                                       frameCapacity: AVAudioFrameCount(sampleCount))
      else { return }
      buf.frameLength = AVAudioFrameCount(sampleCount)
      data.withUnsafeBytes { raw in
        let src = raw.bindMemory(to: Int16.self)
        let dst = buf.floatChannelData![0]
        for i in 0..<sampleCount {
          dst[i] = Float(src[i]) / 32_767.0
        }
      }
      pcmBuffer = buf
    }

    if let buf = pcmBuffer {
      node.scheduleBuffer(buf)
    }
  }

  private func stopPlayback() {
    guard let node = playerNode else { return }
    node.stop()
    engine.disconnectNodeOutput(node)
    engine.detach(node)
    playerNode  = nil
    opusDecoder = nil
    opusDecFmt  = nil
    playbackFmt = nil

    if !isRecording, engine.isRunning {
      engine.stop()
      try? AVAudioSession.sharedInstance()
        .setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}

// MARK: - FlutterStreamHandler (frames channel)

extension PttAudioChannel: FlutterStreamHandler {
  func onListen(withArguments _: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

// MARK: - Session event stream handler

private final class _SessionStreamHandler: NSObject, FlutterStreamHandler {
  var sink: FlutterEventSink?

  func onListen(withArguments _: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
