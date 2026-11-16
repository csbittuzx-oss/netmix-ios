// lib/models/catalog_item.dart
import 'package:equatable/equatable.dart';

class CatalogItem extends Equatable {
  final String id;
  final String? imdbId;
  final String title;
  final String permalink;
  final String? poster;
  final String? backdrop;
  final String? logo;
  final String? year;
  final String? rating;
  final String type; // 'movie' | 'series' | 'anime'
  final List<String> genres;
  final String? description;
  final bool isSeries;
  final bool isAnime;
  final String? provider;
  final List<Season> seasons;
  final List<String> audioLanguages;
  final String? quality;
  final List<String> qualities;
  final String? rawTitle;

  const CatalogItem({
    required this.id,
    this.imdbId,
    required this.title,
    required this.permalink,
    this.poster,
    this.backdrop,
    this.logo,
    this.year,
    this.rating,
    this.type = 'movie',
    this.genres = const [],
    this.description,
    this.isSeries = false,
    this.isAnime = false,
    this.provider,
    this.seasons = const [],
    this.audioLanguages = const [],
    this.quality,
    this.qualities = const [],
    this.rawTitle,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    List<String> parseStrList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return v.split(',').map((e) => e.trim()).toList();
      return [];
    }

    String? resolvedImdbId;
    final explicitImdb = json['imdbId']?.toString() ?? json['imdb_id']?.toString();
    if (explicitImdb != null && explicitImdb.trim().isNotEmpty) {
      resolvedImdbId = explicitImdb.trim();
    } else {
      final rawId = json['id']?.toString() ?? '';
      if (rawId.startsWith('tt')) {
        resolvedImdbId = rawId;
      } else {
        final perm = json['permalink']?.toString() ?? '';
        final m = RegExp(r'tt\d{5,}').firstMatch(perm);
        if (m != null) resolvedImdbId = m.group(0);
      }
    }

    String? resolvedLogo = json['logo']?.toString() ??
        json['logoUrl']?.toString() ??
        json['clearlogo']?.toString() ??
        json['clearLogo']?.toString() ??
        json['titleLogo']?.toString() ??
        json['title_logo']?.toString() ??
        json['logo_path']?.toString();
    if (resolvedLogo != null && resolvedLogo.startsWith('/')) {
      resolvedLogo = 'https://image.tmdb.org/t/p/original';
    }
    if (resolvedLogo == null && json['logos'] is List && (json['logos'] as List).isNotEmpty) {
      final first = (json['logos'] as List).first;
      if (first is Map && first['file_path'] != null) {
        resolvedLogo = 'https://image.tmdb.org/t/p/original';
      } else if (first is String) {
        resolvedLogo = first.startsWith('/') ? 'https://image.tmdb.org/t/p/original' : first;
      }
    }

    final resolvedTitle = (json['title'] ??
            json['name'] ??
            json['rawTitle'] ??
            json['original_title'] ??
            json['original_name'] ??
            '')
        .toString()
        .trim();

    return CatalogItem(
      id: json['id']?.toString() ?? json['permalink']?.toString() ?? '',
      imdbId: resolvedImdbId,
      title: resolvedTitle,
      permalink: json['permalink']?.toString() ?? '',
      poster: json['poster']?.toString() ??
          json['posterUrl']?.toString() ??
          json['image']?.toString(),
      backdrop: json['backdrop']?.toString() ??
          json['backdropUrl']?.toString() ??
          json['fanart']?.toString(),
      logo: resolvedLogo,
      year: json['year']?.toString() ?? json['releaseYear']?.toString(),
      rating: json['rating']?.toString() ?? json['imdbRating']?.toString(),
      type: json['type']?.toString() ?? 'movie',
      genres: parseStrList(json['genres'] ?? json['genre'] ?? json['categories']),
      description: json['description']?.toString() ??
          json['overview']?.toString() ??
          json['plot']?.toString(),
      isSeries: json['isSeries'] == true ||
          json['type'] == 'series' ||
          (json['permalink']?.toString() ?? '').contains('series') ||
          (json['permalink']?.toString() ?? '').contains('season') ||
          ((json['seasons'] as List?)?.isNotEmpty == true),
      isAnime: json['isAnime'] == true ||
          json['provider'] == 'animesalt' ||
          (json['id']?.toString() ?? '').startsWith('animesalt_') ||
          (json['permalink']?.toString() ?? '').contains('animesalt.cx'),
      provider: json['provider']?.toString(),
      seasons: (json['seasons'] as List?)
              ?.map((s) => Season.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      audioLanguages: parseStrList(json['audioLanguages']),
      quality: json['quality']?.toString(),
      qualities: parseStrList(json['qualities'] ?? json['availableQualities']),
      rawTitle: json['rawTitle']?.toString(),
    );
  }

  CatalogItem copyWith({
    String? id,
    String? title,
    String? permalink,
    String? poster,
    String? backdrop,
    String? logo,
    String? year,
    String? rating,
    String? type,
    List<String>? genres,
    String? description,
    bool? isSeries,
    bool? isAnime,
    String? provider,
    List<Season>? seasons,
    List<String>? audioLanguages,
    String? quality,
    List<String>? qualities,
    String? rawTitle,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      imdbId: imdbId,
      title: title ?? this.title,
      permalink: permalink ?? this.permalink,
      poster: poster ?? this.poster,
      backdrop: backdrop ?? this.backdrop,
      logo: logo ?? this.logo,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      type: type ?? this.type,
      genres: genres ?? this.genres,
      description: description ?? this.description,
      isSeries: isSeries ?? this.isSeries,
      isAnime: isAnime ?? this.isAnime,
      provider: provider ?? this.provider,
      seasons: seasons ?? this.seasons,
      audioLanguages: audioLanguages ?? this.audioLanguages,
      quality: quality ?? this.quality,
      qualities: qualities ?? this.qualities,
      rawTitle: rawTitle ?? this.rawTitle,
    );
  }

  /// All streaming qualities dynamically detected from metadata & sources
  List<String> get availableQualities {
    if (qualities.isNotEmpty) return qualities;
    final text = '${rawTitle ?? ''} $title $permalink ${genres.join(' ')} ${quality ?? ''}'.toLowerCase();
    final is4K = text.contains('4k') ||
        text.contains('2160p') ||
        text.contains('uhd') ||
        text.contains('ds4k') ||
        (quality != null && (quality!.toUpperCase().contains('4K') || quality!.contains('2160')));
    final is1080 = text.contains('1080p') ||
        text.contains('fhd') ||
        text.contains('web-dl') ||
        text.contains('bluray') ||
        text.contains('hdrip') ||
        (!is4K && !text.contains('720p') && !text.contains('480p'));
    final is720 = text.contains('720p') || text.contains('hd');
    final is480 = text.contains('480p') || text.contains('sd');

    final list = <String>[];
    if (is1080) list.add('1080p');
    if (is4K) list.add('4K');
    if (list.isEmpty) {
      if (is720) {
        list.add('720p');
      } else if (is480) {
        list.add('480p');
      } else {
        list.add('1080p');
      }
    }
    return list;
  }

  /// Single primary display quality label (e.g. '1080p', '4K', '720p')
  String get displayQuality {
    if (quality != null && quality!.isNotEmpty) {
      final qUpper = quality!.toUpperCase();
      if (qUpper.contains('4K') || qUpper.contains('2160')) return '4K';
      if (qUpper.contains('1080')) return '1080p';
      if (qUpper.contains('720')) return '720p';
      if (qUpper.contains('480')) return '480p';
      return quality!;
    }
    final qs = availableQualities;
    if (qs.contains('4K')) return '4K';
    if (qs.contains('1080p')) return '1080p';
    return qs.isNotEmpty ? qs.first : '1080p';
  }

  /// Whether this item represents AnimeSalt content
  bool get isAnimeContent =>
      isAnime ||
      type == 'anime' ||
      provider == 'animesalt' ||
      id.startsWith('animesalt_') ||
      permalink.contains('animesalt.cx');

  String get displayType {
    if (isAnimeContent) return 'ANIME';
    if (isSeries || type == 'series') return 'SERIES';
    return 'MOVIE';
  }

  @override
  List<Object?> get props => [id, permalink, quality];
}

// ── Season & Episode models ───────────────────────────────────────────────────

class Season extends Equatable {
  final int number;
  final String title;
  final List<Episode> episodes;

