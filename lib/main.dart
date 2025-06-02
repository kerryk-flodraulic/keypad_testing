import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'bluetooth.dart';
import 'crc32.dart';
import 'package:flutter/cupertino.dart';

void main({bool testMode = false}) => runApp(ThemeWrapper(testMode: testMode));

class ThemeWrapper extends StatefulWidget {
  final bool testMode;
  const ThemeWrapper({super.key, this.testMode = false});

  @override
  State<ThemeWrapper> createState() => _ThemeWrapperState();
}

class _ThemeWrapperState extends State<ThemeWrapper> {
  bool _isDarkMode = true;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BM Keypad Interface',
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,

      //Changed for testing
      home: CanKeypadScreen(
        isDarkMode: _isDarkMode,
        onThemeToggle: _toggleTheme,
        testMode: widget.testMode,
      ),
    );
  }
}

//Log entry model for can messages
class CanLogEntry {
  final String channel;
  final String canId;
  final String dlc;
  final String data;
  final String dir;
  final String time;
  final String button;

  CanLogEntry({
    required this.channel,
    required this.canId,
    required this.dlc,
    required this.data,
    required this.dir,
    required this.time,
    required this.button,
  });
}

List<int> dataBytes = List.filled(8, 0); // 8 bytes = 64 bits of state
List<int> ledBytes = List.filled(8, 0); // For LED states (used by PKP2200)

final Map<String, bool> buttonStates = {}; // Tracks ON/OFF state

//Main screen with keypad and CAN log display
class CanKeypadScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final bool testMode;

  const CanKeypadScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
    this.testMode = false,
  });

  @override
  State<CanKeypadScreen> createState() => _CanKeypadScreenState();
}

class _CanKeypadScreenState extends State<CanKeypadScreen> {
  String getPressed2x2Buttons() {
    final pressed = keypad2x2.where((k) => buttonStates[k] == true).toList();
    return pressed.isEmpty ? 'None' : pressed.join(', ');
  }

  void _sendLastRawFrame() {
    if (canFrameLog.isEmpty) {
      //Add \u274c for logo
      debugPrint("No frame in log to send.");
      return;
    }

    final lastEntry = canFrameLog.last;

    // Parse CAN ID
    final canId = int.tryParse(lastEntry.canId, radix: 16);
    if (canId == null) {
      debugPrint("\u274c Invalid CAN ID format.");
      return;
    }

    // Parse data bytes
    final dataBytes =
        lastEntry.data
            .split(' ')
            .map((hex) => int.tryParse(hex, radix: 16) ?? 0)
            .toList();

    if (dataBytes.length != 8) {
      //add \u274c infront for logo opt
      debugPrint("Frame must be exactly 8 bytes.");
      return;
    }

    final deviceId = CanBluetooth.instance.connectedDevices.keys.firstOrNull;
    if (deviceId == null) {
      //Add \u274c infront for logo opt
      debugPrint("No connected Bluetooth device.");
      return;
    }
    // Represents a single CAN frame message to be sent over Bluetooth
    // Includes the CAN identifier, 8-byte payload, and a flag
    final message = BlueMessage(
      identifier: canId,
      data: dataBytes,
      flagged: true,
    );

    CanBluetooth.instance.sendCANMessage(deviceId, message);
    debugPrint(
      //Add \u2705 infront for logo (opt)
      // Formats the CAN ID as an 8-character zero-padded hexadecimal string (e.g., 00000180)
      "Sent raw frame from log: ID=\${canId.toRadixString(16).padLeft(8, '0')} DATA=\${dataBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}",
    );
  }

  bool _isDarkMode = true;
  bool _autoScrollEnabled = true;
  final TextEditingController _deviceFilterController = TextEditingController();
  String _deviceNameFilter = '';

  String getPressed2x6Buttons() {
    final pressed = keypad2x6.where((k) => buttonStates[k] == true).toList();
    return pressed.isEmpty ? 'None' : pressed.join(', ');
  }

