import 'dart:collection';

/// FIFO-Puffer für kritische Outbound-Frames, solange der Konvoi-Socket
/// keine Verbindung hat.
///
/// Kritisch sind Frames, deren stiller Verlust echten Schaden anrichtet:
/// `hazard` (inkl. SOS), `hazard_remove`, `waypoint` und `tour`. GPS- und
/// Status-Frames werden bewusst NICHT gepuffert — eine veraltete Position
/// oder Schnellaktion nachzusenden wäre faktisch falsch; der nächste Tick
/// liefert ohnehin frischere Daten.
///
/// Die Queue speichert bereits enkodierte Wire-Frames (JSON-Strings) und
/// gibt sie beim [drain] in Originalreihenfolge zurück, damit kausal
/// abhängige Frames (z. B. `hazard` → `hazard_remove`) korrekt ankommen.
class OutboundFrameQueue {
  OutboundFrameQueue({this.maxLength = defaultMaxLength})
      : assert(maxLength > 0, 'maxLength must be positive');

  /// Obergrenze der gepufferten Frames. Bei Überlauf wird der ÄLTESTE
  /// Frame verworfen (FIFO-Drop) — die jüngsten Meldungen sind im
  /// Pannenfall die relevantesten.
  static const int defaultMaxLength = 32;

  final int maxLength;
  final Queue<String> _frames = Queue<String>();

  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;
  bool get isNotEmpty => _frames.isNotEmpty;

  /// Hängt [frame] ans Ende an; verwirft bei vollem Puffer den ältesten.
  void enqueue(String frame) {
    if (_frames.length >= maxLength) {
      _frames.removeFirst();
    }
    _frames.addLast(frame);
  }

  /// Entnimmt ALLE gepufferten Frames in Originalreihenfolge (älteste
  /// zuerst) und leert die Queue — gedacht für den Flush direkt nach
  /// einem erfolgreichen (Re-)Connect.
  List<String> drain() {
    final drained = List<String>.unmodifiable(_frames);
    _frames.clear();
    return drained;
  }
}
