import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_theme.dart';
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
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = (widget.user['role'] ?? '') == 'admin';
    final String name =
        widget.user['name'] ?? widget.user['username'] ?? 'Χρήστης';
    final String username = widget.user['username'] ?? '';
    final String roleLabel = isAdmin ? 'Διαχειριστής' : 'Εκπαιδευτικός';

    final bool isOffTime =
        _currentHour.contains('Διάλειμμα') ||
        _currentHour == 'Εκτός Σχολικού Ωραρίου';

    final tiles = <Widget>[
      _DashboardTile(
        title: 'Καταχώριση Απουσιών',
        subtitle: 'Επιλογή τμήματος',
        icon: Icons.assignment_turned_in_rounded,
        accent: AppColors.accent,
        onTap: () => _open(const ClassSelectionPage()),
      ),
      if (!isAdmin)
        _DashboardTile(
          title: 'Αλλαγή Κωδικού',
          subtitle: 'Ασφάλεια λογαριασμού',
          icon: Icons.password_rounded,
          accent: AppColors.primaryMid,
          onTap: () => _open(ChangePasswordPage(user: widget.user)),
        ),
      if (isAdmin) ...[
        _DashboardTile(
          title: 'Live Monitor',
          subtitle: 'Ζωντανή εικόνα ημέρας',
          icon: Icons.monitor_heart_rounded,
          accent: const Color(0xFF2F6B8A),
          onTap: () => _open(const AdminMonitorPage()),
        ),
        _DashboardTile(
          title: 'Διαχείριση',
          subtitle: 'Τμήματα · Μαθητές · Καθηγητές',
          icon: Icons.groups_rounded,
          accent: AppColors.success,
          onTap: () => _open(AdminManagementPage(currentUser: widget.user)),
        ),
        _DashboardTile(
          title: 'Αναφορές',
          subtitle: 'Στατιστικά & ιστορικό',
          icon: Icons.assessment_rounded,
          accent: const Color(0xFF0F766E),
          onTap: () => _open(const AdminReportsPage()),
        ),
        _DashboardTile(
          title: 'Ωράριο',
          subtitle: 'Ώρες & Test Mode',
          icon: Icons.access_time_rounded,
          accent: AppColors.warning,
          onTap: () {
            _open(const ScheduleSettingsPage()).then((_) {
              if (!mounted) return;
              setState(() {
                _currentHour = SchoolSchedule.getCurrentSchoolHour();
              });
            });
          },
        ),
        _DashboardTile(
          title: 'Email Server',
          subtitle: 'SMTP ρυθμίσεις',
          icon: Icons.email_rounded,
          accent: const Color(0xFF475569),
          onTap: () => _open(const EmailSettingsPage()),
        ),
        _DashboardTile(
          title: 'Αλλαγή Κωδικού',
          subtitle: 'Ασφάλεια λογαριασμού',
          icon: Icons.password_rounded,
          accent: AppColors.primaryMid,
          onTap: () => _open(ChangePasswordPage(user: widget.user)),
        ),
      ],
    ];

    return Scaffold(
      body: Container(
        decoration: AppTheme.pageBackground(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Σύστημα Απουσιών',
                            style: GoogleFonts.sora(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            'Αρχική οθόνη',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Αποσύνδεση',
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeBanner(
                        name: name,
                        roleLabel: roleLabel,
                        username: username,
                        isAdmin: isAdmin,
                      ),
                      const SizedBox(height: 14),
                      _HourBanner(
                        currentHour: _currentHour,
                        isOffTime: isOffTime,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        isAdmin ? 'Λειτουργίες διαχειριστή' : 'Λειτουργίες',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount =
                                constraints.maxWidth >= 900
                                    ? 3
                                    : (constraints.maxWidth >= 520 ? 2 : 1);
                            // Πιο «κοντά» κουτάκια: μεγαλύτερο ratio = μικρότερο ύψος
                            final aspectRatio = constraints.maxWidth >= 900
                                ? 2.6
                                : (constraints.maxWidth >= 520 ? 2.35 : 3.2);
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: aspectRatio,
                              children: tiles,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final String name;
  final String roleLabel;
  final String username;
  final bool isAdmin;

  const _WelcomeBanner({
    required this.name,
    required this.roleLabel,
    required this.username,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.availableBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Καλωσήρθατε, $name',
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$roleLabel · @$username',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HourBanner extends StatelessWidget {
  final String currentHour;
  final bool isOffTime;

  const _HourBanner({required this.currentHour, required this.isOffTime});

  @override
  Widget build(BuildContext context) {
    final bg = isOffTime ? const Color(0xFFFFF1F0) : AppColors.accentSoft;
    final border = isOffTime
        ? AppColors.danger.withValues(alpha: 0.35)
        : AppColors.accent.withValues(alpha: 0.35);
    final ink = isOffTime ? AppColors.danger : AppColors.warning;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_filled_rounded,
            size: 34,
            color: ink,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Τρέχουσα διδακτική ώρα',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                Text(
                  currentHour,
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_DashboardTile> createState() => _DashboardTileState();
}

class _DashboardTileState extends State<_DashboardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.availableBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
