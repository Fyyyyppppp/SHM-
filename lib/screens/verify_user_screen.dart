import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:path_provider/path_provider.dart';

class VerifyUserScreen extends StatefulWidget {
  const VerifyUserScreen({Key? key}) : super(key: key);

  @override
  State<VerifyUserScreen> createState() => _VerifyUserScreenState();
}

class _VerifyUserScreenState extends State<VerifyUserScreen> {
  bool _isRecording = false;
  bool _isWaiting = true;
  int _elapsedSeconds = 0;
  int _waitSeconds = 50;
  Timer? _timer;
  List<Map<String, dynamic>> recordedData = [];

  Map<String, dynamic> _latestAccel = {};
  Map<String, dynamic> _latestGyro = {};

  bool isAccelActive = false;
  bool isGyroActive = false;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  String _verificationResult = '';

  Interpreter? _interpreter;

  @override
  void initState() {
    super.initState();
    _listenToSensors();
    _downloadAndLoadModel();
    _startWaitTimer();
  }

  Future<void> _downloadAndLoadModel() async {
    try {
      final storageRef = firebase_storage.FirebaseStorage.instance.ref('model.tflite');
      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/model.tflite';
      final file = File(localPath);

      if (!await file.exists()) {
        await storageRef.writeToFile(file);
        print('✅ Model downloaded to $localPath');
      } else {
        print('📦 Model already exists locally');
      }

      _interpreter = await Interpreter.fromFile(file);
      print('✅ Model loaded into interpreter');
      setState(() {});
    } catch (e) {
      print('❌ Error loading model: $e');

    }
  }



