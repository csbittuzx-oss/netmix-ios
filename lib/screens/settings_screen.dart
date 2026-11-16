// lib/screens/settings_screen.dart
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/app_update_service.dart';

// ── Apple Liquid Glass Icon Component ────────────────────────────────────────

class AppleLiquidGlassIcon extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final double size;

  const AppleLiquidGlassIcon({
    super.key,
    required this.child,
    required this.baseColor,
    this.size = 38.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withValues(alpha: 0.95),
            baseColor.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.38),
          width: 1.1,
        ),
        boxShadow: [
          // Ambient colored glow
          BoxShadow(
            color: baseColor.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          // Deep drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Specular glass reflection layer (Apple gloss highlight on top-half)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size * 0.50,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(size * 0.28),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.40),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Centered Icon with subtle shadow for crisp optical depth
          Center(child: child),
        ],
      ),
    );
  }
}

// ── Apple Liquid Glass Image Frame (Profile & Branding) ──────────────────────

class AppleLiquidGlassImageFrame extends StatelessWidget {
  final Widget image;
  final double size;
  final double borderRadius;

  const AppleLiquidGlassImageFrame({
    super.key,
    required this.image,
    required this.size,
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.32),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE50914).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1.2),
        child: Stack(
          children: [
            Positioned.fill(child: image),
            // Specular glass shine across the top rim
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size * 0.42,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.25),
                      Colors.transparent,
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
}

// ── Official Telegram Paper Plane Painter ────────────────────────────────────

class _TelegramPlanePainter extends CustomPainter {
  const _TelegramPlanePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    // Official Telegram paper airplane vector path
    final path = Path()
      ..moveTo(21.5, 3.5)
      ..lineTo(2.5, 10.8)
      ..cubicTo(1.2, 11.3, 1.2, 12.1, 2.3, 12.4)
      ..lineTo(7.1, 13.9)
      ..lineTo(18.3, 6.8)
      ..cubicTo(18.8, 6.5, 19.3, 6.7, 18.9, 7.1)
      ..lineTo(9.8, 15.3)
      ..lineTo(9.5, 19.8)
      ..cubicTo(9.9, 19.8, 10.1, 19.6, 10.3, 19.4)
      ..lineTo(12.3, 17.5)
      ..lineTo(16.5, 20.6)
      ..cubicTo(17.3, 21.0, 17.8, 20.6, 18.0, 19.7)
      ..lineTo(22.0, 4.8)
      ..cubicTo(22.3, 3.6, 21.5, 3.0, 21.5, 3.5)
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Apple Liquid Glass Popup Modal Sheet ─────────────────────────────────────

void _showAppleLegalPopup(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget headerIcon,
  required List<String> bulletPoints,
}) {
  // CRITICAL: useRootNavigator: true ensures the modal appears ON TOP of
  // the floating bottom navigation bar, eliminating any obscuration!
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).padding.bottom;
      final screenHeight = MediaQuery.of(ctx).size.height;

      return Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.90,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE814141E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.60),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Grab Bar & Liquid Glass Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 34),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      // Liquid Glass Close Button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(34),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(24, 12, 24, bottomInset + 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with Liquid Glass Icon
                        Row(
                          children: [
                            headerIcon,
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFFEBEBF5),
                                        letterSpacing: -0.2,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // Apple Liquid Glass Inset Card for Bullet Points
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < bulletPoints.length; i++) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 7),
                                      child: Container(
                                        width: 6.5,
                                        height: 6.5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFFF3B30),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF3B30)
                                                  .withValues(alpha: 0.50),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        bulletPoints[i],
                                        style: GoogleFonts.inter(
                                          fontSize: 14.5,
                                          height: 1.55,
                                          color: Colors.white,
                                          letterSpacing: -0.15,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (i < bulletPoints.length - 1)
                                  Divider(
                                    height: 22,
                                    thickness: 0.6,
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 38),

                        // Developer Branding & Footer (Fully visible & clear!)
                        Center(
                          child: Column(
                            children: [
                              AppleLiquidGlassImageFrame(
                                image: Image.asset(
                                  'assets/images/profile_icon.png',
                                  fit: BoxFit.cover,
                                ),
                                size: 54,
                                borderRadius: 14,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Content Developer: Teamxyz',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Made with ❤️ by Teamxyz',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.70),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'More features adding soon...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.45),
                                  decoration: TextDecoration.none,
                                ),
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
        ),
      );
    },
  );
}

