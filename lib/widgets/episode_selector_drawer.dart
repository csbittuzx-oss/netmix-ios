// lib/widgets/episode_selector_drawer.dart
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/catalog_item.dart';
import '../services/netflix_metadata_service.dart';

/// Callback when an episode is selected inside the player.
typedef OnEpisodeSelectedCallback = void Function(
  int seasonNumber,
  int episodeNumber,
  EpisodeData? episodeData,
);

/// Apple Liquid Glass In-Player Episode Selector Drawer
///
/// Designed with Apple Design standards (iOS 26 Liquid Glass):
/// - In Portrait: Fluid bottom modal sheet with pill handle and continuous superellipse corners.
/// - In Landscape / Fullscreen: Right-docked side panel that slides in with frosted blur,
///   allowing video playback to remain visible on the left.
class EpisodeSelectorDrawer extends StatefulWidget {
  final CatalogItem? catalogItem;
  final String title;
  final int currentSeason;
  final int currentEpisode;
  final List<EpisodeData> initialEpisodes;
  final bool isLandscape;
  final OnEpisodeSelectedCallback onEpisodeSelected;
  final Future<List<EpisodeData>> Function(int seasonNumber)? onFetchSeasonEpisodes;

  const EpisodeSelectorDrawer({
    super.key,
    this.catalogItem,
    required this.title,
    required this.currentSeason,
    required this.currentEpisode,
    required this.initialEpisodes,
    this.isLandscape = false,
    required this.onEpisodeSelected,
    this.onFetchSeasonEpisodes,
  });

  /// Presents the episode selector drawer modally.
  static Future<void> show(
    BuildContext context, {
    required CatalogItem? catalogItem,
    required String title,
    required int currentSeason,
    required int currentEpisode,
    required List<EpisodeData> initialEpisodes,
    bool isLandscape = false,
    required OnEpisodeSelectedCallback onEpisodeSelected,
    Future<List<EpisodeData>> Function(int seasonNumber)? onFetchSeasonEpisodes,
  }) async {
    HapticFeedback.mediumImpact();

    if (isLandscape) {
      // Landscape side drawer
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close Episodes',
        barrierColor: Colors.black.withValues(alpha: 0.35),
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
        transitionBuilder: (ctx, anim, _, child) {
          final slide = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

          return SlideTransition(
            position: slide,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 420,
                height: double.infinity,
                child: EpisodeSelectorDrawer(
                  catalogItem: catalogItem,
                  title: title,
                  currentSeason: currentSeason,
                  currentEpisode: currentEpisode,
                  initialEpisodes: initialEpisodes,
                  isLandscape: true,
                  onEpisodeSelected: (s, e, d) {
                    Navigator.of(ctx).pop();
                    onEpisodeSelected(s, e, d);
                  },
                  onFetchSeasonEpisodes: onFetchSeasonEpisodes,
                ),
              ),
            ),
          );
        },
      );
    } else {
      // Portrait bottom sheet
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        isScrollControlled: true,
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: EpisodeSelectorDrawer(
            catalogItem: catalogItem,
            title: title,
            currentSeason: currentSeason,
            currentEpisode: currentEpisode,
            initialEpisodes: initialEpisodes,
            isLandscape: false,
            onEpisodeSelected: (s, e, d) {
              Navigator.of(ctx).pop();
              onEpisodeSelected(s, e, d);
            },
            onFetchSeasonEpisodes: onFetchSeasonEpisodes,
          ),
        ),
      );
    }
  }

  @override
  State<EpisodeSelectorDrawer> createState() => _EpisodeSelectorDrawerState();
}

class _EpisodeSelectorDrawerState extends State<EpisodeSelectorDrawer> {
  late int _selectedSeason;
  late List<EpisodeData> _episodes;
  bool _isLoadingSeason = false;
  final ScrollController _scrollController = ScrollController();

  List<int> get _availableSeasons {
    if (widget.catalogItem != null && widget.catalogItem!.seasons.isNotEmpty) {
      return widget.catalogItem!.seasons.map((s) => s.number).toList();
    }
    // Fallback: at least show current season
    return [_selectedSeason];
  }

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
    _episodes = List<EpisodeData>.from(widget.initialEpisodes);

