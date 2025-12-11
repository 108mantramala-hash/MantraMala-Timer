import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:just_audio/just_audio.dart";
import "package:audio_session/audio_session.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:in_app_review/in_app_review.dart";
import "dart:math" as math;
import "dart:async";
import "package:url_launcher/url_launcher.dart";

void main() {
  runApp(const MantraMalaApp());
}

class MantraMalaApp extends StatelessWidget {
  const MantraMalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MantraMala",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD6A54B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1C1E3A),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: Color(0xFFF8F5F0),
            fontWeight: FontWeight.bold,
            fontSize: 48,
          ),
          displayMedium: TextStyle(
            color: Color(0xFFF8F5F0),
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
          bodyLarge: TextStyle(color: Color(0xFFF8F5F0), fontSize: 18),
          bodyMedium: TextStyle(color: Color(0xFFA0A0A8), fontSize: 16),
        ),
      ),
      home: const MantraMalaHome(),
    );
  }
}

class MantraMalaHome extends StatefulWidget {
  const MantraMalaHome({super.key});

  @override
  State<MantraMalaHome> createState() => _MantraMalaHomeState();
}

class _MantraMalaHomeState extends State<MantraMalaHome> {
  int _currentCount = 0;
  int _targetCount = 108;
  bool _isCompleted = false;
  late AudioPlayer _tapPlayer;
  late AudioPlayer _bellPlayer;
  late SharedPreferences _prefs;
  Timer? _completionSoundTimer;
  Timer? _completionSoundStopTimer;
  int _totalMantras = 0; // All-time mantra count
  double _volume = 0.8; // 0.0 - 1.0
  bool _soundEnabled = true;
  bool _hapticsEnabled = true;
  bool _tapAnywhere = false;
  // Disable tap sound globally (tab.mp3)
  bool _tapClickSoundEnabled = false;
  int _defaultTarget = 108;
  DateTime? _firstLaunchDate;
  bool _hasAskedForReview = false;

  // Timer-based counting state
  bool _isTimerRunning = false;
  Timer? _countingTimer;
  double _intervalSeconds = 2.0; // Default 2 seconds per mantra

