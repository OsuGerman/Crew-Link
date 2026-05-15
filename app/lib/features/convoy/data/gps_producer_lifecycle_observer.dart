import 'package:flutter/widgets.dart';

import 'gps_producer.dart';

/// Bridges Flutter's app-lifecycle events to [GpsProducer.background].
///
/// Register once after [GpsProducer.start]; call [dispose] when the
/// convoy session ends. The observer forces the slow bucket (5 s) while
/// the app is backgrounded and re-enables adaptive sampling on resume.
class GpsProducerLifecycleObserver with WidgetsBindingObserver {
  GpsProducerLifecycleObserver(this._producer) {
    WidgetsBinding.instance.addObserver(this);
  }

  final GpsProducer _producer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _producer.background = true;
      case AppLifecycleState.resumed:
        _producer.background = false;
      case AppLifecycleState.inactive:
        break; // transitional — keep current throttle mode
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
