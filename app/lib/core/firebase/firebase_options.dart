// Firebase config for project `crew-link-3c852`.
// Android + iOS carry REAL values (from app/android/app/google-services.json
// and app/ios/Runner/GoogleService-Info.plist). Web/macOS are not registered
// yet — register those apps and re-run `flutterfire configure` to fill them in.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // No Web app registered yet — these stay placeholders. The web build uses the
  // mocked main_web_preview.dart and never calls Firebase.initializeApp, so this
  // is never read. Register a Web app + re-run flutterfire configure to fill in.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_WEB_API_KEY',
    appId: '1:44150442783:web:REPLACE',
    messagingSenderId: '44150442783',
    projectId: 'crew-link-3c852',
    authDomain: 'crew-link-3c852.firebaseapp.com',
    databaseURL: 'https://crew-link-3c852-default-rtdb.firebaseio.com',
    storageBucket: 'crew-link-3c852.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCC7LRFpR8Yhj6nY0MLjlAxLZ3mtW-v-8Y',
    appId: '1:44150442783:android:60fd4868c08cb4a3b67e2a',
    messagingSenderId: '44150442783',
    projectId: 'crew-link-3c852',
    databaseURL: 'https://crew-link-3c852-default-rtdb.firebaseio.com',
    storageBucket: 'crew-link-3c852.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAyjVQ6vOzHCpX6qkyr5G6SzBYc1PLIClA',
    appId: '1:44150442783:ios:cc1874503c95ffe7b67e2a',
    messagingSenderId: '44150442783',
    projectId: 'crew-link-3c852',
    databaseURL: 'https://crew-link-3c852-default-rtdb.firebaseio.com',
    storageBucket: 'crew-link-3c852.firebasestorage.app',
    iosClientId:
        '44150442783-27q479m4mtvsukbm7758d29abvm02tbq.apps.googleusercontent.com',
    iosBundleId: 'de.crewlink.app',
  );

  // macOS is not a build target; reuse the iOS app values so this never throws
  // if run on desktop. Register a macOS app + re-run flutterfire configure for
  // a proper macOS config.
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAyjVQ6vOzHCpX6qkyr5G6SzBYc1PLIClA',
    appId: '1:44150442783:ios:cc1874503c95ffe7b67e2a',
    messagingSenderId: '44150442783',
    projectId: 'crew-link-3c852',
    databaseURL: 'https://crew-link-3c852-default-rtdb.firebaseio.com',
    storageBucket: 'crew-link-3c852.firebasestorage.app',
    iosClientId:
        '44150442783-27q479m4mtvsukbm7758d29abvm02tbq.apps.googleusercontent.com',
    iosBundleId: 'de.crewlink.app',
  );
}