// ── Apple Liquid Glass Privacy Policy Popup Modal Sheet ─────────────────────

class _PrivacyCardData {
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final List<String> bullets;

  const _PrivacyCardData({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });
}

void _showApplePrivacyPolicyPopup(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).padding.bottom;
      final screenHeight = MediaQuery.of(ctx).size.height;

      const sections = [
        _PrivacyCardData(
          badge: '01',
          badgeColor: Color(0xFF34C759),
          title: 'Zero Data Collection Guarantee',
          subtitle: 'We did not, do not, and will never collect any type of user data.',
          bullets: [
            'No Account or Registration: You never submit your name, email address, phone number, password, or identity to use Netmix.',
            'Zero Tracking & Telemetry: We do not log search queries, watch times, opened titles, or playback durations.',
            'Zero Advertising Trackers: Netmix contains 0 ad network SDKs, 0 behavioral trackers, and 0 data broker libraries.',
            'Zero Device Fingerprinting: We never capture IMEI, MAC address, Android ID, or Advertising Identifiers (GAID).',
            'No Remote Log Server: Zero telemetry packets, analytics events, or diagnostic traces are ever uploaded to remote servers.',
          ],
        ),
        _PrivacyCardData(
          badge: '02',
          badgeColor: Color(0xFF007AFF),
          title: '100% Local Device Sovereignty',
          subtitle: 'Your personal media preferences live strictly on your physical phone.',
          bullets: [
            'Local Sandbox Storage: Bookmarks, resume playback positions, custom preferences, and settings reside exclusively on your physical device.',
            'Zero Cloud Database Sync: We maintain no centralized user database. Your watch progress is completely private and offline-first.',
            'Decoupled Client: The application operates autonomously without requiring any account authentication or user token verification.',
          ],
        ),
        _PrivacyCardData(
          badge: '03',
          badgeColor: Color(0xFFFF9500),
          title: 'Direct Peer-to-Source Media Playback',
          subtitle: 'Decentralized media playback with no intermediary proxy logging.',
          bullets: [
            'Direct Connection: Stream requests connect directly between your device and public decentralized providers.',
            'No Traffic Inspection: Netmix does not proxy, intercept, or record your streaming sessions or IP addresses.',
            'Anonymous Poster Queries: Metadata lookups (such as TMDB for posters) are executed with zero personal identifiers attached.',
          ],
        ),
        _PrivacyCardData(
          badge: '04',
          badgeColor: Color(0xFFAF52DE),
          title: 'Zero Invasive Permissions',
          subtitle: 'Only essential internet socket access is used.',
          bullets: [
            'No Contacts or Phone: Zero access to your address book, call logs, or phone hardware state.',
            'No Location: GPS, coarse network location, and Wi-Fi SSID tracking are not requested.',
            'No Camera or Microphone: Netmix has zero audio/video recording capabilities.',
            'No Background Surveillance: Boot receivers and wake-lock monitoring have been eliminated.',
          ],
        ),
        _PrivacyCardData(
          badge: '05',
          badgeColor: Color(0xFFFF2D55),
          title: 'Instant & Permanent Data Eradication',
          subtitle: 'You maintain absolute power over your device storage.',
          bullets: [
            'One-Tap Cache Clear: Tapping "Clear Cache" in Settings instantly wipes all cached files and temporary data.',
            'Total Uninstall Removal: Uninstalling Netmix or clearing app storage in Android settings permanently erases 100% of all data with zero remnants left anywhere.',
          ],
        ),
      ];

      return Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.92,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE814141E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.60),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Grab Bar & Liquid Glass Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 34),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(34),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            const AppleLiquidGlassIcon(
                              baseColor: Color(0xFF34C759),
                              size: 42,
                              child: Icon(
                                CupertinoIcons.shield_fill,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Privacy Policy',
                                    style: GoogleFonts.inter(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'NETMIX • Strict Zero Data Collection Guarantee',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF34C759),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Highlight Banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x2234C759),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF34C759).withValues(alpha: 0.35),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.checkmark_shield_fill,
                                color: Color(0xFF34C759),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'We did not and will never collect any type of user data. Netmix has zero tracking, zero logs, and zero ads.',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Section Cards
                        for (final s in sections) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: s.badgeColor.withValues(alpha: 0.20),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: s.badgeColor.withValues(alpha: 0.45),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        s.badge,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: s.badgeColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        s.title,
                                        style: GoogleFonts.inter(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  s.subtitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.70),
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (final bullet in s.bullets) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Container(
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: s.badgeColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            bullet,
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.white.withValues(alpha: 0.85),
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Dismiss button
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(14),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(
                              'I Understand & Accept',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── Grouped Modal Data Model ───────────────────────────────────────────────

class _ModalGroup {
  final String title;
  final List<String> items;
  const _ModalGroup({required this.title, required this.items});
}

// ── Reusable Apple Liquid Glass Grouped Modal ────────────────────────────────

void _showAppleGroupedModal(
  BuildContext context, {
  required Widget headerIcon,
  required String title,
  required String subtitle,
  required List<_ModalGroup> sections,
}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).padding.bottom;
      final screenHeight = MediaQuery.of(ctx).size.height;

      return Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.90,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE814141E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.60),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Grab Bar & Liquid Glass Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 34),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(34),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(24, 12, 24, bottomInset + 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            headerIcon,
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFEBEBF5),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // Section Groups
                        for (final group in sections) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 8),
                            child: Text(
                              group.title,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.45),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.0,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Column(
                                children: [
                                  for (int i = 0; i < group.items.length; i++) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 15),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6.5,
                                            height: 6.5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFFFF3B30),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFFF3B30)
                                                      .withValues(alpha: 0.50),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              group.items[i],
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                                letterSpacing: -0.15,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (i < group.items.length - 1)
                                      Divider(
                                        height: 1,
                                        thickness: 0.6,
                                        indent: 38,
                                        endIndent: 16,
                                        color: Colors.white.withValues(alpha: 0.08),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 28),

                        // Developer Branding & Footer
                        Center(
                          child: Column(
                            children: [
                              AppleLiquidGlassImageFrame(
                                image: Image.asset(
                                  'assets/images/profile_icon.png',
                                  fit: BoxFit.cover,
                                ),
                                size: 54,
                                borderRadius: 14,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Content Developer: Teamxyz',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Made with ❤️ by Teamxyz',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.70),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'More features adding soon...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
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
        ),
      );
    },
  );
}

