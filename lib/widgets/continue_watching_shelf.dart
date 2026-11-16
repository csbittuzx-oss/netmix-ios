// lib/widgets/continue_watching_shelf.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/watch_progress_service.dart';

class ContinueWatchingShelf extends StatefulWidget {
  final List<WatchProgressItem> items;
  final ValueChanged<WatchProgressItem> onItemTap;

  const ContinueWatchingShelf({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  @override
  State<ContinueWatchingShelf> createState() => _ContinueWatchingShelfState();
}

class _ContinueWatchingShelfState extends State<ContinueWatchingShelf> {
  final Set<String> _disintegratingIds = {};

  void _startDisintegration(WatchProgressItem item) {
    HapticFeedback.mediumImpact();
    setState(() {
      _disintegratingIds.add(item.contentId);
    });
  }

  Future<void> _handleDisintegrationComplete(WatchProgressItem item) async {
    final userId = AuthService.instance.currentUser.id;
    await WatchProgressService.instance.removeProgress(userId, item.contentId);
    if (mounted) {
      setState(() {
        _disintegratingIds.remove(item.contentId);
      });
    }
  }

  void _showRemoveOption(BuildContext context, WatchProgressItem item) {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xE814141E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.60),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Apple-style drag handle
                    Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Content preview item
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 52,
                            height: 74,
                            color: const Color(0xFF1E1E28),
                            child: item.poster != null && item.poster!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.poster!,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(
                                    CupertinoIcons.film,
                                    color: Colors.white54,
                                    size: 26,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (item.subtitleLabel.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  item.subtitleLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 5),
                              Text(
                                '${((item.progressFraction) * 100).toInt()}% watched',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFE50914),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // Remove from Continue Watching Action Button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _startDisintegration(item);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.40),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              CupertinoIcons.trash_fill,
                              color: Color(0xFFFF453A),
                              size: 19,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Remove from Continue Watching',
                              style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFF453A),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Cancel Button
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.80),
                            ),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clean Apple Header without numbers
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Continue Watching',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.items.length,
            separatorBuilder: (_, index) {
              final isCurrentDisintegrating =
                  _disintegratingIds.contains(widget.items[index].contentId);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: isCurrentDisintegrating ? 0 : 12,
              );
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _ContinueWatchingCard(
                key: ValueKey(item.contentId),
                item: item,
                isDisintegrating: _disintegratingIds.contains(item.contentId),
                onTap: () => widget.onItemTap(item),
                onLongHold: () => _showRemoveOption(context, item),
                onDisintegrationComplete: () =>
                    _handleDisintegrationComplete(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Continue Watching Card with 2-Second Hold & Dust Disintegration Animation ─

class _ContinueWatchingCard extends StatefulWidget {
  final WatchProgressItem item;
  final bool isDisintegrating;
  final VoidCallback onTap;
  final VoidCallback onLongHold;
  final VoidCallback onDisintegrationComplete;

  const _ContinueWatchingCard({
    super.key,
    required this.item,
    required this.isDisintegrating,
    required this.onTap,
    required this.onLongHold,
    required this.onDisintegrationComplete,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard>
    with SingleTickerProviderStateMixin {
  Timer? _holdTimer;
  bool _isHolding = false;
  late AnimationController _dustController;
  final List<_DustParticle> _particles = [];

  static const double cardWidth = 120.0;
  static const double cardHeight = 175.0;

  @override
  void initState() {
    super.initState();
    _dustController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _dustController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDisintegrationComplete();
      }
    });

    if (widget.isDisintegrating) {
      _startDustEffect();
    }
  }

  @override
  void didUpdateWidget(covariant _ContinueWatchingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDisintegrating && !oldWidget.isDisintegrating) {
      _startDustEffect();
    }
  }

  void _startDustEffect() {
    _initParticles();
    _dustController.forward(from: 0.0);
  }

  void _initParticles() {
    _particles.clear();
    final random = math.Random();
    const count = 110;

    // Palette of ash, embers, and highlight colors
    const colors = [
      Color(0xFFFFFFFF),
      Color(0xFFE50914),
      Color(0xFFFF453A),
      Color(0xFFE0E0E8),
      Color(0xFFB0B0C0),
      Color(0xFF8E8E98),
      Color(0xFFFF9500),
    ];

    for (int i = 0; i < count; i++) {
      final x = random.nextDouble() * cardWidth;
      final y = random.nextDouble() * cardHeight;
      final vx = (random.nextDouble() - 0.5) * 160.0; // horizontal scatter
      final vy = -60.0 - random.nextDouble() * 200.0; // upward draft like ash
      final size = 1.6 + random.nextDouble() * 2.8;
      final color = colors[random.nextInt(colors.length)];
      final phase = random.nextDouble() * math.pi * 2;

      _particles.add(_DustParticle(
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        size: size,
        color: color,
        phase: phase,
      ));
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.isDisintegrating) return;
    setState(() => _isHolding = true);

    // 2-second press detection matching user's exact specification
    _holdTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _isHolding = false);
      widget.onLongHold();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_isHolding && mounted) {
      setState(() => _isHolding = false);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _dustController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dustController,
      builder: (context, child) {
        final t = _dustController.value;

        // In the second half of disintegration, collapse card width smoothly to 0
        final widthFactor = t > 0.35
            ? Curves.easeInOutCubic.transform(
                (1.0 - (t - 0.35) / 0.65).clamp(0.0, 1.0))
            : 1.0;
        final currentWidth = cardWidth * widthFactor;

        if (currentWidth <= 0.0) return const SizedBox.shrink();

        // Card opacity fades out quickly during initial dust burst
        final cardOpacity = (1.0 - t * 2.4).clamp(0.0, 1.0);
        final blurSigma = t * 14.0;

        return SizedBox(
          width: currentWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The main card with hold scale animation & disintegration fade
              if (cardOpacity > 0.0)
                AnimatedScale(
                  scale: _isHolding ? 0.94 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: Opacity(
                    opacity: cardOpacity,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _onTapDown,
                        onTapUp: (_) => _cancelHold(),
                        onTapCancel: _cancelHold,
                        onLongPress: () {
                          _cancelHold();
                          widget.onLongHold();
                        },
                        onTap: () {
                          _cancelHold();
                          if (!widget.isDisintegrating) {
                            widget.onTap();
                          }
                        },
                        child: _buildCardContent(),
                      ),
                    ),
                  ),
                ),

              // The Dust Particles Burst Layer
              if (t > 0.0 && t < 1.0)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DustParticlePainter(
                      progress: t,
                      particles: _particles,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardContent() {
    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster with progress bar overlay
          Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHolding
                    ? const Color(0xFFE50914).withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.12),
                width: _isHolding ? 1.4 : 0.75,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHolding
                      ? const Color(0xFFE50914).withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.4),
                  blurRadius: _isHolding ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster Image
                  if (widget.item.poster != null &&
                      widget.item.poster!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: widget.item.poster!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF181822),
                      ),
                      errorWidget: (_, __, ___) =>
                          _buildFallback(cardWidth, cardHeight),
                    )
                  else
                    _buildFallback(cardWidth, cardHeight),

