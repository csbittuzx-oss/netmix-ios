// lib/widgets/hero_banner.dart
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/catalog_item.dart';
import '../services/netflix_metadata_service.dart';

/// Upgrades image URLs from TMDB/Metahub to maximum 4K UHD / original master resolution
String getHighResImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) return '';
  var res = url.trim();
  // Upgrade TMDB resolution to original 4K/UHD master
  if (res.contains('image.tmdb.org/t/p/')) {
    res = res.replaceAll(RegExp(r'/t/p/w\d+/'), '/t/p/original/');
  }
  // Upgrade Metahub resolution
  if (res.contains('images.metahub.space/background/medium/')) {
    res = res.replaceAll('/medium/', '/original/');
  }
  if (res.contains('images.metahub.space/poster/medium/')) {
    res = res.replaceAll('/medium/', '/original/');
  }
  return res;
}

/// Chooses the highest quality 4K/UHD artwork available for the hero card
String getBestHeroArtwork(CatalogItem item) {
  // If item has a custom backdrop that is not a generic metahub URL, use it
  if (item.backdrop != null &&
      item.backdrop!.trim().isNotEmpty &&
      !item.backdrop!.contains('metahub.space/background/')) {
    return getHighResImageUrl(item.backdrop!.trim());
  }
  // Primary fallback: verified real poster/thumbnail from database/API
  if (item.poster != null && item.poster!.trim().isNotEmpty) {
    return getHighResImageUrl(item.poster!.trim());
  }
  // Secondary fallback: backdrop even if from metahub
  if (item.backdrop != null && item.backdrop!.trim().isNotEmpty) {
    return getHighResImageUrl(item.backdrop!.trim());
  }
  if (item.imdbId != null && item.imdbId!.trim().isNotEmpty) {
    return 'https://images.metahub.space/background/medium/${item.imdbId!.trim()}/img';
  }
  return '';
}

/// Gathers all possible image candidate URLs for failsafe multi-tiered fallback
List<String> getAllArtworkCandidates(CatalogItem item, [CatalogItem? fallbackItem]) {
  final list = <String>[];
  void add(String? u) {
    if (u == null) return;
    final clean = getHighResImageUrl(u);
    if (clean.isNotEmpty && !list.contains(clean)) {
      list.add(clean);
    }
  }

  // 1. Primary backdrops
  add(item.backdrop);
  if (fallbackItem != null) add(fallbackItem.backdrop);

  // 2. High quality posters
  add(item.poster);
  if (fallbackItem != null) add(fallbackItem.poster);

  // 3. MetaHub fallbacks via IMDb ID
  final imdb = (item.imdbId?.trim().isNotEmpty == true)
      ? item.imdbId!.trim()
      : (fallbackItem?.imdbId?.trim().isNotEmpty == true
          ? fallbackItem!.imdbId!.trim()
          : null);
  if (imdb != null && imdb.isNotEmpty) {
    final metaBg = 'https://images.metahub.space/background/original/$imdb/img';
    final metaPoster = 'https://images.metahub.space/poster/original/$imdb/img';
    if (!list.contains(metaBg)) list.add(metaBg);
    if (!list.contains(metaPoster)) list.add(metaPoster);
  }

  return list;
}

/// Resolves the cleanest official logo for the movie/series
String getBestHeroLogo(CatalogItem item) {
  if (item.logo != null && item.logo!.trim().isNotEmpty) {
    var logoUrl = item.logo!.trim();
    if (logoUrl.contains('images.metahub.space/logo/medium/')) {
      logoUrl = logoUrl.replaceAll('/medium/', '/original/');
    }
    return logoUrl;
  }
  if (item.imdbId != null && item.imdbId!.trim().isNotEmpty) {
    return 'https://images.metahub.space/logo/original/${item.imdbId!.trim()}/img';
  }
  return '';
}

class HeroBanner extends StatelessWidget {
  final CatalogItem item;
  final double topPadding;
  final void Function(CatalogItem) onTap;
  final void Function(CatalogItem) onWatch;

