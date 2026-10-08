import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminMonitorPage extends StatefulWidget {
  const AdminMonitorPage({super.key});

  @override
  State<AdminMonitorPage> createState() => _AdminMonitorPageState();
}

class _AdminMonitorPageState extends State<AdminMonitorPage> {
  List<dynamic> _summaryData = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
    // Αυτόματη ανανέωση κάθε 5 δευτερόλεπτα
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchSummary(showLoading: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSummary({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);

    final data = await ApiService.getDailySummary();

    if (mounted) {
      setState(() {
        _summaryData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Συγκεντρωτική Αναφορά Ημέρας'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaryData.isEmpty
          ? const Center(
              child: Text(
                'Δεν έχουν υποβληθεί απουσίες για σήμερα.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: _summaryData.length,
              itemBuilder: (context, index) {
                final item = _summaryData[index];
                final String className = item['className'] ?? '';
                final String hour = item['hour'] ?? '';
                final String teacher = item['teacherName'] ?? 'Άγνωστος';
                final List<dynamic> absents = item['absentStudents'] ?? [];
                final List<dynamic> reserved =
                    item['reservedStudents'] ?? [];

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Τμήμα: $className',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.indigo),
                              ),
                              child: Text(
                                hour,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Εκπαιδευτικός: $teacher',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        const Text(
                          'Απόντες Μαθητές:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        absents.isEmpty
                            ? const Text(
                                '• Κανένας απόντας',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: absents
                                    .map(
                                      (student) => Padding(
                                        padding: const EdgeInsets.only(
                                          top: 2.0,
                                        ),
                                        child: Text(
                                          '• $student',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                        if (reserved.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Δεσμευμένοι (χωρίς απουσία):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: reserved
                                .map(
                                  (student) => Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      '• $student',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
