import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkxcare_companion/main.dart';

void main() {
  testWidgets('LinkXcare App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: Since main() initializes Firebase, which requires a platform channel,
    // we just test the LinkXcareApp widget here.
    await tester.pumpWidget(const LinkXcareApp());

    // Verify that the dashboard exists.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
