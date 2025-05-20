import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AccessLog {
  final DateTime timestamp;
  final String status; // "Access Granted" or "Access Denied"
  final String details;

  const AccessLog({
    required this.timestamp,
    required this.status,
    required this.details,
  });
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  static List<AccessLog> accessLogs = [
    AccessLog(
      timestamp: DateTime.now().subtract(Duration(minutes: 5)),
      status: 'Access Granted',
      details: 'User recognized and car unlocked successfully',
    ),
    AccessLog(
      timestamp: DateTime.now().subtract(Duration(minutes: 20)),
      status: 'Access Denied',
      details: 'Unauthorized pattern detected, access denied',
    ),
    AccessLog(
      timestamp: DateTime.now().subtract(Duration(hours: 1, minutes: 12)),
      status: 'Access Granted',
      details: 'User recognized and car unlocked successfully',
    ),
    AccessLog(
      timestamp: DateTime.now().subtract(Duration(hours: 3)),
      status: 'Access Denied',
      details: 'Multiple failed recognition attempts detected',
    ),
    AccessLog(
      timestamp: DateTime.now().subtract(Duration(days: 1, hours: 2)),
      status: 'Access Granted',
      details: 'User recognized and car unlocked successfully',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Alerts'),
      ),
      body: ListView.builder(
        itemCount: accessLogs.length,
        itemBuilder: (context, index) {
          final log = accessLogs[index];
          final formattedTime =
          DateFormat('yyyy-MM-dd hh:mm a').format(log.timestamp);

          return ListTile(
            leading: Icon(
              log.status == 'Access Granted'
                  ? Icons.lock_open
                  : Icons.lock_outline,
              color: log.status == 'Access Granted' ? Colors.green : Colors.red,
            ),
            title: Text(log.status),
            subtitle: Text(log.details),
            trailing: Text(formattedTime),
            isThreeLine: true,
          );
        },
      ),
    );
  }
}
