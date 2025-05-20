import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class SensorDataScreen extends StatefulWidget {
  const SensorDataScreen({Key? key}) : super(key: key);

  @override
  State<SensorDataScreen> createState() => _SensorDataScreenState();
}

class _SensorDataScreenState extends State<SensorDataScreen> {
  List<Map<String, dynamic>> recordedData = [];
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  Map<String, dynamic> _latestAccel = {};
  Map<String, dynamic> _latestGyro = {};

  bool _isRecording = false;
  bool isGyroActive = false;
  bool isAccelActive = false;

  int lastSavedTime = 0;
  int gyroCountdown = 50;
  Timer? gyroTimer;

  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  int _elapsedSeconds = 0;
  bool _blink = true;
  Timer? _blinker;

  final user = FirebaseAuth.instance.currentUser;
  final uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _listenToGyroscope();
    _listenToAccelerometer();
    _startGyroCountdown();
  }

  void _startGyroCountdown() {
    gyroTimer?.cancel();
    gyroCountdown = 50;

    gyroTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (isGyroActive) {
        timer.cancel();
        setState(() {});
        return;
      }

      if (gyroCountdown == 0) {
        timer.cancel();
        _listenToGyroscope();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🔁 Retried gyroscope activation."),
          ),
        );
      } else {
        setState(() {
          gyroCountdown--;
        });
      }
    });
  }

  void _listenToGyroscope() {
    _gyroSub?.cancel();
    _gyroSub = gyroscopeEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _latestGyro = {'x': event.x, 'y': event.y, 'z': event.z};
        if (event.x != 0 || event.y != 0 || event.z != 0) {
          isGyroActive = true;
        }
      });
    });
  }

  void _listenToAccelerometer() {
    _accelSub?.cancel();
    _accelSub = accelerometerEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _latestAccel = {'x': event.x, 'y': event.y, 'z': event.z};
        if (event.x != 0 || event.y != 0 || event.z != 0) {
          isAccelActive = true;
        }
      });
    });
  }

  void startRecording() {
    if (!isGyroActive || !isAccelActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Move your phone to activate all sensors before recording.'),
        ),
      );
      return;
    }

    setState(() {
      _isRecording = true;
      recordedData.clear();
      _elapsedSeconds = 0;
      _recordingStartTime = DateTime.now();
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedSeconds++;
      });
    });

    _blinker?.cancel();
    _blinker = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _blink = !_blink;
      });
    });

    _accelSub = accelerometerEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _latestAccel = {'x': event.x, 'y': event.y, 'z': event.z};
      });
      _addToBuffer();
    });
  }

  Future<String> uploadPatternJsonFile(List<Map<String, dynamic>> recordedData, String sessionId) async {
    try {
      final jsonString = jsonEncode(recordedData);
      final storageRef = FirebaseStorage.instance.ref().child('walking_patterns/$sessionId.json');
      await storageRef.putString(jsonString, format: PutStringFormat.raw);
      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Failed to upload JSON file: $e');
      return '';
    }
  }

  void stopRecording() async {
    await _accelSub?.cancel();
    _recordingTimer?.cancel();
    _blinker?.cancel();
    setState(() {
      if (mounted) _isRecording = false;
    });

    if (_recordingStartTime != null && user != null && recordedData.isNotEmpty) {
      final durationInSeconds = DateTime.now().difference(_recordingStartTime!).inSeconds;
      final sessionId = uuid.v4();

      // Save metadata & data in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('walking_patterns')
          .doc(sessionId)
          .set({
        'userId': user!.uid,
        'sessionId': sessionId,
        'timestamp': _recordingStartTime,
        'durationSeconds': durationInSeconds,
        'data': recordedData,
      });

      // Upload JSON file to Firebase Storage
      final downloadUrl = await uploadPatternJsonFile(recordedData, sessionId);

      // Save download URL to Firestore doc
      if (downloadUrl.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('walking_patterns')
            .doc(sessionId)
            .update({'jsonDownloadUrl': downloadUrl});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Recording saved and uploaded')),
        );
      }
    }

    recordedData.clear();
  }

  void _addToBuffer() {
    int now = DateTime.now().millisecondsSinceEpoch;
    if (_latestAccel.isNotEmpty && _latestGyro.isNotEmpty && now - lastSavedTime > 100) {
      lastSavedTime = now;

      recordedData.add({
        'accel': _latestAccel,
        'gyro': _latestGyro,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> deleteRecording(String docId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('walking_patterns')
        .doc(docId)
        .delete();
  }

  String formatTimestamp(Timestamp timestamp) {
    return DateFormat('dd MMM yyyy – hh:mm:ss a').format(timestamp.toDate().toLocal());
  }

  Widget buildSensorCard(String title, Map<String, dynamic> data, IconData icon, Color color) {
    bool noData = data.isEmpty;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("X: ${data['x']?.toStringAsFixed(2) ?? '--'}"),
                  Text("Y: ${data['y']?.toStringAsFixed(2) ?? '--'}"),
                  Text("Z: ${data['z']?.toStringAsFixed(2) ?? '--'}"),
                  if (noData && title == "Gyroscope")
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text("⚠️ No data received", style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildStatusRow(String label, bool isActive) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(isActive ? Icons.check_circle : Icons.warning, color: isActive ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Text(
          isActive ? "$label Active ✅" : "$label Inactive ⚠️ Move device",
          style: TextStyle(fontSize: 16, color: isActive ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    gyroTimer?.cancel();
    _recordingTimer?.cancel();
    _blinker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('walking_patterns')
        .orderBy('timestamp', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Data Recorder'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFFF0F4FF), Color(0xFFE0ECFF)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              buildSensorCard("Accelerometer", _latestAccel, Icons.speed, Colors.blue),
              const SizedBox(height: 12),
              buildSensorCard("Gyroscope", _latestGyro, Icons.rotate_right, Colors.deepPurple),
              const SizedBox(height: 16),
              buildStatusRow("Accelerometer", isAccelActive),
              const SizedBox(height: 8),
              buildStatusRow("Gyroscope", isGyroActive),
              if (!isGyroActive && gyroCountdown > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text("⏳ Waiting for gyroscope... ${gyroCountdown}s", style: const TextStyle(fontSize: 16, color: Colors.deepPurple, fontWeight: FontWeight.w600)),
                ),
              if (_isRecording)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_blink) const Icon(Icons.circle, size: 12, color: Colors.red),
                      const SizedBox(width: 6),
                      Text("Recording: ${_elapsedSeconds ~/ 60}m ${_elapsedSeconds % 60}s", style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                label: Text(_isRecording ? "Stop Recording" : "Start Recording"),
                onPressed: _isRecording ? stopRecording : startRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(thickness: 1),
              const Text("📂 Saved Recordings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: recordingRef.snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final recordings = snapshot.data!.docs;

                    if (recordings.isEmpty) {
                      return const Center(child: Text("No recordings saved."));
                    }

                    return ListView.builder(
                      itemCount: recordings.length,
                      itemBuilder: (context, index) {
                        final doc = recordings[index];
                        final dataMap = doc.data() as Map<String, dynamic>;

                        final timestamp = dataMap['timestamp'] as Timestamp;
                        final duration = dataMap['durationSeconds'] ?? 0;
                        final dataList = dataMap['data'] as List<dynamic>? ?? [];
                        final dataCount = dataList.length;

                        return Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.access_time, color: Colors.deepPurple),
                            title: Text("Recorded on ${formatTimestamp(timestamp)}"),
                            subtitle: Text("Duration: ${duration ~/ 60}m ${duration % 60}s\nTotal Data Points: $dataCount"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteRecording(doc.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
