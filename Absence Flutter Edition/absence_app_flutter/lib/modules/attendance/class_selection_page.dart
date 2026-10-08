import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  Widget build(BuildContext context) {
    // Admin ή forceTestMode: δεν μπλοκάρουμε την οθόνη εκτός ωραρίου
    bool shouldBlockUI =
        !_isAdmin && !SchoolSchedule.allowsTeacherAttendance(_currentSchoolHour);

    return Scaffold(
      appBar: AppBar(
        title: Text('Επιλογή Τμήματος ($_currentSchoolHour)'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : shouldBlockUI
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Αυτή τη στιγμή είναι $_currentSchoolHour.\nΔεν επιτρέπεται η καταγραφή απουσιών.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _classes.length,
              itemBuilder: (context, index) {
                final cls = _classes[index];
                final String className = cls['name'] ?? '';
                final bool isSubmitted = cls['isSubmitted'] ?? false;
                final bool isLocked = cls['isLocked'] ?? false;
                final String? lockedBy = cls['lockedBy'];

                Color cardColor = Colors.white;
                Color textColor = Colors.black;
                String statusText = 'Διαθέσιμο';

                final submittedByTeacherId = cls['submittedByTeacherId'] is int
                    ? cls['submittedByTeacherId'] as int
                    : int.tryParse('${cls['submittedByTeacherId'] ?? ''}');
                final lockedByUserId = cls['lockedByUserId'] is int
                    ? cls['lockedByUserId'] as int
                    : int.tryParse('${cls['lockedByUserId'] ?? ''}');

                if (isSubmitted) {
                  cardColor = Colors.purple.shade50;
                  textColor = Colors.purple.shade900;
                  statusText = 'Υποβλήθηκε · Ωριαία απομάκρυνση';
                } else if (isLocked) {
                  cardColor = Colors.amber.shade100;
                  textColor = Colors.amber.shade900;
                  statusText = 'Σε χρήση ($lockedBy)';
                }

                return Card(
                  color: cardColor,
                  elevation: 2,
                  child: InkWell(
                    onTap: () => _selectClass(
                      className,
                      isLocked,
                      isSubmitted,
                      lockedBy,
                      submittedByTeacherId: submittedByTeacherId,
                      lockedByUserId: lockedByUserId,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            className,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
