import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_theme.dart';
import '../../core/school_schedule.dart';
import '../../services/api_service.dart';
import '../dashboard/dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final TextEditingController _ipController;

  bool _isLoading = false;
  bool _showThundercatsMode = false;
  bool _isPlayingAudio = false;
  String _currentServerIp = '';
  bool _obscurePassword = true;

  late final AudioPlayer _audioPlayer;
  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _audioPlayer = AudioPlayer();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    });

    _loadSavedIp();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
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

  void _activateThundercatsMode() {
    if (_showThundercatsMode) return;
    setState(() => _showThundercatsMode = true);
  }

  Future<void> _toggleAudio() async {
    try {
      if (_isPlayingAudio) {
        await _audioPlayer.stop();
        setState(() => _isPlayingAudio = false);
      } else {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('audio/Thundercats.mp3'));
        setState(() => _isPlayingAudio = true);
      }
    } catch (e) {
      debugPrint('⚠️ [AUDIO ERROR]: $e');
    }
  }

  Future<void> _deactivateThundercatsMode() async {
    if (_isPlayingAudio) {
      try {
        await _audioPlayer.stop();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _showThundercatsMode = false;
        _isPlayingAudio = false;
      });
    }
  }

  Future<void> _saveIpSettings() async {
    final newIp = _ipController.text.trim();
    if (newIp.isNotEmpty) {
      await ApiService.setServerIp(newIp);
      if (!mounted) return;
      setState(() => _currentServerIp = newIp);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Η IP ενημερώθηκε σε: $newIp'),
          backgroundColor: AppColors.primary,
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
        if (_showThundercatsMode) await _deactivateThundercatsMode();
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
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Σφάλμα σύνδεσης με τον Server: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 900;

    return Scaffold(
      body: Container(
        decoration: AppTheme.pageBackground(warmAccent: true),
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _fadeIn, curve: Curves.easeOut),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 48 : 24,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      GestureDetector(
                        onLongPress: _activateThundercatsMode,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          child: _showThundercatsMode
                              ? Column(
                                  key: const ValueKey('tc'),
                                  children: [
                                    Image.asset(
                                      'assets/images/tcatsimage.jpg',
                                      height: 100,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Sight Beyond Sight',
                                      style: GoogleFonts.sora(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.redAccent,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  key: const ValueKey('brand'),
                                  children: [
                                    Container(
                                      width: 88,
                                      height: 88,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.28),
                                            blurRadius: 24,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.school_rounded,
                                        size: 46,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    Text(
                                      'Σύστημα Απουσιών',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.sora(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Καταγραφή & ενημέρωση γονέων',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.manrope(
                                        fontSize: 15,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.availableBorder),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _showThundercatsMode
                                  ? 'THUNDERCATS HO!'
                                  : 'Σύνδεση',
                              style: GoogleFonts.sora(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _usernameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleLogin(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _showThundercatsMode
                                      ? Colors.red.shade800
                                      : AppColors.accent,
                                  foregroundColor: Colors.white,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Σύνδεση',
                                        style: GoogleFonts.manrope(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            if (_currentServerIp.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Server: $_currentServerIp',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Container(
                          margin: const EdgeInsets.only(top: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.redAccent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.bolt, color: Colors.amber),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'ThunderCats IP Config',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _toggleAudio,
                                    icon: Icon(
                                      _isPlayingAudio
                                          ? Icons.stop_circle
                                          : Icons.play_circle_fill,
                                      color: _isPlayingAudio
                                          ? Colors.redAccent
                                          : Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                              TextField(
                                controller: _ipController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'IP Server & Port',
                                  hintText: 'π.χ. localhost:5000',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  labelStyle: TextStyle(color: Colors.white70),
                                  prefixIcon: Icon(
                                    Icons.dns,
                                    color: Colors.amber,
                                  ),
                                  filled: true,
                                  fillColor: Colors.black26,
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
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
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
                        duration: const Duration(milliseconds: 350),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
