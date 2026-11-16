// lib/screens/search_screen.dart
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';
import '../providers/home_provider.dart';
import '../providers/search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (mounted) {
        setState(() => _isFocused = _focusNode.hasFocus);
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        _scrollOffset.value = _scrollController.offset;
      }
    });

    // Ensure home catalog data is loaded so recommendations are immediately populated
    Future.microtask(() {
      final homeState = ref.read(homeProvider);
      if (homeState.data == null && !homeState.isLoading) {
        ref.read(homeProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    ref.read(searchProvider.notifier).setQuery(val);
  }

  void _onSubmitted(String val) {
    final query = val.trim();
    if (query.isNotEmpty) {
      ref.read(searchProvider.notifier).addHistory(query);
      ref.read(searchProvider.notifier).setQuery(query, immediate: true);
    }
  }

  void _onHistorySelected(String query) {
    HapticFeedback.selectionClick();
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _focusNode.unfocus();
    ref.read(searchProvider.notifier).setQuery(query, immediate: true);
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  DateTime? _lastDetailsTap;
  void _openDetails(CatalogItem item) {
    final now = DateTime.now();
    if (_lastDetailsTap != null &&
        now.difference(_lastDetailsTap!).inMilliseconds < 400) {
      return;
    }
    _lastDetailsTap = now;
    HapticFeedback.lightImpact();
    context.push('/details', extra: item);
  }

  List<CatalogItem> _getRecommendedItems(HomeState homeState) {
    final items = <CatalogItem>[];
    final seenIds = <String>{};

    bool hasImage(CatalogItem item) {
      final b = item.backdrop?.trim();
      final p = item.poster?.trim();
      return (b != null && b.isNotEmpty) || (p != null && p.isNotEmpty);
    }

    if (homeState.data?.heroItem != null) {
      final hero = homeState.data!.heroItem!;
      if (hero.id.isNotEmpty && hasImage(hero)) {
        seenIds.add(hero.id);
        items.add(hero);
      }
    }

    if (homeState.data != null) {
      for (final shelf in homeState.data!.shelves) {
        for (final item in shelf.items) {
          if (item.id.isNotEmpty && !seenIds.contains(item.id) && hasImage(item)) {
            seenIds.add(item.id);
            items.add(item);
            if (items.length >= 8) break;
          }
        }
        if (items.length >= 8) break;
      }
    }
    return items.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final homeState = ref.watch(homeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = topPadding + 112.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Layer 1: Scrollable Body (Scrolls underneath floating header) ──
          Positioned.fill(
            child: _buildScrollableBody(
              context,
              searchState: searchState,
              homeState: homeState,
              headerHeight: headerHeight,
            ),
          ),

          // ── Layer 2: Floating Liquid Glass Header ────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFloatingGlassHeader(
              context,
              searchState: searchState,
              topPadding: topPadding,
            ),
          ),

          // ── Layer 3: Recent Searches Popup (When focused with empty query) ─
          if (_isFocused &&
              _controller.text.isEmpty &&
              searchState.searchHistory.isNotEmpty)
            Positioned(
              top: headerHeight - 4,
              left: 0,
              right: 0,
              child: _buildRecentSearchesPopup(context, searchState),
            ),
        ],
      ),
    );
  }

  // ── Floating Liquid Glass Header ─────────────────────────────────────────
  Widget _buildFloatingGlassHeader(
    BuildContext context, {
    required SearchState searchState,
    required double topPadding,
  }) {
    final hasText = _controller.text.isNotEmpty || searchState.query.isNotEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;

    return ValueListenableBuilder<double>(
      valueListenable: _scrollOffset,
      builder: (context, scrollOffset, child) {
        final progress = (scrollOffset / 45.0).clamp(0.0, 1.0);
        final titleOpacity = (1.0 - progress * 1.5).clamp(0.0, 1.0);
        final titleHeightFactor = (1.0 - progress).clamp(0.0, 1.0);

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 20.0 * progress,
              sigmaY: 20.0 * progress,
            ),
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 10),
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0x000F0F14),
                  const Color(0xEC0E0E14),
                  progress,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08 * progress),
                    width: 0.8,
                  ),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Large "Search" Title above Search Bar (matching reference) ──
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topLeft,
                          heightFactor: titleHeightFactor,
                          child: Opacity(
                            opacity: titleOpacity,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Search',
                                style: GoogleFonts.inter(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.6,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C30), // Dark glass fill matching screenshot
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isFocused
                                ? Colors.white.withValues(alpha: 0.35)
                                : Colors.white.withValues(alpha: 0.12),
                            width: _isFocused ? 1.0 : 0.8,
                          ),
                          boxShadow: progress > 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.30 * progress),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(
                              CupertinoIcons.search,
                              size: 20,
                              color: _isFocused
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.60),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                onChanged: _onChanged,
                                onSubmitted: _onSubmitted,
                                textInputAction: TextInputAction.search,
                                cursorColor: Colors.white,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search shows, movies, games...',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 14.5,
                                    color: Colors.white.withValues(alpha: 0.45),
                                    decoration: TextDecoration.none,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (hasText)
                              _ApplePressableScale(
                                onTap: _clearSearch,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Icon(
                                    CupertinoIcons.clear_thick_circled,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 12),
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
      },
    );
  }

  // ── Scrollable Body Switcher ─────────────────────────────────────────────
  Widget _buildScrollableBody(
    BuildContext context, {
    required SearchState searchState,
    required HomeState homeState,
    required double headerHeight,
  }) {
    if (searchState.query.trim().isNotEmpty) {
      return _buildSearchResultsView(
        context,
        searchState: searchState,
        headerHeight: headerHeight,
      );
    }

    return _buildRecommendationsView(
      context,
      homeState: homeState,
      headerHeight: headerHeight,
    );
  }

  // ── Recommendations View (Matching Reference Screenshot) ─────────────────
  Widget _buildRecommendationsView(
    BuildContext context, {
    required HomeState homeState,
    required double headerHeight,
  }) {
    final items = _getRecommendedItems(homeState);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    if (homeState.isLoading && items.isEmpty) {
      return _buildLoadingShimmer(headerHeight: headerHeight);
    }

    if (homeState.error != null && items.isEmpty) {
      return _buildErrorState(homeState.error!, headerHeight: headerHeight);
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: headerHeight,
        bottom: keyboardHeight > 0 ? keyboardHeight + 24 : 110,
      ),
      itemCount: items.length + 1, // +1 for the Collapsing Heading
      itemBuilder: (context, index) {
        if (index == 0) {
          // ── Collapsible "Recommended Shows & Movies" Heading ───────────
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, scrollOffset, _) {
                  final progress = (scrollOffset / 48.0).clamp(0.0, 1.0);
                  final opacity = (1.0 - progress * 1.3).clamp(0.0, 1.0);
                  final heightFactor = (1.0 - progress).clamp(0.0, 1.0);
                  final translateY = -10.0 * progress;

                  if (heightFactor <= 0.001) {
                    return const SizedBox.shrink();
                  }

                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: heightFactor,
                      child: Transform.translate(
                        offset: Offset(0, translateY),
                        child: Opacity(
                          opacity: opacity,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Text(
                              'Recommended Shows & Movies',
                              style: GoogleFonts.inter(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }

        final item = items[index - 1];
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
            child: _RecommendationRow(
              item: item,
              onTap: () => _openDetails(item),
              quality: item.displayQuality,
            ),
          ),
        );
      },
    );
  }

  // ── Search Results View ──────────────────────────────────────────────────
  Widget _buildSearchResultsView(
    BuildContext context, {
    required SearchState searchState,
    required double headerHeight,
  }) {
    if (searchState.isLoading) {
      return _buildLoadingShimmer(headerHeight: headerHeight);
    }

    if (searchState.error != null) {
      return _buildErrorState(searchState.error!, headerHeight: headerHeight);
    }

    if (searchState.results.isEmpty) {
      return _buildNoResultsState(searchState.query, headerHeight: headerHeight);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    // Dynamically expand items into separate 1080p and 4K entries when both qualities are available
    final displayItems = <CatalogItem>[];
    for (final it in searchState.results) {
      final qs = it.availableQualities;
      if (it.quality == null && qs.contains('1080p') && qs.contains('4K')) {
        // Show 1080p entry first, followed by 4K entry (matching reference image)
        displayItems.add(it.copyWith(quality: '1080p'));
        displayItems.add(it.copyWith(quality: '4K'));
      } else {
        displayItems.add(it);
      }
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: headerHeight,
        bottom: keyboardHeight > 0 ? keyboardHeight + 24 : 110,
      ),
      itemCount: displayItems.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  'TOP RESULTS (${displayItems.length})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: const Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
          );
        }

        final item = displayItems[index - 1];
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
            child: _RecommendationRow(
              item: item,
              onTap: () => _openDetails(item),
              quality: item.displayQuality,
            ),
          ),
        );
      },
    );
  }

  // ── Recent Searches Popup ────────────────────────────────────────────────
  Widget _buildRecentSearchesPopup(BuildContext context, SearchState searchState) {
    final history = searchState.searchHistory;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isTablet ? 720 : double.infinity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF5181822),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RECENT SEARCHES',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: const Color(0xFF8E8E93),
                          ),
                        ),
                        _ApplePressableScale(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref.read(searchProvider.notifier).clearHistory();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            child: Text(
                              'Clear All',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length.clamp(0, 5),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Colors.white.withValues(alpha: 0.06),
                      indent: 44,
                      endIndent: 12,
                    ),
                    itemBuilder: (context, index) {
                      final query = history[index];
                      return _ApplePressableScale(
                        onTap: () => _onHistorySelected(query),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.clock,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  query,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              _ApplePressableScale(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ref.read(searchProvider.notifier).removeHistory(query);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    CupertinoIcons.xmark,
                                    size: 13,
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading Skeleton ─────────────────────────────────────────────────────
  Widget _buildLoadingShimmer({required double headerHeight}) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: headerHeight + 14, bottom: 110),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Shimmer.fromColors(
              baseColor: const Color(0xFF1B1B26),
              highlightColor: const Color(0xFF282838),
              child: Container(
                width: 140,
                height: 79,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B26),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Shimmer.fromColors(
                    baseColor: const Color(0xFF1B1B26),
                    highlightColor: const Color(0xFF282838),
                    child: Container(
                      height: 16,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Shimmer.fromColors(
                    baseColor: const Color(0xFF1B1B26),
                    highlightColor: const Color(0xFF282838),
                    child: Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Shimmer.fromColors(
              baseColor: const Color(0xFF1B1B26),
              highlightColor: const Color(0xFF282838),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1B1B26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error State ──────────────────────────────────────────────────────────
  Widget _buildErrorState(String message, {required double headerHeight}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, headerHeight, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: const Icon(
                CupertinoIcons.exclamationmark_circle,
                color: AppColors.accent,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Content Unavailable',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.50),
              ),
            ),
            const SizedBox(height: 20),
            _ApplePressableScale(
              onTap: () {
                final q = _controller.text.trim();
                if (q.isNotEmpty) {
                  ref.read(searchProvider.notifier).setQuery(q, immediate: true);
                } else {
                  ref.read(homeProvider.notifier).load(forceRefresh: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222230),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  'Try Again',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── No Results State ─────────────────────────────────────────────────────
  Widget _buildNoResultsState(String query, {required double headerHeight}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, headerHeight, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 46,
              color: Colors.white.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$query"',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your spelling or try searching for another title.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.45),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Recommendation & Result Row (Matching Reference Screenshot)
// ─────────────────────────────────────────────────────────────────────────────

class _RecommendationRow extends StatelessWidget {
  final CatalogItem item;
  final VoidCallback onTap;
  final String? quality;

  const _RecommendationRow({
    required this.item,
    required this.onTap,
    this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final backdropUrl = item.backdrop?.trim() ?? '';
    final posterUrl = item.poster?.trim() ?? '';
    final primaryUrl = backdropUrl.isNotEmpty ? backdropUrl : posterUrl;
    final fallbackUrl = (backdropUrl.isNotEmpty &&
            posterUrl.isNotEmpty &&
            backdropUrl != posterUrl)
        ? posterUrl
        : null;
    final effectiveQuality = quality ?? item.displayQuality;

    return _ApplePressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Left: Clean 16:9 Thumbnail with Real-Time Quality Tag ────────
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 140,
                height: 79,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnailImage(primaryUrl, fallbackUrl),
                    if (effectiveQuality.isNotEmpty)
                      Positioned(
                        left: 7,
                        bottom: 6,
                        child: _buildQualityBadge(effectiveQuality),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 14),

            // ── Center: Title (Multi-line up to 3 lines) ───────────────────────
            Expanded(
              child: Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  height: 1.25,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ── Right: Circular Outline Play Button ────────────────────────────
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2.2,
                ),
                color: Colors.transparent,
              ),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.only(left: 2.0),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small, clean, rounded dark badge positioned at the bottom-left of the banner.
  /// 4K is highlighted with subtle warm golden/yellow text; others are crisp white.
  Widget _buildQualityBadge(String q) {
    final rawLower = q.toLowerCase().trim();
    final is4K = rawLower.contains('4k') || rawLower.contains('2160');
    final String label;
    if (is4K) {
      label = '4K';
    } else if (rawLower.contains('1080')) {
      label = '1080p';
    } else if (rawLower.contains('720')) {
      label = '720p';
    } else if (rawLower.contains('480')) {
      label = '480p';
    } else {
      label = q.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xE808080C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.6,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: is4K ? FontWeight.w800 : FontWeight.w700,
          color: is4K ? const Color(0xFFFFB800) : Colors.white,
          letterSpacing: -0.2,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _buildThumbnailImage(String primaryUrl, String? fallbackUrl) {
    if (primaryUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: primaryUrl,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      placeholder: (_, __) => Container(
        color: const Color(0xFF1C1C24),
      ),
      errorWidget: (_, __, ___) {
        if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: fallbackUrl,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            placeholder: (_, __) => Container(
              color: const Color(0xFF1C1C24),
            ),
            errorWidget: (_, __, ___) => _buildPlaceholder(),
          );
        }
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1C1C24),
      child: Center(
        child: Icon(
          CupertinoIcons.film,
          color: Colors.white.withValues(alpha: 0.25),
          size: 26,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Apple Pressable Scale (Fluid Spring Interaction from Apple Design)
// ─────────────────────────────────────────────────────────────────────────────

class _ApplePressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ApplePressableScale({
    required this.child,
    required this.onTap,
  });

  @override
  State<_ApplePressableScale> createState() => _ApplePressableScaleState();
}

class _ApplePressableScaleState extends State<_ApplePressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Fast response on pointer-down (Apple: kill latency), smooth spring settle
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOutQuad,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
