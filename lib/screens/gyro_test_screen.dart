import 'dart:async';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

class GyroTestScreen extends StatefulWidget {
  const GyroTestScreen({Key? key}) : super(key: key);

  @override
  State<GyroTestScreen> createState() => _GyroTestScreenState();
}

class _GyroTestScreenState extends State<GyroTestScreen> {
  String modelInfo = 'Detecting...';
  String gyroStatus = 'Waiting for values...';
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  @override
  void initState() {
    super.initState();
    _checkDeviceInfo();
    _listenGyroscope();
  }

  Future<void> _checkDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    setState(() {
      modelInfo = '${androidInfo.manufacturer} ${androidInfo.model} (SDK ${androidInfo.version.sdkInt})';
    });
  }

  void _listenGyroscope() {
    _gyroSub = gyroscopeEvents.listen((event) {
      setState(() {
        gyroStatus = 'X: ${event.x.toStringAsFixed(2)}, Y: ${event.y.toStringAsFixed(2)}, Z: ${event.z.toStringAsFixed(2)}';
      });
    });
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gyroscope Test")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("📱 Device Info:", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(modelInfo),
            SizedBox(height: 20),
            Text("🎯 Gyroscope Status:", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(gyroStatus),
            SizedBox(height: 30),
            Text("➡️ Try tilting or rotating your phone to see changes."),
          ],
        ),
      ),
    );
  }
}
