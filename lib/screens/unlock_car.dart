import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class UnlockCarScreen extends StatefulWidget {
  const UnlockCarScreen({Key? key}) : super(key: key);

  @override
  State<UnlockCarScreen> createState() => _UnlockCarScreenState();
}

class _UnlockCarScreenState extends State<UnlockCarScreen> {
  String _setPin = '';
  String _enteredPin = '';
  bool _isPinAlreadySet = false;
  String _message = '';
  bool _showUnlockAnimation = false;

  // BLE variables
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;

  final String deviceName = 'SHM-Car-Lock'; // ESP32 BLE device name
  final Guid serviceUUID = Guid('12345678-1234-5678-1234-56789abcdef0');
  final Guid characteristicUUID = Guid('abcdefab-1234-5678-1234-abcdefabcdef');

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
    _startScan();
  }

  Future<void> _checkPinStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('userPin');
    setState(() => _isPinAlreadySet = savedPin != null);
  }

  void _startScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.name == deviceName) {
          FlutterBluePlus.stopScan();
          _device = r.device;
          await _connectToDevice();
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice() async {
    if (_device == null) return;

    try {
      await _device!.connect();
    } catch (e) {
      if (e.toString().contains('already connected')) {
        // Already connected, ignore error
      } else {
        rethrow;
      }
    }

    List<BluetoothService> services = await _device!.discoverServices();
    for (var service in services) {
      if (service.uuid == serviceUUID) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid == characteristicUUID) {
            _writeCharacteristic = characteristic;
            setState(() {});
            return;
          }
        }
      }
    }
  }

  Future<void> _sendBleSignal(bool correctPin) async {
    if (_writeCharacteristic == null) {
      setState(() {
        _message = 'BLE device not connected';
      });
      return;
    }

    List<int> command = correctPin ? [49] : [48]; // ASCII '1' or '0'
    try {
      await _writeCharacteristic!.write(command);
    } catch (e) {
      setState(() {
        _message = 'Failed to send BLE signal';
      });
    }
  }

  Future<void> _setNewPin() async {
    if (_setPin.length == 4) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userPin', _setPin);
      setState(() {
        _isPinAlreadySet = true;
        _setPin = '';
        _message = 'PIN set successfully ✅';
      });
    } else {
      setState(() => _message = 'PIN must be 4 digits ❗');
    }
  }

  Future<void> sendBleSignal({
    required BluetoothCharacteristic characteristic,
    required bool correctPin,
  }) async {
    final command = correctPin ? [49] : [48]; // ASCII '1' or '0'
    try {
      await characteristic.write(command, withoutResponse: false);
    } catch (e) {
      print('Error sending BLE command: $e');
      // Optionally show an error message in UI
    }
  }


  Future<void> _verifyPin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('userPin');
    if (_enteredPin == savedPin) {
      setState(() {
        _message = 'Car unlocked 🚗✅';
        _showUnlockAnimation = true;
        _enteredPin = '';
      });
      if (_writeCharacteristic != null) {
        await sendBleSignal(characteristic: _writeCharacteristic!, correctPin: true);
      }
      Future.delayed(const Duration(seconds: 2), () {
        setState(() => _showUnlockAnimation = false);
      });
    } else {
      setState(() {
        _message = 'Incorrect PIN ❌';
        _enteredPin = '';
      });
      if (_writeCharacteristic != null) {
        await sendBleSignal(characteristic: _writeCharacteristic!, correctPin: false);
      }
    }
  }

  Future<void> _resetPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset PIN"),
        content: const Text("Are you sure you want to reset your PIN?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );

    if (confirmed ?? false) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userPin');
      setState(() {
        _isPinAlreadySet = false;
        _setPin = '';
        _enteredPin = '';
        _message = 'PIN reset. Please set a new PIN.';
      });
    }
  }

  void _onKeyTap(String key) {
    setState(() {
      if (_isPinAlreadySet) {
        if (_enteredPin.length < 4) _enteredPin += key;
        if (_enteredPin.length == 4) _verifyPin();
      } else {
        if (_setPin.length < 4) _setPin += key;
      }
    });
  }

  void _onDeleteTap() {
    setState(() {
      if (_isPinAlreadySet) {
        if (_enteredPin.isNotEmpty) _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      } else {
        if (_setPin.isNotEmpty) _setPin = _setPin.substring(0, _setPin.length - 1);
      }
    });
  }

  Widget _buildPinBoxes(String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return Container(
          margin: const EdgeInsets.all(8),
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue, width: 1.5),
          ),
          child: Text(
            index < value.length ? '•' : '',
            style: const TextStyle(fontSize: 28),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['DEL', '0', 'OK'],
    ];
    return Column(
      children: keys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((key) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  fixedSize: const Size(70, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (key == 'DEL') {
                    _onDeleteTap();
                  } else if (key == 'OK') {
                    if (!_isPinAlreadySet && _setPin.length == 4) _setNewPin();
                  } else {
                    _onKeyTap(key);
                  }
                },
                child: Text(
                  key,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin = _isPinAlreadySet ? _enteredPin : _setPin;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Unlock Car"),
        actions: [
          if (_isPinAlreadySet)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset PIN',
              onPressed: _resetPin,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              _isPinAlreadySet ? "Enter PIN to Unlock" : "Set Your 4-digit PIN",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildPinBoxes(pin),
            const SizedBox(height: 10),
            if (_message.isNotEmpty)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _message.contains("Incorrect") ? Colors.red.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _message.contains("Incorrect") ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (_showUnlockAnimation)
              Column(
                children: [
                  const Icon(Icons.lock_open, size: 60, color: Colors.green),
                  const SizedBox(height: 10),
                  Text(
                    "Car Unlocked!",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.green),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            if (!_showUnlockAnimation) _buildKeypad(),
          ],
        ),
      ),
    );
  }
}
