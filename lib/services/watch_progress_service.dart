// lib/services/watch_progress_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/catalog_item.dart';
import 'auth_service.dart';

class WatchProgressItem {
  final String contentId;
  final String title;
  final String? poster;
  final String? backdrop;
  final bool isSeries;
  final int season;
  final int episode;
  final String? episodeTitle;
  final int positionMs;
  final int durationMs;
  final int lastWatchedAt; // epoch ms
  final String? permalink;

  const WatchProgressItem({
    required this.contentId,
    required this.title,
    this.poster,
    this.backdrop,
    this.isSeries = false,
    this.season = 1,
    this.episode = 1,
    this.episodeTitle,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAt,
    this.permalink,
  });

  double get progressFraction {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  bool get isCompleted {
    if (durationMs <= 0) return false;
    final remainingMs = durationMs - positionMs;
    return progressFraction >= 0.95 || remainingMs < 60000; // < 1 min remaining
  }

  Duration get remainingDuration {
    if (durationMs <= 0) return Duration.zero;
    final diff = durationMs - positionMs;
    return Duration(milliseconds: diff < 0 ? 0 : diff);
  }

  String get remainingFormatted {
    if (durationMs <= 0) return '';
    final r = remainingDuration;
    if (r.inHours > 0) {
      return '${r.inHours}h ${r.inMinutes.remainder(60)}m remaining';
    }
    return '${r.inMinutes}m remaining';
  }

  String get subtitleLabel {
    if (isSeries) {
      final rem = remainingFormatted;
      if (rem.isNotEmpty) return 'S$season:E$episode · $rem';
      return 'S$season:E$episode';
    }
    return remainingFormatted;
  }

  CatalogItem toCatalogItem() {
    return CatalogItem(
      id: contentId,
      title: title,
      permalink: permalink ?? '',
      poster: poster,
      backdrop: backdrop,
      isSeries: isSeries,
    );
  }

  Map<String, dynamic> toJson() => {
        'contentId': contentId,
        'title': title,
        'poster': poster,
        'backdrop': backdrop,
        'isSeries': isSeries,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatchedAt': lastWatchedAt,
        'permalink': permalink,
      };

  factory WatchProgressItem.fromJson(Map<String, dynamic> json) =>
      WatchProgressItem(
        contentId: json['contentId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        poster: json['poster']?.toString(),
        backdrop: json['backdrop']?.toString(),
        isSeries: json['isSeries'] == true,
        season: (json['season'] as num?)?.toInt() ?? 1,
        episode: (json['episode'] as num?)?.toInt() ?? 1,
        episodeTitle: json['episodeTitle']?.toString(),
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        lastWatchedAt: (json['lastWatchedAt'] as num?)?.toInt() ?? 0,
        permalink: json['permalink']?.toString(),
      );
}

class WatchProgressService extends ChangeNotifier {
  static final WatchProgressService instance = WatchProgressService._();
  WatchProgressService._();

  String _getStorageKey(String userId) => 'netmix_watch_history_$userId';

  /// Saves watch progress scoped to the active user account.
  Future<void> saveProgress({
    required String userId,
    required String contentId,
    required String title,
    String? poster,
    String? backdrop,
    bool isSeries = false,
    int season = 1,
    int episode = 1,
    String? episodeTitle,
    required int positionMs,
    required int durationMs,
    String? permalink,
  }) async {
    // Only record progress if watched at least 5 seconds
    if (positionMs < 5000) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final list = await getHistoryList(userId);

      // Create new record
      final newItem = WatchProgressItem(
        contentId: contentId,
        title: title,
        poster: poster,
        backdrop: backdrop,
        isSeries: isSeries,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        positionMs: positionMs,
        durationMs: durationMs,
        lastWatchedAt: DateTime.now().millisecondsSinceEpoch,
        permalink: permalink,
      );

      // Remove existing item for this same movie or same series episode
      list.removeWhere((item) =>
          item.contentId == contentId &&
          (!isSeries || (item.season == season && item.episode == episode)));

      // If series, also remove any older episode of the same series so only the latest watched episode shows in Continue Watching
      if (isSeries) {
        list.removeWhere((item) => item.contentId == contentId);
      }

      // Add to front if not completed
      if (!newItem.isCompleted) {
        list.insert(0, newItem);
      }

      // Keep up to 30 recent items
      if (list.length > 30) {
        list.removeRange(30, list.length);
      }

      final encoded = jsonEncode(list.map((i) => i.toJson()).toList());
      await prefs.setString(key, encoded);

      // Persist per-episode progress for detailed episode banner progress line
      if (isSeries) {
        final epKey = 'netmix_ep_prog_${userId}_${contentId}_s${season}e$episode';
        await prefs.setString(
          epKey,
          jsonEncode({'pos': positionMs, 'dur': durationMs}),
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[WatchProgressService] saveProgress error: $e');
    }
  }

  /// Retrieves progress fractions (0.0 to 1.0) for a set of episodes in a season
  Future<Map<int, double>> getSeasonEpisodesProgress({
    required String userId,
    required String contentId,
    required int season,
    required List<int> episodeNumbers,
  }) async {
    final Map<int, double> result = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final epNum in episodeNumbers) {
        final epKey = 'netmix_ep_prog_${userId}_${contentId}_s${season}e$epNum';
        final raw = prefs.getString(epKey);
        if (raw != null && raw.isNotEmpty) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final pos = (data['pos'] as num?)?.toDouble() ?? 0.0;
          final dur = (data['dur'] as num?)?.toDouble() ?? 0.0;
          if (dur > 0 && pos > 0) {
            result[epNum] = (pos / dur).clamp(0.0, 1.0);
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Retrieves full history list for a user account
  Future<List<WatchProgressItem>> getHistoryList(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw) as List?;
      if (decoded == null) return [];

      return decoded
          .map((j) => WatchProgressItem.fromJson(j as Map<String, dynamic>))
          .where((i) => i.contentId.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[WatchProgressService] getHistoryList error: $e');
      return [];
    }
  }

  /// Retrieves active Continue Watching catalogue (non-completed items with > 5s watched)
  Future<List<WatchProgressItem>> getContinueWatching(String userId) async {
    final list = await getHistoryList(userId);
    return list.where((i) => !i.isCompleted && i.positionMs >= 5000).toList();
  }

  /// Retrieves the latest saved progress for a content ID (movie or series)
  Future<WatchProgressItem?> getProgress(String userId, String contentId) async {
    final list = await getHistoryList(userId);
    try {
      return list.firstWhere((i) => i.contentId == contentId);
    } catch (_) {
      return null;
    }
  }

  /// Clears progress for a specific content
  Future<void> removeProgress(String userId, String contentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId);
      final list = await getHistoryList(userId);
      list.removeWhere((i) => i.contentId == contentId);
      await prefs.setString(
          key, jsonEncode(list.map((i) => i.toJson()).toList()));
      notifyListeners();
    } catch (_) {}
  }
}

// ── Riverpod Provider ─────────────────────────────────────────────────────────

final watchProgressServiceProvider =
    ChangeNotifierProvider<WatchProgressService>((ref) {
  return WatchProgressService.instance;
});

final continueWatchingProvider =
    FutureProvider.autoDispose<List<WatchProgressItem>>((ref) async {
  final auth = ref.watch(authProvider);
  final userId = auth.currentUser.id;
  final service = ref.watch(watchProgressServiceProvider);

  return await service.getContinueWatching(userId);
});
