// lib/services/netflix_metadata_service.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/security_vault.dart';
import '../models/catalog_item.dart';

/// Service that discovers and extracts rich IMDb/TMDB metadata and YouTube trailer streams
class NetflixMetadataService {
  static final NetflixMetadataService instance = NetflixMetadataService._();
  NetflixMetadataService._();

  static final String _tmdbApiKey = SecurityVault.tmdbApiKey;
  // Use api.tmdb.org which is globally accessible without regional DNS blocks
  static final String _tmdbBaseUrl = SecurityVault.tmdbBaseUrl;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'Netmix/1.0 (Android; Mobile)',
    },
  ));

  // In-memory caches with TTL (3 hours)
  final Map<String, _CacheEntry<TmdbContentData>> _metadataCache = {};
  final Map<String, _CacheEntry<List<EpisodeData>>> _seasonCache = {};
  final Map<String, _CacheEntry<TrailerStreamInfo?>> _trailerStreamCache = {};
  final Map<String, _CacheEntry<String?>> _logoCache = {};
  final Map<String, _CacheEntry<String?>> _backdropCache = {};

  /// Fetches the highest quality official 4K backdrop from TMDB
  Future<String?> getTmdbBackdropUrl(CatalogItem item) async {
    final cacheKey = item.imdbId?.isNotEmpty == true ? item.imdbId! : item.id;
    final cached = _backdropCache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTtl)) {
      return cached.data;
    }

    try {
      final idResult = await _resolveTmdbId(item);
      final tmdbId = idResult?.tmdbId;
      final isTv = idResult?.isTv ?? item.isSeries;

      if (tmdbId != null) {
        final endpoint = isTv ? '/tv/$tmdbId' : '/movie/$tmdbId';
        final res = await _dio.get(
          '$_tmdbBaseUrl$endpoint',
          queryParameters: {
            'api_key': _tmdbApiKey,
          },
        );
        final data = res.data as Map<String, dynamic>;
        final path = data['backdrop_path']?.toString();
        if (path != null && path.isNotEmpty) {
          final fullUrl = 'https://image.tmdb.org/t/p/original$path';
          _backdropCache[cacheKey] = _CacheEntry(fullUrl);
          return fullUrl;
        }
      }
    } catch (_) {}

    _backdropCache[cacheKey] = _CacheEntry(null);
    return null;
  }

  /// Fetches the highest quality official transparent title logo from TMDB
  Future<String?> getTmdbLogoUrl(CatalogItem item) async {
    final cacheKey = item.imdbId?.isNotEmpty == true ? item.imdbId! : item.id;
    final cached = _logoCache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTtl)) {
      return cached.data;
    }

    try {
      final idResult = await _resolveTmdbId(item);
      final tmdbId = idResult?.tmdbId;
      final isTv = idResult?.isTv ?? item.isSeries;

      if (tmdbId != null) {
        final endpoint = isTv ? '/tv/$tmdbId/images' : '/movie/$tmdbId/images';
        final res = await _dio.get(
          '$_tmdbBaseUrl$endpoint',
          queryParameters: {
            'api_key': _tmdbApiKey,
            'include_image_language': 'en,null',
          },
        );
        final logos = res.data['logos'] as List? ?? [];
        if (logos.isNotEmpty) {
          String? bestPath;
          for (final l in logos) {
            if (l is Map && l['file_path'] != null) {
              final lang = l['iso_639_1'];
              if (lang == 'en' || lang == null) {
                bestPath = l['file_path'].toString();
                break;
              }
            }
          }
          bestPath ??= (logos.first as Map)['file_path']?.toString();
          if (bestPath != null && bestPath.isNotEmpty) {
            final fullLogo = 'https://image.tmdb.org/t/p/original$bestPath';
            _logoCache[cacheKey] = _CacheEntry(fullLogo);
            return fullLogo;
          }
        }
      }
    } catch (_) {}

    _logoCache[cacheKey] = _CacheEntry(null);
    return null;
  }

  static const Duration _cacheTtl = Duration(hours: 3);

  /// Discover full metadata (runtime, certification, cast, director, trailerKey)
  Future<TmdbContentData> getContentMetadata(CatalogItem item) async {
    final cacheKey = item.imdbId?.isNotEmpty == true ? item.imdbId! : item.id;
    final cached = _metadataCache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTtl)) {
      return cached.data;
    }

    try {
      // 1. Resolve TMDB ID and media type
      final idResult = await _resolveTmdbId(item);
      final tmdbId = idResult?.tmdbId;
      final isTv = idResult?.isTv ?? item.isSeries;

      if (tmdbId == null) {
        final fallback = _buildFallbackMetadata(item);
        _metadataCache[cacheKey] = _CacheEntry(fallback);
        return fallback;
      }

      // 2. Fetch full details including credits, release_dates/content_ratings, and videos
      final endpoint = isTv ? '/tv/$tmdbId' : '/movie/$tmdbId';
      final appendToResponse = isTv
          ? 'credits,content_ratings,videos'
          : 'credits,release_dates,videos';

      final res = await _dio.get(
        '$_tmdbBaseUrl$endpoint',
        queryParameters: {
          'api_key': _tmdbApiKey,
          'append_to_response': appendToResponse,
        },
      );

      final data = res.data as Map<String, dynamic>;

      // Runtime
      String runtime = '';
      if (!isTv) {
        final runtimeMin = data['runtime'] as int? ?? 0;
        if (runtimeMin > 0) {
          final h = runtimeMin ~/ 60;
          final m = runtimeMin % 60;
          runtime = h > 0 ? '${h}h ${m}m' : '${m}m';
        }
      } else {
        final seasons = data['number_of_seasons'] as int? ?? 1;
        runtime = seasons > 1 ? '$seasons Seasons' : '1 Season';
      }

      // Certification / Age Rating
      String certification = isTv ? 'TV-14' : 'U/A 13+';
      if (!isTv && data['release_dates'] != null) {
        final results = data['release_dates']['results'] as List? ?? [];
        // Check IN (India) or US
        for (final r in results) {
          final code = r['iso_3166_1']?.toString().toUpperCase();
          if (code == 'IN' || code == 'US') {
            final dates = r['release_dates'] as List? ?? [];
            for (final d in dates) {
              final cert = d['certification']?.toString().trim();
              if (cert != null && cert.isNotEmpty) {
                certification = cert;
                break;
              }
            }
          }
          if (certification.isNotEmpty && certification != 'U/A 13+') break;
        }
      } else if (isTv && data['content_ratings'] != null) {
        final results = data['content_ratings']['results'] as List? ?? [];
        for (final r in results) {
          final code = r['iso_3166_1']?.toString().toUpperCase();
          if (code == 'IN' || code == 'US') {
            final rating = r['rating']?.toString().trim();
            if (rating != null && rating.isNotEmpty) {
              certification = rating;
              break;
            }
          }
        }
      }

      // Cast (Top 4 actors)
      final castList = <String>[];
      if (data['credits']?['cast'] is List) {
        final cast = data['credits']['cast'] as List;
        for (final c in cast.take(4)) {
          final name = c['name']?.toString().trim();
          if (name != null && name.isNotEmpty) castList.add(name);
        }
      }

      // Director
      String? director;
      if (data['credits']?['crew'] is List) {
        final crew = data['credits']['crew'] as List;
        for (final member in crew) {
          if (member['job'] == 'Director') {
            director = member['name']?.toString().trim();
            break;
          }
        }
      }

      // Genres
      final genresList = <String>[];
      if (data['genres'] is List) {
        for (final g in data['genres']) {
          final name = g['name']?.toString().trim();
          if (name != null && name.isNotEmpty) genresList.add(name);
        }
      }

      // Trailer key discovery
      String? trailerKey;
      if (data['videos']?['results'] is List) {
        final videos = data['videos']['results'] as List;
        // Prioritize official YouTube trailer
        final ytTrailers = videos.where((v) =>
            v['site'] == 'YouTube' &&
            v['type'] == 'Trailer' &&
            v['key'] != null &&
            v['key'].toString().isNotEmpty);

        final official = ytTrailers.firstWhere(
          (v) => v['official'] == true,
          orElse: () => ytTrailers.isNotEmpty ? ytTrailers.first : null,
        );

        if (official != null) {
          trailerKey = official['key'].toString();
        } else {
          // Fallback to any YouTube teaser/clip
          final anyYt = videos.firstWhere(
            (v) => v['site'] == 'YouTube' && v['key'] != null,
            orElse: () => null,
          );
          if (anyYt != null) trailerKey = anyYt['key'].toString();
        }
      }

      // Seasons list for TV series from TMDB
      final tmdbSeasons = <TmdbSeason>[];
      if (isTv && data['seasons'] is List) {
        for (final s in data['seasons']) {
          final sNum = s['season_number'] as int? ?? 1;
          if (sNum <= 0) continue; // Skip specials / season 0
          final sName = s['name']?.toString().trim();
          tmdbSeasons.add(TmdbSeason(
            seasonNumber: sNum,
            name: (sName != null && sName.isNotEmpty) ? sName : 'Season $sNum',
            episodeCount: s['episode_count'] as int? ?? 0,
            posterPath: s['poster_path']?.toString(),
            overview: s['overview']?.toString(),
          ));
        }
      }

      final result = TmdbContentData(
        tmdbId: tmdbId,
        isTv: isTv,
        runtime: runtime.isNotEmpty ? runtime : (item.year ?? ''),
        certification: certification,
        cast: castList.isNotEmpty ? castList : (item.genres.take(3).toList()),
        director: director,
        genres: genresList.isNotEmpty ? genresList : item.genres,
        overview: data['overview']?.toString() ?? item.description ?? '',
        trailerKey: trailerKey,
        seasons: tmdbSeasons,
      );

      _metadataCache[cacheKey] = _CacheEntry(result);
      return result;
    } catch (e) {
      debugPrint('Error getting TMDB content metadata: $e');
      final fallback = _buildFallbackMetadata(item);
      _metadataCache[cacheKey] = _CacheEntry(fallback);
      return fallback;
    }
  }

  /// Discover episodes strictly for the season available on backend streaming,
  /// enriched with individual TMDB titles, overviews, and high-quality stills.
  Future<List<EpisodeData>> getSeasonEpisodes({
    required CatalogItem item,
    required int seasonNumber,
  }) async {
    // 1. Identify backend episodes available on streaming server
    Season? backendSeason;
    if (item.seasons.isNotEmpty) {
      backendSeason = item.seasons.firstWhere(
        (s) => s.number == seasonNumber,
        orElse: () => item.seasons.first,
      );
    }

    final backendCount = backendSeason?.episodes.length ?? 0;
    final cacheKey = '${item.id}_s${seasonNumber}_b$backendCount';
    final cached = _seasonCache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTtl)) {
      return cached.data;
    }

    // 2. Query TMDB season episodes to build enrichment lookup
    final tmdbEpMap = <int, Map<String, dynamic>>{};
    try {
      final idResult = await _resolveTmdbId(item);
      final tmdbId = idResult?.tmdbId;

      if (tmdbId != null && (idResult?.isTv ?? item.isSeries)) {
        final res = await _dio.get(
          '$_tmdbBaseUrl/tv/$tmdbId/season/$seasonNumber',
          queryParameters: {'api_key': _tmdbApiKey},
        );

        final rawList = res.data['episodes'] as List? ?? [];
        for (final ep in rawList) {
          final epNum = ep['episode_number'] as int?;
          if (epNum != null) {
            tmdbEpMap[epNum] = ep as Map<String, dynamic>;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching TMDB enrichment for season $seasonNumber: $e');
    }

    final episodesList = <EpisodeData>[];

    // 3. If backend streaming episodes are provided, strictly follow backend count & numbering
    if (backendSeason != null && backendSeason.episodes.isNotEmpty) {
      for (final bEp in backendSeason.episodes) {
        final tmdbEp = tmdbEpMap[bEp.number];
        final stillPath = tmdbEp?['still_path']?.toString();
        final tmdbName = tmdbEp?['name']?.toString().trim();
        final tmdbOverview = tmdbEp?['overview']?.toString().trim() ?? '';
        final runtime = tmdbEp?['runtime'] as int?;

        final title = (tmdbName != null &&
                tmdbName.isNotEmpty &&
                tmdbName.toUpperCase() != 'TBD')
            ? tmdbName
            : bEp.title;
        final duration = (runtime != null && runtime > 0)
            ? '${runtime}m'
            : bEp.duration;
        final thumb = (stillPath != null && stillPath.isNotEmpty)
            ? 'https://image.tmdb.org/t/p/w500$stillPath'
            : (bEp.thumbnail ?? item.backdrop ?? item.poster);

        episodesList.add(EpisodeData(
          number: bEp.number,
          title: title,
          duration: duration,
          thumbnail: thumb,
          overview: tmdbOverview,
        ));
      }
    } else if (!item.isAnimeContent && tmdbEpMap.isNotEmpty) {
      // If backend details haven't fully populated yet, fall back to TMDB list (non-anime only)
      final sortedKeys = tmdbEpMap.keys.toList()..sort();
      for (final epNum in sortedKeys) {
        final tmdbEp = tmdbEpMap[epNum]!;
        final stillPath = tmdbEp['still_path']?.toString();
        final name = tmdbEp['name']?.toString().trim();
        final overview = tmdbEp['overview']?.toString().trim() ?? '';
        final runtime = tmdbEp['runtime'] as int?;

        final upper = (name ?? '').toUpperCase();
        if (upper == 'TBD' || upper.startsWith('TBD ') || upper == 'TBA') {
          continue;
        }

        episodesList.add(EpisodeData(
          number: epNum,
          title: (name != null && name.isNotEmpty) ? name : 'Episode $epNum',
          duration: runtime != null && runtime > 0 ? '${runtime}m' : null,
          thumbnail: (stillPath != null && stillPath.isNotEmpty)
              ? 'https://image.tmdb.org/t/p/w500$stillPath'
              : (item.backdrop ?? item.poster),
          overview: overview,
        ));
      }
    }

    if (episodesList.isNotEmpty) {
      _seasonCache[cacheKey] = _CacheEntry(episodesList);
    }
    return episodesList;
  }

  /// Extracts in-app playable stream URL for a given YouTube video key (with separate audio track)
  Future<TrailerStreamInfo?> resolveYouTubeStreamUrl(String videoKey) async {
    if (videoKey.trim().isEmpty) return null;
    final cached = _trailerStreamCache[videoKey];
    if (cached != null && !cached.isExpired(_cacheTtl)) {
      return cached.data;
    }

    // 1. Try fast Piped stream extraction for direct combined video+audio MP4
    try {
      final pipedRes = await _dio.get(
        'https://api.piped.private.coffee/streams/$videoKey',
        options: Options(
          sendTimeout: const Duration(milliseconds: 3000),
          receiveTimeout: const Duration(milliseconds: 3000),
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
        ),
      );
      if (pipedRes.data is Map<String, dynamic>) {
        final pData = pipedRes.data as Map<String, dynamic>;
        final hls = pData['hls']?.toString();
        if (hls != null && hls.isNotEmpty) {
          final info = TrailerStreamInfo(videoUrl: hls, isCombined: true);
          _trailerStreamCache[videoKey] = _CacheEntry(info);
          return info;
        }
        final vStreams = pData['videoStreams'] as List? ?? [];
        for (final v in vStreams) {
          if (v['videoOnly'] == false) {
            final u = v['url']?.toString();
            if (u != null && u.isNotEmpty) {
              final info = TrailerStreamInfo(videoUrl: u, isCombined: true);
              _trailerStreamCache[videoKey] = _CacheEntry(info);
              return info;
            }
          }
        }
      }
    } catch (_) {
      // Piped failed or timed out, fall through to InnerTube
    }

    try {
      // YouTube InnerTube API request with iOS client payload
      final res = await _dio.post(
        'https://www.youtube.com/youtubei/v1/player',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)',
          },
        ),
        data: {
          'videoId': videoKey,
          'context': {
            'client': {
              'clientName': 'IOS',
              'clientVersion': '20.10.1',
              'deviceModel': 'iPhone16,2',
              'osName': 'iPhone',
              'osVersion': '17.4.0.21E219',
              'hl': 'en',
              'gl': 'US',
            }
          }
        },
      );

      final data = res.data as Map<String, dynamic>?;
      final streamingData = data?['streamingData'] as Map<String, dynamic>?;

      if (streamingData != null) {
        // 1. Check for HLS manifest (best adaptive experience with combined audio+video)
        final hlsUrl = streamingData['hlsManifestUrl']?.toString();
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          final info = TrailerStreamInfo(videoUrl: hlsUrl, isCombined: true);
          _trailerStreamCache[videoKey] = _CacheEntry(info);
          return info;
        }

        // 2. Progressive formats (MP4 with audio & video combined)
        final formats = streamingData['formats'] as List? ?? [];
        for (final f in formats) {
          final url = f['url']?.toString();
          if (url != null && url.isNotEmpty) {
            final info = TrailerStreamInfo(videoUrl: url, isCombined: true);
            _trailerStreamCache[videoKey] = _CacheEntry(info);
            return info;
          }
        }

        // 3. Adaptive formats: Extract highest MP4 video AND MP4 audio track
        final adaptive = streamingData['adaptiveFormats'] as List? ?? [];
        String? bestVideoUrl;
        String? bestAudioUrl;

        for (final f in adaptive) {
          final mime = f['mimeType']?.toString() ?? '';
          final url = f['url']?.toString();
          if (url == null || url.isEmpty) continue;

          if (mime.contains('video/mp4') && bestVideoUrl == null) {
            bestVideoUrl = url;
          } else if (mime.contains('audio/mp4') && bestAudioUrl == null) {
            bestAudioUrl = url;
          }

          if (bestVideoUrl != null && bestAudioUrl != null) break;
        }

        if (bestVideoUrl != null) {
          final info = TrailerStreamInfo(
            videoUrl: bestVideoUrl,
            audioUrl: bestAudioUrl,
            isCombined: false,
          );
          _trailerStreamCache[videoKey] = _CacheEntry(info);
          return info;
        }
      }
    } catch (e) {
      debugPrint('YouTube stream extraction error: $e');
    }

    _trailerStreamCache[videoKey] = _CacheEntry(null);
    return null;
  }

  // ── Helper resolution methods ──────────────────────────────────────────────

  Future<_TmdbIdResult?> _resolveTmdbId(CatalogItem item) async {
    // 1. If IMDb ID is available (starts with 'tt')
    if (item.imdbId != null && item.imdbId!.startsWith('tt')) {
      try {
        final res = await _dio.get(
          '$_tmdbBaseUrl/find/${item.imdbId}',
          queryParameters: {
            'api_key': _tmdbApiKey,
            'external_source': 'imdb_id',
          },
        );
        final data = res.data as Map<String, dynamic>;
        final movieResults = data['movie_results'] as List? ?? [];
        if (movieResults.isNotEmpty) {
          return _TmdbIdResult(
            tmdbId: movieResults.first['id'] as int,
            isTv: false,
          );
        }
        final tvResults = data['tv_results'] as List? ?? [];
        if (tvResults.isNotEmpty) {
          return _TmdbIdResult(
            tmdbId: tvResults.first['id'] as int,
            isTv: true,
          );
        }
      } catch (e) {
        debugPrint('TMDB find by IMDb ID failed: $e');
      }
    }

    // 2. Search by cleaned title
    try {
      final cleanTitle = _cleanSearchTitle(item.title);
      final endpoint = item.isSeries ? '/search/tv' : '/search/movie';
      final res = await _dio.get(
        '$_tmdbBaseUrl$endpoint',
        queryParameters: {
          'api_key': _tmdbApiKey,
          'query': cleanTitle,
        },
      );
      final results = res.data['results'] as List? ?? [];
      if (results.isNotEmpty) {
        return _TmdbIdResult(
          tmdbId: results.first['id'] as int,
          isTv: item.isSeries,
        );
      }
    } catch (e) {
      debugPrint('TMDB search by title failed: $e');
    }

    // 3. Fallback search by rawTitle
    try {
      final raw = (item.title != item.permalink) ? item.title : '';
      if (raw.isNotEmpty) {
        final cleanRaw = _cleanSearchTitle(raw);
        if (cleanRaw.isNotEmpty && cleanRaw != _cleanSearchTitle(item.title)) {
          final endpoint = item.isSeries ? '/search/tv' : '/search/movie';
          final res = await _dio.get(
            '$_tmdbBaseUrl$endpoint',
            queryParameters: {
              'api_key': _tmdbApiKey,
              'query': cleanRaw,
            },
          );
          final results = res.data['results'] as List? ?? [];
          if (results.isNotEmpty) {
            return _TmdbIdResult(
              tmdbId: results.first['id'] as int,
              isTv: item.isSeries,
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  String _cleanSearchTitle(String rawTitle) {
    return rawTitle
        .replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\{.*?\}', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(?:season|s)\s*\d+\b', caseSensitive: false), '')
        .replaceAll(
            RegExp(
                r'\b(?:480p|720p|1080p|2160p|4k|bluray|web-?dl|webrip|hdrip|hevc|x264|x265|dual audio|hindi|english)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'[:\-\|]+$'), '')
        .trim();
  }

  TmdbContentData _buildFallbackMetadata(CatalogItem item) {
    return TmdbContentData(
      tmdbId: null,
      isTv: item.isSeries,
      runtime: item.isSeries ? '1 Season' : (item.year ?? ''),
      certification: item.isSeries ? 'TV-14' : 'U/A 13+',
      cast: const [],
      director: null,
      genres: item.genres,
      overview: item.description ?? '',
      trailerKey: null,
      seasons: const [],
    );
  }
}

class _TmdbIdResult {
  final int tmdbId;
  final bool isTv;
  const _TmdbIdResult({required this.tmdbId, required this.isTv});
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(timestamp) > ttl;
}

class TmdbSeason {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;
  final String? overview;

  const TmdbSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath,
    this.overview,
  });
}

class TmdbContentData {
  final int? tmdbId;
  final bool isTv;
  final String runtime;
  final String certification;
  final List<String> cast;
  final String? director;
  final List<String> genres;
  final String overview;
  final String? trailerKey;
  final List<TmdbSeason> seasons;

  const TmdbContentData({
    required this.tmdbId,
    required this.isTv,
    required this.runtime,
    required this.certification,
    required this.cast,
    required this.director,
    required this.genres,
    required this.overview,
    required this.trailerKey,
    this.seasons = const [],
  });
}

class EpisodeData {
  final int number;
  final String title;
  final String? duration;
  final String? thumbnail;
  final String overview;

  const EpisodeData({
    required this.number,
    required this.title,
    this.duration,
    this.thumbnail,
    required this.overview,
  });
}

class TrailerStreamInfo {
  final String videoUrl;
  final String? audioUrl;
  final bool isCombined;

  const TrailerStreamInfo({
    required this.videoUrl,
    this.audioUrl,
    this.isCombined = false,
  });
}
