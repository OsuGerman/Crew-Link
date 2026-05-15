import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:crew_link/main.dart' as app;

/// Drives the app to key screens and calls [binding.takeScreenshot] so that
/// fastlane snapshot captures one PNG per screen per device/language.
///
/// Run via `fastlane screenshots` which invokes Snapfile + this test target.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture App Store screenshots', (tester) async {
    unawaited(app.main());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 01 – Onboarding welcome
    await binding.takeScreenshot('01_onboarding_welcome');

    // Advance to location permission page
    final nextBtn = find.byKey(const ValueKey('onboarding-primary'));
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // 02 – Onboarding location permission
    await binding.takeScreenshot('02_onboarding_location');

    // Advance to microphone / PTT page
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // 03 – Onboarding PTT
    await binding.takeScreenshot('03_onboarding_ptt');

    // Complete onboarding
    await tester.tap(nextBtn);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 04 – Convoy home (empty state / lobby)
    await binding.takeScreenshot('04_convoy_home');

    // Open "Konvoi erstellen" sheet (key added to LobbyView)
    final createBtn = find.byKey(const ValueKey('create-convoy-btn'));
    if (createBtn.evaluate().isNotEmpty) {
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // 05 – Create convoy sheet
      await binding.takeScreenshot('05_create_convoy_sheet');

      // Dismiss by tapping outside
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();
    }

    // Navigate to vehicle profile via AppBar icon
    final vehicleIcon = find.byKey(const ValueKey('open-vehicle-profile'));
    if (vehicleIcon.evaluate().isNotEmpty) {
      await tester.tap(vehicleIcon);
      await tester.pumpAndSettle();

      // 06 – Vehicle profile
      await binding.takeScreenshot('06_vehicle_profile');

      // Back to home
      final backBtn = find.byType(BackButton);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
        await tester.pumpAndSettle();
      }
    }

    // Navigate to Privacy Policy via the info button in the AppBar
    final privacyBtn = find.byKey(const ValueKey('open-privacy-policy'));
    if (privacyBtn.evaluate().isNotEmpty) {
      await tester.tap(privacyBtn);
      await tester.pumpAndSettle();

      // 07 – Privacy policy
      await binding.takeScreenshot('07_privacy_policy');

      final backBtn2 = find.byType(BackButton);
      if (backBtn2.evaluate().isNotEmpty) {
        await tester.tap(backBtn2);
        await tester.pumpAndSettle();
      }
    }
  });
}
