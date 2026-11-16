// lib/screens/details_sheet.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/catalog_item.dart';
import '../models/stream_info.dart';
import '../providers/details_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/home_provider.dart';
import '../providers/streams_provider.dart';
import '../services/auth_service.dart';
import '../services/netflix_metadata_service.dart';
import '../services/watch_progress_service.dart';
import '../widgets/hero_banner.dart';
import '../widgets/poster_card.dart';

class DetailsSheet extends ConsumerStatefulWidget {
  final CatalogItem item;
  const DetailsSheet({super.key, required this.item});

  @override
  ConsumerState<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<DetailsSheet> {
  final ScrollController _scrollController = ScrollController();
  int _selectedSeasonIdx = 0;
  int? _lastLoadedSeasonNum;
  bool _hasLoadedBackendDetails = false;

  // Metadata & UI State
  bool _isDescriptionExpanded = false;

  // Metadata & Episode Data
  TmdbContentData? _tmdbData;
  List<EpisodeData> _episodes = [];
  Map<int, double> _episodesProgress = {};
  bool _isLoadingEpisodes = false;
  WatchProgressItem? _savedProgress;

  DateTime? _lastNavTapTime;

  @override
  void initState() {
    super.initState();
    _checkSavedProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(detailsProvider(widget.item.id).notifier).load(widget.item);
      _initMetadataAndTrailer();
    });
  }

  Future<void> _checkSavedProgress() async {
    try {
      final userId = AuthService.instance.currentUser.id;
      final p = await WatchProgressService.instance
          .getProgress(userId, widget.item.id);
      if (mounted) {
        setState(() => _savedProgress = p);
        // Pre-warm the user's active resume episode for instant zero-wait startup
        if (p != null && widget.item.isSeries) {
          final targetSeason = p.season > 0 ? p.season : 1;
          final targetEpisode = p.episode > 0 ? p.episode : 1;
          final resumeKey = StreamsKey(
            id: widget.item.id,
            permalink: widget.item.permalink,
            isSeries: true,
            season: targetSeason,
            episode: targetEpisode,
          );
          ref.read(streamsProvider(resumeKey).notifier).load(
            id: widget.item.id,
            permalink: widget.item.permalink,
            isSeries: true,
            season: targetSeason,
            episode: targetEpisode,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchEpisodesProgress(int seasonNum, List<EpisodeData> eps) async {
    try {
      final userId = AuthService.instance.currentUser.id;
      final prog = await WatchProgressService.instance.getSeasonEpisodesProgress(
        userId: userId,
        contentId: widget.item.id,
        season: seasonNum,
        episodeNumbers: eps.map((e) => e.number).toList(),
      );
      if (mounted) {
        setState(() => _episodesProgress = prog);
      }
    } catch (_) {}
  }

  int? _detectSeasonNumber(CatalogItem item) {
    if (item.seasons.isNotEmpty) {
      final firstNum = item.seasons.first.number;
      if (firstNum > 1) return firstNum;
    }
    final text = '${item.title} ${item.permalink}';
    final match = RegExp(r'(?:season|s)[\s._-]*(\d+)', caseSensitive: false)
        .firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    if (item.seasons.isNotEmpty) {
      return item.seasons.first.number;
    }
    return null;
  }

  /// Strictly return only seasons that are available on the backend streaming server
  List<Season> _resolveAvailableSeasons(CatalogItem item) {
    if (item.seasons.isNotEmpty) {
      return item.seasons;
    }
    final detected = _detectSeasonNumber(item) ?? 1;
    return [Season(number: detected, title: 'Season $detected')];
  }

  Future<void> _initMetadataAndTrailer() async {
    if (_savedProgress == null) {
      await _checkSavedProgress();
    }
    final initialSeasonNum = (_savedProgress != null && _savedProgress!.isSeries)
        ? _savedProgress!.season
        : (_detectSeasonNumber(widget.item) ?? 1);

    // 1. Fetch rich metadata (runtime, certification, cast, director, trailerKey)
    final metadata =
        await NetflixMetadataService.instance.getContentMetadata(widget.item);
    if (!mounted) return;
    setState(() {
      _tmdbData = metadata;
    });

    // 2. If it's a TV series or anime, resolve target season index and fetch episodes
    final resolvedNow = ref.read(detailsProvider(widget.item.id)).details ?? widget.item;
    final waitForServerSeasons = (widget.item.id.startsWith('4kott_') || widget.item.isAnimeContent) &&
        (widget.item.isSeries || widget.item.isAnimeContent) &&
        resolvedNow.seasons.isEmpty;

    if (widget.item.isSeries || widget.item.isAnimeContent) {
      if (waitForServerSeasons) {
        if (mounted) {
          setState(() => _isLoadingEpisodes = true);
        }
      } else {
        final seasons = _resolveAvailableSeasons(resolvedNow);
        int targetIdx = seasons.indexWhere((s) => s.number == initialSeasonNum);
        if (targetIdx == -1) targetIdx = 0;
        if (mounted) {
          setState(() => _selectedSeasonIdx = targetIdx);
        }
        final seasonToLoad =
            seasons.isNotEmpty ? seasons[targetIdx].number : initialSeasonNum;
        _loadSeasonEpisodes(seasonToLoad, itemOverride: resolvedNow);
      }
    }

    // Pre-warm streams provider for instant playback response (skip premature pre-warm while waiting on server seasons)
    if (!waitForServerSeasons) {
      final resolvedItem = resolvedNow;
      final streamKey = StreamsKey(
        id: resolvedItem.id,
        permalink: resolvedItem.permalink,
        isSeries: widget.item.isSeries || widget.item.isAnimeContent,
        season: initialSeasonNum,
        episode: 1,
      );
      ref.read(streamsProvider(streamKey).notifier).load(
        id: resolvedItem.id,
        permalink: resolvedItem.permalink,
        isSeries: widget.item.isSeries || widget.item.isAnimeContent,
        season: initialSeasonNum,
        episode: 1,
        title: resolvedItem.title,
      );
    }
  }

  Future<void> _loadSeasonEpisodes(int seasonNum,
      {CatalogItem? itemOverride}) async {
    setState(() => _isLoadingEpisodes = true);
    _lastLoadedSeasonNum = seasonNum;
    final detailsState = ref.read(detailsProvider(widget.item.id));
    final currentItem = itemOverride ?? detailsState.details ?? widget.item;

    final eps = await NetflixMetadataService.instance.getSeasonEpisodes(
      item: currentItem,
      seasonNumber: seasonNum,
    );
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _isLoadingEpisodes = false;
    });
    _fetchEpisodesProgress(seasonNum, eps);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  void _openRelated(CatalogItem relatedItem) {
    final now = DateTime.now();
    if (_lastNavTapTime != null &&
        now.difference(_lastNavTapTime!).inMilliseconds < 450) {
      return;
    }
    _lastNavTapTime = now;
    context.push('/details', extra: relatedItem);
  }

  // ── Download Quality Selection Modal Sheet ─────────────────────────────────

  void _openDownloadQualitySheet(
    CatalogItem item,
    Season activeSeason, {
    EpisodeData? episode,
    int? seasonNum,
  }) {
    HapticFeedback.lightImpact();
    final detailsState = ref.read(detailsProvider(widget.item.id));
    final resolvedItem = (detailsState.details != null &&
            detailsState.details!.permalink.isNotEmpty &&
            !detailsState.details!.permalink.contains('/title/'))
        ? detailsState.details!
        : item;

    final isSeries = resolvedItem.isSeries;
    final targetSeason = isSeries
        ? (seasonNum ??
            (activeSeason.number > 0 ? activeSeason.number : 1))
        : 1;
    final targetEpisode = isSeries
        ? (episode?.number ??
            (activeSeason.episodes.isNotEmpty
                ? activeSeason.episodes.first.number
                : 1))
        : 1;

    final streamKey = StreamsKey(
      id: resolvedItem.id,
      permalink: resolvedItem.permalink,
      isSeries: isSeries,
      season: targetSeason,
      episode: targetEpisode,
    );

    // Warm up / ensure streams are being fetched
    ref.read(streamsProvider(streamKey).notifier).load(
          id: resolvedItem.id,
          permalink: resolvedItem.permalink,
          isSeries: isSeries,
          season: targetSeason,
          episode: targetEpisode,
          title: resolvedItem.title,
        );

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => _AppleDownloadQualityModal(
        item: resolvedItem,
        streamKey: streamKey,
        isSeries: isSeries,
        seasonNumber: targetSeason,
        episodeNumber: targetEpisode,
        episodeTitle: episode?.title,
        posterUrl: episode?.thumbnail ?? resolvedItem.poster,
      ),
    );
  }

  // ── Playback Logic ─────────────────────────────────────────────────────────

  Future<void> _watchEpisode(CatalogItem item, int season, int episode) async {
    Duration startPos = Duration.zero;
    try {
      if (_savedProgress != null &&
          _savedProgress!.season == season &&
          _savedProgress!.episode == episode &&
          !_savedProgress!.isCompleted &&
          _savedProgress!.positionMs >= 5000) {
        startPos = Duration(milliseconds: _savedProgress!.positionMs);
      } else {
        final prefs = await SharedPreferences.getInstance();
        final userId = AuthService.instance.currentUser.id;
        final epKey = 'netmix_ep_prog_${userId}_${item.id}_s${season}e$episode';
        final raw = prefs.getString(epKey);
        if (raw != null && raw.isNotEmpty) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final pos = (data['pos'] as num?)?.toInt() ?? 0;
          final dur = (data['dur'] as num?)?.toInt() ?? 0;
          if (pos >= 5000 && (dur <= 0 || (pos / dur) < 0.95)) {
            startPos = Duration(milliseconds: pos);
          }
        }
      }
    } catch (_) {}

    _navigateToPlayer(
      item: item,
      isSeries: true,
      season: season,
      episode: episode,
      subtitle: 'S${season}E$episode',
      startPosition: startPos,
    );
  }

  void _watchFirstAvailable(CatalogItem item, Season activeSeason) {
    if (item.isSeries) {
      final epNum = activeSeason.episodes.isNotEmpty
          ? activeSeason.episodes.first.number
          : (_episodes.isNotEmpty ? _episodes.first.number : 1);
      _watchEpisode(item, activeSeason.number, epNum);
    } else {
      Duration moviePos = Duration.zero;
      if (_savedProgress != null &&
          !_savedProgress!.isCompleted &&
          _savedProgress!.positionMs >= 5000) {
        moviePos = Duration(milliseconds: _savedProgress!.positionMs);
      }
      _navigateToPlayer(
        item: item,
        isSeries: false,
        season: 1,
        episode: 1,
        subtitle: item.year ?? '',
        startPosition: moviePos,
      );
    }
  }

  Future<void> _navigateToPlayer({
    required CatalogItem item,
    required bool isSeries,
    required int season,
    required int episode,
    required String subtitle,
    Duration startPosition = Duration.zero,
  }) async {
    final detailsState = ref.read(detailsProvider(widget.item.id));
    final resolvedItem = (detailsState.details != null &&
            detailsState.details!.permalink.isNotEmpty &&
            !detailsState.details!.permalink.contains('/title/'))
        ? detailsState.details!
        : item;

    final key = StreamsKey(
      id: resolvedItem.id,
      permalink: resolvedItem.permalink,
      isSeries: isSeries,
      season: season,
      episode: episode,
    );
    final cached = ref.read(streamsProvider(key));

    await context.push('/player', extra: {
      'streams': cached.streams,
      'title': resolvedItem.title,
      'subtitle': subtitle,
      'startPosition': startPosition,
      'itemId': isSeries ? '${resolvedItem.id}_s${season}e$episode' : resolvedItem.id,
      'contentId': resolvedItem.id,
      'permalink': resolvedItem.permalink,
      'poster': resolvedItem.poster,
      'backdrop': resolvedItem.backdrop,
      'isSeries': isSeries,
      'season': season,
      'episode': episode,
      'catalogItem': resolvedItem,
      'episodes': _episodes,
    });

    await _checkSavedProgress();
    if (_episodes.isNotEmpty) {
      await _fetchEpisodesProgress(season, _episodes);
    }
  }

  void _resumePlayback(CatalogItem item, WatchProgressItem progress) {
    _navigateToPlayer(
      item: item,
      isSeries: progress.isSeries,
      season: progress.season,
      episode: progress.episode,
      subtitle: progress.isSeries
          ? 'S${progress.season}E${progress.episode}'
          : (item.year ?? ''),
      startPosition: Duration(milliseconds: progress.positionMs),
    );
  }

  // ── More Like This Builder ─────────────────────────────────────────────────

  List<CatalogItem> _buildRelatedItems(
      HomeState homeState, CatalogItem currentItem) {
    final data = homeState.data;
    if (data == null) return [];
    final currentGenres = currentItem.genres
        .map((g) => g.trim().toLowerCase())
        .where((g) => g.isNotEmpty)
        .toSet();
    final seenIds = <String>{currentItem.id};
    final matches = <CatalogItem>[];
    final others = <CatalogItem>[];

    for (final shelf in data.shelves) {
      for (final candidate in shelf.items) {
        if (candidate.id.isEmpty || seenIds.contains(candidate.id)) continue;
        seenIds.add(candidate.id);

        final candidateGenres =
            candidate.genres.map((g) => g.trim().toLowerCase()).toSet();
        if (currentGenres.isNotEmpty &&
            candidateGenres.intersection(currentGenres).isNotEmpty) {
          matches.add(candidate);
        } else {
          others.add(candidate);
        }
      }
    }

    final combined = [...matches, ...others];
    return combined.take(15).toList();
  }


  // ── Build Method ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<DetailsState>(detailsProvider(widget.item.id), (previous, next) {
      if (next.details != null && next.details != previous?.details) {
        final seasons = _resolveAvailableSeasons(next.details!);
        int targetIdx = _selectedSeasonIdx;
        if (_savedProgress != null && _savedProgress!.isSeries) {
          final savedIdx = seasons.indexWhere((s) => s.number == _savedProgress!.season);
          if (savedIdx != -1) targetIdx = savedIdx;
        }
        if (targetIdx >= seasons.length) targetIdx = 0;
        if (targetIdx != _selectedSeasonIdx && mounted) {
          setState(() => _selectedSeasonIdx = targetIdx);
        }
        final activeS = seasons.isNotEmpty ? seasons[targetIdx] : null;
        final targetSeason = activeS?.number ?? 1;
        final targetEp = (activeS != null && activeS.episodes.isNotEmpty)
            ? activeS.episodes.first.number
            : 1;

        if (next.details!.isSeries || next.details!.isAnimeContent) {
          _loadSeasonEpisodes(targetSeason, itemOverride: next.details);
        }

        // Pre-warm streams with backend resolved details
        final streamKey = StreamsKey(
          id: next.details!.id,
          permalink: next.details!.permalink,
          isSeries: next.details!.isSeries || next.details!.isAnimeContent,
          season: targetSeason,
          episode: targetEp,
        );
        ref.read(streamsProvider(streamKey).notifier).load(
          id: next.details!.id,
          permalink: next.details!.permalink,
          isSeries: next.details!.isSeries,
          season: targetSeason,
          episode: targetEp,
          title: next.details!.title,
        );
      }
    });

    final detailsState = ref.watch(detailsProvider(widget.item.id));
    final item = detailsState.details ?? widget.item;

    // Reactively update episodes when backend details finish loading
    final availableSeasons = _resolveAvailableSeasons(item);
    final activeSeason = availableSeasons[
        _selectedSeasonIdx.clamp(0, availableSeasons.length - 1)];

    if (item.isSeries &&
        detailsState.details != null &&
        (!_hasLoadedBackendDetails || _lastLoadedSeasonNum != activeSeason.number) &&
        !_isLoadingEpisodes) {
      _hasLoadedBackendDetails = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadSeasonEpisodes(activeSeason.number,
              itemOverride: detailsState.details);
        }
      });
    }

    final homeState = ref.watch(homeProvider);
    final relatedItems = _buildRelatedItems(homeState, item);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth >= 600;

    // Synopsis
    final synopsis = (_tmdbData?.overview.isNotEmpty == true)
        ? _tmdbData!.overview
        : (item.description ?? '');

    // Year
    final year = item.year?.isNotEmpty == true
        ? item.year!
        : (widget.item.year ?? '');

    // Certification badge
    final certification = _tmdbData?.certification ??
        (item.isSeries ? 'TV-14' : 'U/A 13+');

    // Runtime / Duration
    final runtime = _tmdbData?.runtime.isNotEmpty == true
        ? _tmdbData!.runtime
        : (item.isSeries
            ? (availableSeasons.length > 1
                ? '${availableSeasons.length} Seasons'
                : '1 Season')
            : '2h 15m');

    // Cast & Director
    final castList = _tmdbData?.cast.isNotEmpty == true
        ? _tmdbData!.cast
        : const <String>[];
    final director = _tmdbData?.director;

    // Genres string
    final genresList = _tmdbData?.genres.isNotEmpty == true
        ? _tmdbData!.genres
        : item.genres;
    final genresStr = genresList.join(', ');

    // ── TABLET: Elegant Popup Page with Rounded Corners ─────────────────────
    if (isTablet) {
      final popupWidth = (screenWidth * 0.72).clamp(560.0, 780.0);
      final popupHeight = (screenHeight * 0.88).clamp(620.0, 920.0);
      final tabletBannerHeight = (popupWidth * (9.0 / 16.0)).clamp(220.0, 310.0);

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 0.70),
          body: Stack(
            children: [
              // Dismiss on tapping outside barrier
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBack,
                  child: const SizedBox.expand(),
                ),
              ),

              // Centered Floating Popup Card with Rounded Corners
              Center(
                child: Container(
                  width: popupWidth,
                  height: popupHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0C14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.75),
                        blurRadius: 36,
                        spreadRadius: 6,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23.2),
                    child: Column(
                      children: [
                        // Pinned 16:9 Banner Section with Close Button
                        SizedBox(
                          height: tabletBannerHeight,
                          width: popupWidth,
                          child: _buildBannerSection(
                            popupWidth,
                            tabletBannerHeight,
                            item,
                          ),
                        ),

                        // Scrollable Body
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildContentInfo(item, year, certification,
                                    runtime, detailsState.isLoading),
                                _buildActionButtons(item, activeSeason),
                                _buildSynopsisAndCredits(
                                    synopsis,
                                    castList,
                                    director,
                                    genresStr,
                                    detailsState.isLoading,
                                    popupWidth),
                                if (item.isSeries)
                                  _buildEpisodesSection(
                                      item, availableSeasons, activeSeason)
                                else
                                  _buildMoreLikeThisSection(relatedItems),
                                SizedBox(
                                    height:
                                        MediaQuery.of(context).padding.bottom +
                                            24),
                              ],
                            ),
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
      );
    }

    // ── PHONE: Full Screen Scaffold (Preserved Exactly) ──────────────────────
    final phoneBannerHeight = screenWidth * (9.0 / 16.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── 1. Top Content Banner (16:9, Pinned & Always Visible on Scroll) ──
              SizedBox(
                height: phoneBannerHeight,
                width: screenWidth,
                child: _buildBannerSection(
                    screenWidth, phoneBannerHeight, item),
              ),

              // ── 2. Scrollable Details Body ─────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Content Information (Title + Badges)
                      _buildContentInfo(item, year, certification, runtime,
                          detailsState.isLoading),

                      // Main Action Buttons (White Play + Dark Grey Download)
                      _buildActionButtons(item, activeSeason),

                      // Main Content Description / Synopsis & Cast/Director
                      _buildSynopsisAndCredits(synopsis, castList, director,
                          genresStr, detailsState.isLoading, screenWidth),

                      // Series Episodes (Strictly Backend Streaming) or Movie More Like This
                      if (item.isSeries)
                        _buildEpisodesSection(
                            item, availableSeasons, activeSeason)
                      else
                        _buildMoreLikeThisSection(relatedItems),

                      // Bottom Safe Insets Padding
                      SizedBox(
                          height: MediaQuery.of(context).padding.bottom + 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. Original Content Banner Section Widget (Resilient Cascading Fallback) ─

  Widget _buildBannerSection(
      double screenWidth, double bannerHeight, CatalogItem item) {
    final candidateUrls = getAllArtworkCandidates(item, widget.item);

    return Stack(
      children: [
        // Resilient Cascading Banner Image / Poster (Never blank)
        Positioned.fill(
          child: _CascadingBannerImage(
            candidates: candidateUrls,
            title: item.title.isNotEmpty ? item.title : widget.item.title,
          ),
        ),

        // Bottom subtle dark gradient for seamless blend into black background
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 60,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x99000000),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),
        ),

        // Close Button in Apple Liquid Glass Icon Style (Kept exactly where it is)
        Positioned(
          top: 10,
          right: 12,
          child: AppleGlassIconButton(
            icon: CupertinoIcons.xmark,
            size: 34,
            iconSize: 16,
            onTap: _handleBack,
          ),
        ),

        // Watch progress indicator at bottom of content banner (thin red line)
        if (_savedProgress != null && _savedProgress!.progressFraction > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 2.5,
              color: Colors.white.withValues(alpha: 0.18),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _savedProgress!.progressFraction.clamp(0.0, 1.0),
                child: Container(
                  color: const Color(0xFFE50914),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 2. Content Info Widget ─────────────────────────────────────────────────

  Widget _buildContentInfo(CatalogItem item, String year, String certification,
      String runtime, bool isLoading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Content Title - fallback to original widget.item.title if enriched item has none
          Text(
            item.title.isNotEmpty ? item.title : widget.item.title,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 8),

          // Metadata Badges Line
          if (_tmdbData == null && isLoading)
            Shimmer.fromColors(
              baseColor: const Color(0xFF181820),
              highlightColor: const Color(0xFF2C2C38),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 54,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 58,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                if (year.isNotEmpty) ...[
                  Text(
                    year,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Age Certification Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222228),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    certification,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Duration / Series Info
                Text(
                  runtime,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),

                const SizedBox(width: 8),

                // Netflix AD))) (Audio Description) Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2.5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'AD)))',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Subtitles CC Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2.5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'CC',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 3. Main Action Buttons Widget ──────────────────────────────────────────

  Widget _buildActionButtons(CatalogItem item, Season activeSeason) {
    final hasProgress = _savedProgress != null &&
        !_savedProgress!.isCompleted &&
        _savedProgress!.positionMs >= 5000;

    final playLabel = hasProgress
        ? (_savedProgress!.remainingFormatted.isNotEmpty
            ? 'Resume · ${_savedProgress!.remainingFormatted}'
            : 'Resume')
        : 'Play';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          // 1. Large White Play / Resume Button (Apple fluid interaction)
          _AppleFluidButton(
            onPressed: () {
              if (hasProgress) {
                _resumePlayback(item, _savedProgress!);
              } else {
                _watchFirstAvailable(item, activeSeason);
              }
            },
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            icon: CupertinoIcons.play_fill,
            label: playLabel,
          ),

          const SizedBox(height: 8),

          // 2. Large Dark Liquid Glass Download Button
          _AppleFluidButton(
            onPressed: () => _openDownloadQualitySheet(item, activeSeason),
            backgroundColor: const Color(0xFF2B2B2B),
            foregroundColor: Colors.white,
            icon: CupertinoIcons.arrow_down_to_line,
            label: 'Download',
            isGlass: true,
          ),
        ],
      ),
    );
  }

  // ── 4. Synopsis & Credits Widget ───────────────────────────────────────────

  Widget _buildSynopsisAndCredits(String synopsis, List<String> castList,
      String? director, String genresStr, bool isLoading, double screenWidth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Content Description / Synopsis with View More / View Less
          if (synopsis.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final textSpan = TextSpan(
                  text: synopsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                );
                final tp = TextPainter(
                  text: textSpan,
                  maxLines: 3,
                  textDirection: TextDirection.ltr,
                )..layout(maxWidth: constraints.maxWidth);

                final exceedsThreeLines = tp.didExceedMaxLines;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedCrossFade(
                      firstChild: Text(
                        synopsis,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                      secondChild: Text(
                        synopsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                      crossFadeState: _isDescriptionExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 220),
                    ),
                    if (exceedsThreeLines || _isDescriptionExpanded) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isDescriptionExpanded = !_isDescriptionExpanded;
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _isDescriptionExpanded ? 'View Less' : 'View More',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            )
          else if (isLoading)
            Shimmer.fromColors(
              baseColor: const Color(0xFF181820),
              highlightColor: const Color(0xFF282836),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: screenWidth * 0.85,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: screenWidth * 0.60,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Cast, Director, Genres Lines
          if (castList.isNotEmpty) ...[
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Cast: ',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  TextSpan(
                    text: '${castList.join(", ")} ... more',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],

          if (director != null && director.isNotEmpty) ...[
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Director: ',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  TextSpan(
                    text: director,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],

          if (genresStr.isNotEmpty) ...[
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Genres: ',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  TextSpan(
                    text: genresStr,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 5. Series Episodes Section Widget (Strictly Backend Streaming) ─────────

  Widget _buildEpisodesSection(
      CatalogItem item, List<Season> availableSeasons, Season activeSeason) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Episodes Header
          Text(
            'Episodes',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 8),

          // Season Selector Dropdown in Apple Liquid Glass Style
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showSeasonPicker(availableSeasons),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 0.75,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            activeSeason.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            CupertinoIcons.chevron_down,
                            color: Colors.white,
                            size: 13,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const AppleGlassIconButton(
                icon: CupertinoIcons.info_circle,
                size: 32,
                iconSize: 18,
              ),
            ],
          ),

          // Tightened spacing between season selector and first episode
          const SizedBox(height: 10),

          // Episode List / Shimmer Skeleton
          if (_isLoadingEpisodes)
            _buildEpisodesSkeleton()
          else
            Builder(
              builder: (context) {
                // Strictly bound episodes to backend streaming catalog
                final backendEpNums = activeSeason.episodes.isNotEmpty
                    ? activeSeason.episodes.map((e) => e.number).toSet()
                    : null;

                final displayEpisodes = _episodes.where((ep) {
                  if (backendEpNums != null &&
                      !backendEpNums.contains(ep.number)) {
                    return false;
                  }
                  final upper = ep.title.trim().toUpperCase();
                  if (upper == 'TBD' ||
                      upper.startsWith('TBD ') ||
                      upper == 'TBA') {
                    return false;
                  }
                  return true;
                }).toList();

                if (displayEpisodes.isNotEmpty) {
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayEpisodes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      final ep = displayEpisodes[i];
                      return _NetflixEpisodeTile(
                        episode: ep,
                        parentItem: item,
                        watchProgress: _episodesProgress[ep.number] ?? 0.0,
                        onWatch: () => _watchEpisode(
                            item, activeSeason.number, ep.number),
                        onDownload: () => _openDownloadQualitySheet(
                          item,
                          activeSeason,
                          episode: ep,
                          seasonNum: activeSeason.number,
                        ),
                      );
                    },
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No episodes available.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── 6. Movies More Like This Section Widget ────────────────────────────────

  Widget _buildMoreLikeThisSection(List<CatalogItem> relatedItems) {
    if (relatedItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'More Like This',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: relatedItems.length,
            itemBuilder: (context, i) {
              final related = relatedItems[i];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PosterCard(
                  item: related,
                  width: 122,
                  onTap: () => _openRelated(related),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Season Picker Sheet ────────────────────────────────────────────────────

  void _showSeasonPicker(List<Season> seasons) {
    if (seasons.length <= 1) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: seasons.length,
                  itemBuilder: (context, idx) {
                    final season = seasons[idx];
                    final isSelected = idx == _selectedSeasonIdx;

                    return ListTile(
                      title: Text(
                        season.title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(CupertinoIcons.check_mark,
                              color: Colors.white, size: 18)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (_selectedSeasonIdx != idx) {
                          setState(() => _selectedSeasonIdx = idx);
                          _loadSeasonEpisodes(season.number);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Shimmer Skeleton Loader for Episodes ───────────────────────────────────

  Widget _buildEpisodesSkeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF16161E),
      highlightColor: const Color(0xFF282834),
      child: Column(
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 122,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 140,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 55,
                            height: 11,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 200,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
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

// ── Apple Liquid Glass Icon Button Component ─────────────────────────────────

class AppleGlassIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color iconColor;
  final VoidCallback? onTap;
  final bool isCircle;
  final double borderRadius;

  const AppleGlassIconButton({
    super.key,
    required this.icon,
    this.size = 36,
    this.iconSize = 18,
    this.iconColor = Colors.white,
    this.onTap,
    this.isCircle = true,
    this.borderRadius = 8,
  });

  @override
  State<AppleGlassIconButton> createState() => _AppleGlassIconButtonState();
}

class _AppleGlassIconButtonState extends State<AppleGlassIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: widget.isCircle
              ? BorderRadius.circular(widget.size / 2)
              : BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: widget.isCircle
                    ? null
                    : BorderRadius.circular(widget.borderRadius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isPressed
                      ? [
                          Colors.white.withValues(alpha: 0.32),
                          Colors.white.withValues(alpha: 0.14),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.07),
                        ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Apple Fluid Action Button Component ──────────────────────────────────────

class _AppleFluidButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final bool isGlass;

  const _AppleFluidButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    this.isGlass = false,
  });

  @override
  State<_AppleFluidButton> createState() => _AppleFluidButtonState();
}

class _AppleFluidButtonState extends State<_AppleFluidButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: BackdropFilter(
            filter: widget.isGlass
                ? ImageFilter.blur(sigmaX: 16, sigmaY: 16)
                : ImageFilter.blur(sigmaX: 0.01, sigmaY: 0.01),
            child: Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isGlass
                    ? const Color(0xFF282828).withValues(alpha: 0.90)
                    : widget.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: widget.isGlass
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.6,
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    color: widget.foregroundColor,
                    size: 19,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.foregroundColor,
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

// ── Netflix Episode Item Component with Apple Liquid Glass Icons ─────────────

class _NetflixEpisodeTile extends StatelessWidget {
  final EpisodeData episode;
  final CatalogItem parentItem;
  final VoidCallback onWatch;
  final VoidCallback onDownload;
  final double watchProgress;

  const _NetflixEpisodeTile({
    required this.episode,
    required this.parentItem,
    required this.onWatch,
    required this.onDownload,
    this.watchProgress = 0.0,
  });

  String? _resolveThumb() {
    if (episode.thumbnail != null && episode.thumbnail!.isNotEmpty) {
      return episode.thumbnail;
    }
    return parentItem.backdrop ?? parentItem.poster;
  }

  Widget _buildFallbackCard() {
    final fallbackImg = parentItem.backdrop ?? parentItem.poster;
    if (fallbackImg != null && fallbackImg.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: fallbackImg,
        fit: BoxFit.cover,
        memCacheWidth: 260,
        color: Colors.black.withValues(alpha: 0.35),
        colorBlendMode: BlendMode.darken,
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFF181820),
          child: const Icon(
            CupertinoIcons.film,
            color: Colors.white24,
            size: 20,
          ),
        ),
      );
    }
    return Container(
      color: const Color(0xFF181820),
      child: const Icon(
        CupertinoIcons.film,
        color: Colors.white24,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = _resolveThumb();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Thumbnail + Title/Duration + Download Icon
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onWatch,
          child: Row(
            children: [
              // 16:9 Thumbnail
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 122,
                      height: 68,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: thumbUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: thumbUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 260,
                                    placeholder: (_, __) => Shimmer.fromColors(
                                      baseColor: const Color(0xFF16161E),
                                      highlightColor: const Color(0xFF282834),
                                      child: Container(
                                        width: 122,
                                        height: 68,
                                        color: Colors.white,
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _buildFallbackCard(),
                                  )
                                : _buildFallbackCard(),
                          ),
                          // Thin red progress line at bottom of episode thumbnail
                          if (watchProgress > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 2.5,
                                color: Colors.white.withValues(alpha: 0.18),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: watchProgress.clamp(0.0, 1.0),
                                  child: Container(
                                    color: const Color(0xFFE50914),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Play Button in Apple Liquid Glass Icon Style
                  AppleGlassIconButton(
                    icon: CupertinoIcons.play_fill,
                    size: 34,
                    iconSize: 15,
                    isCircle: true,
                    onTap: onWatch,
                  ),
                ],
              ),

              const SizedBox(width: 14),

              // Title & Duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.number}. ${episode.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (episode.duration != null &&
                        episode.duration!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.duration!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.50),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Download Icon in Apple Liquid Glass Icon Style
              AppleGlassIconButton(
                icon: CupertinoIcons.arrow_down_to_line,
                size: 34,
                iconSize: 16,
                isCircle: true,
                onTap: onDownload,
              ),
            ],
          ),
        ),

        // Full Episode Description underneath (Only when non-empty)
        if (episode.overview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            episode.overview,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Multi-Tiered Cascading Banner Image (Guarantees Content Banner Displays) ─

class _CascadingBannerImage extends StatelessWidget {
  final List<String> candidates;
  final String title;
  final int index;

  const _CascadingBannerImage({
    required this.candidates,
    required this.title,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (index >= candidates.length) {
      return _buildFallbackPlaceholder();
    }

    final url = candidates[index];
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => Container(
        color: const Color(0xFF101014),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFF121218),
          highlightColor: const Color(0xFF22222C),
          child: Container(color: Colors.white),
        ),
      ),
      errorWidget: (_, __, ___) => _CascadingBannerImage(
        candidates: candidates,
        title: title,
        index: index + 1,
      ),
    );
  }

  Widget _buildFallbackPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1E2C),
            Color(0xFF12121A),
            Color(0xFF08080C),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.0,
                ),
              ),
              child: Icon(
                CupertinoIcons.film,
                size: 26,
                color: Colors.white.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.80),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Apple Liquid Glass Download Quality Selection Modal Sheet ────────────────

class _AppleDownloadQualityModal extends ConsumerStatefulWidget {
  final CatalogItem item;
  final StreamsKey streamKey;
  final bool isSeries;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? posterUrl;

  const _AppleDownloadQualityModal({
    required this.item,
    required this.streamKey,
    required this.isSeries,
    required this.seasonNumber,
    required this.episodeNumber,
    this.episodeTitle,
    this.posterUrl,
  });

  @override
  ConsumerState<_AppleDownloadQualityModal> createState() =>
      _AppleDownloadQualityModalState();
}

class _AppleDownloadQualityModalState
    extends ConsumerState<_AppleDownloadQualityModal> {
  StreamInfo? _selectedStream;
  bool _isStartingDownload = false;

  String _formatSize(StreamInfo stream) {
    if (stream.size != null && stream.size!.trim().isNotEmpty) {
      return stream.size!.trim();
    }
    if (stream.sizeMb != null && stream.sizeMb! > 0) {
      final mb = stream.sizeMb!;
      if (mb >= 1024) {
        return '${(mb / 1024).toStringAsFixed(1)} GB';
      }
      return '${mb.toStringAsFixed(0)} MB';
    }
    final q = stream.quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) return '2.2 GB';
    if (q.contains('1080')) return '1.2 GB';
    if (q.contains('720')) return '650 MB';
    return '380 MB';
  }

  int? _estimatedBytes(StreamInfo stream) {
    if (stream.sizeMb != null && stream.sizeMb! > 0) {
      return (stream.sizeMb! * 1024 * 1024).toInt();
    }
    final q = stream.quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) {
      return (2.2 * 1024 * 1024 * 1024).toInt();
    }
    if (q.contains('1080')) return (1.2 * 1024 * 1024 * 1024).toInt();
    if (q.contains('720')) return (650 * 1024 * 1024).toInt();
    return (380 * 1024 * 1024).toInt();
  }

  String _qualityDisplay(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('4k') || lower.contains('2160')) return '4K Ultra HD';
    if (lower.contains('1080')) return '1080p Full HD';
    if (lower.contains('720')) return '720p HD';
    if (lower.contains('480')) return '480p SD';
    return raw.toUpperCase();
  }

  List<StreamInfo> _deduplicateAndSortStreams(List<StreamInfo> streams) {
    final Map<String, StreamInfo> unique = {};
    for (final s in streams) {
      final q = s.quality.toLowerCase();
      String key;
      if (q.contains('4k') || q.contains('2160')) {
        key = '4k';
      } else if (q.contains('1080')) {
        key = '1080p';
      } else if (q.contains('720')) {
        key = '720p';
      } else {
        key = '480p';
      }
      if (!unique.containsKey(key)) {
        unique[key] = s;
      }
    }
    final order = ['4k', '1080p', '720p', '480p'];
    final result = <StreamInfo>[];
    for (final k in order) {
      if (unique.containsKey(k)) result.add(unique[k]!);
    }
    return result.isNotEmpty ? result : streams;
  }

  Future<void> _handleStartDownload() async {
    if (_selectedStream == null || _isStartingDownload) return;
    setState(() => _isStartingDownload = true);
    HapticFeedback.mediumImpact();

    try {
      await [
        Permission.notification,
        Permission.storage,
        Permission.videos,
      ].request();
    } catch (_) {}

    final selected = _selectedStream!;
    String candidate = selected.playUrl.trim();
    if (candidate.isEmpty || !candidate.startsWith('http')) {
      candidate = (selected.directUrl ?? selected.rawUrl ?? '').trim();
    }
    if (candidate.isEmpty || !candidate.startsWith('http')) {
      candidate = selected.url.trim();
    }
    if (candidate.contains('ugotnothing.onrender.com') ||
        candidate.contains('netmix-play.onrender.com')) {
      candidate = candidate
          .replaceAll('ugotnothing.onrender.com', 'netmix-byoky.onrender.com')
          .replaceAll('netmix-play.onrender.com', 'netmix-byoky.onrender.com');
    }
    final dlUrl = candidate;
    final bytes = _estimatedBytes(selected);

    final titleStr = widget.isSeries
        ? '${widget.item.title} · S${widget.seasonNumber}E${widget.episodeNumber}${widget.episodeTitle != null ? ': ${widget.episodeTitle!}' : ''}'
        : widget.item.title;

    final itemIdStr = widget.isSeries
        ? '${widget.item.id}_s${widget.seasonNumber}e${widget.episodeNumber}'
        : widget.item.id;

    await ref.read(downloadsProvider.notifier).startDownload(
          itemId: itemIdStr,
          title: titleStr,
          poster: widget.posterUrl ?? widget.item.poster,
          downloadUrl: dlUrl,
          quality: selected.quality,
          contentType: widget.isSeries ? 'series' : 'movie',
          seasonNumber: widget.isSeries ? widget.seasonNumber : null,
          episodeNumber: widget.isSeries ? widget.episodeNumber : null,
          estimatedTotalBytes: bytes,
        );

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.arrow_down_circle_fill,
              color: Color(0xFF34C759),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Download started',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xEE161622),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.horizontal,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.8,
          ),
        ),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 96),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streamsState = ref.watch(streamsProvider(widget.streamKey));
    final streams = _deduplicateAndSortStreams(streamsState.streams);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_selectedStream == null && streams.isNotEmpty) {
      _selectedStream = streams.first;
    }

    return AdaptiveGlass(
      quality: GlassQuality.minimal,
      platformViewBackdrop: true,
      shape: const LiquidVerticalRoundedSuperellipse(
        topRadius: 32,
        bottomRadius: 0,
      ),
      settings: const LiquidGlassSettings(
        glassColor: Color(0x32141424), // Dock-style dark glass: only a little dark, not too dark!
        blur: 32,
        thickness: 24,
        saturation: 1.35,
        lightIntensity: 0.55,
        ambientStrength: 0.18,
        ambientRim: 0.25,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          // Apple Dock Specular reflection overlay
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x28FFFFFF), // Delicate top specular reflection (Apple Dock light rim)
              Color(0x06FFFFFF),
              Colors.transparent,
              Color(0x18000000), // Subtle bottom grounding (little dark only!)
            ],
            stops: [0.0, 0.05, 0.22, 1.0],
          ),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.38), // Crisp Apple Dock top specular rim
              width: 1.2,
            ),
            left: BorderSide(
              color: Colors.white.withValues(alpha: 0.12), // Subtle dock side edge
              width: 0.8,
            ),
            right: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 36,
              spreadRadius: -4,
              offset: const Offset(0, -10),
            ),
          ],
        ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Pull-Down Grab Handle (clean Apple modal, no close icon)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),

              // Header (Poster + Title + Subtitle)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 68,
                        child: widget.posterUrl != null &&
                                widget.posterUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.posterUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFF222230),
                                  child: const Icon(CupertinoIcons.film,
                                      color: Colors.white38),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF222230),
                                child: const Icon(CupertinoIcons.film,
                                    color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.isSeries
                                ? 'Season ${widget.seasonNumber} · Episode ${widget.episodeNumber}'
                                : (widget.item.year != null
                                    ? '${widget.item.year} · Full Movie'
                                    : 'Offline Download'),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF34C759)
                                    .withValues(alpha: 0.35),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              'Background & Resume Ready',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // Quality List Section
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVAILABLE DOWNLOAD QUALITIES',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.45),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (streamsState.isLoading && streams.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CupertinoActivityIndicator(
                                    color: Colors.white, radius: 12),
                                const SizedBox(height: 12),
                                Text(
                                  'Resolving highest streaming qualities...',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (streams.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No download sources available for this title right now.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                        )
                      else
                        ...streams.map((s) {
                          final isSelected = _selectedStream == s;
                          final is4K = s.quality.toLowerCase().contains('4k') ||
                              s.quality.toLowerCase().contains('2160');
                          final sizeStr = _formatSize(s);
                          final qualityLabel = _qualityDisplay(s.quality);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedStream = s);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.14)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? (is4K
                                            ? const Color(0xFFFFD700)
                                            : Colors.white
                                                .withValues(alpha: 0.60))
                                        : Colors.white
                                            .withValues(alpha: 0.10),
                                    width: isSelected ? 1.4 : 0.8,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: is4K
                                                ? const Color(0xFFFFD700)
                                                    .withValues(alpha: 0.20)
                                                : Colors.white
                                                    .withValues(alpha: 0.10),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? (is4K
                                                ? const Color(0xFFFFD700)
                                                : Colors.white)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? (is4K
                                                  ? const Color(0xFFFFD700)
                                                  : Colors.white)
                                              : Colors.white38,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              CupertinoIcons.checkmark,
                                              size: 13,
                                              color: Colors.black,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                qualityLabel,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: is4K
                                                      ? const Color(0xFFFFD700)
                                                      : Colors.white,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              if (is4K) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFFD700)
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    'ULTRA',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: const Color(
                                                          0xFFFFD700),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            s.format.toUpperCase() == 'HLS'
                                                ? 'High Speed Adaptive · Resumable'
                                                : 'MP4 Video Stream · Resumable',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.14),
                                          width: 0.6,
                                        ),
                                      ),
                                      child: Text(
                                        sizeStr,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white
                                              .withValues(alpha: 0.90),
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),

              // Bottom Action Button (Download Now)
              if (_selectedStream != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 16),
                  child: _AppleFluidButton(
                    onPressed: _handleStartDownload,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    icon: CupertinoIcons.arrow_down_to_line,
                    label:
                        'Download ${_qualityDisplay(_selectedStream!.quality)} (${_formatSize(_selectedStream!)})',
                    isGlass: false,
                  ),
                ),
            ],
          ),
        ),
    );
  }
}