// ── In-App Update Dialog with Realtime Progress & Installer ──────────────────

class _UpdateDialogContent extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _UpdateDialogContent({required this.updateInfo});

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressText = 'Starting download...';
  String? _errorMessage;
  bool _isReadyToInstall = false;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.5;
      _progressText = 'Opening update download...';
    });

    try {
      await AppUpdateService.instance.downloadAndInstall(
        apkUrl: widget.updateInfo.apkUrl,
        version: widget.updateInfo.latestVersion,
        expectedSha256: widget.updateInfo.sha256Checksum,
        onProgress: (_, __, ___) {},
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isReadyToInstall = true;
          _progress = 1.0;
          _progressText = 'Opened download in browser';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Could not open download link. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF14141E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Netmix Logo Frame
              AppleLiquidGlassImageFrame(
                image: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.cover,
                ),
                size: 64,
                borderRadius: 16,
              ),

              const SizedBox(height: 14),

              // Title & Version
              Text(
                'Update Available',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE50914).withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'v${widget.updateInfo.currentVersion}  ➔  v${widget.updateInfo.latestVersion}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF5A5F),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // What's New Title
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "What's New:",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Changelog Box
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    widget.updateInfo.changelog,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFFF453A),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),

              // Download progress or action buttons
              if (_isDownloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _progressText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ] else if (_isReadyToInstall) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34C759),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Open Download Page',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          await AppUpdateService.instance
                              .dismissUpdate(widget.updateInfo.latestVersion);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.65),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        child: Text(
                          'Later',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _startDownload,
                        icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 16),
                        label: Text(
                          _errorMessage != null ? 'Retry' : 'Download Update',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Up To Date Dialog ────────────────────────────────────────────────────────

void _showUpToDateDialog(BuildContext context, String currentVer) {
  showDialog(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF14141E).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 25,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppleLiquidGlassIcon(
                  baseColor: Color(0xFF34C759),
                  size: 52,
                  child: Icon(CupertinoIcons.checkmark_alt, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  "You're Up to Date",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'NETMIX v$currentVer is currently the latest release available.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── Settings Screen ──────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoPlayNextEpisode = true;
  String _installedVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    AppUpdateService.instance.addListener(_onVersionChanged);
    _installedVersion = AppUpdateService.instance.currentInstalledVersion;
    _loadSettings();
  }

  @override
  void dispose() {
    AppUpdateService.instance.removeListener(_onVersionChanged);
    super.dispose();
  }

  void _onVersionChanged() {
    if (mounted) {
      setState(() {
        _installedVersion = AppUpdateService.instance.currentInstalledVersion;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ver = await AppUpdateService.instance.getInstalledVersion();
    if (mounted) {
      setState(() {
        _autoPlayNextEpisode =
            prefs.getBool(AppConstants.prefAutoPlayNextEpisode) ?? true;
        _installedVersion = ver;
      });
    }
  }

  Future<void> _toggleAutoPlayNextEpisode(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _autoPlayNextEpisode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefAutoPlayNextEpisode, value);
  }

  Future<void> _openTelegram() => AppUpdateService.instance.openTelegram();

  void _showPrivacyPolicyPopup() {
    _showApplePrivacyPolicyPopup(context);
  }

  void _showTermsPopup() {
    _showAppleLegalPopup(
      context,
      title: 'Terms & Conditions',
      subtitle: 'Streaming Interface & Compliance Policy',
      headerIcon: const AppleLiquidGlassIcon(
        baseColor: Color(0xFFFF9F0A),
        size: 40,
        child: Icon(CupertinoIcons.doc_text_fill, color: Colors.white, size: 20),
      ),
      bulletPoints: const [
        'Netmix is an open client-side media player and visual catalog index browser.',
        'Netmix does not host, store, manage, upload, or control any video, audio, or media files on its servers.',
        'All media links and stream endpoints are resolved dynamically from third-party public sources and decentralized providers.',
        'All trademarks, media titles, logos, and copyrights belong to their respective proprietary content owners.',
        'Users bear full and sole responsibility for compliance with local copyright, distribution, and intellectual property laws in their jurisdictions.',
        'Netmix provides its interface on an "as-is" and "as-available" basis without representations or warranties of continuous availability.',
      ],
    );
  }

  void _showSupportersPopup() {
    _showAppleGroupedModal(
      context,
      headerIcon: const AppleLiquidGlassIcon(
        baseColor: Color(0xFF282834),
        size: 40,
        child: Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 20),
      ),
      title: 'Supporters & Contributors',
      subtitle: 'Open recognition and project credits',
      sections: const [
        _ModalGroup(
          title: 'CHANNEL',
          items: ['Teamxyz', 'AxorDevloper'],
        ),
        _ModalGroup(
          title: 'TEAM',
          items: ['Teamxyz'],
        ),
        _ModalGroup(
          title: 'MEMBERS',
          items: ['Revenant deid', 'raj', 'AARAV'],
        ),
      ],
    );
  }

  void _showLicensesPopup() {
    _showAppleGroupedModal(
      context,
      headerIcon: const AppleLiquidGlassIcon(
        baseColor: Color(0xFF282834),
        size: 40,
        child: Icon(CupertinoIcons.info, color: Colors.white, size: 20),
      ),
      title: 'Licenses & Attribution',
      subtitle: 'Data sources, acknowledgements, and platform licenses',
      sections: const [
        _ModalGroup(
          title: 'DATA SOURCES & PLATFORMS',
          items: ['HDHUB4U'],
        ),
      ],
    );
  }

  void _showAppleFloatingToast(String message, {Widget? leading}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.1,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xF21C1C26),
        behavior: SnackBarBehavior.floating,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.9,
          ),
        ),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 102),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  void _showUpdateChannelToast() {
    _showAppleFloatingToast(
      'Coming Soon',
      leading: const Icon(
        CupertinoIcons.sparkles,
        color: Color(0xFFE50914),
        size: 16,
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    _showAppleFloatingToast(
      'Checking for updates...',
      leading: const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );

    final info = await AppUpdateService.instance.checkUpdate();
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (info.updateAvailable) {
      await showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: !info.mandatory,
        builder: (context) => _UpdateDialogContent(updateInfo: info),
      );
      if (mounted) {
        _loadSettings();
      }
    } else {
      _showUpToDateDialog(context, info.currentVersion);
    }
  }

  Widget _buildProfileCard(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;
        final name = user.name.isNotEmpty ? user.name : 'Netmix';
        final email = user.email.isNotEmpty ? user.email : 'netmix@official';

        return GlassContainer.card(
          useOwnLayer: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AppleLiquidGlassImageFrame(
                image: Image.asset(
                  'assets/images/profile_icon.png',
                  fit: BoxFit.cover,
                ),
                size: 54,
                borderRadius: 15,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.50),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'PASS',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFF4D4D),
                    letterSpacing: 0.8,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Apple-style large title
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                    child: Text(
                      'Settings',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.6,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),

                // Profile Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: _buildProfileCard(context),
                  ),
                ),

                // 1. Playback Settings Group (Apple-style Liquid Glass Toggle)
                SliverToBoxAdapter(
                  child: GlassGroupedSection(
                    useOwnLayer: true,
                    header: Text(
                      'PLAYBACK',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFFE50914),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.forward_end_fill,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          'Automatically Play Next Episode',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: CupertinoSwitch(
                          value: _autoPlayNextEpisode,
                          activeTrackColor: const Color(0xFFE50914),
                          onChanged: _toggleAutoPlayNextEpisode,
                        ),
                      ),
                    ],
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 2. General Settings Group (Clean, Less Text, Apple Design)
                SliverToBoxAdapter(
                  child: GlassGroupedSection(
                    useOwnLayer: true,
                    header: Text(
                      'GENERAL',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFF229ED9),
                          size: 34,
                          child: Padding(
                            padding: EdgeInsets.only(right: 1.5, top: 0.5),
                            child: CustomPaint(
                              size: Size(18, 18),
                              painter: _TelegramPlanePainter(),
                            ),
                          ),
                        ),
                        title: Text(
                          'Join Telegram',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: GlassListTile.chevron,
                        onTap: _openTelegram,
                      ),
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFF34C759),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.shield_fill,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Privacy Policy',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        subtitle: Text(
                          'Zero Data Collection Guarantee',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        trailing: GlassListTile.chevron,
                        onTap: _showPrivacyPolicyPopup,
                      ),
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFFFF9F0A),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.doc_text_fill,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Terms & Conditions',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: GlassListTile.chevron,
                        onTap: _showTermsPopup,
                      ),
                    ],
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 2. About Settings Group (Clean, Less Text, Apple Design)
                SliverToBoxAdapter(
                  child: GlassGroupedSection(
                    useOwnLayer: true,
                    header: Text(
                      'ABOUT',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFFFF2D55),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.heart_fill,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Supporters & Contributors',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: GlassListTile.chevron,
                        onTap: _showSupportersPopup,
                      ),
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFF5856D6),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.info,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Licenses & Attribution',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: GlassListTile.chevron,
                        onTap: _showLicensesPopup,
                      ),
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFFAF52DE),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.device_phone_portrait,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Update Channel',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: Text(
                          'Beta',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.50),
                          ),
                        ),
                        onTap: _showUpdateChannelToast,
                      ),
                      GlassListTile(
                        leading: const AppleLiquidGlassIcon(
                          baseColor: Color(0xFF34C759),
                          size: 34,
                          child: Icon(
                            CupertinoIcons.cloud_download_fill,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        title: Text(
                          'Check for Updates',
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'v$_installedVersion',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GlassListTile.chevron,
                          ],
                        ),
                        onTap: _checkForUpdates,
                      ),
                    ],
                  ),
                ),

                // 3. Clean Apple Minimal Footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 36, bottom: 120),
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            'NETMIX v$_installedVersion (Beta)',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.35),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Made with ❤️ by Teamxyz',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ],
                      ),
                    ),
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
