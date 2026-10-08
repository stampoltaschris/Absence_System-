import '../services/api_service.dart';

/// Σχολικό ωράριο με defaults + ρυθμίσεις από το backend (`schedule_settings`).
class SchoolSchedule {
  static const List<String> dayNames = [
    'Δευτέρα',
    'Τρίτη',
    'Τετάρτη',
    'Πέμπτη',
    'Παρασκευή',
    'Σάββατο',
    'Κυριακή',
  ];

  static const Map<String, bool> defaultActiveDays = {
    'Δευτέρα': true,
    'Τρίτη': true,
    'Τετάρτη': true,
    'Πέμπτη': true,
    'Παρασκευή': true,
    'Σάββατο': false,
    'Κυριακή': false,
  };

  static const List<Map<String, String>> defaultTeachingHours = [
    {'name': '1η ώρα', 'start': '08:15', 'end': '09:00'},
    {'name': '2η ώρα', 'start': '09:05', 'end': '09:50'},
    {'name': '3η ώρα', 'start': '10:00', 'end': '10:45'},
    {'name': '4η ώρα', 'start': '10:55', 'end': '11:40'},
    {'name': '5η ώρα', 'start': '11:50', 'end': '12:35'},
    {'name': '6η ώρα', 'start': '12:40', 'end': '13:20'},
    {'name': '7η ώρα', 'start': '13:25', 'end': '14:10'},
  ];

  static Map<String, bool> _activeDays = Map<String, bool>.from(defaultActiveDays);
  static bool _forceTestMode = false;
  static List<Map<String, String>> _teachingHours =
      List<Map<String, String>>.from(
        defaultTeachingHours.map((e) => Map<String, String>.from(e)),
      );
  static List<Map<String, String>> _breaks = _deriveBreaks(defaultTeachingHours);

  static bool get forceTestMode => _forceTestMode;

