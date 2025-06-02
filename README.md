
---

# BM Keypad Interface (PKP2200 & PKP2600)

This Flutter application emulates the functionality of the PKP2200 (2x2) and PKP2600 (2x6) keypads to simulate CAN-like control messages. It is specifically designed to test and validate button logic, UI responsiveness, and frame generation logic within a virtualized environment.

---

## Purpose

The primary goal of this application is to enable developers and QA engineers to perform **automated testing of keypad widgets**, independent of any hardware dependencies. This includes:

* Verifying UI button interaction behavior.
* Confirming proper CAN frame data generation.
* Ensuring logs are captured correctly.
* Supporting test automation with or without Bluetooth hardware present.

---

## Key Features

* Virtual 2x2 and 2x6 keypad simulation.
* CAN frame construction based on button states.
* Real-time CAN frame logging with timestamping and state summaries.
* Bluetooth Low Energy (BLE) scanning and connection (disabled in test mode).
* Support for light/dark themes.
* Dedicated `testMode` for bypassing BLE and enabling widget tests.

---

## Running the App

To run the Flutter app normally (with BLE support):

```bash
flutter run
```

To run the app in widget test mode (without Bluetooth functionality):

```dart
void main() => runApp(ThemeWrapper(testMode: true));
```

---

## Integration Testing

This project includes automated integration tests that simulate full interaction with the keypads and validate output to the CAN log. These tests are run in `testMode` and do not require BLE hardware.

### 1. Using `flutter test` on macOS

This runs the test in a headless environment:

```bash
flutter test integration_test/all_buttons_test.dart -d macos
```

### 2. Using `flutter drive` for integration test automation

This launches the app and performs full button interaction tests with UI validation:

```bash
flutter drive \
  --driver=test_driver/integration_test_driver.dart \
  --target=integration_test/all_buttons_test.dart
```

---

## File Structure

* `main.dart`: Entry point for the app with full UI implementation.
* `integration_test/all_buttons_test.dart`: Integration test that taps all buttons and verifies log updates.
* `test_driver/integration_test_driver.dart`: Entry point for `flutter drive` testing.
* `bluetooth.dart`: BLE scan and connection logic (disabled when `testMode` is true).
* `crc32.dart`: Utility for checksum validation if needed for communication framing.

---

## Dependencies

* `flutter_blue_plus`: For Bluetooth Low Energy scanning and connection.
* `permission_handler`: For runtime permissions on Android and macOS.
* `flutter_test` and `integration_test`: For writing and running widget and integration tests.

---

## Recommended Use Cases

* UI development and verification of Flutter keypad widgets.
* Automated testing pipelines for embedded control applications.
* Early-stage firmware UI simulation without needing hardware.
* Regression testing of button mappings and CAN log generation.

---

© 2025 Kerry Kanhai. All rights reserved.
