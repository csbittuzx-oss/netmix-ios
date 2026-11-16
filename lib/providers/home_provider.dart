// lib/providers/home_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';

// ── Data class ────────────────────────────────────────────────────────────────
class HomeData {
  final CatalogItem? heroItem;
  final List<ShelfData> shelves;

  const HomeData({this.heroItem, required this.shelves});

  List<CatalogItem> get heroItems => heroItem != null ? [heroItem!] : const [];
}

class ShelfData {
  final String title;
  final List<CatalogItem> items;

  const ShelfData({required this.title, required this.items});
}

// ── State ─────────────────────────────────────────────────────────────────────
class HomeState {
  final HomeData? data;
  final bool isLoading;
  final String? error;
  final DateTime? lastFetch;

  const HomeState({
    this.data,
    this.isLoading = false,
    this.error,
    this.lastFetch,
  });

  bool get isCacheValid {
    if (lastFetch == null) return false;
    return DateTime.now().difference(lastFetch!) < AppConstants.homeCacheDuration;
  }

  HomeState copyWith({
    HomeData? data,
    bool? isLoading,
    String? error,
    DateTime? lastFetch,
  }) {
    return HomeState(
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastFetch: lastFetch ?? this.lastFetch,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class HomeNotifier extends StateNotifier<HomeState> {
  static const String _prefHomeCacheKey = 'netmix_home_cached_json_v1';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _connectivityDebounce;
  bool _isInitLoaded = false;
  bool _isLoadingNetwork = false;

  HomeNotifier() : super(const HomeState()) {
    _initFromCache();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
      if (isOnline && (state.error != null || state.data == null)) {
        _connectivityDebounce?.cancel();
        _connectivityDebounce = Timer(const Duration(seconds: 2), () {
          debugPrint('[HomeNotifier] Internet restored, auto-refreshing home catalog...');
          load(forceRefresh: true);
        });
      }
    });
  }

  Future<void> _initFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJsonStr = prefs.getString(_prefHomeCacheKey);
      if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
        final decoded = jsonDecode(cachedJsonStr) as Map<String, dynamic>;
        final cachedData = _parseHomeData(decoded);
        if (cachedData.shelves.isNotEmpty && state.data == null) {
          state = state.copyWith(data: cachedData);
          debugPrint('[HomeNotifier] Loaded ${cachedData.shelves.length} shelves immediately from local cache');
        }
      }
    } catch (e) {
      debugPrint('[HomeNotifier] Cache restore error: $e');
    }
  }

  Future<void> load({bool forceRefresh = false}) async {
    // 1. Ensure local cache is loaded first if state is still blank
    if (state.data == null && !_isInitLoaded) {
      await _initFromCache();
      _isInitLoaded = true;
    }

    // Preserve cached data if valid and not a forced refresh
    if (!forceRefresh && state.data != null && state.isCacheValid) return;

    if (_isLoadingNetwork) {
      debugPrint('[HomeNotifier] Already loading network catalog, ignoring duplicate concurrent call');
      return;
    }
    _isLoadingNetwork = true;

    // Only set isLoading if we have no prior data (avoids jarring full-screen flash)
    if (state.data == null) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final json = await ApiClient.instance.getHome();
      var data = _parseHomeData(json);

      // Filter out any anime shelf from home
      final filteredShelves = data.shelves
          .where((s) =>
              !s.title.toLowerCase().contains('anime') &&
              !s.items.any((i) => i.id.startsWith('animesalt_')))
          .toList();
      data = HomeData(heroItem: data.heroItem, shelves: filteredShelves);

      // Persist to local cache for instant zero-latency future launches
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefHomeCacheKey, jsonEncode(json));
      } catch (_) {}

      state = state.copyWith(
        data: data,
        isLoading: false,
        error: null,
        lastFetch: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[HomeNotifier] Load error: $e');
      // If we already have cached data, NEVER turn entire screen into an error! Keep content visible.
      if (state.data != null) {
        state = state.copyWith(isLoading: false, error: null);
      } else {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    } finally {
      _isLoadingNetwork = false;
    }
  }

  @override
  void dispose() {
    _connectivityDebounce?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  HomeData _parseHomeData(Map<String, dynamic> json) {
    List<CatalogItem> parseShelf(dynamic raw) {
      if (raw == null || raw is! List) return [];
      final items = <CatalogItem>[];
      final shelfSeen = <String>{};
      for (final j in raw) {
        if (j is! Map<String, dynamic>) continue;
        try {
          final item = CatalogItem.fromJson(j);
          if (item.id.isNotEmpty && shelfSeen.add(item.id)) {
            items.add(item);
          }
        } catch (_) {}
      }
      return items;
    }

    // 1. Featured hero item
    CatalogItem? heroItem;
    final heroRaw = json['hero'] ?? json['featured'];
    if (heroRaw is Map<String, dynamic>) {
      try {
        final item = CatalogItem.fromJson(heroRaw);
        if (item.id.isNotEmpty) heroItem = item;
      } catch (_) {}
    } else if (heroRaw is List && heroRaw.isNotEmpty) {
      for (final j in heroRaw) {
        if (j is! Map<String, dynamic>) continue;
        try {
          final item = CatalogItem.fromJson(j);
          if (item.id.isNotEmpty) {
            heroItem = item;
            break;
          }
        } catch (_) {}
      }
    }

    String cleanTitle(String raw) {
      return raw
          .replaceAll(
            RegExp(
              r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}\u{1F100}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1FA00}-\u{1FAFF}\u{FE0F}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[^\w\s]+', unicode: true), '')
          .trim();
    }

    // 2. Parse all categories from `sections`
    final shelves = <ShelfData>[];
    final sectionsRaw = json['sections'];
    if (sectionsRaw is List) {
      for (final sec in sectionsRaw) {
        if (sec is! Map<String, dynamic>) continue;
        final rawTitle = sec['title']?.toString() ?? 'Featured';
        final title = cleanTitle(rawTitle);
        final items = parseShelf(sec['items']);
        if (items.isNotEmpty) {
          shelves.add(ShelfData(title: title, items: items));
        }
      }

      // Promote 'Top 10 Shows Today' to position 2 (after Trending Now & Top Web Series)
      final top10Idx = shelves.indexWhere((s) {
        final t = s.title.toLowerCase();
        return t.contains('top 10 show') || t.contains('top 10 shows');
      });
      if (top10Idx > 2) {
        final top10Shelf = shelves.removeAt(top10Idx);
        final insertIdx = shelves.length >= 2 ? 2 : shelves.length;
        shelves.insert(insertIdx, top10Shelf);
      }
    }

    // Fallback if sections array is not present
    if (shelves.isEmpty) {
      final shelfKeys = [
        ['trending', 'Trending Now'],
        ['series', 'Top Web Series & Binge Shows'],
        ['action', 'Action & Adventure Blockbusters'],
        ['comedy', 'Comedy & Family Entertainers'],
        ['romance', 'Romance & Love Stories'],
        ['horror', 'Horror & Supernatural Thrillers'],
        ['thriller', 'Suspense, Crime & Mystery Thrillers'],
        ['scifi', 'Sci-Fi & Fantasy Universe'],
        ['bollywood', 'Bollywood & Hindi Cinema'],
        ['hollywood', 'Hollywood & Dual Audio Hits'],
        ['south', 'South Indian Action (Hindi Dubbed)'],
      ];
      for (final kv in shelfKeys) {
        final key = kv[0];
        final label = kv[1];
        final raw = json[key] ?? json['${key}Movies'] ?? json['${key}Series'];
        if (raw != null) {
          final items = parseShelf(raw);
          if (items.isNotEmpty) {
            shelves.add(ShelfData(title: label, items: items));
          }
        }
      }
    }

    // If hero was not in API, pick the first item from the first shelf as featured
    if (heroItem == null && shelves.isNotEmpty && shelves.first.items.isNotEmpty) {
      heroItem = shelves.first.items.first;
    }

    return HomeData(heroItem: heroItem, shelves: shelves);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>(
  (ref) => HomeNotifier(),
);