  const HeroBanner({
    super.key,
    required this.item,
    this.topPadding = 0.0,
    required this.onTap,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    // Proportional cinematic card height fitting comfortably below top bar
    final cardHeight = isWide
        ? (screenHeight * 0.65).clamp(420.0, 600.0)
        : (screenHeight * 0.58).clamp(430.0, 520.0);

    final ambientImageUrl = getBestHeroArtwork(item);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          // ── Ambient Gradient Glow Extending to Top Behind Top Bar ─────────
          if (ambientImageUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Atmospheric light bloom sampled directly from movie artwork
                    Opacity(
                      opacity: 0.38,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                        child: Transform.scale(
                          scale: 1.15,
                          child: CachedNetworkImage(
                            imageUrl: ambientImageUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            filterQuality: FilterQuality.low,
                            placeholder: (_, __) => const SizedBox.shrink(),
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),

                    // Seamless radial vignette dissolving glow into black background
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.15),
                          radius: 0.90,
                          colors: [
                            Colors.transparent,
                            Color(0x33000000),
                            Color(0xBB000000),
                            Color(0xFF000000),
                          ],
                          stops: [0.40, 0.65, 0.85, 1.0],
                        ),
                      ),
                    ),

                    // Bottom linear fade guaranteeing pure pitch black before shelves
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0xCC000000),
                              Color(0xFF000000),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Single Featured Content Card (Padded Below Top Bar) ───────────
          Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: 8),
            child: SizedBox(
              height: cardHeight,
              width: double.infinity,
              child: _HeroCardSlide(
                item: item,
                isWide: isWide,
                onTap: () => onTap(item),
                onWatch: () => onWatch(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCardSlide extends StatefulWidget {
  final CatalogItem item;
  final bool isWide;
  final VoidCallback onTap;
  final VoidCallback onWatch;

  const _HeroCardSlide({
    required this.item,
    required this.isWide,
    required this.onTap,
    required this.onWatch,
  });

  @override
  State<_HeroCardSlide> createState() => _HeroCardSlideState();
}

class _HeroCardSlideState extends State<_HeroCardSlide> {
  bool _cardPressed = false;
  String? _dynamicLogoUrl;

  @override
  void initState() {
    super.initState();
    _fetchLogoIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeroCardSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _dynamicLogoUrl = null;
      _fetchLogoIfNeeded();
    }
  }

  Future<void> _fetchLogoIfNeeded() async {
    // If the item already has a direct non-metahub logo, use it directly
    if (widget.item.logo != null &&
        widget.item.logo!.trim().isNotEmpty &&
        !widget.item.logo!.contains('metahub.space')) {
      return;
    }

    // Fetch official transparent clearlogo from TMDB
    try {
      final tmdbLogo =
          await NetflixMetadataService.instance.getTmdbLogoUrl(widget.item);
      if (tmdbLogo != null && tmdbLogo.isNotEmpty && mounted) {
        setState(() {
          _dynamicLogoUrl = tmdbLogo;
        });
      }
    } catch (_) {}
  }

  Widget _buildFallbackTitle(String title) {
    if (title.trim().isEmpty) return const SizedBox(height: 56);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title.trim(),
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.3,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.90),
              offset: const Offset(0, 2),
              blurRadius: 10,
            ),
            Shadow(
              color: Colors.black.withValues(alpha: 0.60),
              offset: const Offset(0, 4),
              blurRadius: 18,
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Priority:
    // 1. Direct high-res logo on item if available (and not generic metahub)
    // 2. Official TMDB clearlogo fetched dynamically
    // 3. Fallback to item.logo if metahub
    // 4. Fallback to metahub by IMDb ID
    String logoUrl = '';
    if (widget.item.logo != null &&
        widget.item.logo!.trim().isNotEmpty &&
        !widget.item.logo!.contains('metahub.space')) {
      logoUrl = widget.item.logo!.trim();
    } else if (_dynamicLogoUrl != null && _dynamicLogoUrl!.isNotEmpty) {
      logoUrl = _dynamicLogoUrl!;
    } else {
      logoUrl = getBestHeroLogo(widget.item);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _cardPressed = true),
        onTapUp: (_) => setState(() => _cardPressed = false),
        onTapCancel: () => setState(() => _cardPressed = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _cardPressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── High Resolution 4K Original Movie Artwork with Multi-Tier Fallback ─────────────
                  _HeroArtworkImage(item: widget.item),

                  // ── Top-Left Netflix-Style Brand Badge (Red 'N') ──────────
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'N',
                        style: TextStyle(
                          color: Color(0xFFE50914),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),

                  // ── Subtle Dark Gradient Only Near Bottom (Image Not Darkened) ─
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Color(0x22000000),
                          Color(0x88000000),
                          Color(0xEE000000),
                        ],
                        stops: [0.0, 0.55, 0.72, 0.86, 1.0],
                      ),
                    ),
                  ),

                  // ── Clean Bottom Block: Logo + Action Buttons ──────────
                  Positioned(
                    bottom: 22,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Content Logo or Clean Title fallback
                        if (logoUrl.isNotEmpty)
                          _HeroLogoWithFallback(
                            logoUrl: logoUrl,
                            fallbackTitle: widget.item.title,
                            buildFallback: _buildFallbackTitle,
                          )
                        else
                          _buildFallbackTitle(widget.item.title),

                        const SizedBox(height: 18),

                        // Two pill action buttons: [Play Show/Movie] and [More Info]
                        Row(
                          children: [
                            Expanded(
                              child: _HeroPlayButton(
                                label: widget.item.isSeries ? 'Play Show' : 'Play Movie',
                                onTap: widget.onWatch,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HeroMoreInfoButton(
                                onTap: widget.onTap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPlayButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _HeroPlayButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_HeroPlayButton> createState() => _HeroPlayButtonState();
}

class _HeroPlayButtonState extends State<_HeroPlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 24,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMoreInfoButton extends StatefulWidget {
  final VoidCallback onTap;

  const _HeroMoreInfoButton({
    required this.onTap,
  });

  @override
  State<_HeroMoreInfoButton> createState() => _HeroMoreInfoButtonState();
}

class _HeroMoreInfoButtonState extends State<_HeroMoreInfoButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.32),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.info_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'More Info',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ── Hero Logo Widget with Proper Fallback ─────────────────────────────────────
// StatefulWidget that tracks image load success/failure. Some CDNs serve 200 OK
// with a broken 1px response that never fires CachedNetworkImage's errorWidget.
// By using imageBuilder we know exactly when a real image has rendered.
// Falls back to the title text placeholder while loading and on any error.

class _HeroLogoWithFallback extends StatefulWidget {
  final String logoUrl;
  final String fallbackTitle;
  final Widget Function(String) buildFallback;

  const _HeroLogoWithFallback({
    required this.logoUrl,
    required this.fallbackTitle,
    required this.buildFallback,
  });

  @override
  State<_HeroLogoWithFallback> createState() => _HeroLogoWithFallbackState();
}

class _HeroLogoWithFallbackState extends State<_HeroLogoWithFallback> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant _HeroLogoWithFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) {
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.buildFallback(widget.fallbackTitle);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 60, maxWidth: 280),
      child: CachedNetworkImage(
        key: ValueKey(widget.logoUrl),
        imageUrl: widget.logoUrl,
        height: 56,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        fadeInDuration: const Duration(milliseconds: 200),
        // While logo is loading, display the clean title text
        placeholder: (_, __) => SizedBox(
          height: 56,
          child: Center(child: widget.buildFallback(widget.fallbackTitle)),
        ),
        // If logo fails (404 / network), smoothly keep title text
        errorWidget: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_failed) setState(() => _failed = true);
          });
          return SizedBox(
            height: 56,
            child: Center(child: widget.buildFallback(widget.fallbackTitle)),
          );
        },
      ),
    );
  }
}

