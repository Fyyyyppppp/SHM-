import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp/screens/gyro_test_screen.dart';
import 'package:fyp/screens/logs_screen.dart';
import 'package:fyp/screens/unlock_car.dart';
import 'package:fyp/screens/verify_user_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? username;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserDetails();
  }

  Future<void> _fetchUserDetails() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      setState(() {
        username = doc.data()?['username'] ?? "User";
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching user: $e");
      setState(() {
        username = "User";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Swift Hold Monitor", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 4,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF3F6FF), Color(0xFFDDE7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome back,",
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.deepPurple.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              username ?? "User",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade900,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildTile(
                    context,
                    icon: Icons.directions_walk,
                    label: "Start Movement\nRecording",
                    onTap: () => Navigator.pushNamed(context, '/sensor'),
                  ),
                  _buildTile(
                    context,
                    icon: Icons.verified_user,
                    label: "Verify\nUser Behavior",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VerifyUserScreen()),
                    ),
                  ),
                  _buildTile(
                    context,
                    icon: Icons.bluetooth_connected,
                    label: "Unlock Car",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UnlockCarScreen()),
                    ),
                  ),
                  _buildTile(
                    context,
                    icon: Icons.warning_amber_rounded,
                    label: "View Alerts\nand Logs",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AlertsScreen()),
                    ),
                  ),
                  _buildTile(
                    context,
                    icon: Icons.sensors,
                    label: "Test Gyroscope",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GyroTestScreen()),
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

  Widget _buildTile(
      BuildContext context, {
        required IconData icon,
        required String label,
        required VoidCallback onTap,
      }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      shadowColor: Colors.deepPurple.withOpacity(0.15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.deepPurple.withOpacity(0.2),
        highlightColor: Colors.deepPurple.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFF9F6FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.deepPurple.shade400),
              const SizedBox(height: 18),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple.shade800,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