  final List<int> presets = [27, 54, 108];

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    _loadData();
  }

  @override
  void dispose() {
    _completionSoundTimer?.cancel();
    _completionSoundStopTimer?.cancel();
    _countingTimer?.cancel();
    _tapPlayer.dispose();
    _bellPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializeAudio() async {
    // Configure audio session to prevent Live Caption notifications
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        ),
      );
    } catch (_) {
      // Audio session configuration failed, continue anyway
    }

    // Initialize players and attempt to preload assets if present
    _tapPlayer = AudioPlayer();
    _bellPlayer = AudioPlayer();
    try {
      // Set audio source; if assets are missing/invalid, fallback will be used
      await _tapPlayer
          .setAudioSource(AudioSource.asset("assets/sounds/tab.mp3"))
          .catchError((_) => Duration.zero);
      await _bellPlayer
          .setAudioSource(AudioSource.asset("assets/sounds/Bell.mp3"))
          .catchError((_) => Duration.zero);
      await _tapPlayer.setVolume(_volume);
      await _bellPlayer.setVolume(_volume);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();

    // Review tracking - initialize first launch date
    final firstLaunchMs = _prefs.getInt("firstLaunchDate");
    if (firstLaunchMs == null) {
      _firstLaunchDate = DateTime.now();
      await _prefs.setInt(
        "firstLaunchDate",
        _firstLaunchDate!.millisecondsSinceEpoch,
      );
    } else {
      _firstLaunchDate = DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
    }

    setState(() {
      _currentCount = _prefs.getInt("currentCount") ?? 0;
      _targetCount = _prefs.getInt("targetCount") ?? 108;
      _isCompleted = _prefs.getBool("isCompleted") ?? false;
      _totalMantras = _prefs.getInt("totalMantras") ?? 0;
      _volume = _prefs.getDouble("volume") ?? 0.8;
      _soundEnabled = _prefs.getBool("soundEnabled") ?? true;
      _hapticsEnabled = _prefs.getBool("hapticsEnabled") ?? true;
      _tapAnywhere = _prefs.getBool("tapAnywhere") ?? false;
      _defaultTarget = _prefs.getInt("defaultTarget") ?? 108;
      _hasAskedForReview = _prefs.getBool("hasAskedForReview") ?? false;
      _intervalSeconds = _prefs.getDouble("intervalSeconds") ?? 2.0;
      // Set target to default (108) on first install or when count is zero
      _targetCount = _prefs.getInt("targetCount") ?? 108;
      if (_currentCount == 0) {
        _targetCount = _defaultTarget;
      }
    });
    try {
      await _tapPlayer.setVolume(_volume);
      await _bellPlayer.setVolume(_volume);
    } catch (_) {}
  }

  Future<void> _saveData() async {
    await _prefs.setInt("currentCount", _currentCount);
    await _prefs.setInt("targetCount", _targetCount);
    await _prefs.setBool("isCompleted", _isCompleted);
    await _prefs.setInt("totalMantras", _totalMantras);
    await _prefs.setDouble("volume", _volume);
    await _prefs.setBool("soundEnabled", _soundEnabled);
    await _prefs.setBool("hapticsEnabled", _hapticsEnabled);
    await _prefs.setBool("tapAnywhere", _tapAnywhere);
    await _prefs.setInt("defaultTarget", _defaultTarget);
    await _prefs.setBool("hasAskedForReview", _hasAskedForReview);
    await _prefs.setDouble("intervalSeconds", _intervalSeconds);
  }

  Future<void> _checkAndRequestReview() async {
    // Only ask once
    if (_hasAskedForReview) return;

    // Check if 3 days have passed since first launch
    if (_firstLaunchDate == null) return;
    final daysSinceInstall = DateTime.now()
        .difference(_firstLaunchDate!)
        .inDays;
    if (daysSinceInstall < 3) return;

    // Check if user has counted at least 10 mantras
    if (_totalMantras < 10) return;

    try {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        _hasAskedForReview = true;
        await _saveData();
      }
    } catch (e) {
      // Silently fail - review request is not critical
    }
  }

  Future<void> _playTapSound() async {
    // Respect global disable for tap sound
    if (!_soundEnabled || !_tapClickSoundEnabled) return;
    // Prefer just_audio if source set; otherwise system click
    try {
      if (_tapPlayer.audioSource != null) {
        await _tapPlayer.seek(Duration.zero);
        await _tapPlayer.play();
      } else {
        // Intentionally disabled: no system click fallback
      }
    } catch (_) {
      // Intentionally disabled: no system click fallback
    }
  }

  void _stopCompletionSoundLoop() {
    _completionSoundTimer?.cancel();
    _completionSoundStopTimer?.cancel();
    // Re-disable tap click sound after completion window
    _tapClickSoundEnabled = false;
  }

  Future<void> _playCompletionSound() async {
    if (!_soundEnabled) return;
    try {
      // Stop the player first to ensure clean state
      await _bellPlayer.stop();
      // Seek to beginning
      await _bellPlayer.seek(Duration.zero);
      // Play the bell sound
      await _bellPlayer.play();
    } catch (e) {
      // If playing fails, try to reload and play
      try {
        await _bellPlayer.stop();
        await _bellPlayer.setAudioSource(
          AudioSource.asset("assets/sounds/Bell.mp3"),
        );
        await _bellPlayer.setVolume(_volume);
        await _bellPlayer.seek(Duration.zero);
        await _bellPlayer.play();
      } catch (_) {
        // Silently fail if sound playback fails
      }
    }
  }

  void _setTarget(int target) {
    setState(() {
      _targetCount = target;
      _currentCount = 0;
      _isCompleted = false;
    });
    _saveData();
  }

  void _incrementCounter() {
    if (!_isCompleted) {
      final bool willComplete = (_currentCount + 1) >= _targetCount;

      setState(() {
        _currentCount++;
        _totalMantras++;
        if (_currentCount >= _targetCount) {
          _isCompleted = true;
        }
      });

      // Show completion sheet and play sound AFTER setState completes
      if (willComplete) {
        // Use WidgetsBinding to ensure the UI is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showCompletionSheet();
            _playCompletionSound();
          }
        });
      }

      // Haptic feedback and sound/vibration
      if (willComplete) {
        // Strong vibration pattern on completion
        if (_hapticsEnabled) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && _hapticsEnabled) HapticFeedback.mediumImpact();
          });
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _hapticsEnabled) HapticFeedback.mediumImpact();
          });
        }
      } else {
        // Light tap haptic feedback on each count
        if (_hapticsEnabled) HapticFeedback.lightImpact();
        _playTapSound();
      }

      _saveData();

      // Check if we should request a review
      _checkAndRequestReview();
    }
  }

  void _resetCounter() {
    _stopCompletionSoundLoop();
    _stopTimer();
    setState(() {
      _currentCount = 0;
      _isCompleted = false;
      _isTimerRunning = false;
    });
    _saveData();
  }

  void _startTimer() {
    if (_isCompleted || _isTimerRunning) return;

    setState(() {
      _isTimerRunning = true;
    });

    final duration = Duration(seconds: _intervalSeconds.round());

    _countingTimer = Timer.periodic(duration, (timer) {
      if (_isCompleted) {
        _stopTimer();
      } else {
        _incrementCounter();
      }
    });
  }

  void _pauseTimer() {
    _stopTimer();
  }

  void _stopTimer() {
    _countingTimer?.cancel();
    _countingTimer = null;
    setState(() {
      _isTimerRunning = false;
    });
  }

  void _toggleTimer() {
    if (_isCompleted) return;

    if (_isTimerRunning) {
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void _showCompletionSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2C48),
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: Color(0xFFD6A54B),
                        size: 28,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Color(0xFFD6A54B), // gold
                              Color(0xFFFFD96A), // shiny highlight
                              Color(0xFFF8F5F0), // off-white
                            ],
                            stops: [0.0, 0.7, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text(
                            "Session Complete",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontFamily: 'Montserrat',
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFFD6A54B), Color(0xFFF8F5F0)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: Text(
                      "You reached $_targetCount mantras.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFFFFD96A), Color(0xFFD6A54B)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: Text(
                      "Total mantras: $_totalMantras",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _stopCompletionSoundLoop();
                            Navigator.of(ctx).pop();
                            _resetCounter();
                          },
                          icon: const Icon(Icons.restart_alt, size: 22),
                          label: const Text(
                            "Reset",
                            style: TextStyle(fontSize: 15),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_targetCount < _defaultTarget)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _stopCompletionSoundLoop();
                              Navigator.of(ctx).pop();
                              // Increase target to next preset or +10%
                              final presetsSorted = [...presets]..sort();
                              int next = _targetCount;
                              for (final p in presetsSorted) {
                                if (p > _targetCount) {
                                  next = p;
                                  break;
                                }
                              }
                              if (next == _targetCount) {
                                next = (_targetCount * 1.1).round();
                              }
                              _setTarget(next);
                            },
                            icon: const Icon(Icons.trending_up, size: 22),
                            label: const Text(
                              "Increase",
                              style: TextStyle(fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      if (_targetCount >= _defaultTarget)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _stopCompletionSoundLoop();
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(Icons.close, size: 22),
                            label: const Text(
                              "Done",
                              style: TextStyle(fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      // Stop the loop when the sheet is closed (by any means)
      _stopCompletionSoundLoop();
    });
  }

  double _getProgressPercentage() {
    if (_targetCount == 0) return 0;
    return (_currentCount / _targetCount).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    // Global pointer listener: stop completion sound on any interaction
    return Listener(
      onPointerDown: (_) {
        _stopCompletionSoundLoop();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 80,
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        Color(0xFFD6A54B), // rich gold
                        Color(0xFFF8E16C), // shiny highlight
                        Color(0xFFB6862C), // deep gold
                      ],
                      stops: [0.0, 0.5, 1.0],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.hourglass_empty,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        Color(0xFFD6A54B),
                        Color(0xFFF8F5F0),
                        Color(0xFFD6A54B),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      'MantraMala',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Japa • Chant • Meditate',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.5,
                  color: Color(0xFFD0D0D0),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1C1E3A),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, size: 32),
              tooltip: "Settings",
              onPressed: () async {
                // Stop any completion sound loop on interaction
                if (_isCompleted) _stopCompletionSoundLoop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      volume: _volume,
                      soundEnabled: _soundEnabled,
                      hapticsEnabled: _hapticsEnabled,
                      tapAnywhere: _tapAnywhere,
                      defaultTarget: _defaultTarget,
                      intervalSeconds: _intervalSeconds,
                      onChanged: (s) async {
                        setState(() {
                          _volume = s.volume;
                          _soundEnabled = s.soundEnabled;
                          _hapticsEnabled = s.hapticsEnabled;
                          _tapAnywhere = s.tapAnywhere;
                          _defaultTarget = s.defaultTarget;
                          _intervalSeconds = s.intervalSeconds;
                          // Always update target count to reflect new default
                          _targetCount = _defaultTarget;
                        });
                        try {
                          await _tapPlayer.setVolume(_volume);
                          await _bellPlayer.setVolume(_volume);
                        } catch (_) {}
                        _saveData();
                      },
                      onResetTotalMantras: () async {
                        setState(() {
                          _totalMantras = 0;
                        });
                        await _prefs.setInt("totalMantras", 0);
                      },
                      onResetTodaysTarget: () async {
                        setState(() {
                          _currentCount = 0;
                          _isCompleted = false;
                          _targetCount = _defaultTarget;
                        });
                        await _saveData();
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: GestureDetector(
            onTap: () {
              if (_isCompleted) {
                _stopCompletionSoundLoop();
              } else if (_tapAnywhere) {
                _incrementCounter();
              }
            },
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.1,
                  vertical: screenHeight * 0.05,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildStatsBar(context, screenWidth),
                    SizedBox(height: screenHeight * 0.025),
                    _buildCircularCounter(context, screenWidth * 0.8),
                    SizedBox(height: screenHeight * 0.018),
                    _buildResetButton(context, screenWidth * 0.28),
                    SizedBox(height: screenHeight * 0.012),
                    _buildTapButton(context, screenWidth * 0.7),
                    SizedBox(height: screenHeight * 0.012),
                    _buildStatusText(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context, double screenWidth) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3C4E), Color(0xFF2A2C3E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFF1A1C2E).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF4A4C5E).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF262835).withValues(alpha: 0.8),
              const Color(0xFF1A1C2E).withValues(alpha: 0.95),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildStatItem(
                context,
                "Total Count",
                _totalMantras.toString(),
              ),
            ),
            Container(
              width: 2,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF4A4C5E).withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Expanded(
              child: _buildStatItem(context, "Target", _targetCount.toString()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: const Color(0xFF9A9CA8).withOpacity(0.7),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3A3C4E), Color(0xFF2A2C3E)],
            ),
            border: Border.all(
              color: const Color(0xFFFFD96A).withOpacity(0.22),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD96A).withOpacity(0.13),
                blurRadius: 7,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFE55C), Color(0xFFD6A54B)],
            ).createShader(bounds),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(
                    color: Color(0x40000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircularCounter(BuildContext context, double screenWidth) {
    final counterSize = screenWidth * 0.65;
    final progress = _getProgressPercentage();
    return Container(
      width: counterSize,
      height: counterSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: const Color(0xFFD6A54B).withValues(alpha: 0.15),
            blurRadius: 40,
            spreadRadius: -10,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.2,
            colors: [
              const Color(0xFF3A3C58).withValues(alpha: 0.9),
              const Color(0xFF2A2C48),
              const Color(0xFF1C1E3A),
              const Color(0xFF14162A),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
          border: Border.all(
            color: const Color(0xFF4A4C6E).withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.2),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background track with inner shadow effect
              CustomPaint(
                size: Size(counterSize, counterSize),
                painter: CircleProgressPainter(
                  progress: 1.0,
                  color: const Color(0xFF0D0E1A).withValues(alpha: 0.6),
                  strokeWidth: 12,
                ),
              ),
              // Subtle glow track
              CustomPaint(
                size: Size(counterSize, counterSize),
                painter: CircleProgressPainter(
                  progress: 1.0,
                  color: const Color(0xFF3A3C4E).withValues(alpha: 0.2),
                  strokeWidth: 11,
                ),
              ),
              // Progress arc with gradient effect
              CustomPaint(
                size: Size(counterSize, counterSize),
                painter: GradientCircleProgressPainter(
                  progress: progress,
                  strokeWidth: 12,
                ),
              ),
              // Outer glow on progress
              if (progress > 0)
                CustomPaint(
                  size: Size(counterSize, counterSize),
                  painter: CircleProgressPainter(
                    progress: progress,
                    color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
                    strokeWidth: 16,
                  ),
                ),
              // Content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFFFFFFF),
                        const Color(0xFFE8E8E8),
                      ],
                    ).createShader(bounds),
                    child: Text(
                      _currentCount.toString(),
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: Color(0x40000000),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "/ $_targetCount",
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFFA0A0A8).withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: progress >= 1.0
                            ? [
                                const Color(0xFF4CAF50).withValues(alpha: 0.3),
                                const Color(0xFF45A049).withValues(alpha: 0.2),
                              ]
                            : [
                                const Color(0xFFD6A54B).withValues(alpha: 0.2),
                                const Color(0xFFB8873D).withValues(alpha: 0.15),
                              ],
                      ),
                      border: Border.all(
                        color: progress >= 1.0
                            ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                            : const Color(0xFFD6A54B).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: progress >= 1.0
                            ? [const Color(0xFF66BB6A), const Color(0xFF4CAF50)]
                            : [
                                const Color(0xFFFFD96A),
                                const Color(0xFFD6A54B),
                              ],
                      ).createShader(bounds),
                      child: Text(
                        "${(progress * 100).toStringAsFixed(0)}%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText(BuildContext context) {
    if (_isCompleted) {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
        ).createShader(bounds),
        child: const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTapButton(BuildContext context, double screenWidth) {
    String buttonText;
    IconData buttonIcon;

    if (_isCompleted) {
      buttonText = "Completed ✓";
      buttonIcon = Icons.check_circle;
    } else if (_isTimerRunning) {
      buttonText = "Pause Timer";
      buttonIcon = Icons.pause_circle_filled;
    } else if (_currentCount > 0) {
      buttonText = "Resume Timer";
      buttonIcon = Icons.play_circle_filled;
    } else {
      buttonText = "Start Timer";
      buttonIcon = Icons.play_circle_filled;
    }

    return Column(
      children: [
        // Interval display
        if (!_isCompleted)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2A2C48).withValues(alpha: 0.8),
                    const Color(0xFF1C1E3A).withValues(alpha: 0.9),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFD6A54B).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: const Color(0xFFD6A54B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Interval: ${_intervalSeconds.toStringAsFixed(_intervalSeconds == _intervalSeconds.roundToDouble() ? 0 : 1)}s per mantra",
                    style: TextStyle(
                      color: const Color(0xFFA0A0A8).withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Main button
        Center(
          child: Container(
            width: screenWidth * 0.85,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: _isCompleted
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF3A3C4E).withValues(alpha: 0.9),
                        const Color(0xFF2A2C48).withValues(alpha: 0.9),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [
                        Color(0xFFFFE55C),
                        Color(0xFFE5B84D),
                        Color(0xFFC4934D),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: [0.0, 0.5, 1.0],
                    ),
              boxShadow: _isCompleted
                  ? [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0xFFFFD96A).withValues(alpha: 0.7),
                        blurRadius: 28,
                        spreadRadius: 3,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFE55C).withValues(alpha: 0.4),
                        blurRadius: 40,
                        spreadRadius: -8,
                        offset: const Offset(0, 0),
                      ),
                    ],
              border: _isCompleted
                  ? Border.all(color: const Color(0xFF3A3C4E), width: 1.5)
                  : Border.all(
                      color: const Color(0xFFFFF8E7).withValues(alpha: 0.5),
                      width: 2,
                    ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: _isCompleted
                    ? null
                    : LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.25),
                          Colors.white.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.6],
                      ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isCompleted ? null : _toggleTimer,
                  borderRadius: BorderRadius.circular(36),
                  splashColor: Colors.white.withValues(alpha: 0.3),
                  highlightColor: Colors.white.withValues(alpha: 0.15),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          buttonIcon,
                          size: 28,
                          color: _isCompleted
                              ? const Color(0xFFA0A0A8)
                              : const Color(0xFF1C1E3A),
                        ),
                        const SizedBox(width: 12),
                        ShaderMask(
                          shaderCallback: (bounds) => _isCompleted
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFA0A0A8),
                                    Color(0xFFA0A0A8),
                                  ],
                                ).createShader(bounds)
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF1C1E3A),
                                    Color(0xFF0A0B1A),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ).createShader(bounds),
                          child: Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Color(0x60000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                                Shadow(
                                  color: Color(0x30000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 1),
                                ),
                              ],
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
        ),
      ],
    );
  }

  Widget _buildResetButton(BuildContext context, double screenWidth) {
    return Center(
      child: Container(
        width: screenWidth * 0.5,
        height: screenWidth * 0.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment.topLeft,
            radius: 1.2,
            colors: [Color(0xFF3A3A3A), Color(0xFF1C1C1C), Color(0xFF0A0A0A)],
            stops: [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.8),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: 4,
            ),
            BoxShadow(
              color: const Color(0xFFFFD96A).withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
          ],
          border: Border.all(
            color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
            width: 2.5,
          ),
        ),
        child: Stack(
          children: [
            // Metallic rim highlight
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFFD96A).withValues(alpha: 0.2),
                      Colors.transparent,
                      const Color(0xFFFFD96A).withValues(alpha: 0.1),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Glass shine overlay
            Positioned(
              top: screenWidth * 0.05,
              left: screenWidth * 0.05,
              right: screenWidth * 0.2,
              height: screenWidth * 0.08,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(screenWidth * 0.2),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFFFFF).withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Button content
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (_isCompleted) _stopCompletionSoundLoop();
                  _resetCounter();
                },
                borderRadius: BorderRadius.circular(screenWidth / 2),
                splashColor: const Color(0xFFFFD96A).withValues(alpha: 0.2),
                highlightColor: const Color(0xFFFFD96A).withValues(alpha: 0.1),
                child: Center(
                  child: Text(
                    "RESET",
                    style: TextStyle(
                      fontSize: screenWidth * 0.055,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFFD96A),
                      letterSpacing: 2.5,
                      shadows: [
                        Shadow(
                          color: const Color(0xFFFFD96A).withValues(alpha: 0.8),
                          blurRadius: 20,
                        ),
                        Shadow(
                          color: const Color(0xFFFFD96A).withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsData {
  final double volume;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool tapAnywhere;
  final int defaultTarget;
  final double intervalSeconds;

  const SettingsData({
    required this.volume,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.tapAnywhere,
    required this.defaultTarget,
    required this.intervalSeconds,
  });
}

class SettingsPage extends StatefulWidget {
  final double volume;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool tapAnywhere;
  final int defaultTarget;
  final double intervalSeconds;
  final Future<void> Function(SettingsData) onChanged;
  final Future<void> Function() onResetTotalMantras;
  final Future<void> Function() onResetTodaysTarget;

  const SettingsPage({
    super.key,
    required this.volume,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.tapAnywhere,
    required this.defaultTarget,
    required this.intervalSeconds,
    required this.onChanged,
    required this.onResetTotalMantras,
    required this.onResetTodaysTarget,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _volume;
  late bool _soundEnabled;
  late bool _hapticsEnabled;
  late bool _tapAnywhere;
  late int _defaultTarget;
  late double _intervalSeconds;
  late FixedExtentScrollController _thousandsController;
  late FixedExtentScrollController _hundredsController;
  late FixedExtentScrollController _tensController;
  late FixedExtentScrollController _onesController;

  @override
  void initState() {
    super.initState();
    _volume = widget.volume;
    _soundEnabled = widget.soundEnabled;
    _hapticsEnabled = widget.hapticsEnabled;
    _tapAnywhere = widget.tapAnywhere;
    _defaultTarget = widget.defaultTarget;
    _intervalSeconds = widget.intervalSeconds;

    // Initialize scroll controllers to current target value
    _thousandsController = FixedExtentScrollController(
      initialItem: (_defaultTarget ~/ 1000) % 2,
    );
    _hundredsController = FixedExtentScrollController(
      initialItem: (_defaultTarget ~/ 100) % 10,
    );
    _tensController = FixedExtentScrollController(
      initialItem: (_defaultTarget ~/ 10) % 10,
    );
    _onesController = FixedExtentScrollController(
      initialItem: _defaultTarget % 10,
    );
  }

  @override
  void dispose() {
    _thousandsController.dispose();
    _hundredsController.dispose();
    _tensController.dispose();
    _onesController.dispose();
    super.dispose();
  }

  void _updateTargetFromPickers() {
    final thousands = _thousandsController.selectedItem % 2; // 0-1 only
    final hundreds = _hundredsController.selectedItem % 10;
    final tens = _tensController.selectedItem % 10;
    final ones = _onesController.selectedItem % 10;
    final newTarget =
        (thousands * 1000) + (hundreds * 100) + (tens * 10) + ones;
    // Cap at 1008 and ensure minimum is 1
    final cappedTarget = newTarget > 1008
        ? 1008
        : (newTarget == 0 ? 1 : newTarget);
    setState(() => _defaultTarget = cappedTarget);
    _autoSave();
  }

  void _autoSave() {
    widget.onChanged(
      SettingsData(
        volume: _volume,
        soundEnabled: _soundEnabled,
        hapticsEnabled: _hapticsEnabled,
        tapAnywhere: _tapAnywhere,
        defaultTarget: _defaultTarget,
        intervalSeconds: _intervalSeconds,
      ),
    );
  }

  Widget _buildIntervalChip(double seconds) {
    final isSelected = _intervalSeconds == seconds;
    final label =
        "${seconds.toStringAsFixed(seconds == seconds.roundToDouble() ? 0 : 1)}s";

    return GestureDetector(
      onTap: () {
        setState(() {
          _intervalSeconds = seconds;
        });
        _autoSave();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD96A), Color(0xFFD6A54B)],
                )
              : LinearGradient(
                  colors: [
                    const Color(0xFF3A3C4E).withValues(alpha: 0.6),
                    const Color(0xFF2A2C3E).withValues(alpha: 0.6),
                  ],
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFE55C)
                : const Color(0xFF4A4C5E).withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD96A).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF1C1E3A)
                : const Color(0xFFA0A0A8),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberWheel(
    FixedExtentScrollController controller,
    String label, {
    int maxDigit = 9,
  }) {
    final digitCount = maxDigit + 1;
    return Column(
      children: [
        Container(
          height: 82,
          width: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A2C48), Color(0xFF1F2131)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color(0xFFFFD96A).withValues(alpha: 0.2),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Selection highlight in center
              Center(
                child: Container(
                  height: 37,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFFD96A).withValues(alpha: 0.15),
                        const Color(0xFFFFD96A).withValues(alpha: 0.25),
                        const Color(0xFFFFD96A).withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Number wheel
              ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: 37,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                perspective: 0.003,
                onSelectedItemChanged: (_) => _updateTargetFromPickers(),
                childDelegate: ListWheelChildLoopingListDelegate(
                  children: List.generate(digitCount, (index) {
                    return Center(
                      child: Text(
                        index.toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFD96A),
                          height: 1.0,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [Color(0xFFD6A54B), Color(0xFFFFD96A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: const Text(
                  "Scroll the wheels to set your daily target",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    letterSpacing: 1.1,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
              const SizedBox(height: 12),
              // Rolling Number Picker (Slot Machine Style)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF262835), Color(0xFF1A1C2E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD96A).withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Current Target Display
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD96A), Color(0xFFD6A54B)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _defaultTarget.toString().padLeft(4, '0'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C1E3A),
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Rolling Number Wheels
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildNumberWheel(
                            _thousandsController,
                            "1000s",
                            maxDigit: 1,
                          ),
                          const SizedBox(width: 5),
                          _buildNumberWheel(_hundredsController, "100s"),
                          const SizedBox(width: 5),
                          _buildNumberWheel(_tensController, "10s"),
                          const SizedBox(width: 5),
                          _buildNumberWheel(_onesController, "1s", maxDigit: 8),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Scroll to select target (1-1008)",
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFFA0A0A8).withValues(alpha: 0.9),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Timer Interval Selector
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [Color(0xFFD6A54B), Color(0xFFFFD96A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: const Text(
                  "Timer Interval",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Time between each mantra count (in seconds)",
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFA0A0A8).withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF262835), Color(0xFF1A1C2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildIntervalChip(1),
                        _buildIntervalChip(2),
                        _buildIntervalChip(3),
                        _buildIntervalChip(4),
                        _buildIntervalChip(5),
                        _buildIntervalChip(10),
                        _buildIntervalChip(15),
                        _buildIntervalChip(30),
                        _buildIntervalChip(60),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1E3A).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 18,
                            color: const Color(0xFFFFD96A),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Current: ${_intervalSeconds.toStringAsFixed(_intervalSeconds == _intervalSeconds.roundToDouble() ? 0 : 1)}s",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFFFD96A),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch(
                    value: _soundEnabled,
                    onChanged: (v) {
                      setState(() => _soundEnabled = v);
                      _autoSave();
                    },
                  ),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFFD6A54B), Color(0xFFFFD96A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      "Enable Sound",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              // Removed 'Tap Anywhere to Count' button
              // Reset Total Count Button
              Row(
                children: [
                  Switch(
                    value: false,
                    onChanged: (v) async {
                      // Show premium confirmation dialog
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF2A2C48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.fromLTRB(
                            24,
                            28,
                            24,
                            18,
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Color(0xFFD6A54B),
                                    Color(0xFFFFD96A),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(bounds),
                                child: const Text(
                                  "Reset Total Count?",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Montserrat',
                                    color: Colors.white,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Color(0xFFD6A54B),
                                    Color(0xFFFFD96A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                                child: const Text(
                                  "This will reset your lifetime mantra count to 0.\nThis action cannot be undone.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Montserrat',
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            LinearGradient(
                                              colors: [
                                                Color(0xFFD6A54B),
                                                Color(0xFFFFD96A),
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ).createShader(bounds),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Montserrat',
                                            color: Colors.white,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            LinearGradient(
                                              colors: [
                                                Color(0xFFD6A54B),
                                                Color(0xFFFFD96A),
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ).createShader(bounds),
                                        child: const Text(
                                          "Reset",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Montserrat',
                                            color: Colors.white,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );

                      if (confirmed == true) {
                        await widget.onResetTotalMantras();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF2A2C48),
                              content: ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Color(0xFFD6A54B),
                                    Color(0xFFFFD96A),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(bounds),
                                child: const Text(
                                  "Total mantras count has been reset",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Montserrat',
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFFFFD96A), Color(0xFFD6A54B)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      "Reset Total Count",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 2.0,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF23254A),
                    borderRadius: BorderRadius.circular(12.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 12.0,
                    ),
                    child: Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [Color(0xFFD6A54B), Color(0xFFFFD96A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: const Icon(
                            Icons.volume_up,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Color(0xFFD6A54B),
                                    Color(0xFFFFD96A),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ).createShader(bounds),
                                child: const Text(
                                  "Volume",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Montserrat',
                                    color: Colors.white,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              Slider(
                                value: _volume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label: (_volume * 100).round().toString(),
                                onChanged: (v) {
                                  setState(() => _volume = v);
                                  _autoSave();
                                },
                                activeColor: const Color(0xFFD6A54B),
                                inactiveColor: const Color(0xFF44465C),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  "Settings are saved automatically",
                  style: TextStyle(
                    fontSize: 11,
                    color: const Color(0xFFA0A0A8).withValues(alpha: 0.8),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Support & Contributions Handle
              Center(
                child: GestureDetector(
                  onTap: () => _showSupportBottomSheet(context),
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity! < 0) {
                      _showSupportBottomSheet(context);
                    }
                  },
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A2C48), Color(0xFF1F2131)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD96A).withValues(alpha: 0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_up,
                          color: Color(0xFFFFD96A),
                          size: 24,
                        ),
                        const Text(
                          "Support & Contributions",
                          style: TextStyle(
                            color: Color(0xFFFFD96A),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_up,
                          color: Color(0xFFFFD96A),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupportBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1E3A), Color(0xFF252745)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD96A).withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Ram Mandir Temple Background
            Positioned.fill(
              child: CustomPaint(painter: HimalayanTemplePainter()),
            ),
            // Content overlay
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Drag handle
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Title with gaming-quality text
                    Text(
                      "Support the Journey 🙏",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFFFD96A),
                        letterSpacing: 1.2,
                        shadows: [
                          Shadow(
                            color: const Color(
                              0xFFFFD96A,
                            ).withValues(alpha: 0.8),
                            blurRadius: 20,
                          ),
                          Shadow(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.6),
                            offset: const Offset(0, 3),
                            blurRadius: 10,
                          ),
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            offset: const Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Body text with enhanced styling
                    Text(
                      "Your contribution helps us maintain and improve MantraMala, keeping it free and ad-free for everyone. Every donation, big or small, supports our mission to provide a peaceful spiritual practice tool.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFF8F5F0).withValues(alpha: 0.95),
                        height: 1.6,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    // India UPI Button with premium styling
                    _buildPremiumDonationButton(
                      context: context,
                      title: "Support from India 🇮🇳",
                      emoji: "",
                      onTap: () async {
                        final upiUrl = Uri.parse(
                          'upi://pay?pa=6472084641@icici&pn=MantraMala&cu=INR',
                        );
                        try {
                          await launchUrl(
                            upiUrl,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No UPI app found. Please install Google Pay, PhonePe, or Paytm.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    // Worldwide Ko-fi Button with premium styling
                    _buildPremiumDonationButton(
                      context: context,
                      title: "Support from Worldwide 🌍",
                      emoji: "",
                      onTap: () async {
                        final kofiUrl = Uri.parse(
                          'https://ko-fi.com/mantramala',
                        );
                        try {
                          final result = await launchUrl(
                            kofiUrl,
                            mode: LaunchMode.externalApplication,
                          );
                          if (!result) {
                            throw Exception('Failed to launch URL');
                          }
                        } catch (e) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Cannot open browser. Please try again later.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 32),
                    // Footer text with enhanced styling
                    Text(
                      "Thank you for being part of this spiritual journey! 🙏✨",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFA0A0A8).withValues(alpha: 0.9),
                        letterSpacing: 0.4,
                        height: 1.4,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumDonationButton({
    required BuildContext context,
    required String title,
    required String emoji,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A3A3A), Color(0xFF1C1C1C), Color(0xFF0A0A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD96A).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFFD96A).withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0xFFFFD96A).withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFFD96A),
                    letterSpacing: 0.8,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFFFD96A).withValues(alpha: 0.6),
                        blurRadius: 10,
                      ),
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HimalayanTemplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = const Color(0xFFFFD96A).withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = const Color(0xFFFFD96A).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final width = size.width;
    final height = size.height;
    final centerX = width / 2;

    // 1. Grand stepped platform (bottom foundation)
    final platformWidth = width * 0.35;
    final platformHeight = height * 0.03;
    final platformY = height * 0.80;

    for (int i = 0; i < 3; i++) {
      final stepWidth = platformWidth + (i * width * 0.04);
      final stepY = platformY + (i * platformHeight);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(centerX, stepY),
          width: stepWidth,
          height: platformHeight,
        ),
        basePaint,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(centerX, stepY),
          width: stepWidth,
          height: platformHeight,
        ),
        outlinePaint,
      );
    }

    // 2. Main temple base (rectangular foundation)
    final baseWidth = width * 0.50;
    final baseHeight = height * 0.20;
    final baseY = platformY - baseHeight;

    canvas.drawRect(
      Rect.fromLTWH(centerX - baseWidth / 2, baseY, baseWidth, baseHeight),
      basePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX - baseWidth / 2, baseY, baseWidth, baseHeight),
      outlinePaint,
    );

    // 3. Five colonnade pillars
    final pillarWidth = width * 0.03;
    final pillarHeight = height * 0.10;
    final pillarSpacing = width * 0.10;
    final pillarY = baseY;

    for (int i = -2; i <= 2; i++) {
      final pillarX = centerX + (i * pillarSpacing) - pillarWidth / 2;
      canvas.drawRect(
        Rect.fromLTWH(pillarX, pillarY, pillarWidth, pillarHeight),
        basePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(pillarX, pillarY, pillarWidth, pillarHeight),
        outlinePaint,
      );
    }

    // 4. Three-tiered shikhara (tapering tower)
    final tier1Width = width * 0.18;
    final tier1Height = height * 0.08;
    final tier1Y = baseY - tier1Height;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier1Y),
        width: tier1Width,
        height: tier1Height,
      ),
      basePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier1Y),
        width: tier1Width,
        height: tier1Height,
      ),
      outlinePaint,
    );

    final tier2Width = width * 0.12;
    final tier2Height = height * 0.06;
    final tier2Y = tier1Y - tier2Height;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier2Y),
        width: tier2Width,
        height: tier2Height,
      ),
      basePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier2Y),
        width: tier2Width,
        height: tier2Height,
      ),
      outlinePaint,
    );

    final tier3Width = width * 0.08;
    final tier3Height = height * 0.05;
    final tier3Y = tier2Y - tier3Height;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier3Y),
        width: tier3Width,
        height: tier3Height,
      ),
      basePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, tier3Y),
        width: tier3Width,
        height: tier3Height,
      ),
      outlinePaint,
    );

    // 5. Central spire (triangular peak)
    final spireWidth = width * 0.04;
    final spireHeight = height * 0.06;
    final spireY = tier3Y - tier3Height / 2;

    final spirePath = Path()
      ..moveTo(centerX, spireY - spireHeight)
      ..lineTo(centerX - spireWidth / 2, spireY)
      ..lineTo(centerX + spireWidth / 2, spireY)
      ..close();

    canvas.drawPath(spirePath, basePaint);
    canvas.drawPath(spirePath, outlinePaint);

    // 6. Kalash dome (circular ornament)
    final kalashRadius = width * 0.015;
    final kalashY = spireY - spireHeight;

    canvas.drawCircle(Offset(centerX, kalashY), kalashRadius, basePaint);
    canvas.drawCircle(Offset(centerX, kalashY), kalashRadius, outlinePaint);

    // 7. Flag pole (vertical line)
    final flagPoleHeight = height * 0.06;
    final flagPoleY = kalashY - kalashRadius;

    canvas.drawLine(
      Offset(centerX, flagPoleY),
      Offset(centerX, flagPoleY - flagPoleHeight),
      outlinePaint,
    );

    // 8. Triangular flag at top
    final flagWidth = width * 0.025;
    final flagHeight = height * 0.02;
    final flagY = flagPoleY - flagPoleHeight;

    final flagPath = Path()
      ..moveTo(centerX, flagY)
      ..lineTo(centerX + flagWidth, flagY + flagHeight / 2)
      ..lineTo(centerX, flagY + flagHeight)
      ..close();

    canvas.drawPath(flagPath, basePaint);
    canvas.drawPath(flagPath, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  CircleProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    canvas.drawArc(
      Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class GradientCircleProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  GradientCircleProgressPainter({
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      // Nothing to paint for zero progress; avoids invalid SweepGradient angles
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2,
      height: radius * 2,
    );

    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + (2 * math.pi * progress),
      colors: const [Color(0xFFFFD96A), Color(0xFFD6A54B), Color(0xFFB8873D)],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(GradientCircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
