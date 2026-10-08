import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'admin_reports_page.dart';

class AdminManagementPage extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const AdminManagementPage({super.key, this.currentUser});

  @override
  State<AdminManagementPage> createState() => _AdminManagementPageState();
}

class _AdminManagementPageState extends State<AdminManagementPage> {
  final _classNameController = TextEditingController();
  final _studentNameController = TextEditingController();
  final _studentEmailController = TextEditingController();
  final _userNameController = TextEditingController();
  final _userUsernameController = TextEditingController();
  final _userPasswordController = TextEditingController();

  List<Map<String, dynamic>> _classList = [];
  List<dynamic> _studentsInSelectedClass = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _loadingTeachers = false;
  int? _selectedClassId;
  bool _hasSearched = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadTeachers();
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _studentNameController.dispose();
    _studentEmailController.dispose();
    _userNameController.dispose();
    _userUsernameController.dispose();
    _userPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await ApiService.getClasses('1η ώρα');
      if (mounted) {
        setState(() {
          _classList = classes
              .map((c) => Map<String, dynamic>.from(c))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("❌ Σφάλμα κατά τη φόρτωση τμημάτων: $e");
    }
  }

  Future<void> _loadStudentsForClass() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ επιλέξτε πρώτα ένα τμήμα.')),
      );
      return;
    }

    final students = await ApiService.getStudentsByClass(_selectedClassId!);

    if (mounted) {
      setState(() {
        _studentsInSelectedClass = students;
        _hasSearched = true;
      });
    }
  }

  // ----------------------------------------------------
  // ΕΙΣΑΓΩΓΗ ΜΑΘΗΤΩΝ ΑΠΟ EXCEL (Αποστολή στον Server)
  // ----------------------------------------------------
  Future<void> _importStudentsFromExcel() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ επιλέξτε πρώτα ένα τμήμα.')),
      );
      return;
    }

    try {
      final pickerResult = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (pickerResult.isEmpty) {
        return;
      }

      final String? filePath = pickerResult.single.path;
      if (filePath == null) return;

      setState(() => _isImporting = true);

      final result = await ApiService.uploadStudentsExcel(
        filePath: filePath,
        classId: _selectedClassId!,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _loadStudentsForClass();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Επιτυχής εισαγωγή!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Αποτυχία εισαγωγής.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Σφάλμα κατά την επιλογή αρχείου: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // ----------------------------------------------------
  // ΕΠΕΞΕΡΓΑΣΙΑ ΜΑΘΗΤΗ (EDIT)
  // ----------------------------------------------------
  Future<void> _editStudent(Map<String, dynamic> student) async {
    final editNameController = TextEditingController(
      text: student['name'] ?? '',
    );
    final editEmailController = TextEditingController(
      text: student['email'] ?? '',
    );

    final bool? updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Επεξεργασία Μαθητή'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editNameController,
                decoration: const InputDecoration(
                  labelText: 'Ονοματεπώνυμο',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email Κηδεμόνα',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ακύρωση'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        );
      },
    );

    if (updated == true) {
      final newName = editNameController.text.trim();
      final newEmail = editEmailController.text.trim();

      if (newName.isEmpty) return;

      final success = await ApiService.updateStudent(
        student['id'] as int,
        newName,
        newEmail,
      );

      if (!mounted) return;

      if (success) {
        await _loadStudentsForClass();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Τα στοιχεία του μαθητή ενημερώθηκαν!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Σφάλμα κατά την ενημέρωση του μαθητή.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Διάλογος Επιβεβαίωσης & Καθαρισμού Βάσης Δεδομένων
  Future<void> _showResetDatabaseDialog() async {
    final bool? confirmFirst = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Προσοχή! Καθαρισμός'),
          ],
        ),
        content: const Text(
          'Είστε σίγουροι ότι θέλετε να διαγράψετε ΟΛΑ τα δεδομένα;\n\nΗ ενέργεια αυτή είναι μόνιμη και δεν αναιρείται!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ακύρωση'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Ναι, Συνέχεια',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmFirst != true) return;

    final passwordController = TextEditingController();
    if (!mounted) return;

    final bool? confirmSecond = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Επιβεβαίωση Κωδικού Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Πληκτρολογήστε τον κωδικό πρόσβασής σας για να προχωρήσει ο μηδενισμός:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Κωδικός Πρόσβασης',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ακύρωση'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Εκτέλεση Καθαρισμού',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmSecond == true && passwordController.text.isNotEmpty) {
      if (!mounted) return;
      final result = await ApiService.resetDatabase(
        adminId: widget.currentUser?['id'] ?? 1,
        password: passwordController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? ''),
          backgroundColor: result['success'] == true
              ? Colors.green
              : Colors.red,
        ),
      );

      if (result['success'] == true) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  // 1. Προσθήκη & Διαγραφή Τμήματος
  Future<void> _addClass() async {
    final name = _classNameController.text.trim();
    if (name.isEmpty) return;

    final success = await ApiService.insertClass(name);
    if (success) {
      _classNameController.clear();
      await _loadClasses(); // 👉 Άμεση ανανέωση της λίστας
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Το τμήμα "$name" προστέθηκε!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Αποτυχία προσθήκης τμήματος.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteClass(int classId, String className) async {
    final success = await ApiService.deleteClass(classId);
    if (success) {
      if (_selectedClassId == classId) {
        _selectedClassId = null;
        _studentsInSelectedClass.clear();
        _hasSearched = false;
      }
      await _loadClasses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Το τμήμα "$className" διαγράφηκε.')),
      );
    }
  }

  // 2. Προσθήκη Μεμονωμένου Μαθητή
  Future<void> _addStudent() async {
    final name = _studentNameController.text.trim();
    final email = _studentEmailController.text.trim();

    if (name.isEmpty || _selectedClassId == null) return;

    final success = await ApiService.insertStudent(
      name,
      email,
      _selectedClassId!,
    );

    if (!mounted) return;

    if (success) {
      _studentNameController.clear();
      _studentEmailController.clear();
      await _loadStudentsForClass();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ο μαθητής "$name" προστέθηκε!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Σφάλμα κατά την προσθήκη μαθητή.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadTeachers() async {
    setState(() => _loadingTeachers = true);
    try {
      final users = await ApiService.getAllUsers(role: 'teacher');
      if (!mounted) return;
      setState(() {
        _teachers = users
            .map((u) => Map<String, dynamic>.from(u as Map))
            .toList();
        _loadingTeachers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTeachers = false);
      debugPrint('❌ Σφάλμα φόρτωσης εκπαιδευτικών: $e');
    }
  }

  // 3. Προσθήκη Εκπαιδευτικού
  Future<void> _addUser() async {
    final name = _userNameController.text.trim();
    final username = _userUsernameController.text.trim().toLowerCase();
    final password = _userPasswordController.text.trim();

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ συμπληρώστε όλα τα πεδία.')),
      );
      return;
    }

    final result = await ApiService.registerUser(
      name: name,
      username: username,
      password: password,
      role: 'teacher',
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _userNameController.clear();
      _userUsernameController.clear();
      _userPasswordController.clear();
      await _loadTeachers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Ο εκπαιδευτικός "$name" δημιουργήθηκε!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Αποτυχία δημιουργίας εκπαιδευτικού.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editTeacher(Map<String, dynamic> teacher) async {
    final id = teacher['id'] is int
        ? teacher['id'] as int
        : int.tryParse('${teacher['id']}') ?? 0;
    if (id == 0) return;

    final nameController = TextEditingController(
      text: teacher['name']?.toString() ?? '',
    );
    final usernameController = TextEditingController(
      text: teacher['username']?.toString() ?? '',
    );
    final passwordController = TextEditingController();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Επεξεργασία Εκπαιδευτικού'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ονοματεπώνυμο',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Νέος κωδικός (προαιρετικά)',
                    hintText: 'Άδειο = χωρίς αλλαγή',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ακύρωση'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      nameController.dispose();
      usernameController.dispose();
      passwordController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final username = usernameController.text.trim().toLowerCase();
    final password = passwordController.text.trim();
    nameController.dispose();
    usernameController.dispose();
    passwordController.dispose();

    if (name.isEmpty || username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Όνομα και username είναι υποχρεωτικά.')),
      );
      return;
    }

    final result = await ApiService.updateUser(
      userId: id,
      name: name,
      username: username,
      password: password.isEmpty ? null : password,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? ''),
        backgroundColor:
            result['success'] == true ? Colors.green : Colors.red,
      ),
    );
    if (result['success'] == true) {
      await _loadTeachers();
    }
  }

  Future<void> _deleteTeacher(Map<String, dynamic> teacher) async {
    final id = teacher['id'] is int
        ? teacher['id'] as int
        : int.tryParse('${teacher['id']}') ?? 0;
    final name = teacher['name']?.toString() ?? '';
    if (id == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Διαγραφή Εκπαιδευτικού'),
        content: Text(
          'Θέλετε να διαγράψετε τον/την "$name";\n\n'
          'Θα διαγραφούν και οι σχετικές καταχωρίσεις απουσιών που υπέβαλε.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ακύρωση'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Διαγραφή',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await ApiService.deleteUser(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message'] ?? ''),
        backgroundColor:
            result['success'] == true ? Colors.green : Colors.red,
      ),
    );
    if (result['success'] == true) {
      await _loadTeachers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Διαχείριση Δεδομένων'),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: 'Αναφορές & Στατιστικά',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminReportsPage(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Καθαρισμός Όλων των Δεδομένων',
              onPressed: _showResetDatabaseDialog,
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.class_), text: 'Τμήματα'),
              Tab(icon: Icon(Icons.person_add), text: 'Μαθητές'),
              Tab(icon: Icon(Icons.badge), text: 'Εκπαιδευτικοί'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Τμήματα
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _classNameController,
                          decoration: const InputDecoration(
                            labelText: 'Όνομα Νέου Τμήματος (π.χ. Α1)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _addClass,
                        icon: const Icon(Icons.add),
                        label: const Text('Προσθήκη'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Υπάρχοντα Τμήματα',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _classList.isEmpty
                        ? const Center(
                            child: Text('Δεν έχουν καταχωρηθεί τμήματα.'),
                          )
                        : ListView.builder(
                            itemCount: _classList.length,
                            itemBuilder: (context, index) {
                              final c = _classList[index];
                              return Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.class_,
                                    color: Colors.green,
                                  ),
                                  title: Text(
                                    c['name'] as String? ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteClass(
                                      c['id'] as int? ?? 0,
                                      c['name'] as String? ?? '',
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // TAB 2: Μαθητές
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedClassId,
                          decoration: const InputDecoration(
                            labelText: 'Επιλογή Τμήματος',
                            border: OutlineInputBorder(),
                          ),
                          items: _classList.map((c) {
                            return DropdownMenuItem<int>(
                              value: c['id'] as int?,
                              child: Text(c['name'] as String? ?? ''),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedClassId = val;
                              _hasSearched = true;
                            });
                            if (val != null) {
                              _loadStudentsForClass();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _loadStudentsForClass,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                        ),
                        icon: const Icon(Icons.search),
                        label: const Text('Προβολή'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (!_hasSearched)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'Επιλέξτε ένα τμήμα για να εμφανιστούν οι μαθητές του.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Μαθητές Τμήματος (${_studentsInSelectedClass.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isImporting
                                  ? null
                                  : _importStudentsFromExcel,
                              icon: _isImporting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                _isImporting ? 'Εισαγωγή...' : 'Excel',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.person_add,
                                color: Colors.green,
                              ),
                              tooltip: 'Χειροκίνητη Προσθήκη',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: const Text('Προσθήκη Μαθητή'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: _studentNameController,
                                            decoration: const InputDecoration(
                                              labelText: 'Ονοματεπώνυμο',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _studentEmailController,
                                            decoration: const InputDecoration(
                                              labelText: 'Email Κηδεμόνα',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Ακύρωση'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _addStudent();
                                          },
                                          child: const Text('Προσθήκη'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Expanded(
                      child: _studentsInSelectedClass.isEmpty
                          ? const Center(
                              child: Text(
                                'Δεν υπάρχουν καταχωρημένοι μαθητές στο τμήμα.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _studentsInSelectedClass.length,
                              itemBuilder: (context, index) {
                                final student = _studentsInSelectedClass[index];
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.green[100],
                                      child: Text('${index + 1}'),
                                    ),
                                    title: Text(
                                      student['name'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      student['email'] ?? 'Χωρίς email',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          tooltip: 'Επεξεργασία',
                                          onPressed: () =>
                                              _editStudent(student),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          tooltip: 'Διαγραφή',
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Διαγραφή Μαθητή',
                                                ),
                                                content: Text(
                                                  'Θέλετε να διαγράψετε τον/την ${student['name']};',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text(
                                                      'Ακύρωση',
                                                    ),
                                                  ),
                                                  ElevatedButton(
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Διαγραφή',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              final ok =
                                                  await ApiService.deleteStudent(
                                                    student['id'],
                                                  );
                                              if (ok) {
                                                _loadStudentsForClass();
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),

            // TAB 3: Εκπαιδευτικοί
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _userNameController,
                    decoration: const InputDecoration(
                      labelText: 'Ονοματεπώνυμο Εκπαιδευτικού',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _userUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username (Μικρά λατινικά)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _userPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Κωδικός πρόσβασης',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _addUser,
                      icon: const Icon(Icons.how_to_reg),
                      label: const Text('Δημιουργία Λογαριασμού'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Εγγεγραμμένοι Εκπαιδευτικοί',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ανανέωση',
                        onPressed: _loadingTeachers ? null : _loadTeachers,
                        icon: _loadingTeachers
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loadingTeachers && _teachers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _teachers.isEmpty
                        ? const Center(
                            child: Text(
                              'Δεν υπάρχουν εγγεγραμμένοι εκπαιδευτικοί.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _teachers.length,
                            itemBuilder: (context, index) {
                              final t = _teachers[index];
                              final name = t['name']?.toString() ?? '';
                              final username = t['username']?.toString() ?? '';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green.shade100,
                                    child: Icon(
                                      Icons.badge,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text('@$username'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Επεξεργασία',
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () => _editTeacher(t),
                                      ),
                                      IconButton(
                                        tooltip: 'Διαγραφή',
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => _deleteTeacher(t),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