                  // Bottom dark gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.88),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Play Center Icon
                  Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),

                  // Progress bar at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: widget.item.progressFraction,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFE50914),
                      ),
                      minHeight: 3.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Content Title
          Text(
            widget.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              decoration: TextDecoration.none,
            ),
          ),

          // Subtitle / Remaining progress
          if (widget.item.subtitleLabel.isNotEmpty)
            Text(
              widget.item.subtitleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.6),
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF181822),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: Colors.white.withValues(alpha: 0.3),
          size: 32,
        ),
      ),
    );
  }
}

// ── Particle Data Model for Dust Disintegration Effect ────────────────────────

class _DustParticle {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double phase;

  _DustParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.phase,
  });
}

// ── Custom Painter Rendering Dissolving Dust / Ash Particles ─────────────────

class _DustParticlePainter extends CustomPainter {
  final double progress;
  final List<_DustParticle> particles;

  _DustParticlePainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final paint = Paint()..isAntiAlias = true;

    for (final p in particles) {
      // Swirling aerodynamic draft
      final curX = p.x + p.vx * progress + math.sin(progress * 8.0 + p.phase) * 14.0;
      final curY = p.y + p.vy * progress;

      // Particle opacity fades out smoothly
      final alpha = (1.0 - progress).clamp(0.0, 1.0);
      final currentSize = (p.size * (1.0 - progress * 0.4)).clamp(0.5, 5.0);

      paint.color = p.color.withValues(alpha: p.color.a * alpha);
      canvas.drawCircle(Offset(curX, curY), currentSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DustParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
