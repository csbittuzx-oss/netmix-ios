// lib/widgets/apps_glass_popup.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// App data model for the Quick Launch / OTT Apps Floating Glass Dock
class OttAppItem {
  final String id;
  final String name;
  final String categoryTarget;
  final String? assetPath;
  final String? svgSource;

  const OttAppItem({
    required this.id,
    required this.name,
    required this.categoryTarget,
    this.assetPath,
    this.svgSource,
  });
}

// ── Official Authentic App Logos ─────────────────────────────────────────────

const String _netflixSvg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="nfShadow" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#000000" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="100" height="100" rx="22" fill="#000000"/>
  <path fill="#B81D24" d="M30 18h14v64H30z"/>
  <path fill="#B81D24" d="M56 18h14v64H56z"/>
  <path fill="url(#nfShadow)" d="M30 18h14v64H30z"/>
  <path fill="#E50914" d="M30 18h14l26 64H56z"/>
</svg>
''';

/// The featured OTT platforms with user-supplied high-res logos
final List<OttAppItem> ottAppsList = [
  const OttAppItem(
    id: 'netflix',
    name: 'Netflix',
    categoryTarget: 'Netflix Specials',
    svgSource: _netflixSvg,
  ),
  const OttAppItem(
    id: 'prime',
    name: 'Prime Video',
    categoryTarget: 'Amazon Prime',
    assetPath: 'assets/images/prime_video_icon.jpg',
  ),
  const OttAppItem(
    id: 'hotstar',
    name: 'JioHotstar',
    categoryTarget: 'JioHotstar',
    assetPath: 'assets/images/jiohotstar_icon.jpg',
  ),
  const OttAppItem(
    id: 'apple_tv',
    name: 'Apple TV+',
    categoryTarget: 'Apple TV+',
    assetPath: 'assets/images/apple_tv_icon.png',
  ),
  const OttAppItem(
    id: 'disney',
    name: 'Disney+',
    categoryTarget: 'Disney+',
    assetPath: 'assets/images/disney_plus_icon.jpg',
  ),
  const OttAppItem(
    id: 'hbo_max',
    name: 'HBO Max',
    categoryTarget: 'HBO Max',
    assetPath: 'assets/images/hbo_max_icon.jpg',
  ),
];

/// Apple Liquid Glass Dock Floating Page attached below the top-bar button
class AppsGlassPopup extends StatelessWidget {
  final Rect buttonRect;
  final Animation<double> animation;
  final ValueChanged<OttAppItem> onSelectApp;
  final VoidCallback onClose;

  const AppsGlassPopup({
    super.key,
    required this.buttonRect,
    required this.animation,
    required this.onSelectApp,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;

    // Apple Liquid Glass Dock platter (2 columns x 3 rows)
    const popupWidth = 136.0;
    const popupHeight = 196.0;

    // Attach directly to downside of the button, right-aligned with comfortable padding
    final top = buttonRect.bottom + 6.0;
    final right = (screenWidth - buttonRect.right).clamp(12.0, 24.0);

    return Positioned.fill(
      child: Stack(
        children: [
          // Dismiss barrier on tap outside
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                return Container(
                  color: Colors.black.withValues(
                    alpha: 0.35 * animation.value,
                  ),
                );
              },
            ),
          ),

          // Floating Apple Liquid Glass Dock Platter
          Positioned(
            right: right,
            top: top,
            width: popupWidth,
            height: popupHeight,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.82 + (0.18 * animation.value),
                  alignment: Alignment.topRight,
                  child: Opacity(
                    opacity: animation.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xCC151624),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 0.75,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.12),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.60),
                          blurRadius: 32,
                          spreadRadius: 2,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.06),
                          blurRadius: 1,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    // 2x3 Grid of App Icons (Dock Platter)
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Row 1: Netflix & Amazon Prime Video
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DockAppItem(
                              app: ottAppsList[0],
                              onTap: () => onSelectApp(ottAppsList[0]),
                            ),
                            _DockAppItem(
                              app: ottAppsList[1],
                              onTap: () => onSelectApp(ottAppsList[1]),
                            ),
                          ],
                        ),

                        // Row 2: JioHotstar & Apple TV+
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DockAppItem(
                              app: ottAppsList[2],
                              onTap: () => onSelectApp(ottAppsList[2]),
                            ),
                            _DockAppItem(
                              app: ottAppsList[3],
                              onTap: () => onSelectApp(ottAppsList[3]),
                            ),
                          ],
                        ),

                        // Row 3: Disney+ & HBO Max
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DockAppItem(
                              app: ottAppsList[4],
                              onTap: () => onSelectApp(ottAppsList[4]),
                            ),
                            _DockAppItem(
                              app: ottAppsList[5],
                              onTap: () => onSelectApp(ottAppsList[5]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dock App Icon Item with Apple squircle shape & fluid spring tap physics
class _DockAppItem extends StatefulWidget {
  final OttAppItem app;
  final VoidCallback onTap;

  const _DockAppItem({
    required this.app,
    required this.onTap,
  });

  @override
  State<_DockAppItem> createState() => _DockAppItemState();
}

class _DockAppItemState extends State<_DockAppItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: widget.app.assetPath != null
                ? Image.asset(
                    widget.app.assetPath!,
                    fit: BoxFit.cover,
                  )
                : SvgPicture.string(
                    widget.app.svgSource!,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}
