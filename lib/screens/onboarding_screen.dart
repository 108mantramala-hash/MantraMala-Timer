import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      icon: Icons.spa_rounded,
      title: 'Welcome to MantraMala Timer',
      body:
          'A calm, distraction-free timer for mantra chanting, japa, and mindful meditation.\n\nBuilt to help you stay focused — no ads, no noise, just presence.',
      cta: 'Begin Gently →',
    ),
    _OnboardingPageData(
      icon: Icons.timer_rounded,
      title: 'How it works',
      body:
          '① Choose a session duration\n② Select your timer rhythm\n③ Start and chant mindfully\n\nA gentle alert guides you when your session completes.',
      cta: 'Continue',
    ),
    _OnboardingPageData(
      icon: Icons.self_improvement_rounded,
      title: 'Use it your way',
      body:
          'Practice japa, breath meditation, affirmations, or silent mindfulness — your way.\n\nAdjust rhythm, sound, and timing anytime — your practice evolves with you.',
      cta: 'Start My First Session',
      helper: 'No sign-up required • Always free',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MantraMalaHome()),
    );
  }

  void _onNext() {
    if (_currentPage == _pages.length - 1) {
      _finishOnboarding();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.ease,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C1026), Color(0xFF0A0F21)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) => _OnboardingPage(
                  data: _pages[i],
                  animate: i == _currentPage,
                  pageIndex: i,
                ),
              ),
              if (_currentPage < _pages.length - 1)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextButton(
                      onPressed: () {
                        if (_currentPage < _pages.length - 1) {
                          _pageController.animateToPage(
                            _currentPage + 1,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.ease,
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.65),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PremiumDotsIndicator(
                      count: _pages.length,
                      active: _currentPage,
                      color: const Color(0xFFF6C453),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF6C453),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _onNext,
                          child: Text(
                            _pages[_currentPage].cta ??
                                (_currentPage == _pages.length - 1
                                    ? 'Start My First Session'
                                    : 'Continue'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_pages[_currentPage].helper != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          _pages[_currentPage].helper!,
                          style: const TextStyle(
                            color: Color(0xFFBFC3D9),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;
  final String? cta;
  final String? helper;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
    this.cta,
    this.helper,
  });
}

class _OnboardingPage extends StatefulWidget {
  final _OnboardingPageData data;
  final bool animate;
  final int pageIndex;
  const _OnboardingPage({
    required this.data,
    this.animate = false,
    required this.pageIndex,
  });

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWelcome = widget.pageIndex == 0;
    final isHowItWorks = widget.pageIndex == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isWelcome)
            FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF6C453).withOpacity(0.25),
                        blurRadius: 32,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/logo/logo1.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            )
          else
            FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: _PremiumIcon(icon: widget.data.icon),
              ),
            ),
          const SizedBox(height: 36),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFF6C453), Color(0xFFFFD96A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.data.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                  letterSpacing: 1.1,
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isWelcome)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 18.0),
              child: Text(
                'Japa • Chant • Meditate',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFF6C453),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Montserrat',
                  letterSpacing: 0.2,
                ),
              ),
            ),
          const SizedBox(height: 18),
          if (isHowItWorks)
            _HowItWorksSteps()
          else
            Text(
              widget.data.body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFBFC3D9),
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.6,
                fontFamily: 'Montserrat',
                letterSpacing: 0.1,
                shadows: [
                  Shadow(color: Colors.black.withOpacity(0.10), blurRadius: 4),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HowItWorksSteps extends StatelessWidget {
  const _HowItWorksSteps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      'Choose a session duration',
      'Select your timer rhythm',
      'Start and chant mindfully',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 14 : 0),
            child: NumberedStepRow(stepNumber: i + 1, text: steps[i]),
          ),
        const SizedBox(height: 18),
        Text(
          'A gentle alert guides you when your session completes.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFBFC3D9),
            fontSize: 17,
            fontWeight: FontWeight.w400,
            fontFamily: 'Montserrat',
          ),
        ),
      ],
    );
  }
}

class NumberedStepRow extends StatelessWidget {
  final int stepNumber;
  final String text;
  const NumberedStepRow({required this.stepNumber, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFF6C453),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF6C453).withOpacity(0.25),
                blurRadius: 6,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$stepNumber',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFBFC3D9),
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    );
  }
}


class _PremiumIcon extends StatelessWidget {
  final IconData icon;
  const _PremiumIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF23274D), Color(0xFF181B36)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF6C453).withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF6C453).withOpacity(0.22),
          width: 1.6,
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Icon(
        icon,
        color: const Color(0xFFF6C453),
        size: 56,
        shadows: [Shadow(color: Colors.black.withOpacity(0.18), blurRadius: 8)],
      ),
    );
  }
}

class _PremiumDotsIndicator extends StatelessWidget {
  final int count;
  final int active;
  final Color color;
  const _PremiumDotsIndicator({
    required this.count,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: isActive ? 20 : 9,
          height: isActive ? 9 : 7,
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1.5,
                    ),
                  ]
                : [],
          ),
        );
      }),
    );
  }
}
