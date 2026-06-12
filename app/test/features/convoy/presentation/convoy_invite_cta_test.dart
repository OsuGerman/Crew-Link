import 'package:crew_link/features/convoy/presentation/convoy_invite_cta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the invite label and fires onInvite on tap',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConvoyInviteCta(onInvite: () => tapped = true)),
      ),
    );

    expect(find.text('Freunde einladen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('convoy-invite-cta')));
    expect(tapped, isTrue);
  });
}
