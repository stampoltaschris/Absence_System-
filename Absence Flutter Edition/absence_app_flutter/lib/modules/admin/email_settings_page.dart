import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class EmailSettingsPage extends StatefulWidget {
  const EmailSettingsPage({super.key});

  @override
  State<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<EmailSettingsPage> {
  final _smtpEmailController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _testEmailController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSmtpSettings();
  }

  // Λήψη τρεχουσών ρυθμίσεων SMTP από τη βάση δεδομένων
  Future<void> _loadSmtpSettings() async {
    setState(() => _isLoading = true);
    final settings =
        await ApiService.getSmtpSettings(); // Καλούμε τη μέθοδο του ApiService
    if (mounted) {
      setState(() {
        _smtpEmailController.text = settings['smtp_email'] ?? '';
        _smtpPasswordController.text = settings['smtp_password'] ?? '';
        _isLoading = false;
      });
    }
  }

  // Αποθήκευση ρυθμίσεων SMTP στη βάση δεδομένων
  Future<void> _saveSmtpSettings() async {
    final email = _smtpEmailController.text.trim();
    final password = _smtpPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Συμπληρώστε το SMTP Email και τον Κωδικό Εφαρμογής.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final success = await ApiService.saveSmtpSettings(email, password);

    setState(() => _isSaving = false);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Οι ρυθμίσεις SMTP αποθηκεύτηκαν επιτυχώς!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Αποτυχία αποθήκευσης ρυθμίσεων.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendTestEmail() async {
    final recipient = _testEmailController.text.trim();
    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Παρακαλώ εισάγετε ένα email δοκιμής.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await ApiService.sendTestEmail(recipient);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Το δοκιμαστικό email στάλθηκε επιτυχώς!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Αποτυχία αποστολής. Ελέγξτε αν τα στοιχεία SMTP είναι σωστά.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Διαχείριση & Δοκιμή Email (SMTP)'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ρυθμίσεις Διακομιστή Email (SMTP)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Εισάγετε το Gmail του σχολείου και τον Κωδικό Εφαρμογής (App Password) για την αυτόματη αποστολή ειδοποιήσεων στους κηδεμόνες:',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Πεδίο SMTP Email
                    TextField(
                      controller: _smtpEmailController,
                      decoration: const InputDecoration(
                        labelText: 'SMTP Email (π.χ. school@gmail.com)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.mark_email_read),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Πεδίο SMTP Password
                    TextField(
                      controller: _smtpPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'App Password (16-ψήφιος κωδικός)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Κουμπί Αποθήκευσης
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveSmtpSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                        ),
                        icon: _isSaving
                            ? const SizedBox.shrink()
                            : const Icon(Icons.save, color: Colors.white),
                        label: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Αποθήκευση Ρυθμίσεων SMTP',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                    const Divider(height: 40, thickness: 1.5),

                    const Text(
                      'Δοκιμή Αποστολής Email',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Εισάγετε ένα email για να επιβεβαιώσετε ότι οι ρυθμίσεις λειτουργούν κανονικά:',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Πεδίο Email Δοκιμής
                    TextField(
                      controller: _testEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Email Παραλήπτη Δοκιμής',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.send_sharp),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Κουμπί Αποστολής Δοκιμής
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _sendTestEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                        ),
                        icon: const Icon(Icons.send, color: Colors.white),
                        label: const Text(
                          'Αποστολή Δοκιμαστικού Email',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
