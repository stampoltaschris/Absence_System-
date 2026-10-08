import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/school_schedule.dart';
import '../admin/admin_management_page.dart';
import '../admin/admin_monitor_page.dart';
import '../admin/change_password_page.dart';
import '../admin/email_settings_page.dart';
import '../admin/schedule_settings_page.dart'; // 👉 Εισαγωγή της νέας οθόνης ρυθμίσεων ωραρίου
import '../attendance/class_selection_page.dart';
import '../auth/login_page.dart';
import '../../services/api_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = (widget.user['role'] ?? '') == 'admin';
    final String name =
        widget.user['name'] ?? widget.user['username'] ?? 'Χρήστης';
    final String username = widget.user['username'] ?? '';
    final String role = (widget.user['role'] ?? 'teacher')
        .toString()
        .toUpperCase();

    bool isOffTime =
        _currentHour.contains('Διάλειμμα') ||
        _currentHour == 'Εκτός Σχολικού Ωραρίου';

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
            // Κάρτα Καλωσορίσματος Χρήστη
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

            // 👉 ΣΤΑΘΕΡΟ ΠΛΑΙΣΙΟ ΕΜΦΑΝΙΣΗΣ ΤΡΕΧΟΥΣΑΣ ΔΙΔΑΚΤΙΚΗΣ ΩΡΑΣ
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
            const SizedBox(height: 30),

            const Text(
              'Λειτουργίες',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Πλέγμα Επιλογών (Modules)
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  // 1. Καταχώριση Απουσιών
                  _buildMenuCard(
                    context,
                    title: 'Καταχώριση Απουσιών',
                    icon: Icons.assignment_turned_in,
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ClassSelectionPage(),
                        ),
                      );
                    },
                  ),

                  // 2. Αλλαγή Κωδικού (για Εκπαιδευτικούς)
                  if (!isAdmin)
                    _buildMenuCard(
                      context,
                      title: 'Αλλαγή Κωδικού',
                      icon: Icons.password,
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ChangePasswordPage(user: widget.user),
                          ),
                        );
                      },
                    ),

                  // 3. Πάνελ Διαχειριστή (για Admin)
                  if (isAdmin)
                    _buildMenuCard(
                      context,
                      title: 'Πάνελ Διαχειριστή',
                      icon: Icons.dashboard_customize,
                      color: Colors.green,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.monitor,
                                      color: Colors.green,
                                    ),
                                    title: const Text('Live Monitor Απουσιών'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AdminMonitorPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  const Divider(),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.access_time,
                                      color: Colors.green,
                                    ),
                                    title: const Text(
                                      'Ρυθμίσεις Ωραρίου & Test Mode',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ScheduleSettingsPage(),
                                        ),
                                      ).then((_) {
                                        if (!mounted) return;
                                        setState(() {
                                          _currentHour =
                                              SchoolSchedule.getCurrentSchoolHour();
                                        });
                                      });
                                    },
                                  ),
                                  const Divider(),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.settings,
                                      color: Colors.green,
                                    ),
                                    title: const Text(
                                      'Διαχείριση Τμημάτων/Μαθητών/Εκπαιδευτικών',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              AdminManagementPage(
                                                currentUser: widget.user,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Divider(),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.password,
                                      color: Colors.green,
                                    ),
                                    title: const Text(
                                      'Αλλαγή Κωδικού Διαχειριστή',
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ChangePasswordPage(
                                                user: widget.user,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Divider(),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.email,
                                      color: Colors.green,
                                    ),
                                    title: const Text('Ρυθμίσεις Email Server'),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const EmailSettingsPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
