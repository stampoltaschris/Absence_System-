import 'package:flutter/material.dart';

import '../../core/school_schedule.dart';
import '../../services/api_service.dart';

class ScheduleSettingsPage extends StatefulWidget {
  const ScheduleSettingsPage({super.key});

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Ημέρες Εβδομάδας (True = Ενεργή ημέρα)
  Map<String, bool> _activeDays = {
    'Δευτέρα': true,
    'Τρίτη': true,
    'Τετάρτη': true,
    'Πέμπτη': true,
    'Παρασκευή': true,
    'Σάββατο': false, // Δοκιμαστικός τομέας
    'Κυριακή': false, // Δοκιμαστικός τομέας
  };

  // Χειροκίνητη ενεργοποίηση Test Mode
  bool _forceTestMode = false;

  // Controllers για τις 7 Διδακτικές Ώρες (Start & End)
  final Map<int, TextEditingController> _teachingStartControllers = {};
  final Map<int, TextEditingController> _teachingEndControllers = {};

  // Controllers για τη διάρκεια των 6 Διαλειμμάτων (σε λεπτά)
  final Map<int, TextEditingController> _breakDurationControllers = {};

  // Προκαθορισμένες τιμές (Defaults)
  final List<Map<String, String>> _defaultTeachingHours = [
    {'start': '08:15', 'end': '09:00'}, // 1η ώρα
    {'start': '09:05', 'end': '09:50'}, // 2η ώρα
    {'start': '10:00', 'end': '10:45'}, // 3η ώρα
    {'start': '10:55', 'end': '11:40'}, // 4η ώρα
    {'start': '11:50', 'end': '12:35'}, // 5η ώρα
    {'start': '12:40', 'end': '13:20'}, // 6η ώρα
    {'start': '13:25', 'end': '14:10'}, // 7η ώρα
  ];

