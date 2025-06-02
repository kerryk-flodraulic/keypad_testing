/*import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:can_bt_testing_p1/main.dart' as app;

void main() {
  // Initializes integration test bindings
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Launch app, press all buttons, verify log entries, then exit',
    (WidgetTester tester) async {
      // Launch the main app in test mode (testMode disables real Bluetooth, etc.)
      app.main(testMode: true);

      // Wait until all widgets have settled
      await tester.pumpAndSettle();

      // Locate the first scrollable widget (used to scroll buttons into view)
      final scrollable = find.byType(Scrollable).first;

      // Press all 2x2 keypad buttons (K1 to K4)
      for (final label in ['K1', 'K2', 'K3', 'K4']) {
        final buttonFinder = find.byKey(Key(label));

        // Ensure button is visible by scrolling
        await tester.scrollUntilVisible(
          buttonFinder,
          100,
          scrollable: scrollable,
        );

        // Verify the button exists
        expect(buttonFinder, findsOneWidget);

        // Tap the button
        await tester.tap(buttonFinder);

        // Wait a second for UI/log updates
        await tester.pump(const Duration(seconds: 1));
      }

      // Press all 2x6 keypad buttons (F1 to F12)
      for (final label in [
        'F1', 'F2', 'F3', 'F4', 'F5', 'F6',
        'F7', 'F8', 'F9', 'F10', 'F11', 'F12'
      ]) {
        final buttonFinder = find.byKey(Key(label));

        // Scroll to bring button into view
        await tester.scrollUntilVisible(
          buttonFinder,
          100,
          scrollable: scrollable,
        );

        // Check button exists
        expect(buttonFinder, findsOneWidget);

        // Tap the button
        await tester.tap(buttonFinder);

        // Wait for UI/log update
        await tester.pump(const Duration(seconds: 1));
      }

      //  Verify log contains at least one CAN frame labeled 'TX'
      final logEntry = find.textContaining('TX');
      expect(logEntry, findsWidgets);

      // Optional delay for visual inspection before test ends
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
*/

//The 2x6 keypad test works showing that it is displaying on the can output but the 2x2 is showing no buttons pressed == need to fix 
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:can_bt_testing_p1/main.dart' as app;

void main() {
  // Initializes the integration test environment
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Full Keypad Test', () {
    testWidgets(
      'Launch app, press all buttons, and verify CAN log entries',
      (WidgetTester tester) async {
        // Launch the app in test mode
        app.main(testMode: true);
        await tester.pumpAndSettle();

        // Reference to scrollable view (for scrolling buttons into view)
        final scrollable = find.byType(Scrollable).first;

        // Combined list of all button keys
        final List<String> allKeys = [
          'K1', 'K2', 'K3', 'K4',
          'F1', 'F2', 'F3', 'F4', 'F5', 'F6',
          'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
        ];

        // Tap each button with delays and logging
        for (final keyLabel in allKeys) {
          final buttonFinder = find.byKey(Key(keyLabel));

          await tester.scrollUntilVisible(
            buttonFinder,
            100,
            scrollable: scrollable,
          );

          expect(buttonFinder, findsOneWidget,
              reason: 'Expected to find button with key: $keyLabel');

          await tester.tap(buttonFinder);
          await tester.pump(const Duration(milliseconds: 800));

          // Optional console output
          debugPrint('Pressed $keyLabel');
        }

        // Assert that log contains entries for CAN TX
        final txLogEntry = find.textContaining('TX');
        expect(txLogEntry, findsWidgets,
            reason: 'Expected log to contain at least one TX entry');

        // Let UI settle before exiting
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