  // Handles press logic for 2x2 and 2x6 buttons, updates CAN bytes and logs
  final List<String> keypad2x2 = ['K1', 'K2', 'K3', 'K4']; // K = Keypad PKP2200
  // Defines button labels for the 2x6 PKP2600 keypad (F1–F12)
  final List<String> keypad2x6 = [
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
  ];
  // Maps 2x2 keys (PKP2200) to LED control byte/bit positions in CAN frames
  final Map<String, List<int>> ledButtonMap = {
    'K1': [0, 0],
    'K2': [0, 1],
    'K3': [0, 2],
    'K4': [0, 3],
  };
  // Maps 2x6 keys (PKP2600) to data byte/bit positions for functional control
  final Map<String, List<int>> buttonBitMap = {
    'F1': [0, 0],
    'F2': [0, 1],
    'F3': [0, 2],
    'F4': [0, 3],
    'F5': [0, 4],
    'F6': [0, 5],
    'F7': [1, 0],
    'F8': [1, 1],
    'F9': [1, 2],
    'F10': [1, 3],
    'F11': [1, 4],
    'F12': [1, 5],
  };
  //Reset all buttons and Led Data bytes
  void _resetAllButtons() {
    setState(() {
      dataBytes = List.filled(8, 0);
      ledBytes = List.filled(8, 0);
      buttonStates.clear();
    });
  }

  //Clears only the 2x2 keypad and sends cleared can frames + logs
  void _clear2x2Buttons() {
    setState(() {
      //Resets
      for (var key in ['K1', 'K2', 'K3', 'K4']) {
        buttonStates[key] = false;
      }
      ledBytes = List.filled(8, 0);

      // Only declare once
      final deviceId = CanBluetooth.instance.connectedDevices.keys.firstOrNull;
      if (deviceId == null) {
        debugPrint(" No connected device found.");
        return;
      }

      // Send Cleared Frame PKP2200
      final clearedFrame = BlueMessage(
        identifier: 0x00000180,
        data: List.filled(8, 0x00),
        flagged: true,
      );
      CanBluetooth.instance.sendCANMessage(deviceId, clearedFrame);

      // Log LED  Frame
      List<int> ledDataBytes = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
      String ledData =
          ledDataBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ')
              .toUpperCase();
      // Logs the outgoing CAN frame along with button state and timestamp

      canFrameLog.add(
        CanLogEntry(
          channel: '1',
          canId: '00000180', //225
          dlc: '8',
          data: ledData,
          dir: 'TX',
          time: _elapsedFormatted,
          button: 'LEDs Off',
        ),
      );

      // Send LED Frame over Bluetooth
      final ledFrame = BlueMessage(
        identifier: 0x00000180,
        data: [0x0F, 0x0F, 0x0F, 0x0F, 0x00, 0x00, 0x00, 0x00],
        flagged: true,
      );
      CanBluetooth.instance.sendCANMessage(deviceId, ledFrame);
    });
  }

  //Clears only 2x6 keypad and logs
  void _clear2x6Buttons() {
    setState(() {
      for (var key in [
        'F1',
        'F2',
        'F3',
        'F4',
        'F5',
        'F6',
        'F7',
        'F8',
        'F9',
        'F10',
        'F11',
        'F12',
      ]) {
        buttonStates[key] = false;
      }
      dataBytes = List.filled(8, 0);

      String data =
          dataBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ')
              .toUpperCase();
      // Logs the outgoing CAN frame along with button state and timestamp

      canFrameLog.add(
        CanLogEntry(
          channel: '1',
          canId: '00000195',
          dlc: '8',
          data: data,
          dir: 'TX',
          time: _elapsedFormatted,
          button: '2x6 Cleared',
        ),
      );
    });
  }

  List<int> getByteValues() {
    return [0x00, ...dataBytes];
  }

  // Returns the name of the currently connected Bluetooth device (or fallback)
  String get connectedDeviceName {
    if (CanBluetooth.instance.connectedDevices.isEmpty) {
      return 'No Bluetooth connected';
    }
    final deviceId = CanBluetooth.instance.connectedDevices.keys.first;
    final device = CanBluetooth.instance.scanResults[deviceId]?.device;
    final name =
        CanBluetooth
            .instance
            .scanResults[deviceId]
            ?.advertisementData
            .localName;

    return name != null && name.isNotEmpty
        ? 'Connected to: $name'
        : 'Connected to: $deviceId';
  }

