import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../dashboard/dashboard_page.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  /// Παράθυρο διαλόγου για τη δυναμική αλλαγή/αποθήκευση της IP του Server
  Future<void> _showServerConfigDialog() async {
    final currentIp = await ApiService.getServerIp();
    final ipController = TextEditingController(text: currentIp);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns, color: Colors.green),
            SizedBox(width: 8),
            Text('Ρύθμιση Server IP'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Εισάγετε τη διεύθυνση IP και τη θύρα του Server στο τοπικό δίκτυο:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IP & Θύρα Server',
                hintText: 'π.χ. 192.168.1.16:5000',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ακύρωση'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newIp = ipController.text.trim();
              if (newIp.isNotEmpty) {
                await ApiService.setServerIp(newIp);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Η διεύθυνση του server ενημερώθηκε!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );
  }

  Future<void> _loginAdmin() async {
    if (_isLoading) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ συμπληρώστε όλα τα πεδία.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    print('🔘 [FLUTTER] Εκκίνηση σύνδεσης για username: $username');

    try {
      // Κλήση του Node.js Backend API
      final result = await ApiService.login(username, password);

      // 🛡️ Ασφαλής έλεγχος πριν τη χρήση του context
      if (!mounted) return;

      if (result['success'] == true) {
        final userData = result['user'];

        // Έλεγχος αν ο χρήστης είναι πράγματι admin
        if (userData != null && userData['role'] == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardPage(user: userData),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Δεν έχετε δικαιώματα διαχειριστή.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Λανθασμένα στοιχεία σύνδεσης.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stack) {
      print('❌ [FLUTTER ERROR] Σφάλμα κατά τη σύνδεση: $e');
      print(stack);

      // 🛡️️ Προσθήκη ασφαλούς ελέγχου mounted πριν την εμφάνιση του SnackBar στο catch
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Σφάλμα δικτύου/σύνδεσης: $e'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Είσοδος Διαχειριστή'),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔒 Long Press Gesture στο Icon για κρυφή αλλαγή Server IP
                    GestureDetector(
                      onLongPress: _showServerConfigDialog,
                      child: Icon(
                        Icons.admin_panel_settings,
                        size: 64,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Πάνελ Διαχειριστή',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Όνομα Χρήστη Admin',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _loginAdmin(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Κωδικός Πρόσβασης',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _loginAdmin(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isLoading ? null : _loginAdmin,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Σύνδεση Διαχειριστή',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
