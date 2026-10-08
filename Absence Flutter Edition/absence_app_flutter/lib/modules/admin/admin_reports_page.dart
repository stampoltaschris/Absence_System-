import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  List<dynamic> _teachers = [];
  List<dynamic> _reports = [];
  bool _isLoading = false;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  int? _selectedTeacherId;
  String _selectedHour = 'Όλες';

  final List<String> _schoolHours = [
    'Όλες',
    '1η ώρα',
    '2η ώρα',
    '3η ώρα',
    '4η ώρα',
    '5η ώρα',
    '6η ώρα',
    '7η ώρα',
  ];

  @override
  void initState() {
    super.initState();
    _loadTeachers();
    _fetchReports();
  }

  Future<void> _loadTeachers() async {
    final users = await ApiService.getAllUsers();
    if (!mounted) return;
    setState(() {
      _teachers = users
          .where((u) => u['role'] == 'teacher' || u['role'] == 'admin')
          .toList();
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: Colors.green.shade700),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchReports();
    }
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);

    final String startStr =
        "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}";
    final String endStr =
        "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}";
    final String teacherFilter = _selectedTeacherId != null
        ? _selectedTeacherId.toString()
        : '';

    try {
      final results = await ApiService.getReports(
        startDate: startStr,
        endDate: endStr,
        teacherIds: teacherFilter,
      );

      if (!mounted) return;

      setState(() {
        // Φιλτράρισμα τοπικά αν έχει επιλεγεί συγκεκριμένη διδακτική ώρα
        if (_selectedHour != 'Όλες') {
          _reports = results
              .where(
                (r) =>
                    r['schoolHour'] == _selectedHour ||
                    r['hour'] == _selectedHour,
              )
              .toList();
        } else {
          _reports = results;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Σφάλμα λήψης αναφορών: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String startStr =
        "${_startDate.day}/${_startDate.month}/${_startDate.year}";
    final String endStr = "${_endDate.day}/${_endDate.month}/${_endDate.year}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Αναφορές & Στατιστικά'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- ΠΑΝΕΛ ΦΙΛΤΡΩΝ ---
          Card(
            margin: const EdgeInsets.all(12.0),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  // 1. Επιλογή Εύρους Ημερομηνιών
                  InkWell(
                    onTap: _selectDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.green),
                          const SizedBox(width: 10),
                          Text(
                            'Εύρος: $startStr - $endStr',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Dropdowns για Καθηγητή & Διδακτική Ώρα
                  Row(
                    children: [
                      // Dropdown Καθηγητή
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          decoration: const InputDecoration(
                            labelText: 'Καθηγητής',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          initialValue: _selectedTeacherId,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Όλοι οι Καθηγητές'),
                            ),
                            ..._teachers.map<DropdownMenuItem<int?>>((t) {
                              return DropdownMenuItem<int?>(
                                value: t['id'] as int?,
                                child: Text(
                                  t['name'] ?? t['username'] ?? 'Καθηγητής',
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedTeacherId = val);
                            _fetchReports();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Dropdown Διδακτικής Ώρας
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Διδακτική Ώρα',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          initialValue: _selectedHour,
                          items: _schoolHours.map((hour) {
                            return DropdownMenuItem<String>(
                              value: hour,
                              child: Text(hour),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedHour = val);
                              _fetchReports();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // --- ΛΙΣΤΑ ΑΠΟΤΕΛΕΣΜΑΤΩΝ ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                ? const Center(child: Text('Δεν βρέθηκαν καταγραφές.'))
                : ListView.builder(
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final item = _reports[index];
                      final String className =
                          item['className'] ?? item['class_name'] ?? '';
                      final String hour =
                          item['schoolHour'] ?? item['hour'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.assignment_turned_in,
                            color: Colors.green,
                          ),
                          title: Text(
                            '$className - $hour',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Καθηγητής: ${item['teacherName'] ?? item['teacher_name'] ?? 'Άγνωστος'}\nΗμ/νία: ${item['date'] ?? ''}",
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