  //Formats elapsed stopwatch time as MM:SS.mmm for display
  String get _elapsedFormatted {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (elapsed.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$millis';
  }

  // Builds the Bluetooth scan results list with signal strength and connect/disconnect control
  Widget bluetoothDeviceList() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ValueListenableBuilder(
        valueListenable: CanBluetooth.instance.addedDevice,
        builder: (_, __, ___) {
          // Filter device names using the user-defined text filter
          final entries =
              CanBluetooth.instance.scanResults.entries.where((entry) {
                final name =
                    entry.value.advertisementData.localName.toLowerCase();
                return name.contains(_deviceNameFilter);
              }).toList();

          return ListView(
            children:
                entries.map((entry) {
                  final device = entry.value.device;
                  final name = entry.value.advertisementData.localName;
                  final isConnected = CanBluetooth.instance.connectedDevices
                      .containsKey(device.remoteId.str);
                  // Shows signal icon, RSSI in dBm, and device name
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Row(
                      children: [
                        Icon(
                          entry.value.rssi > -60
                              ? Icons.signal_cellular_4_bar
                              : entry.value.rssi > -80
                              ? Icons.signal_cellular_alt
                              : Icons.signal_cellular_null,
                          size: 18,
                          color:
                              entry.value.rssi > -70
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(name.isNotEmpty ? name : '(Unnamed)'),
                      ],
                    ),
                    subtitle: Text(device.remoteId.str),
                    // Connection button
                    trailing: ElevatedButton(
                      onPressed: () {
                        if (isConnected) {
                          CanBluetooth.instance.disconnect(device);
                        } else {
                          CanBluetooth.instance.connect(device);
                        }
                      },
                      child: Text(isConnected ? 'Disconnect' : 'Connect'),
                    ),
                  );
                }).toList(),
          );
        },
      ),
    );
  }

  Widget scanControl() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: () => CanBluetooth.instance.startScan(),
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text("Scan"),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => CanBluetooth.instance.stopScan(),
          icon: const Icon(Icons.stop),
          label: const Text("Stop"),
        ),
      ],
    );
  }

  // Requests Bluetooth and location permissions required for scanning
  Future<void> _ensureBluetoothPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  @override
  void initState() {
    super.initState();

    _stopwatch = Stopwatch()..start();

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {});
    });

    if (!widget.testMode) {
      _ensureBluetoothPermissions();
      CanBluetooth.instance.init();
      CanBluetooth.instance.startScan();
      CanBluetooth.instance.addedDevice.addListener(() {
        setState(() {});
      });
    }
  }



  Widget _buildKeyButton(String label) {
    return ElevatedButton(
      key: Key(label),
      onPressed: () => _handleButtonPress(label),
      child: Text(label),
    );
  }

