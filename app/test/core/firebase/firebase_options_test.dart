import 'package:crew_link/core/firebase/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultFirebaseOptions', () {
    test('all platforms share the same project id', () {
      const expectedProjectId = 'crew-link';
      expect(DefaultFirebaseOptions.android.projectId, expectedProjectId);
      expect(DefaultFirebaseOptions.ios.projectId, expectedProjectId);
      expect(DefaultFirebaseOptions.macos.projectId, expectedProjectId);
      expect(DefaultFirebaseOptions.web.projectId, expectedProjectId);
    });

    test('iOS and macOS have distinct appIds', () {
      expect(
        DefaultFirebaseOptions.ios.appId,
        isNot(DefaultFirebaseOptions.macos.appId),
      );
    });

    test('all platforms share the same realtime database URL', () {
      const expectedUrl =
          'https://crew-link-default-rtdb.firebaseio.com';
      expect(DefaultFirebaseOptions.android.databaseURL, expectedUrl);
      expect(DefaultFirebaseOptions.ios.databaseURL, expectedUrl);
      expect(DefaultFirebaseOptions.macos.databaseURL, expectedUrl);
      expect(DefaultFirebaseOptions.web.databaseURL, expectedUrl);
    });

    test('iOS bundleId matches Xcode PRODUCT_BUNDLE_IDENTIFIER', () {
      expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.crewlink.crewLink');
    });
  });
}
