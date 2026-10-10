import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  /// Για tablets στο σχολικό Wi‑Fi βάλε την IP του κεντρικού PC.
  /// Στο Flutter Web (ίδιος υπολογιστής με τον server) χρησιμοποιείται localhost.
  static const String defaultLanServerIp = '192.168.2.102:5000';
  static String get defaultServerIp =>
      kIsWeb ? 'localhost:5000' : defaultLanServerIp;

  // --- CONFIGURATION & HELPERS ---
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String savedIp = prefs.getString('server_ip') ?? defaultServerIp;
    savedIp = savedIp.trim();

    if (savedIp.isEmpty) {
      savedIp = defaultServerIp;
    }

    if (!savedIp.startsWith('http://') && !savedIp.startsWith('https://')) {
      savedIp = 'http://$savedIp';
    }

    if (savedIp.endsWith('/')) {
      savedIp = savedIp.substring(0, savedIp.length - 1);
    }

    if (!savedIp.endsWith('/api')) {
      savedIp = '$savedIp/api';
    }

    return savedIp;
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<String> getServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('server_ip') ?? defaultServerIp;
  }

  static Future<void> setServerIp(String newIp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp.trim());
  }

  // --- 1. AUTHENTICATION & USERS ---
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    try {
      final baseUrl = await getBaseUrl();
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['token'] ?? '');
        await prefs.setString('username', data['user']['username'] ?? '');
        await prefs.setString('user_role', data['user']['role'] ?? '');
        await prefs.setInt('user_id', data['user']['id'] ?? 1);

        return {'success': true, 'user': data['user']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Λανθασμένα στοιχεία σύνδεσης.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον Server.'};
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('username');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
  }

  static Future<bool> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/change-password'),
            headers: headers,
            body: jsonEncode({
              'userId': userId,
              'oldPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getAllUsers({String? role}) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final roleQuery = (role != null && role.isNotEmpty)
          ? '?role=${Uri.encodeComponent(role)}'
          : '';
      final response = await http
          .get(Uri.parse('$baseUrl/auth/users$roleQuery'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/auth/users'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'username': username,
          'password': password,
          'role': role,
        }),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data is Map
              ? (data['message'] ?? 'Ο λογαριασμός δημιουργήθηκε.')
              : 'Ο λογαριασμός δημιουργήθηκε.',
          'user': data is Map ? data['user'] ?? data : null,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία δημιουργίας.')
            : 'Αποτυχία δημιουργίας.',
      };
    } catch (e) {
      print('❌ Σφάλμα registerUser: $e');
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον server.'};
    }
  }

  static Future<Map<String, dynamic>> updateUser({
    required int userId,
    required String name,
    required String username,
    String? password,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final body = <String, dynamic>{
        'name': name,
        'username': username,
      };
      if (password != null && password.trim().isNotEmpty) {
        body['password'] = password.trim();
      }

      final response = await http.put(
        Uri.parse('$baseUrl/auth/users/$userId'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data is Map
              ? (data['message'] ?? 'Ενημερώθηκε.')
              : 'Ενημερώθηκε.',
          'user': data is Map ? data['user'] : null,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία ενημέρωσης.')
            : 'Αποτυχία ενημέρωσης.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον server.'};
    }
  }

  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/users/$userId'),
        headers: headers,
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data is Map
              ? (data['message'] ?? 'Διαγράφηκε.')
              : 'Διαγράφηκε.',
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία διαγραφής.')
            : 'Αποτυχία διαγραφής.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον server.'};
    }
  }

  /// Διαγραφή όλων των εκπαιδευτικών — παραμένουν μόνο οι admin.
  static Future<Map<String, dynamic>> deleteAllTeachers() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/auth/users/delete-all-teachers'),
        headers: headers,
        body: jsonEncode({}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data is Map
              ? (data['message'] ?? 'Ολοκληρώθηκε.')
              : 'Ολοκληρώθηκε.',
          'deleted': data is Map ? data['deleted'] : null,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία διαγραφής.')
            : 'Αποτυχία διαγραφής.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον server.'};
    }
  }

  // --- 2. SCHOOL & CLASSES ---
  static Future<List<dynamic>> getClasses([
    String currentHour = '1η ώρα',
  ]) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/school/classes?currentHour=${Uri.encodeComponent(currentHour)}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> insertClass(String className) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/school/classes'),
            headers: headers,
            body: jsonEncode({'name': className}),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteClass(int id) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .delete(Uri.parse('$baseUrl/school/classes/$id'), headers: headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> deleteAllClasses() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/school/classes/delete-all'),
            headers: headers,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 15));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': data['success'] == true,
          'message': data['message'] ?? 'Ολοκληρώθηκε.',
          'deleted': data['deleted'] ?? 0,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία διαγραφής τμημάτων.')
            : 'Αποτυχία διαγραφής τμημάτων.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα διαγραφής τμημάτων: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> lockClass(
    String className,
    String currentHour,
  ) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final prefs = await SharedPreferences.getInstance();

      final response = await http
          .post(
            Uri.parse('$baseUrl/school/lock-class'),
            headers: headers,
            body: jsonEncode({
              'className': className,
              'currentHour': currentHour,
              'userId': prefs.getInt('user_id') ?? 1,
              'userName': prefs.getString('username') ?? 'Εκπαιδευτικός',
            }),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα δικτύου κατά τη δέσμευση'};
    }
  }

  static Future<Map<String, dynamic>> unlockClass(
    String className, {
    String? currentHour,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final body = <String, dynamic>{'className': className};
      if (currentHour != null && currentHour.isNotEmpty) {
        body['currentHour'] = currentHour;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/school/unlock-class'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};
      return {
        'success': response.statusCode == 200,
        'message': data is Map
            ? (data['message'] ?? '')
            : '',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα δικτύου κατά την αποδέσμευση',
      };
    }
  }

  // --- 3. STUDENTS ---
  static Future<List<dynamic>> getStudentsByClass(int classId) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/school/students/class/$classId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> insertStudent(
    String name,
    String email,
    int classId,
  ) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/school/students'),
        headers: headers,
        body: jsonEncode({'name': name, 'email': email, 'classId': classId}),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('❌ Σφάλμα insertStudent: $e');
      return false;
    }
  }

  static Future<bool> updateStudent(int id, String name, String email) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();

      final response = await http.put(
        Uri.parse('$baseUrl/school/students/$id'),
        headers: headers,
        body: jsonEncode({'name': name, 'email': email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteStudent(int id) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();

      final response = await http.delete(
        Uri.parse('$baseUrl/school/students/$id'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> uploadStudentsExcel({
    String? filePath,
    List<int>? bytes,
    String filename = 'students.xlsx',
    required int classId,
  }) async {
    try {
      if ((filePath == null || filePath.isEmpty) &&
          (bytes == null || bytes.isEmpty)) {
        return {
          'success': false,
          'message': 'Δεν επιλέχθηκε αρχείο (κενό path/bytes).',
        };
      }

      final baseUrl = await getBaseUrl();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/school/students/import-excel'),
      );

      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['classId'] = classId.toString();
      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', filePath!));
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
      );
      final response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);

      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Ολοκληρώθηκε η εισαγωγή.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα κατά την αποστολή του αρχείου στον Server: $e',
      };
    }
  }

  /// Excel αναθέσεων: στήλη A ονοματεπώνυμο, στήλη B τμήματα.
  /// Δημιουργεί λογαριασμούς (όπως import teachers) + αποθηκεύει αναθέσεις.
  static Future<Map<String, dynamic>> uploadTeacherAssignmentsExcel({
    String? filePath,
    List<int>? bytes,
    String filename = 'assignments.xlsx',
  }) async {
    try {
      if ((filePath == null || filePath.isEmpty) &&
          (bytes == null || bytes.isEmpty)) {
        return {
          'success': false,
          'message': 'Δεν επιλέχθηκε αρχείο (κενό path/bytes).',
        };
      }

      final baseUrl = await getBaseUrl();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/users/import-assignments-excel'),
      );

      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', filePath!));
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Ολοκληρώθηκε η εισαγωγή.',
          'count': data['count'] ?? 0,
          'createdCount': data['createdCount'] ?? 0,
          'reusedCount': data['reusedCount'] ?? 0,
          'credentials': data['credentials'] ?? [],
          'assignments': data['assignments'] ?? [],
          'skipped': data['skipped'] ?? [],
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία εισαγωγής αναθέσεων.')
            : 'Αποτυχία εισαγωγής αναθέσεων.',
        'skipped': data is Map ? (data['skipped'] ?? []) : [],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα κατά την αποστολή του αρχείου στον Server: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> getTeacherAssignments() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/school/teacher-assignments'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200 && data is Map) {
        return {
          'success': true,
          'assignments': data['assignments'] ?? [],
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία φόρτωσης αναθέσεων.')
            : 'Αποτυχία φόρτωσης αναθέσεων.',
        'assignments': [],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα φόρτωσης αναθέσεων: $e',
        'assignments': [],
      };
    }
  }

  static Future<Map<String, dynamic>> clearTeacherAssignments() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/school/teacher-assignments'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Οι αναθέσεις διαγράφηκαν.',
          'deleted': data['deleted'] ?? 0,
        };
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία διαγραφής.')
            : 'Αποτυχία διαγραφής.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα διαγραφής αναθέσεων: $e',
      };
    }
  }

  /// Excel εκπαιδευτικών: στήλη A επώνυμο, στήλη B όνομα → username/password.
  /// Στο Web χρησιμοποίησε [bytes] (το path είναι συχνά null).
  static Future<Map<String, dynamic>> uploadTeachersExcel({
    String? filePath,
    List<int>? bytes,
    String filename = 'teachers.xlsx',
  }) async {
    try {
      if ((filePath == null || filePath.isEmpty) &&
          (bytes == null || bytes.isEmpty)) {
        return {
          'success': false,
          'message': 'Δεν επιλέχθηκε αρχείο (κενό path/bytes).',
        };
      }

      final baseUrl = await getBaseUrl();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/auth/users/import-excel'),
      );

      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', filePath!));
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Ολοκληρώθηκε η εισαγωγή.',
          'count': data['count'] ?? 0,
          'credentials': data['credentials'] ?? [],
          'skipped': data['skipped'] ?? [],
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Αποτυχία εισαγωγής.')
            : 'Αποτυχία εισαγωγής.',
        'skipped': data is Map ? (data['skipped'] ?? []) : [],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Σφάλμα κατά την αποστολή του αρχείου στον Server: $e',
      };
    }
  }

  // --- 4. ATTENDANCE & REPORTS ---
  /// Υπάρχουσες καταχωρίσεις απουσιών για τμήμα/ώρα (μετά την υποβολή).
  static Future<Map<String, dynamic>> getAttendanceRecords({
    required String className,
    required String period,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/attendance/records?className=${Uri.encodeComponent(className)}&period=${Uri.encodeComponent(period)}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('⚠️ Σφάλμα λήψης attendance records: $e');
    }
    return {};
  }

  /// Καταχώριση μόνο ωριαίων απομακρύνσεων σε ήδη υποβληθέν τμήμα.
  static Future<Map<String, dynamic>> submitHourlyRemovals({
    required String className,
    required String period,
    required List<int> studentIds,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/attendance/hourly-removal'),
            headers: headers,
            body: jsonEncode({
              'className': className,
              'period': period,
              'studentIds': studentIds,
            }),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && (data['success'] ?? false),
        'message': data['message'] ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Αποτυχία καταχώρισης ωριαίων απομακρύνσεων.',
      };
    }
  }

  static Future<Map<String, dynamic>> submitAttendance({
    required String className,
    required String period,
    required List<Map<String, dynamic>> absences,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();

      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role') ?? 'teacher';
      final teacherId = prefs.getInt('user_id') ?? 1;

      final response = await http
          .post(
            Uri.parse('$baseUrl/attendance/submit'),
            headers: headers,
            body: jsonEncode({
              'className': className,
              'period': period,
              'absences': absences,
              'userRole': userRole,
              'teacherId': teacherId,
            }),
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Αποτυχία υποβολής απουσιών.'};
    }
  }

  static Future<List<String>> getSubmittedClassNames(
    String date,
    String schoolHour,
  ) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/attendance/submitted?date=${Uri.encodeComponent(date)}&schoolHour=${Uri.encodeComponent(schoolHour)}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => item.toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> getReports({
    required String startDate,
    required String endDate,
    String teacherIds = '',
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/reports/logs?startDate=$startDate&endDate=$endDate&teacherIds=$teacherIds',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- 5. SETTINGS & ADMIN ---
  static Future<Map<String, String>> getSmtpSettings() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/settings/smtp'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'smtp_email': data['smtp_email'] ?? '',
          'smtp_password': data['smtp_password'] ?? '',
        };
      }
    } catch (e) {
      print('❌ Σφάλμα κατά τη λήψη ρυθμίσεων SMTP: $e');
    }
    return {'smtp_email': '', 'smtp_password': ''};
  }

  static Future<bool> saveSmtpSettings(String email, String password) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/settings/smtp'),
            headers: headers,
            body: jsonEncode({'smtp_email': email, 'smtp_password': password}),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Σφάλμα κατά την αποθήκευση ρυθμίσεων SMTP: $e');
      return false;
    }
  }

  static Future<bool> sendTestEmail(String recipientEmail) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/settings/send-test-email'),
            headers: headers,
            body: jsonEncode({'recipientEmail': recipientEmail}),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> getDailySummary() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();

      final response = await http
          .get(Uri.parse('$baseUrl/attendance/daily-summary'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List;
      }
      return [];
    } catch (e) {
      print('❌ Σφάλμα κατά τη λήψη συγκεντρωτικής αναφοράς: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> resetDatabase({
    required int adminId,
    required String password,
  }) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/admin/reset-database'),
            headers: headers,
            body: jsonEncode({'adminId': adminId, 'password': password}),
          )
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && (data['success'] ?? false),
        'message': data['message'] ?? 'Σφάλμα κατά τον καθαρισμό.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Σφάλμα σύνδεσης με τον server.'};
    }
  }
  // --- SCHEDULE & TEST MODE SETTINGS ---

  /// Λήψη των ρυθμίσεων ωραρίου από το Backend
  static Future<Map<String, dynamic>> getScheduleSettings() async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/settings/schedule'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('⚠️ Σφάλμα λήψης ρυθμίσεων ωραρίου: $e');
    }
    return {};
  }

  /// Αποθήκευση ρυθμίσεων ωραρίου & Test Mode
  static Future<bool> saveScheduleSettings(
    Map<String, dynamic> settings,
  ) async {
    try {
      final baseUrl = await getBaseUrl();
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/settings/schedule'),
            headers: headers,
            body: jsonEncode(settings),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ Σφάλμα αποθήκευσης ρυθμίσεων ωραρίου: $e');
      return false;
    }
  }
}
