// lib/providers/search_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';

class SearchState {
  final String query;
  final List<CatalogItem> results;
  final bool isLoading;
  final String? error;
  final List<String> searchHistory;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.searchHistory = const [],
  });

  SearchState copyWith({
    String? query,
    List<CatalogItem>? results,
    bool? isLoading,
    String? error,
    List<String>? searchHistory,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchHistory: searchHistory ?? this.searchHistory,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  static const String _historyKey = 'netmix_search_history';
  Timer? _debounce;
  final Map<String, List<CatalogItem>> _cache = {};

  SearchNotifier() : super(const SearchState()) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_historyKey) ?? [];
      state = state.copyWith(searchHistory: list);
    } catch (_) {}
  }

  Future<void> addHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(state.searchHistory);
      current.removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase());
      current.insert(0, trimmed);
      if (current.length > 12) {
        current.removeRange(12, current.length);
      }
      await prefs.setStringList(_historyKey, current);
      state = state.copyWith(searchHistory: current);
    } catch (_) {}
  }

  Future<void> removeHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(state.searchHistory);
      current.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());
      await prefs.setStringList(_historyKey, current);
      state = state.copyWith(searchHistory: current);
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      state = state.copyWith(searchHistory: []);
    } catch (_) {}
  }

  void setQuery(String q, {bool immediate = false}) {
    state = state.copyWith(query: q);
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(results: [], isLoading: false, error: null);
      return;
    }

    if (immediate) {
      _search(trimmed);
      addHistory(trimmed);
      return;
    }

    final key = trimmed.toLowerCase();
    // Immediate response from cache if available
    if (_cache.containsKey(key)) {
      state = state.copyWith(
        results: _cache[key]!,
        isLoading: false,
        error: null,
      );
      // Background refresh
      _debounce = Timer(AppConstants.searchDebounce, () => _search(trimmed, isBackground: true));
      return;
    }

    // Debounce network request
    _debounce = Timer(AppConstants.searchDebounce, () => _search(trimmed));
  }

  Future<void> _search(String q, {bool isBackground = false}) async {
    if (!isBackground) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final json = await ApiClient.instance.search(q);
      // Cancel/ignore outdated requests if query has changed in the meantime
      if (state.query.trim().toLowerCase() != q.toLowerCase()) return;

      final raw = json['items'] as List? ?? [];
      final items = raw
          .map((j) {
            try {
              return CatalogItem.fromJson(j as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<CatalogItem>()
          .toList();

      // Store in memory cache
      _cache[q.toLowerCase()] = items;

      if (state.query.trim().toLowerCase() == q.toLowerCase()) {
        state = state.copyWith(results: items, isLoading: false, error: null);
        if (items.isNotEmpty && q.trim().length >= 2) {
          addHistory(q.trim());
        }
      }
    } catch (e) {
      if (state.query.trim().toLowerCase() == q.toLowerCase()) {
        state = state.copyWith(
          isLoading: false,
          error: state.results.isEmpty ? 'Search failed. Please check your connection and try again.' : null,
        );
      }
    }
  }

  void clear() {
    _debounce?.cancel();
    state = state.copyWith(query: '', results: [], isLoading: false, error: null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
  (ref) => SearchNotifier(),
);