Widget build2x2Keypad() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildKeyButton('K1'),
                const SizedBox(width: 16),
                _buildKeyButton('K2'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildKeyButton('K3'),
                const SizedBox(width: 16),
                _buildKeyButton('K4'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget build2x6Keypad() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: _buildKeyButton('F${i + 1}'),
              )),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: _buildKeyButton('F${i + 7}'),
              )),
            ),
          ],
        ),
      ),
    );
  }


  Widget buildKeypadButton(String label) {
    final is2x2 = ['K1', 'K2', 'K3', 'K4'].contains(label);
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: SizedBox(
        width: 80,
        height: 80,
        child: AnimatedContainer(
          key: Key(label),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          transform:
              buttonStates[label] == true
                  ? Matrix4.translationValues(0, -2, 0)
                  : Matrix4.identity(),
          decoration: BoxDecoration(
            color:
                buttonStates[label] == true ? Colors.green : Colors.grey[800],
            shape: is2x2 ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: is2x2 ? null : BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: buildButton(label),
        ),
      ),
    );
  }

  BoxDecoration _keypadBoxDecoration() {
    return BoxDecoration(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.5),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  //Cacnels timer to avoid mem leaks
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  late final Stopwatch _stopwatch; //Tracks elapsed time
  late final Timer _timer; //Triggers UI to refresh every 100ms
  bool _isTimerRunning = true; // Controls pause/resume

  final List<CanLogEntry> canFrameLog = [];
  //CAN log ents.
  final ScrollController _logScrollController = ScrollController();
  // Handles press logic for 2x2 and 2x6 buttons, updates CAN bytes and logs
  void _handleButtonPress(String label) {
    setState(() {
      buttonStates[label] = !(buttonStates[label] ?? false);
    });

    if (widget.testMode) {
      debugPrint('TEST LOG: $label was pressed');
    }
    HapticFeedback.lightImpact();
    final elapsed = _stopwatch.elapsed;
    final timestamp =
        '${elapsed.inSeconds}.${(elapsed.inMilliseconds % 1000).toString().padLeft(3, '0')}s';

    // Toggle button state
    buttonStates[label] = !(buttonStates[label] ?? false);

    // Handle 2x6 functional buttons (control bytes)
    if (buttonBitMap.containsKey(label)) {
      final byteIndex = buttonBitMap[label]![0];
      final bitIndex = buttonBitMap[label]![1];
      if (buttonStates[label] == true) {
        dataBytes[byteIndex] |= (1 << bitIndex);
      } else {
        dataBytes[byteIndex] &= ~(1 << bitIndex);
      }
    }
/*
    // Handle 2x2 LED buttons (LED control bytes)
    if (ledButtonMap.containsKey(label)) {
      final byteIndex = ledButtonMap[label]![0];
      final bitIndex = ledButtonMap[label]![1];
      if (buttonStates[label] == true) {
        ledBytes[byteIndex] |= (1 << bitIndex);
      } else {
        ledBytes[byteIndex] &= ~(1 << bitIndex);
      }
    }
    */

    String formattedData;
    String canId;
    String buttonExplanation = label;

    // Handle PKP2200SI: 2x2 keys = custom CAN frame format
    if (ledButtonMap.containsKey(label)) {
      List<int> keyStateMessage = [
        ledBytes[0], // Byte 0: K4-K1 state
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ];

      // Format message
      formattedData =
          keyStateMessage
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ')
              .toUpperCase();

      canId = '00000180'; // 0x180 + 0x25 = 0x1A5 (PKP2200 keypad state frame)
    // Handle 2x2 LED buttons (LED control bytes)
    if (ledButtonMap.containsKey(label)) {
      final byteIndex = ledButtonMap[label]![0];
      final bitIndex = ledButtonMap[label]![1];
      if (buttonStates[label] == true) {
        ledBytes[byteIndex] |= (1 << bitIndex);
      } else {
        ledBytes[byteIndex] &= ~(1 << bitIndex);
      }
    }
      int state = ledBytes[0];
      List<String> keyStates = [];
      if ((state & 0x01) != 0) keyStates.add("Key #1");
      if ((state & 0x02) != 0) keyStates.add("Key #2");
      if ((state & 0x04) != 0) keyStates.add("Key #3");
      if ((state & 0x08) != 0) keyStates.add("Key #4");

      buttonExplanation =
          keyStates.isEmpty
              ? "No Key pressed"
              : keyStates.join(" and ") + " pressed";
    } else {
      // Handle PKP2600 (standard functional 2x6 buttons)
      formattedData =
          dataBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ')
              .toUpperCase();

      canId = '00000195';
    }

    final entry = CanLogEntry(
      channel: '1',
      canId: canId,
      dlc: '8',
      data: formattedData,
      dir: 'TX',
      time: timestamp,
      button: buttonExplanation,
    );

    setState(() {
      canFrameLog.add(entry);
      if (ledButtonMap.containsKey(label)) {
        // LED frame (red/green/blue support)
        List<int> ledControlFrame = [
          ledBytes[0], // RED
          ledBytes[1], // GREEN
          ledBytes[2], // BLUE
          0x00, 0x00, 0x00, 0x00, 0x00,
        ];

        String ledFormattedData =
            ledControlFrame
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ')
                .toUpperCase();

        //Commented out because this should be under receiving
        /*
        canFrameLog.add(CanLogEntry(
          channel: 'CH0',
          canId: '215', //  LED control frame ID
          dlc: '8',
          data: ledFormattedData,
          dir: 'TX',
          time: timestamp,
          button: 'LED Update',
        ));

        */
      }
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_autoScrollEnabled &&
          _logScrollController.hasClients &&
          _logScrollController.offset >=
              _logScrollController.position.maxScrollExtent - 100) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Clears the entire CAN log and resets the stopwatch
  void _clearLog() {
    setState(() {
      canFrameLog.clear();
      _stopwatch.reset();
      if (!_isTimerRunning) {
        _stopwatch.stop();
      }
    });
  }

  // Resets only the timer (does not clear log or button states)
  void _resetTimerOnly() {
    setState(() {
      _stopwatch.reset();
      if (_isTimerRunning) {
        _stopwatch.start();
      } else {
        _stopwatch.stop();
      }
    });
  }

  //Returns styled buttons with tool tios and icons and assignes icons based on button logic
  Widget buildButton(String label) {
    IconData? icon;
    String tooltip = '';
    String stateSuffix = buttonStates[label] == true ? 'ON' : 'OFF';
    switch (label) {
      // 2x2 PKP2200 Keys
      case 'K1':
        icon = Icons.power; // ON
        tooltip = 'Power On';
        break;
      case 'K2':
        icon = Icons.power_off; // OFF
        tooltip = 'Power Off ';
        break;
      case 'K3':
        icon = Icons.warning_amber_rounded; // Emergency Stop
        tooltip = 'Emergency Stop ';
        break;
      case 'K4':
        icon = Icons.settings_backup_restore; // Reset
        tooltip = 'System Reset ';
        break;

      //2x6 PKP2600 Functions
      case 'F1':
        icon = Icons.water_drop;
        tooltip = 'Water Pump On';
        break;
      case 'F2':
        icon = Icons.water_drop_outlined;
        tooltip = 'Water Pump Off';
        break;
      case 'F3':
        icon = CupertinoIcons.gear_solid;
        tooltip = 'Engine On';
        break;
      case 'F4':
        icon = CupertinoIcons.gear_big;
        tooltip = 'Engine Off';
        break;
      case 'F5':
        icon = Icons.vertical_align_top;
        tooltip = 'Boom Up';
        break;
      case 'F6':
        icon = Icons.vertical_align_bottom;
        tooltip = 'Boom Down';
        break;
      case 'F7':
        icon = Icons.lock_open;
        tooltip = 'Door Unlock';
        break;
      case 'F8':
        icon = Icons.lock;
        tooltip = 'Door Lock';
        break;
      case 'F9':
        icon = Icons.sensors; // Vacuum On
        tooltip = 'Vacuum On';
        break;
      case 'F10':
        icon = Icons.sensors_off; // Vacuum Off
        tooltip = 'Vacuum Off';
        break;
      case 'F11':
        icon = Icons.arrow_circle_up;
        tooltip = 'Tank Raise / Dozer Out';
        break;
      case 'F12':
        icon = Icons.arrow_circle_down;
        tooltip = 'Tank Lower / Dozer In';
        break;

      // Fallback
      default:
        icon = Icons.help_outline;
        tooltip = 'Unlabeled Button';
    }

    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 140, // restrict button width to avoid overflow
        ),
        child: ElevatedButton.icon(
          key: Key(label),
          onPressed: () => _handleButtonPress(label),
          icon: Icon(
            icon ?? Icons.help_outline,
            size: 24, // slightly smaller to help fit layout
            color: Colors.tealAccent,
          ),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          style: ElevatedButton.styleFrom(
            backgroundColor:
                buttonStates[label] == true
                    ? Colors.green.shade700
                    : Colors.grey.shade800,
            elevation: 4,
            shadowColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          ).copyWith(
            overlayColor: MaterialStateProperty.all(
              Colors.teal.withOpacity(0.1),
            ),
          ),
        ),
      ),
    );
  }

  // scrollable table of all the CAN frame logs
  Widget buildCanLogTable() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            border: const Border(bottom: BorderSide(color: Colors.white24)),
          ),
          child: Row(
            children: const [
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Icon(Icons.device_hub, size: 14, color: Colors.tealAccent),
                    SizedBox(width: 4),
                    Text('CH', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(Icons.code, size: 14, color: Colors.tealAccent),
                    SizedBox(width: 4),
                    Text('CAN ID', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.confirmation_number,
                      size: 14,
                      color: Colors.tealAccent,
                    ),
                    SizedBox(width: 4),
                    Text('DLC', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(Icons.memory, size: 14, color: Colors.tealAccent),
                    SizedBox(width: 4),
                    Text('Data', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.compare_arrows,
                      size: 14,
                      color: Colors.tealAccent,
                    ),
                    SizedBox(width: 4),
                    Text('Dir', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: Colors.tealAccent),
                    SizedBox(width: 4),
                    Text('Time', style: _headerStyle),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(
                      Icons.radio_button_checked,
                      size: 14,
                      color: Colors.tealAccent,
                    ),
                    SizedBox(width: 4),
                    Text('Button', style: _headerStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Scrollable log area
        Expanded(
          child: ListView.builder(
            controller: _logScrollController,
            itemCount: canFrameLog.length,
            itemBuilder: (context, index) {
              final f = canFrameLog[index];
              final isEven = index % 2 == 0;
              final isLatest = index == canFrameLog.length - 1;

              return Container(
                color:
                    isLatest
                        ? Colors.teal.withOpacity(0.2)
                        : (isEven ? Colors.black : Colors.grey.shade900),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: Text(f.channel, style: _rowStyle)),
                    Expanded(flex: 2, child: Text(f.canId, style: _rowStyle)),
                    Expanded(flex: 1, child: Text(f.dlc, style: _rowStyle)),
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(f.data, style: _rowStyle),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Icon(
                            f.dir == 'TX' ? Icons.upload : Icons.download,
                            size: 12,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Text(f.dir, style: _rowStyle),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Text(f.time, style: _rowStyle)),
                    Expanded(
                      flex: 2,
                      child: Text(
                        f.button,
                        style: _rowStyle.copyWith(
                          color:
                              f.button.contains('No')
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  //Displays BT status and number of frames at the bottom
  Widget buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.black87,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth, color: Colors.tealAccent),
          const SizedBox(width: 6),
          Text(
            connectedDeviceName,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.list_alt, color: Colors.tealAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                'Frames: ${canFrameLog.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.timer, color: Colors.tealAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                _elapsedFormatted,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _isTimerRunning ? Colors.greenAccent : Colors.grey,
                  shape: BoxShape.circle,
                  boxShadow:
                      _isTimerRunning
                          ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                          : [],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        title: const Text('BM Keypad Interface'),
        centerTitle: true,
        backgroundColor: Colors.teal.shade800,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.dark_mode : Icons.light_mode),
            tooltip: 'Toggle Theme',
            onPressed: widget.onThemeToggle,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bluetooth, color: Colors.tealAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Bluetooth Device Scanner',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color: Colors.tealAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: scanControl(),
                  ),

                  // Filter Field
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: TextField(
                      controller: _deviceFilterController,
                      decoration: InputDecoration(
                        hintText: 'Filter by device name...',
                        prefixIcon: const Icon(Icons.filter_alt),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.tealAccent,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _deviceNameFilter = value.trim().toLowerCase();
                        });
                      },
                    ),
                  ),

                  // Device List
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: bluetoothDeviceList(),
                  ),

                  // Keypad Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Card(
                      elevation: 6,
                      color: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 2x2 Keypad Section
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '2x2 Keypad (PKP2200 - Node ID: 25h)',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: Colors.tealAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pressed: ${getPressed2x2Buttons()}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                build2x2Keypad(),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _clear2x2Buttons,
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear 2x2'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade800,
                                  ),
                                ),
                              ],
                            ),

                            const Divider(
                              height: 36,
                              thickness: 1,
                              color: Colors.white24,
                            ),

                            // 2x6 Keypad Section
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '2x6 Keypad (PKP2600 - Node ID: 15h)',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: Colors.tealAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pressed: ${getPressed2x6Buttons()}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                build2x6Keypad(),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _clear2x6Buttons,
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Clear 2x6'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // CAN Frame Log Title
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.dns,
                                color: Colors.tealAccent,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'CAN Frame Log',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall?.copyWith(
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),

                  // Log Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isTimerRunning = !_isTimerRunning;
                              if (_isTimerRunning) {
                                _stopwatch.start();
                              } else {
                                _stopwatch.stop();
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade800,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: Icon(
                            _isTimerRunning ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(
                            _isTimerRunning ? 'Pause Timer' : 'Resume Timer',
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _resetTimerOnly,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reset Timer'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _clearLog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear Log'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _resetAllButtons,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset All'),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _sendLastRawFrame,
                          icon: const Icon(Icons.send_rounded),
                          label: const Text(
                            'Send to Kvaser CANKing',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(
                              0xFF37474F,
                            ), // Change this color as desired
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ).copyWith(
                            overlayColor: MaterialStateProperty.all(
                              const Color.fromARGB(255, 59, 172, 78),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Log Container
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Card(
                      elevation: 4,
                      color: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SizedBox(height: 260, child: buildCanLogTable()),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Status Bar
          buildStatusBar(),
        ],
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.bold,
  fontFamily: 'Courier',
  fontSize: 13,
);

const TextStyle _rowStyle = TextStyle(
  color: Colors.greenAccent,
  fontFamily: 'Courier',
  fontSize: 12.5,
);