  const Season({
    required this.number,
    required this.title,
    this.episodes = const [],
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    final num = (json['seasonNumber'] ?? json['season'] ?? json['number'] ?? 1) is int
        ? (json['seasonNumber'] ?? json['season'] ?? json['number'] ?? 1)
        : int.tryParse(
                (json['seasonNumber'] ?? json['season'] ?? json['number'] ?? '1').toString()) ??
            1;
    final name = json['name']?.toString() ?? json['title']?.toString();
    return Season(
      number: num,
      title: (name != null && name.trim().isNotEmpty) ? name.trim() : 'Season $num',
      episodes: (json['episodes'] as List?)
              ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  @override
  List<Object?> get props => [number];
}

class Episode extends Equatable {
  final int number;
  final String title;
  final String? thumbnail;
  final String? duration;
  final bool isBonus;

  const Episode({
    required this.number,
    required this.title,
    this.thumbnail,
    this.duration,
    this.isBonus = false,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    final epNum = (json['episodeNumber'] ?? json['episode'] ?? json['number'] ?? 1) is int
        ? (json['episodeNumber'] ?? json['episode'] ?? json['number'] ?? 1)
        : int.tryParse(
                (json['episodeNumber'] ?? json['episode'] ?? json['number'] ?? '1').toString()) ??
            1;
    final title = json['title']?.toString() ?? json['name']?.toString();
    return Episode(
      number: epNum,
      title: (title != null && title.trim().isNotEmpty) ? title.trim() : 'Episode $epNum',
      thumbnail: json['thumbnail']?.toString() ??
          json['thumb']?.toString() ??
          json['still_path']?.toString(),
      duration: json['duration']?.toString() ?? json['runtime']?.toString(),
      isBonus: json['isBonus'] == true,
    );
  }

  @override
  List<Object?> get props => [number];
}
