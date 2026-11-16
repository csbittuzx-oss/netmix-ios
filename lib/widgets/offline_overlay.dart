// lib/widgets/offline_overlay.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connectivity_service.dart';

class OfflineOverlay extends ConsumerWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectivityProvider);

    return Stack(
      children: [
        child,
        // Offline Liquid Glass Overlay
        IgnorePointer(
          ignoring: !conn.isOffline,
          child: AnimatedOpacity(
            opacity: conn.isOffline ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: conn.isOffline
                ? ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        color: const Color(0xE009090E),
                        width: double.infinity,
                        height: double.infinity,
                        child: SafeArea(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Disconnected Wi-Fi Icon with restrained coral accent
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE57373)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.wifi_off_rounded,
                                      size: 44,
                                      color: Color(0xFFE57373),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Heading
                                  Text(
                                    'No connection',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Reconnection Countdown Message
                                  Text(
                                    conn.isChecking
                                        ? 'Checking connection…'
                                        : 'Attempting to reconnect in ${conn.countdown} seconds…',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: Colors.white.withValues(alpha: 0.65),
                                      height: 1.4,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 22),

                                  // Retry action
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      ref
                                          .read(connectivityProvider.notifier)
                                          .checkNow();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Text(
                                        'Retry now',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF4A90E2),
                                          decoration: TextDecoration.none,
                                        ),
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
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