  /// Εφαρμογή payload από API / οθόνη ρυθμίσεων.
  static void applyConfig(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    if (data['activeDays'] is Map) {
      final raw = Map<String, dynamic>.from(data['activeDays'] as Map);
      _activeDays = {
        for (final day in dayNames) day: raw[day] == true,
      };
    }

    if (data.containsKey('forceTestMode')) {
      _forceTestMode = data['forceTestMode'] == true;
    }

    if (data['teachingHours'] is List && (data['teachingHours'] as List).isNotEmpty) {
      final list = data['teachingHours'] as List;
      _teachingHours = [];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) continue;
        final start = (item['start'] ?? '').toString().trim();
        final end = (item['end'] ?? '').toString().trim();
        if (start.isEmpty || end.isEmpty) continue;
        final name = (item['name'] ?? '').toString().trim();
        _teachingHours.add({
          'name': name.isNotEmpty ? name : '${i + 1}η ώρα',
          'start': start,
          'end': end,
        });
      }
      if (_teachingHours.isEmpty) {
        _teachingHours = List<Map<String, String>>.from(
          defaultTeachingHours.map((e) => Map<String, String>.from(e)),
        );
      }
    }

    if (data['calculatedBreaks'] is List &&
        (data['calculatedBreaks'] as List).isNotEmpty) {
      final list = data['calculatedBreaks'] as List;
      _breaks = [];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) continue;
        final start = (item['start'] ?? '').toString().trim();
        final end = (item['end'] ?? '').toString().trim();
        if (start.isEmpty || end.isEmpty) continue;
        final name = (item['name'] ?? '').toString().trim();
        _breaks.add({
          'name': name.isNotEmpty ? name : '${i + 1}ο Διάλειμμα',
          'start': start,
          'end': end,
        });
      }
    } else {
      _breaks = _deriveBreaks(_teachingHours);
    }
  }

  /// Φόρτωση ρυθμίσεων από τον server (μετά το login / άνοιγμα dashboard).
  static Future<void> loadFromApi() async {
    final data = await ApiService.getScheduleSettings();
    if (data.isNotEmpty) {
      applyConfig(data);
    }
  }

  static List<Map<String, String>> _deriveBreaks(
    List<Map<String, String>> hours,
  ) {
    final breaks = <Map<String, String>>[];
    for (var i = 0; i < hours.length - 1; i++) {
      final start = hours[i]['end'] ?? '';
      final end = hours[i + 1]['start'] ?? '';
      if (start.isEmpty || end.isEmpty) continue;
      breaks.add({
        'name': '${i + 1}ο Διάλειμμα',
        'start': start,
        'end': end,
      });
    }
    return breaks;
  }

  static int? _parseTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    return hours * 60 + minutes;
  }

  // 📅 Επιστρέφει την Ημέρα & Ημερομηνία (π.χ. "Δευτέρα, 28/09/2026")
  static String getFormattedDate([DateTime? customTime]) {
    final now = customTime ?? DateTime.now();
    final dayName = dayNames[now.weekday - 1];
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year;

    return '$dayName, $day/$month/$year';
  }

  // ⏰ Επιστρέφει την τρέχουσα διδακτική ώρα ή κατάσταση διαλείμματος
  static String getCurrentSchoolHour([DateTime? customTime]) {
    final now = customTime ?? DateTime.now();
    final dayName = dayNames[now.weekday - 1];

    if (!(_activeDays[dayName] ?? false)) {
      return 'Εκτός Σχολικού Ωραρίου';
    }

    final currentMinutes = now.hour * 60 + now.minute;

    for (final hour in _teachingHours) {
      final start = _parseTime(hour['start']);
      final end = _parseTime(hour['end']);
      if (start == null || end == null) continue;
      if (currentMinutes >= start && currentMinutes < end) {
        return hour['name'] ?? 'ώρα';
      }
    }

    for (final br in _breaks) {
      final start = _parseTime(br['start']);
      final end = _parseTime(br['end']);
      if (start == null || end == null) continue;
      if (currentMinutes >= start && currentMinutes < end) {
        return br['name'] ?? 'Διάλειμμα';
      }
    }

    return 'Εκτός Σχολικού Ωραρίου';
  }

  /// Διδακτική ώρα (όχι διάλειμμα / εκτός). Με forceTestMode επιτρέπεται πάντα.
  static bool isTeachingHour(String hourStatus) {
    return hourStatus.contains('ώρα');
  }

  /// Αν επιτρέπεται καταχώριση για μη-admin (διδακτική ώρα ή δοκιμαστική λειτουργία).
  static bool allowsTeacherAttendance([String? hourStatus]) {
    if (_forceTestMode) return true;
    final status = hourStatus ?? getCurrentSchoolHour();
    return isTeachingHour(status);
  }

  /// Εύρεση διδακτικής ώρας από όνομα (π.χ. "1η ώρα").
  static Map<String, String>? getTeachingHourByName(String periodName) {
    final needle = periodName.trim();
    if (needle.isEmpty) return null;
    for (final hour in _teachingHours) {
      if ((hour['name'] ?? '').trim() == needle) return hour;
    }
    return null;
  }

  /// Ώρα έναρξης διδακτικής ώρας σε λεπτά από τα μεσάνυχτα.
  static int? getPeriodStartMinutes(String periodName) {
    final hour = getTeachingHourByName(periodName);
    if (hour == null) return null;
    return _parseTime(hour['start']);
  }

  /// Προθεσμία υπενθύμισης αποστολής: έναρξη ώρας + [minutesAfterStart] (π.χ. 08:15 → 08:30).
  static DateTime? getSubmitReminderDeadline(
    String periodName, {
    int minutesAfterStart = 15,
    DateTime? onDate,
  }) {
    final startMins = getPeriodStartMinutes(periodName);
    if (startMins == null) return null;
    final day = onDate ?? DateTime.now();
    return DateTime(day.year, day.month, day.day)
        .add(Duration(minutes: startMins + minutesAfterStart));
  }
}
