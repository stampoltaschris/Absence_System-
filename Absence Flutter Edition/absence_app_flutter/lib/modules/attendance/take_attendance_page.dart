import 'package:flutter/material.dart';

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

class _TakeAttendancePageState extends State<TakeAttendancePage> {
  List<Map<String, dynamic>> _students = [];
  List<dynamic> _teachers = [];
  bool _isLoading = false;

  bool get _hourlyOnly => widget.hourlyRemovalOnly;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    ApiService.unlockClass(widget.className);
    super.dispose();
  }

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
                  'absent': isAbsent,
                  'isExcused': isExcused,
                  'isHourlyRemoval': isHourly,
                  'wasAlreadyAbsent': isAbsent && !isHourly,
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

  Future<void> _submitAttendance() async {
    setState(() => _isLoading = true);

    final List<Map<String, dynamic>> absencesList = _students.map((s) {
      final bool isAbsent = s['absent'] ?? false;
      final bool isHourlyRemoval =
          isAbsent ? (s['isHourlyRemoval'] ?? false) : false;
      final bool isExcused =
          isAbsent && !isHourlyRemoval ? (s['isExcused'] ?? false) : false;

      return {
        'studentId': s['id'],
        'student_id': s['id'],
        'studentName': s['name'],
        'absent': isAbsent,
        'isAbsent': isAbsent,
        'is_absent': isAbsent ? 1 : 0,
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

    final result = await ApiService.submitAttendance(
      className: widget.className,
      period: widget.currentPeriod,
      absences: absencesList,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Οι απουσίες υποβλήθηκαν!'),
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

  @override
  Widget build(BuildContext context) {
    final appBarColor = _hourlyOnly ? Colors.purple.shade700 : Colors.blue.shade700;

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
          ? const Center(child: Text('Δεν βρέθηκαν μαθητές για αυτό το τμήμα.'))
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
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : (_hourlyOnly
                                ? _submitHourlyRemovals
                                : _submitAttendance),
                      icon: Icon(
                        _hourlyOnly ? Icons.door_front_door : Icons.send,
                        color: Colors.white,
                      ),
                      label: Text(
                        _hourlyOnly
                            ? 'Καταχώριση Ωριαίων Απομακρύνσεων'
                            : 'Υποβολή Απουσιών',
                        style: const TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hourlyOnly
                            ? Colors.purple.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
          ? 'Ήδη απόν (δέσμευση) — δεν αλλάζει'
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
          '⚠️ Δεσμευμένος: ${student['excuseReason'] ?? "Χωρίς αιτιολογία"}';
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
