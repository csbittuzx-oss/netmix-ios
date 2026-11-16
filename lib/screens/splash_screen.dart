// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../core/router.dart';
import '../core/security_checker.dart';
import '../core/security_vault.dart';
import '../providers/home_provider.dart';
import '../services/ad_verification_service.dart';
import 'security_lockdown_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  VideoPlayerController? _controller;
  Timer? _fallbackTimer;
  Timer? _hardSafetyTimer;
  bool _hasNavigated = false;
  bool _isInitStarted = false;

  @override
  void initState() {
    super.initState();

    // 1. Hard safety timer: Guaranteed entry within 2.8s on any device (especially 32-bit legacy phones)
    _hardSafetyTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted && !_hasNavigated) {
        _navigateToHome();
      }
    });

    // 2. Warm up the home catalog and ad verification status in the background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeProvider.notifier).load();
      AdVerificationService.instance.init();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitStarted) {
      _isInitStarted = true;
      _setupVideo();
    }
  }

  Future<void> _setupVideo() async {
    final size = MediaQuery.of(context).size;
    final isTabletOrLandscape =
        size.width > size.height || size.shortestSide >= 600;

    final assetPath = isTabletOrLandscape
        ? 'assets/videos/loading_tablet.mp4'
        : 'assets/videos/loading_phone.mp4';

    try {
      final controller = VideoPlayerController.asset(assetPath);
      _controller = controller;

      // Timeout after 1.5s so low-end 32-bit hardware decoders never hang startup
      await controller.initialize().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {
          throw TimeoutException('Video controller initialization timed out');
        },
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_videoListener);
      await controller.setVolume(1.0);
      await controller.play();
      setState(() {});

      final videoDuration = controller.value.duration;
      final safetyDuration = videoDuration > Duration.zero
          ? videoDuration + const Duration(milliseconds: 200)
          : const Duration(milliseconds: 2200);

      _fallbackTimer = Timer(safetyDuration, _navigateToHome);
    } catch (e) {
      debugPrint('[SplashScreen] Video initialization fallback: $e');
      _navigateToHome();
    }
  }

  void _videoListener() {
    if (_controller == null || _hasNavigated) return;
    final value = _controller!.value;
    if (value.isInitialized) {
      // If position reached the end of the video
      if (value.position >= value.duration && value.duration > Duration.zero) {
        _navigateToHome();
      }
    }
  }

  Future<void> _navigateToHome() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _fallbackTimer?.cancel();
    _hardSafetyTimer?.cancel();

    // Fast non-blocking security integrity check (1.2s timeout)
    try {
      final isSecure = await SecurityChecker.verifyAppIntegrity().timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => true,
      );
      if (!mounted) return;
      if (!isSecure || SecurityVault.isCompromised) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SecurityLockdownScreen()),
        );
        return;
      }
    } catch (_) {}

    // Check server-side access status with timeout so slow network/32-bit never hangs
    bool hasAccess = true;
    try {
      hasAccess = await AdVerificationService.instance.checkAccessStatus().timeout(
        const Duration(milliseconds: 2200),
        onTimeout: () => true,
      );
    } catch (_) {
      hasAccess = true;
    }
    if (!mounted) return;

    if (hasAccess) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.support);
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _hardSafetyTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: SizedBox.expand(
          child: _controller != null && _controller!.value.isInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/netmix_n_logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 24),
                      const CupertinoActivityIndicator(
                        color: Colors.white70,
                        radius: 12,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
