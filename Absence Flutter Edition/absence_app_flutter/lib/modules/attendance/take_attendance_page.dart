import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/school_schedule.dart';
import '../../services/api_service.dart';

class TakeAttendancePage extends StatefulWidget {
  final String className;
  final String currentPeriod;

  /// true = ήδη υποβληθέν τμήμα· επιτρέπεται μόνο ωριαία απομάκρυνση
  final bool hourlyRemovalOnly;

  const TakeAttendancePage({
    super.key,
    required this.className,
    required this.currentPeriod,
    this.hourlyRemovalOnly = false,
  });

  @override
  State<TakeAttendancePage> createState() => _TakeAttendancePageState();
}

class _TakeAttendancePageState extends State<TakeAttendancePage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _students = [];
  List<dynamic> _teachers = [];
  bool _isLoading = false;
  bool _hasSubmitted = false;

  /// Υπενθύμιση αποστολής (ήχος + αναβοσβήσιμο)
  bool _showSubmitReminder = false;
  Timer? _selectionReminderTimer;
  Timer? _deadlineCheckTimer;
  Timer? _alertSoundTimer;
  late final AnimationController _flashController;
  late final AudioPlayer _alertPlayer;
  late final DateTime _pageOpenedAt;

  bool get _hourlyOnly => widget.hourlyRemovalOnly;

  bool get _hasAnyMarked =>
      _students.any((s) => s['absent'] == true);

  @override
  void initState() {
    super.initState();
    _pageOpenedAt = DateTime.now();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _alertPlayer = AudioPlayer();
    _loadInitialData();
    if (!_hourlyOnly) {
      _deadlineCheckTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkDeadlineReminder(),
      );
      // Έλεγχος αμέσως (π.χ. άνοιγμα μετά τις 08:30)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkDeadlineReminder();
      });
    }
  }

  @override
  void dispose() {
    _selectionReminderTimer?.cancel();
    _deadlineCheckTimer?.cancel();
    _stopAlertEffects();
    _flashController.dispose();
    _alertPlayer.dispose();
    if (!_hasSubmitted) {
      ApiService.unlockClass(widget.className);
    }
    super.dispose();
  }

  // ── Υπενθυμίσεις αποστολής ──────────────────────────────────────────

  void _onAbsenceSelectionChanged() {
    if (_hourlyOnly || _hasSubmitted) return;

    _selectionReminderTimer?.cancel();

    if (!_hasAnyMarked) return;

    // Περίπτωση α: 5′ μετά την τελευταία επιλογή απόντα
    _selectionReminderTimer = Timer(const Duration(minutes: 5), () {
      if (!mounted || _hasSubmitted) return;
      if (_hasAnyMarked) {
        _triggerSubmitReminder();
      }
    });
  }

  DateTime _resolveAllPresentDeadline() {
    final fromSchedule = SchoolSchedule.getSubmitReminderDeadline(
      widget.currentPeriod,
    );
    final inTeachingHour = SchoolSchedule.isTeachingHour(
      SchoolSchedule.getCurrentSchoolHour(),
    );

    // Εκτός ωραρίου / test mode: 15′ από το άνοιγμα της οθόνης
    if (SchoolSchedule.forceTestMode && !inTeachingHour) {
      return _pageOpenedAt.add(const Duration(minutes: 15));
    }

    if (fromSchedule != null) {
      return fromSchedule;
    }
    return _pageOpenedAt.add(const Duration(minutes: 15));
  }

  void _checkDeadlineReminder() {
    if (_hourlyOnly || _hasSubmitted || _showSubmitReminder) return;
    // Περίπτωση β: χωρίς επιλεγμένους απόντες → υπενθύμιση στην προθεσμία (π.χ. 08:30)
    if (_hasAnyMarked) return;

    final deadline = _resolveAllPresentDeadline();
    if (!DateTime.now().isBefore(deadline)) {
      _triggerSubmitReminder();
    }
  }

  Future<void> _triggerSubmitReminder() async {
    if (!mounted || _hasSubmitted || _showSubmitReminder) return;

    setState(() => _showSubmitReminder = true);
    _flashController.repeat(reverse: true);
    await _playAlertSound();
    _alertSoundTimer?.cancel();
    _alertSoundTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _playAlertSound();
    });
  }

  Future<void> _playAlertSound() async {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      await _alertPlayer.stop();
      await _alertPlayer.play(AssetSource('audio/submit_reminder.wav'));
    } catch (_) {
      // Οπτική υπενθύμιση παραμένει ακόμα κι αν αποτύχει ο ήχος
    }
  }

  void _stopAlertEffects() {
    _alertSoundTimer?.cancel();
    _alertSoundTimer = null;
    _flashController.stop();
    _flashController.reset();
    _alertPlayer.stop();
  }

  void _dismissSubmitReminder() {
    _stopAlertEffects();
    if (!mounted) return;
    setState(() => _showSubmitReminder = false);

    // Επανάληψη σε 2′ αν ακόμα δεν έχει γίνει αποστολή
    if (_hasAnyMarked) {
      _selectionReminderTimer?.cancel();
      _selectionReminderTimer = Timer(const Duration(minutes: 2), () {
        if (!mounted || _hasSubmitted) return;
        if (_hasAnyMarked) _triggerSubmitReminder();
      });
    }
  }

  void _clearReminderStateAfterSubmit() {
    _hasSubmitted = true;
    _selectionReminderTimer?.cancel();
    _deadlineCheckTimer?.cancel();
    _stopAlertEffects();
    if (_showSubmitReminder && mounted) {
      setState(() => _showSubmitReminder = false);
    }
  }

  // ── Φόρτωση / υποβολή ───────────────────────────────────────────────

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final teachersFuture = ApiService.getAllUsers();
      final classesFuture = ApiService.getClasses(widget.currentPeriod);

      final teachersData = await teachersFuture;
      final classes = await classesFuture;

      final currentClass = classes.firstWhere(
        (c) => c['name'] == widget.className,
        orElse: () => null,
      );

      if (currentClass != null && currentClass['id'] != null) {
        final studentsData = await ApiService.getStudentsByClass(
          currentClass['id'] as int,
        );

        Map<int, Map<String, dynamic>> existingById = {};
        if (_hourlyOnly) {
          final recordsRes = await ApiService.getAttendanceRecords(
            className: widget.className,
            period: widget.currentPeriod,
          );
          final records = recordsRes['records'];
          if (records is List) {
            for (final r in records) {
              final id = r['studentId'];
              if (id != null) {
                existingById[id is int ? id : int.tryParse('$id') ?? -1] =
                    Map<String, dynamic>.from(r as Map);
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _teachers = teachersData;
            _students = studentsData.map((s) {
              final int id = s['id'] is int
                  ? s['id'] as int
                  : int.tryParse('${s['id']}') ?? 0;
              final existing = existingById[id];

              if (_hourlyOnly && existing != null) {
                final bool isAbsent = existing['isAbsent'] == true;
                final bool isHourly = existing['isHourlyRemoval'] == true;
                final bool isExcused = existing['isExcused'] == true;
                return {
                  'id': id,
                  'name': s['name'] ?? existing['studentName'] ?? '',
                  'guardianEmail':
                      s['email'] ?? existing['guardianEmail'] ?? '',
                  'absent': isAbsent || isExcused,
                  'isExcused': isExcused,
                  'isHourlyRemoval': isHourly,
                  'wasAlreadyAbsent': (isAbsent && !isHourly) || isExcused,
                  'wasAlreadyHourly': isHourly,
                  'lockedStatus': isAbsent || isExcused || isHourly,
                  'excusedByTeacherId': null,
                  'excuseReason': existing['excuseReason'],
                };
              }

              return {
                'id': id,
                'name': s['name'] ?? '',
                'guardianEmail': s['email'] ?? '',
                'absent': false,
                'isExcused': false,
                'isHourlyRemoval': false,
                'wasAlreadyAbsent': false,
                'wasAlreadyHourly': false,
                'lockedStatus': false,
                'excusedByTeacherId': null,
                'excuseReason': null,
              };
            }).toList();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Σφάλμα κατά τη φόρτωση δεδομένων.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _buildAbsencesPayload() {
    return _students.map((s) {
      final bool marked = s['absent'] ?? false;
      final bool isHourlyRemoval =
          marked ? (s['isHourlyRemoval'] ?? false) : false;
      final bool isExcused =
          marked && !isHourlyRemoval ? (s['isExcused'] ?? false) : false;
      final bool isAbsentForDb = isHourlyRemoval
          ? true
          : (isExcused ? false : marked);

      return {
        'studentId': s['id'],
        'student_id': s['id'],
        'studentName': s['name'],
        'absent': isAbsentForDb,
        'isAbsent': isAbsentForDb,
        'is_absent': isAbsentForDb ? 1 : 0,
        'isHourlyRemoval': isHourlyRemoval,
        'is_hourly_removal': isHourlyRemoval,
        'isExcused': isExcused,
        'is_excused': isExcused,
        'excusedByTeacherId': isExcused ? s['excusedByTeacherId'] : null,
        'excused_by_teacher_id': isExcused ? s['excusedByTeacherId'] : null,
        'excuseReason': isHourlyRemoval
            ? 'Ωριαία απομάκρυνση'
            : (isExcused ? s['excuseReason'] : null),
        'excuse_reason': isHourlyRemoval
            ? 'Ωριαία απομάκρυνση'
            : (isExcused ? s['excuseReason'] : null),
        'guardianEmail': s['guardianEmail'] ?? '',
      };
    }).toList();
  }

  Future<void> _submitAttendance({required bool allPresent}) async {
    setState(() => _isLoading = true);

    if (allPresent) {
      for (final s in _students) {
        s['absent'] = false;
        s['isExcused'] = false;
        s['isHourlyRemoval'] = false;
        s['excusedByTeacherId'] = null;
        s['excuseReason'] = null;
      }
    }

    final result = await ApiService.submitAttendance(
      className: widget.className,
      period: widget.currentPeriod,
      absences: _buildAbsencesPayload(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      _clearReminderStateAfterSubmit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allPresent
                ? (result['message'] ?? 'Καταχωρήθηκε: όλοι παρόντες.')
                : (result['message'] ?? 'Οι απουσίες υποβλήθηκαν!'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Σφάλμα υποβολής'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmAllPresent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Όλοι παρόντες;'),
        content: Text(
          'Θα καταχωρηθεί το τμήμα ${widget.className} χωρίς απουσίες '
          'για την ${widget.currentPeriod}. Συνέχεια;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ναι, όλοι παρόντες'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _submitAttendance(allPresent: true);
    }
  }

  Future<void> _submitHourlyRemovals() async {
    final ids = _students
        .where(
          (s) =>
              (s['isHourlyRemoval'] == true) &&
              (s['wasAlreadyHourly'] != true) &&
              (s['wasAlreadyAbsent'] != true),
        )
        .map((s) => s['id'] as int)
        .toList();

    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Επιλέξτε τουλάχιστον έναν παρόντα μαθητή.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.submitHourlyRemovals(
      className: widget.className,
      period: widget.currentPeriod,
      studentIds: ids,
    );
    setState(() => _isLoading = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? ''),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
    );

    if (result['success'] == true) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appBarColor =
        _hourlyOnly ? Colors.purple.shade700 : Colors.blue.shade700;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _hourlyOnly
              ? 'Ωριαία απομάκρυνση: ${widget.className}'
              : 'Καταγραφή: ${widget.className} (${widget.currentPeriod})',
        ),
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _students.isEmpty
              ? const Center(
                  child: Text('Δεν βρέθηκαν μαθητές για αυτό το τμήμα.'),
                )
              : Column(
                  children: [
                    if (_hourlyOnly)
                      Container(
                        width: double.infinity,
                        color: Colors.purple.shade50,
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Οι απουσίες έχουν ήδη υποβληθεί.\n'
                          'Μπορείτε να καταχωρήσετε μόνο ωριαία απομάκρυνση για παρόντες μαθητές (χωρίς email).',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          if (_hourlyOnly) {
                            return _buildHourlyOnlyTile(index, student);
                          }
                          return _buildFullAttendanceTile(index, student);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: _hourlyOnly
                          ? SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isLoading ? null : _submitHourlyRemovals,
                                icon: const Icon(
                                  Icons.door_front_door,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Καταχώριση Ωριαίων Απομακρύνσεων',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade700,
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        _isLoading ? null : _confirmAllPresent,
                                    icon: Icon(
                                      Icons.done_all,
                                      color: Colors.teal.shade800,
                                    ),
                                    label: Text(
                                      'Όλοι παρόντες',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.teal.shade800,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Colors.teal.shade700,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : () => _submitAttendance(
                                              allPresent: false,
                                            ),
                                    icon: const Icon(
                                      Icons.send,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Υποβολή Απουσιών',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
          if (_showSubmitReminder) _buildSubmitReminderOverlay(),
        ],
      ),
    );
  }

  Widget _buildSubmitReminderOverlay() {
    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, _) {
        final flash = _flashController.value;
        final bg = Color.lerp(
          Colors.red.shade900.withValues(alpha: 0.88),
          Colors.orange.shade800.withValues(alpha: 0.92),
          flash,
        )!;
        return Positioned.fill(
          child: Material(
            color: bg,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 88,
                      color: Colors.white.withValues(alpha: 0.7 + 0.3 * flash),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Δεν έχετε προχωρήσει σε αποστολή των απόντων',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _dismissSubmitReminder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                      ),
                      child: const Text(
                        'Εντάξει',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHourlyOnlyTile(int index, Map<String, dynamic> student) {
    final bool wasAlreadyAbsent = student['wasAlreadyAbsent'] == true;
    final bool wasAlreadyHourly = student['wasAlreadyHourly'] == true;
    final bool isHourlyRemoval = student['isHourlyRemoval'] == true;
    final bool canMark = !wasAlreadyAbsent && !wasAlreadyHourly;

    String statusLabel;
    Color borderColor;
    if (wasAlreadyHourly || (isHourlyRemoval && !canMark)) {
      statusLabel = 'Ήδη: Ωριαία απομάκρυνση';
      borderColor = Colors.purple;
    } else if (wasAlreadyAbsent) {
      statusLabel = student['isExcused'] == true
          ? 'Δεσμευμένος (όχι απουσία) — δεν αλλάζει'
          : 'Ήδη απόν — δεν αλλάζει';
      borderColor = Colors.grey;
    } else if (isHourlyRemoval) {
      statusLabel = 'Νέα ωριαία απομάκρυνση (χωρίς email)';
      borderColor = Colors.purple;
    } else {
      statusLabel = 'Παρών — μπορείτε να σημειώσετε ωριαία απομάκρυνση';
      borderColor = Colors.green.shade300;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      elevation: isHourlyRemoval ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: SwitchListTile(
        title: Text(
          student['name'] ?? '',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: canMark ? Colors.black : Colors.grey.shade700,
          ),
        ),
        subtitle: Text(
          statusLabel,
          style: TextStyle(
            color: wasAlreadyAbsent
                ? Colors.grey.shade600
                : Colors.purple.shade800,
            fontWeight: FontWeight.w500,
          ),
        ),
        value: isHourlyRemoval,
        activeThumbColor: Colors.purple,
        onChanged: canMark
            ? (bool val) {
                setState(() {
                  _students[index]['isHourlyRemoval'] = val;
                  _students[index]['absent'] = val;
                });
              }
            : null,
      ),
    );
  }

  Widget _buildFullAttendanceTile(int index, Map<String, dynamic> student) {
    final bool isAbsent = student['absent'] ?? false;
    final bool isHourlyRemoval = student['isHourlyRemoval'] ?? false;
    final bool isExcused = student['isExcused'] ?? false;

    Color borderColor = Colors.red;
    if (isHourlyRemoval) {
      borderColor = Colors.purple;
    } else if (isExcused) {
      borderColor = Colors.orange;
    }

    String subtitleText;
    if (isAbsent && isHourlyRemoval) {
      subtitleText = '🚪 Ωριαία απομάκρυνση (χωρίς email κηδεμόνα)';
    } else if (isAbsent && isExcused) {
      subtitleText =
          'Δεσμευμένος (όχι απουσία): ${student['excuseReason'] ?? "Χωρίς αιτιολογία"}';
    } else if (student['guardianEmail'] != null &&
        student['guardianEmail'].toString().isNotEmpty) {
      subtitleText = student['guardianEmail'].toString();
    } else {
      subtitleText = 'Χωρίς email';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      elevation: isAbsent ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isAbsent
            ? BorderSide(color: borderColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(
                student['name'] ?? '',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitleText,
                style: TextStyle(
                  color: isAbsent && (isExcused || isHourlyRemoval)
                      ? (isHourlyRemoval
                            ? Colors.purple.shade800
                            : Colors.orange.shade800)
                      : Colors.grey.shade600,
                  fontWeight: isAbsent && (isExcused || isHourlyRemoval)
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              value: isAbsent,
              activeColor: isHourlyRemoval
                  ? Colors.purple
                  : (isExcused ? Colors.orange : Colors.red),
              onChanged: (bool? val) {
                setState(() {
                  _students[index]['absent'] = val ?? false;
                  if (!(val ?? false)) {
                    _students[index]['isExcused'] = false;
                    _students[index]['isHourlyRemoval'] = false;
                    _students[index]['excusedByTeacherId'] = null;
                    _students[index]['excuseReason'] = null;
                  }
                });
                _onAbsenceSelectionChanged();
              },
            ),
            if (isAbsent) ...[
              const Divider(height: 1),
              SwitchListTile(
                dense: true,
                title: const Text(
                  'Ωριαία απομάκρυνση',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple,
                  ),
                ),
                subtitle: const Text(
                  'Καταγράφεται χωρίς αποστολή email',
                  style: TextStyle(fontSize: 12),
                ),
                value: isHourlyRemoval,
                activeThumbColor: Colors.purple,
                onChanged: (bool val) {
                  setState(() {
                    _students[index]['isHourlyRemoval'] = val;
                    if (val) {
                      _students[index]['isExcused'] = false;
                      _students[index]['excusedByTeacherId'] = null;
                      _students[index]['excuseReason'] = null;
                    }
                  });
                  _onAbsenceSelectionChanged();
                },
              ),
              if (!isHourlyRemoval)
                SwitchListTile(
                  dense: true,
                  title: const Text(
                    'Δέσμευση από άλλον εκπαιδευτικό',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                  subtitle: const Text(
                    'Δεν καταχωρείται απουσία και δεν στέλνεται email',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: isExcused,
                  activeThumbColor: Colors.orange,
                  onChanged: (bool val) {
                    setState(() {
                      _students[index]['isExcused'] = val;
                      if (!val) {
                        _students[index]['excusedByTeacherId'] = null;
                        _students[index]['excuseReason'] = null;
                      }
                    });
                    _onAbsenceSelectionChanged();
                  },
                ),
              if (isExcused && !isHourlyRemoval)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Εκπαιδευτικός που δέσμευσε',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        initialValue: student['excusedByTeacherId'],
                        items: _teachers.map<DropdownMenuItem<int>>((t) {
                          return DropdownMenuItem<int>(
                            value: t['id'] as int?,
                            child: Text(
                              t['name'] ?? t['username'] ?? 'Καθηγητής',
                            ),
                          );
                        }).toList(),
                        onChanged: (int? teacherId) {
                          setState(() {
                            _students[index]['excusedByTeacherId'] = teacherId;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Λόγος Δέσμευσης',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        initialValue: student['excuseReason'],
                        items: const [
                          DropdownMenuItem(
                            value: 'Πρόβα γιορτής',
                            child: Text('Πρόβα γιορτής'),
                          ),
                          DropdownMenuItem(
                            value: 'Διαγώνισμα',
                            child: Text('Διαγώνισμα'),
                          ),
                          DropdownMenuItem(
                            value: 'Σχολική δράση',
                            child: Text('Σχολική δράση'),
                          ),
                          DropdownMenuItem(value: 'Άλλο', child: Text('Άλλο')),
                        ],
                        onChanged: (String? reason) {
                          setState(() {
                            _students[index]['excuseReason'] = reason;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
