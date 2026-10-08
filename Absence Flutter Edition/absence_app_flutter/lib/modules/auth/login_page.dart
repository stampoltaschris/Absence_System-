import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../core/school_schedule.dart';
import '../../services/api_service.dart';
import '../dashboard/dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final TextEditingController _ipController;

  bool _isLoading = false;
  bool _showThundercatsMode = false; // Easter Egg state
  bool _isPlayingAudio = false; // Audio play/pause state
  String _currentServerIp = '';

  late final AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _audioPlayer = AudioPlayer();

    // Ακρόαση ολοκλήρωσης του τραγουδιού για επαναφορά του κουμπιού Play
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlayingAudio = false);
      }
    });

    _loadSavedIp();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedIp() async {
    final savedIp = await ApiService.getServerIp();
    if (mounted) {
      setState(() {
        _currentServerIp = savedIp;
        _ipController.text = savedIp;
      });
    }
  }

  /// ⚡ Ενεργοποίηση ThunderCats Mode (ΧΩΡΙΣ αυτόματο ήχο)
  void _activateThundercatsMode() {
    if (_showThundercatsMode) return;
    setState(() {
      _showThundercatsMode = true;
    });
  }

  /// 🎵 On-demand Toggle Αναπαραγωγής Ήχου
  Future<void> _toggleAudio() async {
    try {
      if (_isPlayingAudio) {
        await _audioPlayer.stop();
        setState(() => _isPlayingAudio = false);
      } else {
        await _audioPlayer.stop(); // Καθαρισμός αν έπαιζε κάτι άλλο
        await _audioPlayer.play(AssetSource('audio/Thundercats.mp3'));
        setState(() => _isPlayingAudio = true);
      }
    } catch (e) {
      debugPrint('⚠️ [AUDIO ERROR]: $e');
    }
  }

  /// 🛑 Απενεργοποίηση ThunderCats Mode & Σταμάτημα Ήχου
  Future<void> _deactivateThundercatsMode() async {
    if (_isPlayingAudio) {
      try {
        await _audioPlayer.stop();
      } catch (e) {
        debugPrint('⚠️ [AUDIO STOP ERROR]: $e');
      }
    }
    if (mounted) {
      setState(() {
        _showThundercatsMode = false;
        _isPlayingAudio = false;
      });
    }
  }

  /// 💾 Αποθήκευση Νέας Διεύθυνσης IP
  Future<void> _saveIpSettings() async {
    final newIp = _ipController.text.trim();
    if (newIp.isNotEmpty) {
      await ApiService.setServerIp(newIp);
      if (!mounted) return;
      setState(() {
        _currentServerIp = newIp;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚡ ThunderCats Ho! Η IP ενημερώθηκε σε: $newIp'),
          backgroundColor: Colors.orange.shade900,
        ),
      );
    }
    await _deactivateThundercatsMode();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Συμπληρώστε username και password.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.login(username, password);

      if (!mounted) return;

      if (result['success'] == true) {
        final user = result['user'];

        if (_showThundercatsMode) {
          await _deactivateThundercatsMode();
        }

        // Φόρτωση ωραρίου από backend ώστε το ρολόι να ακολουθεί τις ρυθμίσεις
        await SchoolSchedule.loadFromApi();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => DashboardPage(user: user)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Αποτυχία σύνδεσης.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Σφάλμα σύνδεσης με τον Server: $e'),
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
        title: Text(
          _showThundercatsMode
              ? 'THUNDERCATS HO!'
              : 'Σύνδεση στο Σύστημα Απουσιών',
        ),
        backgroundColor: _showThundercatsMode
            ? Colors.red.shade900
            : Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ----------------------------------------------------
                // 👁️ LOGO ME GESTURE DETECTOR (ThunderCats Easter Egg)
                // ----------------------------------------------------
                GestureDetector(
                  onLongPress: _activateThundercatsMode,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _showThundercatsMode
                        ? Column(
                            key: const ValueKey('thundercats_logo'),
                            children: [
                              Image.asset(
                                'assets/images/tcatsimage.jpg',
                                height: 110,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Sight Beyond Sight',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('normal_logo'),
                            children: [
                              Icon(
                                Icons.school,
                                size: 80,
                                color: Colors.blue.shade700,
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Πεδίο Username
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),

                // Πεδίο Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),

                // Κουμπί Σύνδεσης
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showThundercatsMode
                          ? Colors.red.shade900
                          : Colors.blue.shade700,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Σύνδεση',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                  ),
                ),

                // ----------------------------------------------------
                // ⚡ ΠΑΡΑΘΥΡΟ IP SETTINGS ME KΟΥΜΠΙ PLAY/STOP
                // ----------------------------------------------------
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Container(
                    margin: const EdgeInsets.only(top: 24.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt, color: Colors.amber),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'ThunderCats IP Config',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            // 🎵 Κουμπί Play / Stop Intro
                            IconButton(
                              onPressed: _toggleAudio,
                              tooltip: _isPlayingAudio
                                  ? 'Παύση Ήχου'
                                  : 'Αναπαραγωγή Intro',
                              icon: Icon(
                                _isPlayingAudio
                                    ? Icons.stop_circle
                                    : Icons.play_circle_fill,
                                color: _isPlayingAudio
                                    ? Colors.redAccent
                                    : Colors.amber,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'IP Server & Port',
                            hintText: 'π.χ. 192.168.1.16:5000',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            prefixIcon: Icon(Icons.dns, color: Colors.amber),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.redAccent),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.amber),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _deactivateThundercatsMode,
                              child: const Text(
                                'Ακύρωση',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _saveIpSettings,
                              icon: const Icon(Icons.save),
                              label: const Text('Αποθήκευση'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _showThundercatsMode
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
