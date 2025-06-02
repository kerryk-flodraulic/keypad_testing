import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:can_bt_testing_p1/main.dart' as app;

void main() {
  // Initializes the integration test environment
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Launch app, press all buttons, verify log entries, then exit', (WidgetTester tester) async {
    // Launch the app with testMode enabled to skip real Bluetooth initialization
    app.main(testMode: true);
    await tester.pumpAndSettle(); // Wait until all UI settles

    // Combine all 2x2 and 2x6 button labels
    final allLabels = [
      'K1', 'K2', 'K3', 'K4',
      'F1', 'F2', 'F3', 'F4',
      'F5', 'F6', 'F7', 'F8',
      'F9', 'F10', 'F11', 'F12'
    ];

    // Press each button one-by-one with a 5-second delay between presses
    for (final label in allLabels) {
      // Find the button by matching its structure: ElevatedButton → Row → Text(label)
      final button = find.byWidgetPredicate((widget) =>
          widget is ElevatedButton &&
          widget.child is Row &&
          (widget.child as Row).children.any((child) =>
              child is Text && child.data == label));

      // Ensure the button exists in the widget tree
      expect(button, findsOneWidget);

      // Simulate a tap
      await tester.tap(button);
      await tester.pumpAndSettle(); // Wait for the UI response

      // Wait 5 seconds between taps to simulate realistic usage
      await tester.pump(const Duration(seconds: 5));
    }

    // Look for log entries containing "TX" in the UI (indicating frame sent)
    final logEntry = find.textContaining('TX');
    expect(logEntry, findsWidgets); // Expect at least one log entry

    // Final buffer wait before ending the test
    await tester.pump(const Duration(seconds: 2));
  });
}
