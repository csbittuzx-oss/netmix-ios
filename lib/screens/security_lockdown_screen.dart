// lib/screens/security_lockdown_screen.dart
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/security_checker.dart';

/// Clean Apple-style Liquid Glass Security Lockdown Screen
class SecurityLockdownScreen extends StatelessWidget {
  const SecurityLockdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          SecurityChecker.terminateCompromisedApp();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.shield_slash_fill,
                            color: Colors.redAccent,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Security Protection Alert',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Netmix integrity verification failed. An unauthorized package modification, invalid signature, or active reverse-engineering tool was detected.\n\nTo safeguard content and credentials, Netmix cannot run in this environment.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(16),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onPressed: () {
                              SecurityChecker.terminateCompromisedApp();
                            },
                            child: const Text(
                              'Close Application',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
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
        ),
      ),
    );
  }
}
