// lib/screens/we_need_support_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/router.dart';
import '../providers/home_provider.dart';
import '../services/ad_verification_service.dart';

class WeNeedSupportScreen extends ConsumerStatefulWidget {
  const WeNeedSupportScreen({super.key});

  @override
  ConsumerState<WeNeedSupportScreen> createState() => _WeNeedSupportScreenState();
}

class _WeNeedSupportScreenState extends ConsumerState<WeNeedSupportScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final AdVerificationService _adService = AdVerificationService.instance;
  bool _isButtonDown = false;
  bool _isReloadDown = false;
  bool _isLocalVerifying = false;
  String? _errorMessage;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;

  // Apple-style fluid press animation controller
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    // Initial status check to confirm if device already has valid access
    _checkInitialStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialStatus() async {
    final hasAccess = await _adService.checkAccessStatus();
    if (mounted && hasAccess) {
      context.go(AppRoutes.home);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning to Netmix from Chrome/browser, automatically verify
    if (state == AppLifecycleState.resumed) {
      if (_adService.activeSessionId != null && !_isLocalVerifying) {
        _verifyAdAutomatically();
      }
    }
  }

  Future<void> _onAdsButtonClicked() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _errorMessage = null;
      _remainingSeconds = 0;
    });

    final opened = await _adService.startAdSession();
    if (!opened && mounted) {
      setState(() {
        _errorMessage = _adService.lastVerificationError ??
            'Could not open Google Chrome. Please check your browser settings.';
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _verifyAdAutomatically() async {
    if (_isLocalVerifying || !mounted) return;

    setState(() {
      _isLocalVerifying = true;
      _errorMessage = null;
    });

    final result = await _adService.verifyAdSession();
    if (!mounted) return;

    setState(() {
      _isLocalVerifying = false;
    });

    if (result.success) {
      HapticFeedback.heavyImpact();
      // Access granted! Smoothly transition to Home
      context.go(AppRoutes.home);
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = result.error ??
            "You didn't complete the ad. Please reopen it, watch for 30 seconds, and return to the Netmix app.";
        _remainingSeconds = result.remainingSeconds;
      });

      _startLocalCountdown();
    }
  }

  void _startLocalCountdown() {
    _countdownTimer?.cancel();
    if (_remainingSeconds <= 0) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
        });
      }
    });
  }

  Future<void> _onReloadClicked() async {
    HapticFeedback.lightImpact();
    // If there's an active session, verify it; otherwise re-check server access status
    if (_adService.activeSessionId != null) {
      await _verifyAdAutomatically();
    } else {
      setState(() => _isLocalVerifying = true);
      final hasAccess = await _adService.checkAccessStatus();
      if (!mounted) return;
      setState(() => _isLocalVerifying = false);

      if (hasAccess) {
        HapticFeedback.heavyImpact();
        context.go(AppRoutes.home);
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _errorMessage =
              "You didn't complete the ad. Please reopen it, watch for 30 seconds, and return to the Netmix app.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeData = ref.watch(homeProvider).data;
    final allItems = [
      if (homeData != null) ...[
        if (homeData.heroItem != null) homeData.heroItem!,
        ...homeData.shelves.expand((s) => s.items),
      ]
    ];

    return PopScope(
      canPop: false, // Strict mandatory restriction: cannot dismiss or back out
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Layer 1: Background Movie Mosaic Poster Grid ─────────────────
            Positioned.fill(
              child: Opacity(
                opacity: 0.28,
                child: _buildPosterGrid(allItems),
              ),
            ),

            // ── Layer 2: Apple Frosted Backdrop Glass Blur ───────────────────
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
            ),

            // ── Layer 3: Main Scrollable Content ────────────────────────────
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),

                      // 1. Heading: We Need Support (Yellow, Bold Display)
                      Text(
                        'We Need Support',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFFFE600),
                          letterSpacing: -0.6,
                          shadows: [
                            Shadow(
                              color: const Color(0xFFFFE600).withValues(alpha: 0.35),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // 2. Prominent Red Button: Click Here (Apple Fluid Press)
                      _buildAppleRedAdButton(),

                      const SizedBox(height: 36),

                      // 3. Section Heading: How To Use.
                      Text(
                        'How To Use.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 4. Instructions List
                      _buildInstructionsCard(),

                      const SizedBox(height: 28),

                      // 5. Incomplete Warning Banner (if user returned before 30s)
                      if (_errorMessage != null) ...[
                        _buildWarningBanner(),
                        const SizedBox(height: 20),
                      ],

                      // 6. Green Friendly Notice Message
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          "Guys, we know ads are a headache. If we don't put ads then we will have to shut down the app because there is not enough funds to run the app.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2E7D32),
                            height: 1.45,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // 7. Bottom Reload Button
                      _buildReloadButton(),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Apple Fluid Press Red Button
  Widget _buildAppleRedAdButton() {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isButtonDown = true);
        _animController.forward();
      },
      onTapUp: (_) {
        setState(() => _isButtonDown = false);
        _animController.reverse();
        _onAdsButtonClicked();
      },
      onTapCancel: () {
        setState(() => _isButtonDown = false);
        _animController.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFC62828), // Crimson Red
                Color(0xFF9E1B1B), // Deep Red
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC62828).withValues(alpha: _isButtonDown ? 0.35 : 0.6),
                blurRadius: _isButtonDown ? 12 : 28,
                offset: Offset(0, _isButtonDown ? 4 : 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Click Here',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Open 1 AD per 12 Hours',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFFD700),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Instructions card matching the exact numbered format
  Widget _buildInstructionsCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepRow('(1)', 'Click on above ADS Button.'),
          const SizedBox(height: 10),
          _buildStepRow('(2)', "Ads will open in your device's browser."),
          const SizedBox(height: 10),
          _buildStepRow('(3)', 'Check ads more then 30 seconds.'),
          const SizedBox(height: 10),
          _buildStepRow('(4)', 'After 30 Seconds Close ads and come back to APP.'),
        ],
      ),
    );
  }

  Widget _buildStepRow(String numPrefix, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          numPrefix,
          style: GoogleFonts.inter(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// Apple Warning Banner when user returns before 30 seconds
  Widget _buildWarningBanner() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0D0F).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF453A).withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF453A).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: Color(0xFFFF453A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF6961),
                    height: 1.4,
                  ),
                ),
                if (_remainingSeconds > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Time remaining: $_remainingSeconds seconds',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFFD700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Apple Pill Reload Button
  Widget _buildReloadButton() {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isReloadDown = true),
      onTapUp: (_) {
        setState(() => _isReloadDown = false);
        _onReloadClicked();
      },
      onTapCancel: () => setState(() => _isReloadDown = false),
      child: AnimatedScale(
        scale: _isReloadDown ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isReloadDown ? 0.8 : 0.96),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _isLocalVerifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CupertinoActivityIndicator(
                    color: Colors.black,
                    radius: 8,
                  ),
                )
              : Text(
                  'Reload',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }

  /// Decorative background poster grid
  Widget _buildPosterGrid(List<dynamic> items) {
    if (items.isEmpty) {
      return Container(color: const Color(0xFF101014));
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.67,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length.clamp(0, 18),
      itemBuilder: (context, index) {
        final item = items[index];
        final poster = item.poster as String?;
        if (poster == null || poster.isEmpty) {
          return Container(color: const Color(0xFF181820));
        }
        return Image.network(
          poster,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF181820)),
        );
      },
    );
  }
}
