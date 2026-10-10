import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/school_schedule.dart';
import '../../services/api_service.dart';
import 'take_attendance_page.dart';

class ClassSelectionPage extends StatefulWidget {
  const ClassSelectionPage({super.key});

  @override
  State<ClassSelectionPage> createState() => _ClassSelectionPageState();
}

class _ClassSelectionPageState extends State<ClassSelectionPage> {
  List<dynamic> _classes = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  late String _currentSchoolHour;
  bool _isAdmin = false; // 👉 Προσθήκη μεταβλητής για τον έλεγχο Admin

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _currentSchoolHour = SchoolSchedule.getCurrentSchoolHour();
    _bootstrap();

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final nextHour = SchoolSchedule.getCurrentSchoolHour();
      final hourChanged = nextHour != _currentSchoolHour;
      if (hourChanged && mounted) {
        setState(() => _currentSchoolHour = nextHour);
      }
      _fetchClasses(showLoading: false);
    });
  }

  Future<void> _bootstrap() async {
    await SchoolSchedule.loadFromApi();
    if (!mounted) return;
    setState(() {
      _currentSchoolHour = SchoolSchedule.getCurrentSchoolHour();
    });
    await _fetchClasses();
  }

  // 👉 Ανάγνωση ρόλου από τη μνήμη της συσκευής
  Future<void> _checkUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'teacher';
    if (mounted) {
      setState(() {
        _isAdmin = (role == 'admin');
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchClasses({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);

    final classesData = await ApiService.getClasses(_currentSchoolHour);

    if (mounted) {
      setState(() {
        _classes = classesData;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectClass(
    String className,
    bool isLocked,
    bool isSubmitted,
    String? lockedBy, {
    int? submittedByTeacherId,
    int? lockedByUserId,
  }) async {
    final canAttend =
        _isAdmin || SchoolSchedule.allowsTeacherAttendance(_currentSchoolHour);

    if (!canAttend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν μπορείτε να καταχωρήσετε απουσίες κατά τη διάρκεια διαλείμματος ή εκτός σχολικού ωραρίου.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final myId = prefs.getInt('user_id');
    if (!mounted) return;

    // Ήδη υποβληθέν: άνοιγμα μόνο για ωριαία απομάκρυνση (ίδιος καθηγητής ή admin)
    if (isSubmitted) {
      final canHourly =
          _isAdmin ||
          (submittedByTeacherId != null && submittedByTeacherId == myId);

      if (!canHourly) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Οι απουσίες για το τμήμα $className έχουν ήδη υποβληθεί. '
              'Ωριαία απομάκρυνση μπορεί να καταχωρήσει μόνο ο εκπαιδευτικός που τις υπέβαλε.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Μπλοκάρισμα μόνο αν το κρατά άλλος χρήστης.
    // Αν το lock είναι δικό σου (π.χ. μετά από hot restart), επιτρέπεται επανείσοδος.
    // Admin μπορεί να αναλάβει οποιοδήποτε lock.
    if (isLocked && lockedBy != null) {
      final isOwnLock = lockedByUserId != null && lockedByUserId == myId;
      if (!isOwnLock && !_isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Το τμήμα $className το επεξεργάζεται ο/η $lockedBy.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    final lockResult = await ApiService.lockClass(
      className,
      _currentSchoolHour,
    );
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (lockResult['success'] == true) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => TakeAttendancePage(
                className: className,
                currentPeriod: _currentSchoolHour,
                hourlyRemovalOnly: isSubmitted,
              ),
            ),
          )
          .then((_) => _fetchClasses());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lockResult['message'] ?? 'Σφάλμα δέσμευσης'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Μόνο admin: αναγκαστική αποδέσμευση τμήματος (όλες οι ώρες).
  Future<void> _adminForceUnlock(String className, String? lockedBy) async {
    if (!_isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ξεκλείδωμα τμήματος'),
        content: Text(
          'Να αποδεσμευτεί το τμήμα $className'
          '${lockedBy != null ? " (σε χρήση από $lockedBy)" : ""};\n\n'
          'Μόνο ο διαχειριστής μπορεί να το κάνει.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Ξεκλείδωμα'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    // Χωρίς currentHour → admin καθαρίζει όλα τα locks του τμήματος
    final result = await ApiService.unlockClass(className);
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Το τμήμα $className αποδεσμεύτηκε.'
              : (result['message'] ?? 'Αποτυχία ξεκλειδώματος'),
        ),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
    );

    if (result['success'] == true) {
      await _fetchClasses(showLoading: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Admin ή forceTestMode: δεν μπλοκάρουμε την οθόνη εκτός ωραρίου
    bool shouldBlockUI =
        !_isAdmin && !SchoolSchedule.allowsTeacherAttendance(_currentSchoolHour);

    return Scaffold(
      appBar: AppBar(
        title: Text('Επιλογή Τμήματος · $_currentSchoolHour'),
      ),
      body: Container(
        decoration: AppTheme.pageBackground(),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : shouldBlockUI
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 48,
                          color: AppColors.danger,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Αυτή τη στιγμή είναι $_currentSchoolHour.\n'
                          'Δεν επιτρέπεται η καταγραφή απουσιών.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.sora(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        _LegendDot(color: AppColors.availableBorder, label: 'Διαθέσιμο'),
                        const SizedBox(width: 14),
                        _LegendDot(color: AppColors.locked, label: 'Σε χρήση'),
                        const SizedBox(width: 14),
                        _LegendDot(color: AppColors.submittedInk, label: 'Υποβλήθηκε'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _classes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_late_outlined,
                                    size: 56,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _isAdmin
                                        ? 'Δεν υπάρχουν τμήματα στη βάση.'
                                        : 'Δεν σας έχουν ανατεθεί τμήματα.\n'
                                            'Επικοινωνήστε με τον διαχειριστή.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.sora(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.muted,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth >= 1000
                            ? 4
                            : (constraints.maxWidth >= 700 ? 3 : 2);
                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            childAspectRatio: 1.25,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: _classes.length,
                          itemBuilder: (context, index) {
                            final cls = _classes[index];
                            final String className = cls['name'] ?? '';
                            final bool isSubmitted =
                                cls['isSubmitted'] ?? false;
                            final bool isLocked = cls['isLocked'] ?? false;
                            final String? lockedBy = cls['lockedBy'];

                            Color cardColor = AppColors.available;
                            Color textColor = AppColors.ink;
                            Color borderColor = AppColors.availableBorder;
                            String statusText = 'Διαθέσιμο';
                            IconData statusIcon = Icons.circle_outlined;

                            final submittedByTeacherId =
                                cls['submittedByTeacherId'] is int
                                    ? cls['submittedByTeacherId'] as int
                                    : int.tryParse(
                                        '${cls['submittedByTeacherId'] ?? ''}',
                                      );
                            final lockedByUserId = cls['lockedByUserId'] is int
                                ? cls['lockedByUserId'] as int
                                : int.tryParse(
                                    '${cls['lockedByUserId'] ?? ''}',
                                  );

                            if (isSubmitted) {
                              cardColor = AppColors.submitted;
                              textColor = AppColors.submittedInk;
                              borderColor = AppColors.primaryMid
                                  .withValues(alpha: 0.35);
                              statusText = 'Υποβλήθηκε · Ωριαία';
                              statusIcon = Icons.check_circle_rounded;
                            } else if (isLocked) {
                              cardColor = AppColors.locked;
                              textColor = AppColors.lockedInk;
                              borderColor = AppColors.warning
                                  .withValues(alpha: 0.35);
                              statusText = 'Σε χρήση ($lockedBy)';
                              statusIcon = Icons.lock_rounded;
                            }

                            return Material(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _selectClass(
                                  className,
                                  isLocked,
                                  isSubmitted,
                                  lockedBy,
                                  submittedByTeacherId: submittedByTeacherId,
                                  lockedByUserId: lockedByUserId,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 1.4,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                className,
                                                style: GoogleFonts.sora(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w700,
                                                  color: textColor,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    statusIcon,
                                                    size: 14,
                                                    color: textColor,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      statusText,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style:
                                                          GoogleFonts.manrope(
                                                        color: textColor,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_isAdmin &&
                                          isLocked &&
                                          !isSubmitted)
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: IconButton(
                                            tooltip:
                                                'Ξεκλείδωμα (μόνο διαχειριστής)',
                                            icon: Icon(
                                              Icons.lock_open_rounded,
                                              color: AppColors.warning,
                                            ),
                                            onPressed: () => _adminForceUnlock(
                                              className,
                                              lockedBy,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
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
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.availableBorder),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
