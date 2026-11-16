// lib/providers/details_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/catalog_item.dart';

class DetailsState {
  final CatalogItem? details;
  final bool isLoading;
  final String? error;

  const DetailsState({this.details, this.isLoading = false, this.error});

  DetailsState copyWith({CatalogItem? details, bool? isLoading, String? error}) =>
      DetailsState(
        details: details ?? this.details,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class DetailsNotifier extends StateNotifier<DetailsState> {
  DetailsNotifier() : super(const DetailsState());

  Future<void> load(CatalogItem item) async {
    // If full details (with seasons for series or already loaded) exist, avoid re-fetching
    if (state.details != null &&
        (state.details!.seasons.isNotEmpty || !item.isSeries) &&
        !state.isLoading) {
      return;
    }
    // Retain initial item data immediately so UI renders with basic metadata instantly
    state = DetailsState(
      details: state.details ?? item,
      isLoading: true,
    );
    try {
      final json = await ApiClient.instance.getDetails(
        id: item.id,
        permalink: item.permalink,
        title: item.title,
      );
      final detailsJson = json['details'] as Map<String, dynamic>? ?? {};
      final existingTitle = item.title.trim();
      final fullTitle = (detailsJson['title'] ??
              detailsJson['name'] ??
              detailsJson['rawTitle'] ??
              detailsJson['original_title'] ??
              detailsJson['original_name'] ??
              existingTitle)
          .toString()
          .trim();

      // Resolve backend permalink: if backend returned a streaming permalink, use it!
      final rawBackendPerm = detailsJson['permalink']?.toString() ?? '';
      final resolvedPermalink = (rawBackendPerm.isNotEmpty && !rawBackendPerm.contains('/title/'))
          ? rawBackendPerm
          : (detailsJson['backendPermalink']?.toString() ?? item.permalink);

      final full = CatalogItem.fromJson({
        ...detailsJson,
        'id': item.id,
        'permalink': resolvedPermalink,
        'title': fullTitle.isNotEmpty ? fullTitle : existingTitle,
        'poster': item.poster ?? detailsJson['poster'],
        'backdrop': item.backdrop ?? detailsJson['backdrop'],
        'logo': detailsJson['logo'] ?? item.logo,
        'imdbId': detailsJson['imdbId'] ?? item.imdbId,
      });
      state = DetailsState(details: full, isLoading: false);
    } catch (e) {
      // Retain the basic item on error
      state = DetailsState(
        details: state.details ?? item,
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

// Family of providers keyed by item id
final detailsProvider =
    StateNotifierProvider.family<DetailsNotifier, DetailsState, String>(
  (ref, itemId) => DetailsNotifier(),
);