    // Auto-scroll to currently playing episode after initial layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
    });
  }

  void _scrollToCurrentEpisode() {
    if (!mounted || _episodes.isEmpty) return;
    final index = _episodes.indexWhere((ep) => ep.number == widget.currentEpisode);
    if (index > 0 && _scrollController.hasClients) {
      final targetOffset = (index * 110.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _changeSeason(int season) async {
    if (_selectedSeason == season || _isLoadingSeason) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSeason = season;
      _isLoadingSeason = true;
    });

    List<EpisodeData> fetched = [];
    try {
      if (widget.onFetchSeasonEpisodes != null) {
        fetched = await widget.onFetchSeasonEpisodes!(season);
      } else if (widget.catalogItem != null) {
        fetched = await NetflixMetadataService.instance.getSeasonEpisodes(
          item: widget.catalogItem!,
          seasonNumber: season,
        );
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _episodes = fetched;
        _isLoadingSeason = false;
      });
      _scrollToCurrentEpisode();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final borderRadius = widget.isLandscape
        ? const BorderRadius.horizontal(left: Radius.circular(28))
        : const BorderRadius.vertical(top: Radius.circular(32));

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE6101018), // Apple Liquid Glass Dark Tint
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 36,
                spreadRadius: -4,
                offset: widget.isLandscape
                    ? const Offset(-10, 0)
                    : const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Pull Indicator (Portrait only)
              if (!widget.isLandscape)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),

              // Header Row: Title & Close Button
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  widget.isLandscape ? 16 : 8,
                  16,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EPISODES',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: Colors.white.withValues(alpha: 0.50),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Apple Liquid Glass Circular Close Button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 15,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Season Selector Pills (if multiple seasons exist)
              if (_availableSeasons.length > 1) ...[
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _availableSeasons.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final seasonNum = _availableSeasons[index];
                      final isSelected = seasonNum == _selectedSeason;
                      return GestureDetector(
                        onTap: () => _changeSeason(seasonNum),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.55)
                                  : Colors.white.withValues(alpha: 0.12),
                              width: 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Season $seasonNum',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],

              const Divider(color: Colors.white12, height: 1),

              // Episodes List
              Expanded(
                child: _isLoadingSeason
                    ? const Center(
                        child: CupertinoActivityIndicator(
                          color: Colors.white,
                          radius: 12,
                        ),
                      )
                    : _episodes.isEmpty
                        ? Center(
                            child: Text(
                              'No episodes available for Season $_selectedSeason',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white60,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              bottomInset + 16,
                            ),
                            itemCount: _episodes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final ep = _episodes[index];
                              final isCurrent =
                                  _selectedSeason == widget.currentSeason &&
                                      ep.number == widget.currentEpisode;

                              return _EpisodeTile(
                                episode: ep,
                                isCurrent: isCurrent,
                                posterFallback: widget.catalogItem?.poster,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onEpisodeSelected(
                                    _selectedSeason,
                                    ep.number,
                                    ep,
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final EpisodeData episode;
  final bool isCurrent;
  final String? posterFallback;
  final VoidCallback onTap;

  const _EpisodeTile({
    required this.episode,
    required this.isCurrent,
    this.posterFallback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isCurrent
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isCurrent
                ? Colors.white.withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.08),
            width: isCurrent ? 1.4 : 0.8,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with Duration Overlay
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 104,
                height: 62,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    episode.thumbnail != null && episode.thumbnail!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: episode.thumbnail!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _posterFallback(),
                          )
                        : _posterFallback(),
                    // Dark gradient overlay
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xB3000000)],
                          stops: [0.5, 1.0],
                        ),
                      ),
                    ),
                    // Playing Icon overlay if current (Apple Pure White)
                    if (isCurrent)
                      Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.play_fill,
                            size: 13,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    // Duration badge bottom right
                    if (episode.duration != null && episode.duration!.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            episode.duration!,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Episode Title & Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${episode.number}. ${episode.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'NOW PLAYING',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (episode.overview.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      episode.overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55),
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback() {
    if (posterFallback != null && posterFallback!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: posterFallback!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _filmPlaceholder(),
      );
    }
    return _filmPlaceholder();
  }

  Widget _filmPlaceholder() {
    return Container(
      color: const Color(0xFF1E1E28),
      child: const Icon(
        CupertinoIcons.film,
        color: Colors.white30,
        size: 20,
      ),
    );
  }
}