  final List<String> _defaultBreakDurations = [
    '5',
    '10',
    '10',
    '10',
    '5',
    '5',
  ]; // 6 Διαλείμματα

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadSettings();
  }

  void _initControllers() {
    // 7 Διδακτικές Ώρες
    for (int i = 0; i < 7; i++) {
      _teachingStartControllers[i + 1] = TextEditingController(
        text: _defaultTeachingHours[i]['start'],
      );
      _teachingEndControllers[i + 1] = TextEditingController(
        text: _defaultTeachingHours[i]['end'],
      );
    }
    // 6 Διαλείμματα (αρχικοποίηση με τις προκαθορισμένες τιμές)
    for (int i = 0; i < 6; i++) {
      _breakDurationControllers[i + 1] = TextEditingController(
        text: _defaultBreakDurations[i],
      );
    }
  }

  @override
  void dispose() {
    for (var c in _teachingStartControllers.values) {
      c.dispose();
    }
    for (var c in _teachingEndControllers.values) {
      c.dispose();
    }
    for (var c in _breakDurationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getScheduleSettings();

    if (mounted && data.isNotEmpty) {
      setState(() {
        if (data['activeDays'] != null) {
          _activeDays = Map<String, bool>.from(data['activeDays']);
        }
        _forceTestMode = data['forceTestMode'] ?? false;

        // Φόρτωση Διδακτικών Ωρών
        if (data['teachingHours'] != null && data['teachingHours'] is List) {
          final List hoursList = data['teachingHours'];
          for (int i = 0; i < hoursList.length && i < 7; i++) {
            if (hoursList[i]['start'] != null &&
                hoursList[i]['start'].isNotEmpty) {
              _teachingStartControllers[i + 1]?.text = hoursList[i]['start'];
            }
            if (hoursList[i]['end'] != null && hoursList[i]['end'].isNotEmpty) {
              _teachingEndControllers[i + 1]?.text = hoursList[i]['end'];
            }
          }
        }

        // Φόρτωση Διαρκειών Διαλειμμάτων
        if (data['breakDurations'] != null && data['breakDurations'] is List) {
          final List breaksList = data['breakDurations'];
          for (int i = 0; i < breaksList.length && i < 6; i++) {
            final val = breaksList[i].toString();
            if (val.isNotEmpty && val != 'null') {
              _breakDurationControllers[i + 1]?.text = val;
            }
          }
        }
      });
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // 1. Συλλογή 7 Διδακτικών Ωρών
    List<Map<String, String>> teachingHoursPayload = [];
    for (int i = 1; i <= 7; i++) {
      teachingHoursPayload.add({
        'name': '$iη ώρα',
        'start': _teachingStartControllers[i]?.text.trim() ?? '',
        'end': _teachingEndControllers[i]?.text.trim() ?? '',
      });
    }

    // 2. Συλλογή 6 Διαρκειών Διαλειμμάτων
    List<int> breakDurationsPayload = [];
    for (int i = 1; i <= 6; i++) {
      final duration =
          int.tryParse(_breakDurationControllers[i]?.text.trim() ?? '5') ?? 5;
      breakDurationsPayload.add(duration);
    }

    // 3. Υπολογισμός ορίων διαλειμμάτων
    List<Map<String, String>> calculatedBreaksPayload = [];
    for (int i = 0; i < 6; i++) {
      final breakNum = i + 1;
      final startOfBreak = _teachingEndControllers[breakNum]?.text.trim() ?? '';
      final endOfBreak =
          _teachingStartControllers[breakNum + 1]?.text.trim() ?? '';

      calculatedBreaksPayload.add({
        'name': '$breakNumο Διάλειμμα',
        'start': startOfBreak,
        'end': endOfBreak,
        'durationMinutes': breakDurationsPayload[i].toString(),
      });
    }

    final payload = {
      'activeDays': _activeDays,
      'forceTestMode': _forceTestMode,
      'teachingHours': teachingHoursPayload,
      'breakDurations': breakDurationsPayload,
      'calculatedBreaks': calculatedBreaksPayload,
    };

    final success = await ApiService.saveScheduleSettings(payload);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      // Άμεση εφαρμογή στο τοπικό ρολόι (χωρίς επανεκκίνηση)
      SchoolSchedule.applyConfig(payload);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Το πρόγραμμα και τα διαλείμματα αποθηκεύτηκαν!'
              : 'Αποτυχία αποθήκευσης.',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Διαχείριση Ωραρίου & Διαλειμμάτων'),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- KARTA TEST MODE ---
                  Card(
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: Colors.amber.shade700,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Χειροκίνητη Ενεργοποίηση Δοκιμαστικής Λειτουργίας',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Επιτρέπει την καταχώριση δοκιμαστικών απουσιών οποιαδήποτε στιγμή.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _forceTestMode,
                      activeThumbColor: Colors.amber.shade900,
                      onChanged: (val) {
                        setState(() => _forceTestMode = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- 1. ΕΠΙΛΟΓΗ ΗΜΕΡΩΝ ---
                  const Text(
                    '1. Ημέρες Διδασκαλίας & Δοκιμαστικός Τομέας',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Card(
                    child: Column(
                      children: _activeDays.keys.map((day) {
                        final isWeekend = day == 'Σάββατο' || day == 'Κυριακή';
                        return CheckboxListTile(
                          dense: true,
                          title: Row(
                            children: [
                              Text(
                                day,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isWeekend)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Δοκιμαστικό',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          value: _activeDays[day],
                          onChanged: (val) {
                            setState(() {
                              _activeDays[day] = val ?? false;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- 2. ΩΡΕΣ ΔΙΔΑΣΚΑΛΙΑΣ & ΔΙΑΛΕΙΜΜΑΤΑ ---
                  const Text(
                    '2. Ώρες Διδασκαλίας (7) & Διάρκεια Διαλειμμάτων (6)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Εισάγετε την έναρξη/λήξη για κάθε ώρα και τη διάρκεια (λεπτά) για κάθε διάλειμμα.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final hourNum = index + 1;
                      final hasBreakAfter = hourNum < 7;

                      final breakStart =
                          _teachingEndControllers[hourNum]?.text ?? '';
                      final breakEnd =
                          _teachingStartControllers[hourNum + 1]?.text ?? '';

                      return Column(
                        children: [
                          // Κάρτα Διδακτικής Ώρας
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '$hourNumη Ώρα:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller:
                                          _teachingStartControllers[hourNum],
                                      decoration: const InputDecoration(
                                        labelText: 'Έναρξη',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller:
                                          _teachingEndControllers[hourNum],
                                      decoration: const InputDecoration(
                                        labelText: 'Λήξη',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Γραμμή Διάρκειας & Ωρών Διαλείμματος
                          if (hasBreakAfter)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6.0,
                                horizontal: 12.0,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.brown.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.brown.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.coffee,
                                      color: Colors.brown,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$hourNumο Διάλειμμα:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.brown,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        controller:
                                            _breakDurationControllers[hourNum],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          suffixText: 'λεπτά',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    // Εμφάνιση αυτόματου υπολογισμού ώρας διαλείμματος
                                    if (breakStart.isNotEmpty &&
                                        breakEnd.isNotEmpty)
                                      Text(
                                        '($breakStart - $breakEnd)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.brown.shade800,
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // --- ΚΟΥΜΠΙ ΑΠΟΘΗΚΕΥΣΗΣ ---
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[800],
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSaving
                          ? const SizedBox.shrink()
                          : const Icon(Icons.save),
                      label: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Αποθήκευση & Υπολογισμός Προγράμματος',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
