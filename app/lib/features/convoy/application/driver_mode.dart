import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Driver-Mode toggle. When `true`, the active-convoy screen renders a
/// simplified, large-touch-target layout intended for use while
/// driving — reduced text, single-column focus, oversized leave button.
/// In a future iteration this will auto-engage when the device's
/// reported speed crosses a threshold.
final driverModeProvider = StateProvider<bool>((ref) => false);
