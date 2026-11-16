// lib/screens/home_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';
import '../core/router.dart';
import '../models/catalog_item.dart';
import '../providers/home_provider.dart';
import '../providers/streams_provider.dart';
import '../services/app_update_service.dart';
import '../services/watch_progress_service.dart';
import '../widgets/continue_watching_shelf.dart';
import '../widgets/hero_banner.dart';
import '../widgets/apps_glass_popup.dart';
import '../widgets/home_category_nav.dart';
import '../widgets/shelf_row.dart';
import '../widgets/shimmer_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _appBarOpacity = ValueNotifier<double>(0.0);
  final GlobalKey _categoriesKey = GlobalKey();

  String? _selectedCategory;
  bool _isCategoriesPopupOpen = false;
  late final AnimationController _popupAnimController;
  late final Animation<double> _popupAnimation;

  // OTT Apps Floating Glass Page
  final GlobalKey _threeDotKey = GlobalKey();
  bool _isAppsPopupOpen = false;
  late final AnimationController _appsPopupAnimController;
  late final Animation<double> _appsPopupAnimation;

  // Direction-based scroll state for category navigation
  bool _showCategoryNav = true;
  double _lastScrollOffset = 0.0;
  double _accumulatedUpScroll = 0.0;
  late final AnimationController _categoryNavAnimController;
  late final Animation<double> _categoryNavAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    _popupAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _popupAnimation = CurvedAnimation(
      parent: _popupAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _appsPopupAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _appsPopupAnimation = CurvedAnimation(
      parent: _appsPopupAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _categoryNavAnimController = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _categoryNavAnimation = CurvedAnimation(
      parent: _categoryNavAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(homeProvider.notifier).load();
      try {
        await AppUpdateService.instance.checkUpdate();
      } catch (_) {}
    });
  }

  void _onScroll() {
    if (_isCategoriesPopupOpen) {
      _closeCategoriesPopup();
    }
    if (_isAppsPopupOpen) {
      _closeAppsPopup();
    }
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;

    // 1. Transparent at the top (0.0), transitioning smoothly to Apple Liquid Glass (1.0) on scroll
    final newOpacity = (offset / 60.0).clamp(0.0, 1.0);
    if ((newOpacity - _appBarOpacity.value).abs() > 0.015) {
      _appBarOpacity.value = newOpacity;
    }

    // 2. Failsafe direction tracking for momentum scrolls & boundary recovery
    if (offset <= 15.0) {
      // At the very top of Home page: always visible with transparent background
      _accumulatedUpScroll = 0.0;
      if (!_showCategoryNav) {
        _showCategoryNav = true;
        _categoryNavAnimController.forward();
      }
    } else if (delta > 4.0 && offset > 40.0) {
      // Scrolling DOWN: Hide entire category navigation bar & reset up-scroll distance
      _accumulatedUpScroll = 0.0;
      if (_showCategoryNav) {
        _showCategoryNav = false;
        _categoryNavAnimController.reverse();
      }
    } else if (delta < -2.0) {
      // Scrolling UP: Accumulate upward scroll distance.
      // If user only scrolls up a little bit, do NOT expand back into view!
      _accumulatedUpScroll += (-delta);
      if (_accumulatedUpScroll >= 80.0) {
        if (!_showCategoryNav) {
          _showCategoryNav = true;
          _categoryNavAnimController.forward();
        }
      }
    }

    _lastScrollOffset = offset;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _appBarOpacity.dispose();
    _popupAnimController.dispose();
    _appsPopupAnimController.dispose();
    _categoryNavAnimController.dispose();
    super.dispose();
  }

  void _toggleCategoriesPopup() {
    if (_isCategoriesPopupOpen) {
      _closeCategoriesPopup();
    } else {
      _openCategoriesPopup();
    }
  }

  void _openCategoriesPopup() {
    if (_isAppsPopupOpen) {
      _closeAppsPopup();
    }
    setState(() => _isCategoriesPopupOpen = true);
    _popupAnimController.forward();
  }

  void _closeCategoriesPopup() {
    _popupAnimController.reverse().then((_) {
      if (mounted) {
        setState(() => _isCategoriesPopupOpen = false);
      }
    });
  }

  void _toggleAppsPopup() {
    if (_isAppsPopupOpen) {
      _closeAppsPopup();
    } else {
      _openAppsPopup();
    }
  }

  void _openAppsPopup() {
    if (_isCategoriesPopupOpen) {
      _closeCategoriesPopup();
    }
    setState(() => _isAppsPopupOpen = true);
    _appsPopupAnimController.forward();
  }

  void _closeAppsPopup() {
    _appsPopupAnimController.reverse().then((_) {
      if (mounted) {
        setState(() => _isAppsPopupOpen = false);
      }
    });
  }

  void _onAppSelected(OttAppItem app) {
    _closeAppsPopup();
    context.push(AppRoutes.category, extra: app.categoryTarget);
  }

  Rect _getThreeDotButtonRect() {
    final renderBox =
        _threeDotKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      return offset & renderBox.size;
    }
    final top = MediaQuery.of(context).padding.top + 8.0;
    return Rect.fromLTWH(
        MediaQuery.of(context).size.width - 50, top, 34, 34);
  }

  void _onCategorySelected(String? category) {
    if (_isCategoriesPopupOpen) {
      _closeCategoriesPopup();
    }

    if (category == null ||
        category == 'All Categories' ||
        category == 'All') {
      return;
    }

    if (category == 'Available for Download') {
      context.push('/downloads');
      return;
    }

    // Open dedicated category page with Apple Liquid Glass design
    context.push(AppRoutes.category, extra: category);
  }

  Rect _getCategoriesButtonRect() {
    final renderBox =
        _categoriesKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      return offset & renderBox.size;
    }
    final top = MediaQuery.of(context).padding.top + 52.0;
    return Rect.fromLTWH(
        MediaQuery.of(context).size.width - 150, top, 130, 36);
  }

  List<String> _buildPopupCategories(List<ShelfData>? shelves) {
    return const [
      'Movies',
      'Series',
      'Bollywood',
      'Hollywood',
      'Hindi Movies',
      'English Movies',
      'Netflix Specials',
      'Amazon Prime',
      'JioHotstar',
      'Apple TV+',
      'Disney+',
      'HBO Max',
      'South Hindi Dubbed',
      'Anime',
      'Action',
      'Comedy',
      'Romance',
      'Horror & Thriller',
      'Sci-Fi & Fantasy',
      'Crime & Mystery',
    ];
  }

  List<ShelfData> _getFilteredShelves(List<ShelfData> allShelves) {
    if (_selectedCategory == null) return allShelves;
    final cat = _selectedCategory!.toLowerCase();

    if (cat == 'shows') {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return t.contains('series') ||
            t.contains('show') ||
            t.contains('binge') ||
            t.contains('tv');
      }).toList();
      return res.isNotEmpty ? res : allShelves;
    }

    if (cat == 'movies') {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return t.contains('movie') ||
            t.contains('cinema') ||
            t.contains('film') ||
            t.contains('blockbuster');
      }).toList();
      return res.isNotEmpty ? res : allShelves;
    }

    if (cat == 'new & hot') {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return t.contains('trending') ||
            t.contains('top 10') ||
            t.contains('latest') ||
            t.contains('top web series');
      }).toList();
      return res.isNotEmpty ? res : allShelves;
    }

    final matched = allShelves.where((s) {
      final t = s.title.toLowerCase();
      if (cat == 'action' && t.contains('action')) {
        return true;
      }
      if (cat == 'comedy' && t.contains('comedy')) {
        return true;
      }
      if (cat == 'romance' && t.contains('romance')) {
        return true;
      }
      if (cat == 'horror' && t.contains('horror')) {
        return true;
      }
      if (cat == 'thriller' &&
          (t.contains('thriller') || t.contains('suspense'))) {
        return true;
      }
      if (cat == 'sci-fi & fantasy' &&
          (t.contains('sci-fi') || t.contains('fantasy'))) {
        return true;
      }
      if (cat == 'hindi' &&
          (t.contains('hindi') || t.contains('bollywood'))) {
        return true;
      }
      if ((cat == 'tamil' || cat == 'telugu' || cat == 'malayalam') &&
          (t.contains('south') || t.contains(cat))) {
        return true;
      }
      if (cat == 'english' &&
          (t.contains('hollywood') || t.contains('english'))) {
        return true;
      }
      if (cat == 'anime' &&
          (t.contains('anime') || t.contains('animation'))) {
        return true;
      }
      if (cat.contains('apple') && t.contains('apple')) {
        return true;
      }
      if ((cat.contains('disney') || cat.contains('disnep')) && (t.contains('disney') || t.contains('dsnp'))) {
        return true;
      }
      if ((cat.contains('hbo') || cat.contains('max')) && (t.contains('hbo') || t.contains('max'))) {
        return true;
      }
      return t.contains(cat);
    }).toList();

    if (matched.isNotEmpty) return matched;

    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final s in allShelves) {
      for (final item in s.items) {
        if (seen.contains(item.id)) continue;
        final gMatch = item.genres.any((g) => g.toLowerCase().contains(cat));
        final lMatch =
            item.audioLanguages.any((l) => l.toLowerCase().contains(cat));
        final tMatch = item.title.toLowerCase().contains(cat);
        if (gMatch || lMatch || tMatch) {
          seen.add(item.id);
          items.add(item);
        }
      }
    }

    if (items.isNotEmpty) {
      return [ShelfData(title: '$_selectedCategory on Netmix', items: items)];
    }

    return allShelves;
  }

  DateTime? _lastDetailsTap;
  void _openDetails(CatalogItem item) {
    final now = DateTime.now();
    if (_lastDetailsTap != null &&
        now.difference(_lastDetailsTap!).inMilliseconds < 450) {
      return;
    }
    _lastDetailsTap = now;
    context.push('/details', extra: item);
  }

  Future<void> _openTelegram() => AppUpdateService.instance.openTelegram();

  String? _preloadedHeroId;
  void _preloadHeroStreams(CatalogItem item) {
    if (_preloadedHeroId == item.id) return;
    _preloadedHeroId = item.id;
    final key = StreamsKey(
      id: item.id,
      permalink: item.permalink,
      isSeries: item.isSeries,
      season: 1,
      episode: 1,
    );
    ref.read(streamsProvider(key).notifier).load(
      id: item.id,
      permalink: item.permalink,
      isSeries: item.isSeries,
      season: 1,
      episode: 1,
    );
  }

  Future<void> _watchHero(CatalogItem item) async {
    final key = StreamsKey(
      id: item.id,
      permalink: item.permalink,
      isSeries: item.isSeries,
      season: 1,
      episode: 1,
    );

    // Fast-track navigation: immediately launch PlayerScreen.
    // If streams are cached in memory, playback starts in ~1.5s.
    // If still resolving, PlayerScreen connects concurrently without
    // locking the UI thread in an artificial 4-second waiting loop.
    final cached = ref.read(streamsProvider(key));
    final streams = cached.streams;

    context.push('/player', extra: {
      'streams': streams,
      'title': item.title,
      'subtitle': '',
      'startPosition': Duration.zero,
      'itemId': item.id,
      'contentId': item.id,
      'permalink': item.permalink,
      'poster': item.poster,
      'backdrop': item.backdrop,
      'isSeries': item.isSeries,
      'season': 1,
      'episode': 1,
      'catalogItem': item,
    });
  }

  void _openContinueWatching(WatchProgressItem item) {
    context.push('/details', extra: item.toCatalogItem());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HomeState>(homeProvider, (previous, next) {
      if (next.data?.heroItem != null) {
        _preloadHeroStreams(next.data!.heroItem!);
      }
    });

    final state = ref.watch(homeProvider);
    final continueWatchingAsync = ref.watch(continueWatchingProvider);

    final statusBarHeight = MediaQuery.of(context).padding.top;
    const topBarContentHeight = 52.0;
    const categoryNavHeight = 44.0;
    final totalTopBarHeight =
        statusBarHeight + topBarContentHeight + categoryNavHeight;

    final filteredShelves = state.data != null
        ? _getFilteredShelves(state.data!.shelves)
        : <ShelfData>[];

    CatalogItem? activeHeroItem;
    if (state.data?.heroItem != null) {
      if (_selectedCategory == 'Shows') {
        if (state.data!.heroItem!.isSeries) {
          activeHeroItem = state.data!.heroItem;
        } else {
          for (final s in filteredShelves) {
            final found = s.items.firstWhere((i) => i.isSeries,
                orElse: () => s.items.first);
            activeHeroItem = found;
            break;
          }
        }
      } else if (_selectedCategory == 'Movies') {
        if (!state.data!.heroItem!.isSeries) {
          activeHeroItem = state.data!.heroItem;
        } else {
          for (final s in filteredShelves) {
            final found = s.items.firstWhere((i) => !i.isSeries,
                orElse: () => s.items.first);
            activeHeroItem = found;
            break;
          }
        }
      } else {
        activeHeroItem = state.data!.heroItem;
      }
    }

    return PopScope(
      canPop: !_isCategoriesPopupOpen && !_isAppsPopupOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isAppsPopupOpen) {
          _closeAppsPopup();
          return;
        }
        if (_isCategoriesPopupOpen) {
          _closeCategoriesPopup();
          return;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
          children: [
            // ── Fast, Virtualized Scrollable Body (Slivers) ────────────────────
            ScrollConfiguration(
              behavior: const ScrollBehavior().copyWith(
                overscroll: false,
              ),
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (_isAppsPopupOpen &&
                      notification.metrics.axis == Axis.vertical) {
                    _closeAppsPopup();
                  }
                  final offset = _scrollController.hasClients
                      ? _scrollController.offset
                      : 0.0;
                  if (offset <= 15.0) {
                    _accumulatedUpScroll = 0.0;
                    if (!_showCategoryNav) {
                      _showCategoryNav = true;
                      _categoryNavAnimController.forward();
                    }
                  } else if (notification.direction == ScrollDirection.reverse &&
                      offset > 30.0) {
                    // Scrolling DOWN: Hide category navigation and reset accumulated up distance
                    _accumulatedUpScroll = 0.0;
                    if (_showCategoryNav) {
                      _showCategoryNav = false;
                      _categoryNavAnimController.reverse();
                    }
                  }
                  // Note: Intentionally do NOT immediately expand on ScrollDirection.forward.
                  // Only expand if accumulated upward scroll reaches threshold (handled in _onScroll)
                  // or user scrolls back to the very top.
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    if (state.isLoading && state.data == null) ...[
                      SliverToBoxAdapter(
                        child: SizedBox(height: totalTopBarHeight + 10),
                      ),
                      const SliverToBoxAdapter(child: ShimmerHero()),
                      const SliverToBoxAdapter(child: ShimmerShelf()),
                      const SliverToBoxAdapter(child: ShimmerShelf()),
                      const SliverToBoxAdapter(child: ShimmerShelf()),
                    ] else if (state.error != null && state.data == null) ...[
                      SliverToBoxAdapter(
                        child: SizedBox(height: totalTopBarHeight + 20),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: _ErrorView(
                            message: state.error!,
                            onRetry: () => ref
                                .read(homeProvider.notifier)
                                .load(forceRefresh: true),
                          ),
                        ),
                      ),
                    ] else if (state.data != null) ...[
                      // Hero Section
                      if (activeHeroItem != null)
                        SliverToBoxAdapter(
                          child: RepaintBoundary(
                            child: HeroBanner(
                              item: activeHeroItem,
                              topPadding: totalTopBarHeight + 8,
                              onTap: _openDetails,
                              onWatch: _watchHero,
                            ),
                          ),
                        ),

                      // Continue Watching Catalogue (only when on full Home)
                      if (_selectedCategory == null)
                        SliverToBoxAdapter(
                          child: continueWatchingAsync.when(
                            data: (items) {
                              if (items.isEmpty) return const SizedBox.shrink();
                              return RepaintBoundary(
                                child: ContinueWatchingShelf(
                                  items: items,
                                  onItemTap: _openContinueWatching,
                                ),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ),

                      // Virtualized Shelves (Only renders visible shelves)
                      SliverList.builder(
                        itemCount: filteredShelves.length,
                        itemBuilder: (context, index) {
                          final shelf = filteredShelves[index];
                          return RepaintBoundary(
                            child: ShelfRow(
                              title: shelf.title,
                              items: shelf.items,
                              onItemTap: _openDetails,
                            ),
                          );
                        },
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 110)),
                    ],
                  ],
                ),
              ),
            ),

            // ── Apple-Inspired Liquid Glass Top Bar (Zero-Rebuild Opacity Update) ─
            ValueListenableBuilder<double>(
              valueListenable: _appBarOpacity,
              builder: (context, opacity, child) {
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: opacity * 20.0,
                          sigmaY: opacity * 20.0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF09090D).withValues(
                              alpha: 0.76 * opacity,
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: 0.08 * opacity,
                                ),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Netmix Brand Logo + "Home" text + Telegram Icon Button
                    Container(
                      height: topBarContentHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/images/netmix_n_logo.png',
                                height: 31,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Home',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          _TelegramIconButton(onTap: _openTelegram),
                          const SizedBox(width: 8),
                          _ThreeDotIconButton(
                            key: _threeDotKey,
                            onTap: _toggleAppsPopup,
                            isOpen: _isAppsPopupOpen,
                          ),
                        ],
                      ),
                    ),

                    // Row 2: Apple Liquid Glass Category Navigation Bar (Direction-sensitive animated hide/show)
                    SizeTransition(
                      sizeFactor: _categoryNavAnimation,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(
                        opacity: _categoryNavAnimation,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: HomeCategoryNavBar(
                            selectedCategory: _selectedCategory,
                            onCategorySelected: _onCategorySelected,
                            categoriesKey: _categoriesKey,
                            onCategoriesTap: _toggleCategoriesPopup,
                            isCategoriesOpen: _isCategoriesPopupOpen,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Categories Liquid Glass Popup Overlay ─────────────────────────
            if (_isCategoriesPopupOpen || _popupAnimController.value > 0)
              AnimatedBuilder(
                animation: _popupAnimation,
                builder: (context, _) {
                  if (_popupAnimController.value == 0 &&
                      !_isCategoriesPopupOpen) {
                    return const SizedBox.shrink();
                  }
                  final buttonRect = _getCategoriesButtonRect();
                  return CategoriesGlassPopup(
                    buttonRect: buttonRect,
                    animation: _popupAnimation,
                    categories: _buildPopupCategories(state.data?.shelves),
                    selectedCategory: _selectedCategory,
                    onSelectCategory: _onCategorySelected,
                    onClose: _closeCategoriesPopup,
                  );
                },
              ),

            // ── OTT Apps Liquid Glass Floating Page ───────────────────────────
            if (_isAppsPopupOpen || _appsPopupAnimController.value > 0)
              AnimatedBuilder(
                animation: _appsPopupAnimation,
                builder: (context, _) {
                  if (_appsPopupAnimController.value == 0 &&
                      !_isAppsPopupOpen) {
                    return const SizedBox.shrink();
                  }
                  final buttonRect = _getThreeDotButtonRect();
                  return AppsGlassPopup(
                    buttonRect: buttonRect,
                    animation: _appsPopupAnimation,
                    onSelectApp: _onAppSelected,
                    onClose: _closeAppsPopup,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

const String _telegramSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#29B6F6" d="M12,0C5.373,0 0,5.373 0,12s5.373,12 12,12 12,-5.373 12,-12S18.627,0 12,0z"/>
  <path fill="#FFFFFF" d="m5.421,11.971 c2.946,-1.284 4.912,-2.13 5.897,-2.54 2.812,-1.17 3.398,-1.374 3.78,-1.381 0.084,-0.002 0.272,0.019 0.393,0.118 0.103,0.083 0.131,0.196 0.145,0.275 0.014,0.079 0.031,0.259 0.018,0.399 -0.155,1.632 -0.825,5.586 -1.166,7.408 -0.144,0.771 -0.428,1.029 -0.702,1.055 -0.597,0.055 -1.05,-0.395 -1.628,-0.774 -0.905,-0.593 -1.416,-0.962 -2.295,-1.541 -1.016,-0.669 -0.357,-1.037 0.222,-1.638 0.151,-0.157 2.784,-2.553 2.835,-2.771 0.006,-0.027 0.012,-0.129 -0.048,-0.183 -0.061,-0.053 -0.15,-0.035 -0.215,-0.02 -0.092,0.021 -1.56,0.991 -4.403,2.909 -0.416,0.286 -0.793,0.426 -1.13,0.419 -0.372,-0.008 -1.087,-0.21 -1.619,-0.383 -0.653,-0.212 -1.172,-0.324 -1.127,-0.684 0.023,-0.188 0.283,-0.38 0.778,-0.578z"/>
</svg>
''';

class _TelegramIconButton extends StatefulWidget {
  final VoidCallback onTap;

  const _TelegramIconButton({required this.onTap});

  @override
  State<_TelegramIconButton> createState() => _TelegramIconButtonState();
}

class _TelegramIconButtonState extends State<_TelegramIconButton> {
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
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29B6F6).withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SvgPicture.string(
            _telegramSvg,
            width: 34,
            height: 34,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.onSurfaceMuted, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Unable to connect',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ThreeDotIconButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isOpen;

  const _ThreeDotIconButton({
    super.key,
    required this.onTap,
    this.isOpen = false,
  });

  @override
  State<_ThreeDotIconButton> createState() => _ThreeDotIconButtonState();
}

class _ThreeDotIconButtonState extends State<_ThreeDotIconButton> {
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
        child: SizedBox(
          width: 32,
          height: 34,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return RotationTransition(
                  turns: child.key == const ValueKey('close')
                      ? Tween<double>(begin: -0.25, end: 0.0).animate(animation)
                      : Tween<double>(begin: 0.25, end: 0.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: widget.isOpen
                  ? const Icon(
                      Icons.close_rounded,
                      key: ValueKey('close'),
                      color: Colors.white,
                      size: 22,
                    )
                  : const _VerticalColonDots(key: ValueKey('dots')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two crisp round vertical dots ": " without any rounded circle container
class _VerticalColonDots extends StatelessWidget {
  const _VerticalColonDots({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4.5),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
