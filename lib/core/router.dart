// lib/core/router.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/player_screen.dart';
import '../screens/details_sheet.dart';
import '../screens/splash_screen.dart';
import '../screens/category_screen.dart';
import '../models/catalog_item.dart';
import '../models/stream_info.dart';
import '../services/netflix_metadata_service.dart';
import '../services/ad_verification_service.dart';
import '../screens/we_need_support_screen.dart';

// Route path constants
class AppRoutes {
  static const String splash = '/splash';
  static const String support = '/support';
  static const String home = '/';
  static const String category = '/category';
  static const String search = '/search';
  static const String downloads = '/downloads';
  static const String settings = '/settings';
  static const String details = '/details';
  static const String player = '/player';
}

// Shell route navigator keys – one per bottom-tab so each has its own back stack
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _searchNavKey = GlobalKey<NavigatorState>(debugLabel: 'search');
final _downloadsNavKey = GlobalKey<NavigatorState>(debugLabel: 'downloads');
final _settingsNavKey = GlobalKey<NavigatorState>(debugLabel: 'settings');
final _rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouter = GoRouter(
  navigatorKey: _rootNavKey,
  initialLocation: AppRoutes.splash,
  refreshListenable: AdVerificationService.instance,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    // Splash screen is always allowed to finish its intro video
    if (loc == AppRoutes.splash) {
      return null;
    }
    final hasAccess = AdVerificationService.instance.isAccessGranted;
    if (!hasAccess && loc != AppRoutes.support) {
      return AppRoutes.support;
    }
    if (hasAccess && loc == AppRoutes.support) {
      return AppRoutes.home;
    }
    return null;
  },
  routes: [
    // Splash screen route
    GoRoute(
      parentNavigatorKey: _rootNavKey,
      path: AppRoutes.splash,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SplashScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ),
    // Mandatory Ad Verification & Support Screen
    GoRoute(
      parentNavigatorKey: _rootNavKey,
      path: AppRoutes.support,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const WeNeedSupportScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ),
    // Full-screen routes (no bottom nav)
    GoRoute(
      parentNavigatorKey: _rootNavKey,
      path: AppRoutes.player,
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          child: PlayerScreen(
            streams: (extra['streams'] as List<StreamInfo>?) ?? const [],
            title: extra['title'] as String? ?? 'Playing',
            subtitle: extra['subtitle'] as String? ?? '',
            startPosition: extra['startPosition'] as Duration? ?? Duration.zero,
            itemId: extra['itemId'] as String? ?? '',
            contentId: extra['contentId'] as String?,
            permalink: extra['permalink'] as String?,
            poster: extra['poster'] as String?,
            backdrop: extra['backdrop'] as String?,
            isSeries: extra['isSeries'] as bool? ?? false,
            season: extra['season'] as int? ?? 1,
            episode: extra['episode'] as int? ?? 1,
            catalogItem: extra['catalogItem'] as CatalogItem?,
            episodes: (extra['episodes'] as List?)?.cast<EpisodeData>(),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavKey,
      path: AppRoutes.details,
      builder: (context, state) {
        final item = state.extra as CatalogItem;
        return DetailsSheet(item: item);
      },
    ),

    // Shell with bottom navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _RootShell(shell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavKey,
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (_, __) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'category',
                  builder: (context, state) {
                    final categoryName =
                        (state.extra as String?) ?? 'Movies';
                    return CategoryScreen(categoryName: categoryName);
                  },
                ),
                GoRoute(
                  parentNavigatorKey: _rootNavKey,
                  path: 'details',
                  builder: (context, state) {
                    final item = state.extra as CatalogItem;
                    return DetailsSheet(item: item);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _searchNavKey,
          routes: [
            GoRoute(
              path: AppRoutes.search,
              builder: (_, __) => const SearchScreen(),
              routes: [
                GoRoute(
                  parentNavigatorKey: _rootNavKey,
                  path: 'details',
                  builder: (context, state) {
                    final item = state.extra as CatalogItem;
                    return DetailsSheet(item: item);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _downloadsNavKey,
          routes: [
            GoRoute(
              path: AppRoutes.downloads,
              builder: (_, __) => const DownloadsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavKey,
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (_, __) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

// ── Bottom-nav shell with Floating Liquid Glass ──────────────────────────────
class _RootShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _RootShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    const double barHeight = 58.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return GlassScaffold(
      backgroundColor: const Color(0xFF000000),
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomBarHeight: barHeight,
      bottomBar: PreferredSize(
        preferredSize: const Size.fromHeight(barHeight),
        child: AnimatedOpacity(
          opacity: isKeyboardOpen ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: isKeyboardOpen,
            child: Material(
              type: MaterialType.transparency,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: isTablet ? 420.0 : double.infinity,
                  child: GlassTabBar.bottom(
            selectedIndex: shell.currentIndex,
            onTabSelected: (index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            ),
            tabs: [
              const GlassTab(
                icon: Icon(CupertinoIcons.house),
                activeIcon: Icon(CupertinoIcons.house_fill),
                semanticLabel: 'Home',
              ),
              const GlassTab(
                icon: Icon(CupertinoIcons.search),
                activeIcon: Icon(CupertinoIcons.search),
                semanticLabel: 'Search',
              ),
              const GlassTab(
                icon: Icon(CupertinoIcons.arrow_down_circle),
                activeIcon: Icon(CupertinoIcons.arrow_down_circle_fill),
                semanticLabel: 'Downloads',
              ),
              GlassTab(
                icon: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6.5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5.5),
                    child: Opacity(
                      opacity: 0.65,
                      child: Image.asset(
                        'assets/images/profile_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                activeIcon: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6.5),
                    border: Border.all(
                      color: Colors.white,
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/profile_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.35),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                semanticLabel: 'Settings',
              ),
            ],
            settings: const LiquidGlassSettings(
              glassColor: Color(0x9E1C1C26), // Lighter translucent charcoal glass
              blur: 24.0, // Smooth background blur
              thickness: 18.0,
              ambientStrength: 0.20,
              fresnelStrength: 0.30,
              lightIntensity: 0.35,
              rimLight: 0.20,
              refractiveIndex: 1.15,
            ),
            indicatorSettings: const LiquidGlassSettings(
              glassColor: Color(0x28FFFFFF), // Apple translucent white glass highlight
              blur: 10.0,
              thickness: 8.0,
              ambientStrength: 0.25,
              fresnelStrength: 0.25,
              lightIntensity: 0.35,
            ),
            selectedIconColor: Colors.white, // Active icon is pure white
            unselectedIconColor: const Color(0x8AFFFFFF), // Muted translucent gray
            showIndicator: true,
            indicatorColor: const Color(0x28FFFFFF), // Apple translucent pill
            iconSize: 26.0, // Increased icon size for clean tactile interaction
            barHeight: barHeight,
            horizontalPadding: 24,
            verticalPadding: 16,
          ),
        ),
      ),
    ),
  ),
),
),
body: shell,
);
  }
}
