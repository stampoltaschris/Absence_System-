import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/school_schedule.dart';
import '../../services/api_service.dart';
import '../admin/admin_management_page.dart';
import '../admin/admin_monitor_page.dart';
import '../admin/admin_reports_page.dart';
import '../admin/change_password_page.dart';
import '../admin/email_settings_page.dart';
import '../admin/schedule_settings_page.dart';
import '../attendance/class_selection_page.dart';
import '../auth/login_page.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const DashboardPage({super.key, required this.user});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _clockTimer;
  String _currentHour = SchoolSchedule.getCurrentSchoolHour();

  @override
  void initState() {
    super.initState();
    _refreshSchedule();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final next = SchoolSchedule.getCurrentSchoolHour();
      if (next != _currentHour) {
        setState(() => _currentHour = next);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSchedule() async {
    await SchoolSchedule.loadFromApi();
    if (!mounted) return;
    setState(() => _currentHour = SchoolSchedule.getCurrentSchoolHour());
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  Future<void> _open(Widget page) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = (widget.user['role'] ?? '') == 'admin';
    final String name =
        widget.user['name'] ?? widget.user['username'] ?? 'Χρήστης';
    final String username = widget.user['username'] ?? '';
    final String role = (widget.user['role'] ?? 'teacher')
        .toString()
        .toUpperCase();

    final bool isOffTime =
        _currentHour.contains('Διάλειμμα') ||
        _currentHour == 'Εκτός Σχολικού Ωραρίου';

    final tiles = <Widget>[
      _buildMenuCard(
        title: 'Καταχώριση Απουσιών',
        icon: Icons.assignment_turned_in,
        color: Colors.orange,
        onTap: () => _open(const ClassSelectionPage()),
      ),
      if (!isAdmin)
        _buildMenuCard(
          title: 'Αλλαγή Κωδικού',
          icon: Icons.password,
          color: Colors.blue,
          onTap: () => _open(ChangePasswordPage(user: widget.user)),
        ),
      if (isAdmin) ...[
        _buildMenuCard(
          title: 'Live Monitor',
          icon: Icons.monitor,
          color: Colors.indigo,
          onTap: () => _open(const AdminMonitorPage()),
        ),
        _buildMenuCard(
          title: 'Διαχείριση\nΤμημάτων / Μαθητών',
          icon: Icons.groups,
          color: Colors.green.shade700,
          onTap: () => _open(AdminManagementPage(currentUser: widget.user)),
        ),
        _buildMenuCard(
          title: 'Αναφορές',
          icon: Icons.assessment,
          color: Colors.teal,
          onTap: () => _open(const AdminReportsPage()),
        ),
        _buildMenuCard(
          title: 'Ωράριο &\nTest Mode',
          icon: Icons.access_time,
          color: Colors.deepOrange,
          onTap: () {
            _open(const ScheduleSettingsPage()).then((_) {
              if (!mounted) return;
              setState(() {
                _currentHour = SchoolSchedule.getCurrentSchoolHour();
              });
            });
          },
        ),
        _buildMenuCard(
          title: 'Email Server',
          icon: Icons.email,
          color: Colors.purple,
          onTap: () => _open(const EmailSettingsPage()),
        ),
        _buildMenuCard(
          title: 'Αλλαγή Κωδικού',
          icon: Icons.password,
          color: Colors.blueGrey,
          onTap: () => _open(ChangePasswordPage(user: widget.user)),
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Αρχική - Σύστημα Απουσιών'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Αποσύνδεση',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.person,
                    color: Colors.blue.shade800,
                  ),
                ),
                title: Text(
                  'Καλωσήρθατε, $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  'Ρόλος: $role | Username: $username',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: isOffTime ? Colors.red[50] : Colors.blue[50],
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isOffTime ? Colors.red.shade300 : Colors.blue.shade300,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_filled,
                      size: 36,
                      color: isOffTime ? Colors.red : Colors.blue.shade700,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Τρέχουσα Διδακτική Ώρα:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentHour,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isOffTime
                                  ? Colors.red.shade800
                                  : Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isAdmin ? 'Λειτουργίες διαχειριστή' : 'Λειτουργίες',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Tablet landscape: 3 στήλες, αλλιώς 2
                  final crossAxisCount = constraints.maxWidth >= 900
                      ? 3
                      : 2;
                  final aspectRatio = constraints.maxWidth >= 900
                      ? 1.35
                      : 1.15;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: aspectRatio,
                    children: tiles,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 52, color: color),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
