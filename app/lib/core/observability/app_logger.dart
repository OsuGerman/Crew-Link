import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final appLog = Logger(
  printer: PrettyPrinter(methodCount: 0, colors: false, printEmojis: false),
  level: kReleaseMode ? Level.warning : Level.debug,
);