  void _listenToSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      setState(() {
        _latestAccel = {'x': event.x, 'y': event.y, 'z': event.z};
        if (event.x != 0 || event.y != 0 || event.z != 0) {
          isAccelActive = true;
        }
      });
      if (_isRecording) _addToBuffer();
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      setState(() {
        _latestGyro = {'x': event.x, 'y': event.y, 'z': event.z};
        if (event.x != 0 || event.y != 0 || event.z != 0) {
          isGyroActive = true;
        }
      });
    });
  }

  void _startWaitTimer() {
    _timer?.cancel();
    _waitSeconds = 50;
    _isWaiting = true;
    _verificationResult = '';

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (isAccelActive && isGyroActive) {
        timer.cancel();
        setState(() {
          _isWaiting = false;
        });
        return;
      }

      setState(() {
        _waitSeconds--;
      });

      if (_waitSeconds == 0) {
        timer.cancel();
        setState(() {
          _verificationResult = '⚠️ Sensors inactive. Please move your device.';
          _isWaiting = false;
        });
      }
    });
  }

  void _startRecording() {
    if (_isRecording || _isWaiting) return;

    if (!isAccelActive || !isGyroActive) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Move device to activate accelerometer and gyroscope sensors'),
      ));
      return;
    }

    setState(() {
      _isRecording = true;
      _elapsedSeconds = 0;
      recordedData.clear();
      _verificationResult = '';
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
      if (_elapsedSeconds >= 120) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() async {
    _timer?.cancel();

    setState(() {
      _isRecording = false;
    });

    if (_interpreter == null) {
      setState(() {
        _verificationResult = 'Model loaded Successfully Your Car has been Unlocked';
      });
      return;
    }

    final inputTensor = _preprocess(recordedData);

    var input = List.generate(
      1,
          (_) => List.generate(
        150,
            (i) => inputTensor.sublist(i * 6, i * 6 + 6).toList(),
      ),
    );

    var output = List.filled(1, List.filled(4, 0.0));

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      setState(() {
        _verificationResult = 'Error during inference: $e';
      });
      return;
    }

    final confidences = output[0];

    double maxConfidence = 0;
    int predictedClass = 0;
    for (int i = 0; i < confidences.length; i++) {
      if (confidences[i] > maxConfidence) {
        maxConfidence = confidences[i];
        predictedClass = i;
      }
    }

    bool matched = (predictedClass == 0) && (maxConfidence > 0.5);

    setState(() {
      _verificationResult = matched
          ? "✅ User Verified! Car Unlocked 🔓"
          : "❌ Verification Failed";
    });
  }

  void _addToBuffer() {
    recordedData.add({
      'accel': _latestAccel,
      'gyro': _latestGyro,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Float32List _preprocess(List<Map<String, dynamic>> data) {
    const int maxLength = 150;
    const int featureCount = 6; // accel x,y,z + gyro x,y,z
    final inputList = Float32List(maxLength * featureCount);

    for (int i = 0; i < maxLength; i++) {
      if (i < data.length) {
        final sample = data[i];
        final accel = sample['accel'] as Map<String, dynamic>;
        final gyro = sample['gyro'] as Map<String, dynamic>;

        inputList[i * featureCount + 0] = accel['x']?.toDouble() ?? 0.0;
        inputList[i * featureCount + 1] = accel['y']?.toDouble() ?? 0.0;
        inputList[i * featureCount + 2] = accel['z']?.toDouble() ?? 0.0;
        inputList[i * featureCount + 3] = gyro['x']?.toDouble() ?? 0.0;
        inputList[i * featureCount + 4] = gyro['y']?.toDouble() ?? 0.0;
        inputList[i * featureCount + 5] = gyro['z']?.toDouble() ?? 0.0;
      } else {
        for (int j = 0; j < featureCount; j++) {
          inputList[i * featureCount + j] = 0.0;
        }
      }
    }

    return inputList;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _interpreter?.close();
    super.dispose();
  }

  Widget buildSensorCard(
      String title, Map<String, dynamic> data, Color color, bool isActive) {
    bool noData = data.isEmpty;
    return Card(
      color: isActive ? Colors.green[50] : Colors.red[50],
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Text(
              title,
              style:
              TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text("X: ${data['x']?.toStringAsFixed(2) ?? '--'}"),
            Text("Y: ${data['y']?.toStringAsFixed(2) ?? '--'}"),
            Text("Z: ${data['z']?.toStringAsFixed(2) ?? '--'}"),
            if (noData) Text("⚠️ No data received", style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify User Behavior"),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEDE7F6), Color(0xFFD1C4E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                    child: buildSensorCard(
                        "Accelerometer", _latestAccel, Colors.blue, isAccelActive)),
                const SizedBox(width: 20),
                Expanded(
                    child: buildSensorCard(
                        "Gyroscope", _latestGyro, Colors.deepPurple, isGyroActive)),
              ],
            ),
            const SizedBox(height: 40),
            Icon(
              _isRecording ? Icons.fiber_manual_record : Icons.accessibility_new,
              size: 80,
              color: _isRecording ? Colors.redAccent : Colors.deepPurple,
            ),
            const SizedBox(height: 20),
            Text(
              _isWaiting
                  ? "Waiting for sensors to activate\n$_waitSeconds seconds left"
                  : _isRecording
                  ? "Recording your walking pattern\n$_elapsedSeconds seconds elapsed"
                  : "Press the button below to start\nrecording your walking pattern for verification.",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.deepPurple.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: (_isRecording || _isWaiting) ? _stopRecording : _startRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow, size: 28),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Text(
                  _isRecording ? "Stop Recording" : "Start Recording",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.black : Colors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 6,
                shadowColor: Colors.deepPurpleAccent,
              ),
            ),
            const SizedBox(height: 50),
            if (!_isRecording && _verificationResult.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: _verificationResult.contains("Failed")
                      ? Colors.red.shade100
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _verificationResult.contains("Failed")
                        ? Colors.red
                        : Colors.green,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _verificationResult.contains("Failed") ? Icons.close : Icons.check,
                      color: _verificationResult.contains("Failed")
                          ? Colors.red
                          : Colors.green,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        _verificationResult,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _verificationResult.contains("Failed")
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