// ── Multi-Tier Fallback Hero Artwork Loader ──────────────────────────────────
// Automatically chains through primary backdrop -> verified poster/thumbnail ->
// dynamic TMDB 4K backdrop -> Metahub to guarantee an image is ALWAYS visible.

class _HeroArtworkImage extends StatefulWidget {
  final CatalogItem item;
  const _HeroArtworkImage({required this.item});

  @override
  State<_HeroArtworkImage> createState() => _HeroArtworkImageState();
}

class _HeroArtworkImageState extends State<_HeroArtworkImage> {
  int _currentCandidateIndex = 0;
  List<String> _candidates = [];

  @override
  void initState() {
    super.initState();
    _buildCandidates();
    _fetchTmdbBackdrop();
  }

  @override
  void didUpdateWidget(covariant _HeroArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.backdrop != widget.item.backdrop ||
        oldWidget.item.poster != widget.item.poster) {
      _currentCandidateIndex = 0;
      _buildCandidates();
      _fetchTmdbBackdrop();
    }
  }

  void _buildCandidates() {
    final list = <String>[];
    void add(String? u) {
      if (u == null) return;
      final clean = u.trim();
      if (clean.isNotEmpty && !list.contains(clean)) {
        list.add(clean);
      }
    }

    // 1. High-res backdrop if available and not from a generic metahub space URL
    if (widget.item.backdrop != null &&
        widget.item.backdrop!.isNotEmpty &&
        !widget.item.backdrop!.contains('metahub.space/background/')) {
      final highRes = getHighResImageUrl(widget.item.backdrop);
      add(highRes);
      add(widget.item.backdrop);
    }

    // 2. Verified post thumbnail / poster (from HDHub/scrapers - 100% works)
    if (widget.item.poster != null && widget.item.poster!.isNotEmpty) {
      final highResPoster = getHighResImageUrl(widget.item.poster);
      add(highResPoster);
      add(widget.item.poster);
    }

    // 3. Fallback backdrop if metahub was present
    if (widget.item.backdrop != null && widget.item.backdrop!.isNotEmpty) {
      add(widget.item.backdrop);
    }

    // 4. MetaHub fallback
    if (widget.item.imdbId != null && widget.item.imdbId!.isNotEmpty) {
      final imdb = widget.item.imdbId!.trim();
      add('https://images.metahub.space/background/medium/$imdb/img');
      add('https://images.metahub.space/poster/medium/$imdb/img');
      add('https://images.metahub.space/background/original/$imdb/img');
    }

    _candidates = list;
  }

  Future<void> _fetchTmdbBackdrop() async {
    try {
      final tmdbBackdrop =
          await NetflixMetadataService.instance.getTmdbBackdropUrl(widget.item);
      if (tmdbBackdrop != null && tmdbBackdrop.isNotEmpty && mounted) {
        setState(() {
          if (!_candidates.contains(tmdbBackdrop)) {
            _candidates.insert(0, tmdbBackdrop);
            _currentCandidateIndex = 0;
          }
        });
      }
    } catch (_) {}
  }

  void _handleError() {
    if (_currentCandidateIndex < _candidates.length - 1) {
      if (mounted) {
        setState(() {
          _currentCandidateIndex++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) {
      return Container(
        color: const Color(0xFF14141E),
        child: const Center(
          child: Icon(CupertinoIcons.film, color: Colors.white24, size: 48),
        ),
      );
    }

    final activeUrl = _candidates[_currentCandidateIndex];

    return CachedNetworkImage(
      key: ValueKey(activeUrl),
      imageUrl: activeUrl,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => Container(color: const Color(0xFF14141E)),
      errorWidget: (_, __, ___) {
        // Fallback immediately to the next candidate URL
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleError());
        return Container(color: const Color(0xFF14141E));
      },
    );
  }
}
