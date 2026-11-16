// lib/screens/category_screen.dart
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/api_client.dart';
import '../models/catalog_item.dart';
import '../providers/home_provider.dart';
import '../widgets/poster_card.dart';
import '../widgets/shelf_row.dart';
import '../widgets/shimmer_card.dart';

class _OttCachedCatalog {
  final List<CatalogItem> items;
  final Set<String> itemIds;
  final int currentPage;
  final bool hasMore;
  final DateTime lastFetchTime;

  const _OttCachedCatalog({
    required this.items,
    required this.itemIds,
    required this.currentPage,
    required this.hasMore,
    required this.lastFetchTime,
  });
}

class CategoryScreen extends ConsumerStatefulWidget {
  final String categoryName;

  const CategoryScreen({
    super.key,
    required this.categoryName,
  });

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _headerOpacity = ValueNotifier<double>(0.0);

  // Static persistent in-memory cache per OTT 4K platform (Netflix, Amazon Prime, JioHotstar)
  static final Map<String, _OttCachedCatalog> _ottPlatformCache = {};

  List<ShelfData> _shelves = [];
  List<CatalogItem> _ottItems = [];
  int _ottCurrentPage = 1;
  bool _ottHasMore = false;
  bool _isLoadingMoreOtt = false;
  bool _isLoading = true;
  String? _errorMessage;

  String? _getOtt4kSlug(String category) {
    final lower = category.toLowerCase().trim();
    if (lower.contains('netflix')) return 'netflix';
    if (lower.contains('prime') || lower.contains('amazon')) return 'amazon_prime_video';
    if (lower.contains('hotstar') || lower.contains('jio')) return 'jiohotstar';
    if (lower.contains('apple')) return 'apple_tv';
    if (lower.contains('disney') || lower.contains('disnep')) return 'disney';
    if (lower.contains('hbo') || lower.contains('max')) return 'hbo_max';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    final ottSlug = _getOtt4kSlug(widget.categoryName);

    // 1. If OTT 4K category and cached items exist, restore immediately without wipe or reload
    if (ottSlug != null) {
      final cached = _ottPlatformCache[ottSlug];
      if (cached != null && cached.items.isNotEmpty) {
        _ottItems = List<CatalogItem>.from(cached.items);
        _ottCurrentPage = cached.currentPage;
        _ottHasMore = cached.hasMore;
        _isLoading = false;

        final now = DateTime.now();
        if (now.difference(cached.lastFetchTime).inMinutes >= 5) {
          _checkNewOttContentOnly(ottSlug);
        }
        return;
      }
    }

    // 2. Synchronously populate initial high-density shelves from home data only for non-OTT categories
    if (ottSlug == null) {
      final homeShelves = ref.read(homeProvider).data?.shelves;
      if (homeShelves != null && homeShelves.isNotEmpty) {
        _shelves = _extractInitialShelves(widget.categoryName, homeShelves);
        if (_shelves.isNotEmpty) {
          _isLoading = false;
        }
      }
    }

    // 3. Fetch fresh dynamic catalog from backend
    _fetchCategoryContent();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    // Transparent at the top (0.0), smoothly transitioning to full Liquid Glass (1.0) on scroll
    final newOpacity = (offset / 50.0).clamp(0.0, 1.0);
    if ((newOpacity - _headerOpacity.value).abs() > 0.015) {
      _headerOpacity.value = newOpacity;
    }

    final ottSlug = _getOtt4kSlug(widget.categoryName);
    if (ottSlug != null &&
        _ottHasMore &&
        !_isLoadingMoreOtt &&
        !_isLoading &&
        offset >= _scrollController.position.maxScrollExtent - 450) {
      _loadMoreOttPage(ottSlug);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerOpacity.dispose();
    super.dispose();
  }

  String _getCategorySlug(String category) {
    final lower = category.toLowerCase().trim();
    if (lower == 'shows' || lower == 'series') return 'series';
    if (lower == 'movies') return 'movies';
    if (lower == 'new & hot') return 'trending';
    if (lower == 'netflix specials' || lower == 'netflix') return 'netflix';
    if (lower.contains('prime') || lower.contains('amazon')) return 'amazon-prime';
    if (lower.contains('hotstar') || lower.contains('jio')) return 'jiohotstar';
    if (lower.contains('apple')) return 'apple_tv';
    if (lower.contains('disney') || lower.contains('disnep')) return 'disney';
    if (lower.contains('hbo') || lower.contains('max')) return 'hbo_max';
    if (lower == 'bollywood' || lower == 'hindi movies' || lower == 'hindi') return 'bollywood';
    if (lower == 'hollywood' || lower == 'english movies' || lower == 'english') return 'hollywood';
    if (lower.contains('south')) return 'south-hindi';
    if (lower == 'anime' || lower.contains('crunchyroll')) return 'anime';
    if (lower == 'action') return 'action';
    if (lower == 'comedy' || lower == 'comedies') return 'comedy';
    if (lower == 'romance') return 'romance';
    if (lower.contains('horror') || lower.contains('thriller')) return 'horror';
    if (lower.contains('sci-fi') || lower.contains('fantasy')) return 'sci-fi';
    if (lower.contains('crime') || lower.contains('mystery')) return 'crime';
    if (lower == 'wwe') return 'wwe';
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  /// Strictly exclude sports, cricket, tournaments from JioHotstar
  static bool _isSportsOrNonFiction(CatalogItem item) {
    final text = '${item.title} ${item.genres.join(" ")}'.toLowerCase();
    const badKeywords = [
      'live cricket', 'cricket', 'ipl', 't20', 'odi', 'test match', 'wcl',
      'isl', 'kabaddi', 'premier league', 'fifa', 'wimbledon', 'sports',
      'world cup', 'highlights', 'match highlights', 'trophy'
    ];
    for (final kw in badKeywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  // ── PLATFORM CATALOG BUILDERS ─────────────────────────────────────────────

  /// Builds rich authentic shelves matching Netflix India (netflix.com/in/)
  static List<ShelfData> _buildNetflixShelves(List<CatalogItem> items) {
    if (items.isEmpty) return [];
    final shelves = <ShelfData>[];

    void addShelf(String title, List<CatalogItem> list) {
      final valid = list.where((i) => i.poster != null && i.poster!.isNotEmpty).toList();
      if (valid.length >= 4) {
        shelves.add(ShelfData(title: title, items: valid));
      }
    }

    // 1. Trending Now on Netflix
    addShelf('Trending Now on Netflix', items.take(20).toList());

    // 2. Netflix Original Series & Binge Shows
    final series = items.where((i) {
      if (i.isSeries || i.type == 'series') return true;
      final catStr = i.genres.join(' ').toLowerCase();
      return catStr.contains('series') || catStr.contains('show');
    }).toList();
    addShelf('Netflix Original Series & Binge Shows', series);

    // 3. Netflix Blockbuster Movies
    final movies = items.where((i) {
      if (i.isSeries || i.type == 'series') return false;
      return i.type == 'movie' || !i.genres.any((g) => g.toLowerCase().contains('series'));
    }).toList();
    addShelf('Netflix Blockbuster Movies', movies);

    // 4. Action & Adventure Thrillers
    final action = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('action') || t.contains('adventure') || t.contains('thriller');
    }).toList();
    addShelf('Action & Adventure Thrillers', action);

    // 5. Crime, Suspense & Mystery
    final crime = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('crime') || t.contains('mystery') || t.contains('suspense') || t.contains('investigation');
    }).toList();
    addShelf('Crime, Suspense & Mystery', crime);

    // 6. Comedy & Family Entertainers
    final comedy = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('comedy') || t.contains('family');
    }).toList();
    addShelf('Comedy & Family Entertainers', comedy);

    // 7. Romantic Dramas & Heartfelt Stories
    final romance = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('romance') || t.contains('drama') || t.contains('love');
    }).toList();
    addShelf('Romantic Dramas & Heartfelt Stories', romance);

    // 8. Bollywood & Hindi Cinema on Netflix
    final hindi = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hindi') || t.contains('bollywood');
    }).toList();
    addShelf('Bollywood & Hindi Cinema on Netflix', hindi);

    // 9. Hollywood & Dual Audio Specials
    final hollywood = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hollywood') || t.contains('english') || t.contains('dual audio');
    }).toList();
    addShelf('Hollywood & Dual Audio Specials', hollywood);

    // 10. All Netflix Catalog (guarantees 100% of loaded content is browseable)
    addShelf('All Netflix Titles', items);

    return shelves;
  }

  /// Builds rich authentic shelves matching Amazon Prime Video (primevideo.com)
  static List<ShelfData> _buildAmazonPrimeShelves(List<CatalogItem> items) {
    if (items.isEmpty) return [];
    final shelves = <ShelfData>[];

    void addShelf(String title, List<CatalogItem> list) {
      final valid = list.where((i) => i.poster != null && i.poster!.isNotEmpty).toList();
      if (valid.length >= 4) {
        shelves.add(ShelfData(title: title, items: valid));
      }
    }

    // 1. Trending on Prime Video
    addShelf('Trending on Prime Video', items.take(20).toList());

    // 2. Amazon Originals & Exclusive Series
    final series = items.where((i) {
      if (i.isSeries || i.type == 'series') return true;
      final catStr = i.genres.join(' ').toLowerCase();
      return catStr.contains('series') || catStr.contains('show');
    }).toList();
    addShelf('Amazon Originals & Exclusive Series', series);

    // 3. Blockbuster Prime Movies
    final movies = items.where((i) {
      if (i.isSeries || i.type == 'series') return false;
      return i.type == 'movie' || !i.genres.any((g) => g.toLowerCase().contains('series'));
    }).toList();
    addShelf('Blockbuster Prime Movies', movies);

    // 4. Action & High-Octane Thrillers
    final action = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('action') || t.contains('adventure') || t.contains('thriller');
    }).toList();
    addShelf('Action & High-Octane Thrillers', action);

    // 5. Crime & Investigation
    final crime = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('crime') || t.contains('investigation') || t.contains('suspense') || t.contains('mystery');
    }).toList();
    addShelf('Crime & Investigation', crime);

    // 6. Comedy & Feel-Good Movies
    final comedy = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('comedy') || t.contains('family');
    }).toList();
    addShelf('Comedy & Feel-Good Movies', comedy);

    // 7. Hindi & Regional Cinema on Prime
    final regional = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hindi') || t.contains('south') || t.contains('tamil') || t.contains('telugu') || t.contains('bollywood');
    }).toList();
    addShelf('Hindi & Regional Cinema on Prime', regional);

    // 8. Hollywood & International Hits
    final hollywood = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hollywood') || t.contains('english') || t.contains('dual audio');
    }).toList();
    addShelf('Hollywood & International Hits', hollywood);

    // 9. All Prime Video Catalog (guarantees 100% of loaded content is browseable)
    addShelf('All Prime Video Titles', items);

    return shelves;
  }

  /// Builds rich authentic shelves matching JioHotstar (hotstar.com/in)
  /// STRICT CONSTRAINT: Strictly movies and series only! Zero sports/news.
  static List<ShelfData> _buildJioHotstarShelves(List<CatalogItem> items) {
    if (items.isEmpty) return [];
    final shelves = <ShelfData>[];

    // Filter strictly movies and series, excluding any sports content
    final cleanHotstar = items.where((i) {
      final isMovieOrSeries = i.isSeries || i.type == 'movie' || i.type == 'series';
      if (!isMovieOrSeries) return false;
      return !_isSportsOrNonFiction(i);
    }).toList();

    void addShelf(String title, List<CatalogItem> list) {
      final valid = list.where((i) => i.poster != null && i.poster!.isNotEmpty).toList();
      if (valid.length >= 4) {
        shelves.add(ShelfData(title: title, items: valid));
      }
    }

    // 1. Trending on JioHotstar
    addShelf('Trending on JioHotstar', cleanHotstar.take(20).toList());

    // 2. Hotstar Specials & Web Series
    final series = cleanHotstar.where((i) {
      if (i.isSeries || i.type == 'series') return true;
      final catStr = i.genres.join(' ').toLowerCase();
      return catStr.contains('series') || catStr.contains('show');
    }).toList();
    addShelf('Hotstar Specials & Web Series', series);

    // 3. Blockbuster Hindi Movies
    final movies = cleanHotstar.where((i) {
      if (i.isSeries || i.type == 'series') return false;
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hindi') || t.contains('bollywood');
    }).toList();
    addShelf('Blockbuster Hindi Movies', movies);

    // 4. Disney+ & Marvel Blockbusters
    final marvelDisney = cleanHotstar.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('marvel') || t.contains('disney') || t.contains('dual audio') || t.contains('hollywood');
    }).toList();
    addShelf('Disney+ & Marvel Blockbusters', marvelDisney);

    // 5. Crime, Suspense & Thrillers
    final crime = cleanHotstar.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('crime') || t.contains('suspense') || t.contains('thriller') || t.contains('mystery');
    }).toList();
    addShelf('Crime, Suspense & Thrillers', crime);

    // 6. Romantic Dramas & Family Stories
    final romance = cleanHotstar.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return t.contains('romance') || t.contains('drama') || t.contains('family');
    }).toList();
    addShelf('Romantic Dramas & Family Stories', romance);

    // 7. South Indian Cinema on Hotstar
    final south = cleanHotstar.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('south') || t.contains('tamil') || t.contains('telugu') || t.contains('malayalam');
    }).toList();
    addShelf('South Indian Cinema on Hotstar', south);

    // 8. All JioHotstar Movies & Series
    addShelf('All JioHotstar Movies & Series', cleanHotstar);

    return shelves;
  }

  /// Builds rich authentic shelves matching Crunchyroll Discover (crunchyroll.com/discover)
  static List<ShelfData> _buildCrunchyrollShelves(List<CatalogItem> items) {
    if (items.isEmpty) return [];
    final shelves = <ShelfData>[];

    void addShelf(String title, List<CatalogItem> list) {
      final valid = list.where((i) => i.poster != null && i.poster!.isNotEmpty).toList();
      if (valid.length >= 4) {
        shelves.add(ShelfData(title: title, items: valid));
      }
    }

    // 1. Trending This Season on Crunchyroll
    addShelf('Trending This Season on Crunchyroll', items.take(20).toList());

    // 2. Popular Shonen & High-Octane Action
    const shonenKeywords = [
      'zatch', 'jojo', 'slime', 'firefly', 'piece', 'slayer', 'jujutsu', 'titan',
      'dragon', 'naruto', 'bleach', 'hero', 'punch', 'hunter', 'clover', 'kaisen',
      'chainsaw', 'action', 'battle', 'demon'
    ];
    final shonen = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return shonenKeywords.any((kw) => t.contains(kw));
    }).toList();
    addShelf('Popular Shonen & High-Octane Action', shonen);

    // 3. Top Anime Movies & Features
    final movies = items.where((i) => i.type == 'movie' || (!i.isSeries && i.seasons.length <= 1)).toList();
    addShelf('Top Anime Movies & Features', movies);

    // 4. Fantasy, Isekai & Reincarnation
    const isekaiKeywords = [
      'slime', 'reincarnat', 'fantasy', 'dungeon', 'isekai', 'magic', 'shield',
      'overlord', 'sword', 'mushoku', 'world', 'adventure'
    ];
    final isekai = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return isekaiKeywords.any((kw) => t.contains(kw));
    }).toList();
    addShelf('Fantasy, Isekai & Reincarnation', isekai);

    // 5. Dark Fantasy & Supernatural Thrillers
    const darkKeywords = [
      'death', 'dark', 'ghoul', 'chainsaw', 'titan', 'tokyo', 'psycho',
      'supernatural', 'monster', 'shadow', 'apothecary', 'mystery', 'thriller'
    ];
    final dark = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return darkKeywords.any((kw) => t.contains(kw));
    }).toList();
    addShelf('Dark Fantasy & Supernatural Thrillers', dark);

    // 6. Romance, Drama & Slice of Life
    const romanceKeywords = [
      'wedding', 'love', 'apothecary', 'school', 'life', 'romance', 'basket',
      'dress-up', 'horimiya', 'drama', 'heart', 'girlfriend'
    ];
    final romance = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")}'.toLowerCase();
      return romanceKeywords.any((kw) => t.contains(kw));
    }).toList();
    addShelf('Romance, Drama & Slice of Life', romance);

    // 7. Hindi Dubbed & Dual Audio Anime
    final dubbed = items.where((i) {
      final t = '${i.title} ${i.genres.join(" ")} ${i.audioLanguages.join(" ")}'.toLowerCase();
      return t.contains('hindi') || t.contains('dub') || t.contains('dual audio') || t.contains('english');
    }).toList();
    addShelf('Hindi Dubbed & Dual Audio Anime', dubbed);

    // 8. All Crunchyroll Anime Series (guarantees 100% of loaded content is browseable)
    addShelf('All Crunchyroll Anime Series', items);

    return shelves;
  }

  /// Groups generic category items into rich full shelves with zero truncation
  static List<ShelfData> _buildGenericCategoryShelves(String categoryName, List<CatalogItem> items) {
    if (items.isEmpty) return [];

    const int chunkSize = 15;
    final shelves = <ShelfData>[];

    void addShelf(String title, List<CatalogItem> list) {
      final valid = list.where((i) => i.poster != null && i.poster!.isNotEmpty).toList();
      if (valid.length >= 4) {
        shelves.add(ShelfData(title: title, items: valid));
      }
    }

    if (items.length <= chunkSize) {
      addShelf('Top Picks in $categoryName', items);
      return shelves;
    }

    // 1. Trending Now
    addShelf('Trending in $categoryName', items.take(chunkSize).toList());

    // 2. Series / Shows (if any)
    final series = items.where((i) => i.isSeries || i.type == 'series').toList();
    if (series.length >= 4) {
      addShelf('Top $categoryName Series & Shows', series);
    }

    // 3. Movies (if any)
    final movies = items.where((i) => !i.isSeries && i.type == 'movie').toList();
    if (movies.length >= 4) {
      addShelf('Blockbuster $categoryName Movies', movies);
    }

    // 4. More segments in chunks so no items are ever lost
    int offset = chunkSize;
    int chunkIndex = 2;
    const chunkTitles = [
      'Popular Hits',
      'Highly Rated',
      'Recent Releases',
      'More to Explore',
    ];

    while (offset < items.length) {
      final chunk = items.skip(offset).take(chunkSize).toList();
      if (chunk.length >= 4) {
        final label = chunkIndex - 2 < chunkTitles.length
            ? '${chunkTitles[chunkIndex - 2]} in $categoryName'
            : 'More $categoryName (Part ${chunkIndex - 1})';
        addShelf(label, chunk);
      }
      offset += chunkSize;
      chunkIndex++;
    }

    // 5. Complete Catalog
    if (items.length > chunkSize * 2) {
      addShelf('All $categoryName Titles', items);
    }

    return shelves;
  }

  List<ShelfData> _extractInitialShelves(
    String categoryName,
    List<ShelfData> allShelves,
  ) {
    final cat = categoryName.toLowerCase().trim();

    // ── SHOWS / SERIES ────────────────────────────────────────────────────────
    if (cat == 'shows' || cat == 'series') {
      final res = <ShelfData>[];
      final seenTitles = <String>{};

      for (final s in allShelves) {
        final t = s.title.toLowerCase();
        final isDedicatedSeriesShelf = t.contains('series') ||
            t.contains('show') ||
            t.contains('binge') ||
            t.contains('top 10') ||
            t.contains('tv ');

        if (isDedicatedSeriesShelf) {
          final seriesItems = s.items.where((i) => i.isSeries).toList();
          final itemsToUse = seriesItems.length >= 4 ? seriesItems : s.items;
          if (itemsToUse.length >= 4 && seenTitles.add(s.title)) {
            res.add(ShelfData(title: s.title, items: itemsToUse));
          }
        }
      }

      if (res.isNotEmpty) return res;

      final allShows = allShelves
          .expand((s) => s.items)
          .where((i) => i.isSeries)
          .toList();
      if (allShows.length >= 4) {
        return _buildGenericCategoryShelves('Shows', allShows);
      }
      return [];
    }

    // ── MOVIES ───────────────────────────────────────────────────────────────
    if (cat == 'movies') {
      final res = <ShelfData>[];
      final seenTitles = <String>{};

      for (final s in allShelves) {
        final t = s.title.toLowerCase();
        if (t.contains('series') ||
            t.contains('tv show') ||
            t.contains('binge') ||
            t.contains('top 10 show')) {
          continue;
        }

        final movieItems = s.items.where((i) => !i.isSeries).toList();
        if (movieItems.length >= 4 && seenTitles.add(s.title)) {
          res.add(ShelfData(title: s.title, items: movieItems));
        }
      }

      if (res.isNotEmpty) return res;

      final allMovies = allShelves
          .expand((s) => s.items)
          .where((i) => !i.isSeries)
          .toList();
      if (allMovies.length >= 4) {
        return _buildGenericCategoryShelves('Movies', allMovies);
      }
      return [];
    }

    // ── NETFLIX SPECIALS ─────────────────────────────────────────────────────
    if (cat.contains('netflix')) {
      final items = <CatalogItem>[];
      final seen = <String>{};
      for (final s in allShelves) {
        for (final item in s.items) {
          if (!seen.add(item.id)) continue;
          final match = item.genres.any((g) => g.toLowerCase().contains('netflix')) ||
              item.title.toLowerCase().contains('netflix') ||
              s.title.toLowerCase().contains('netflix');
          if (match) items.add(item);
        }
      }
      if (items.length >= 4) {
        return _buildNetflixShelves(items);
      }
    }

    // ── AMAZON PRIME ─────────────────────────────────────────────────────────
    if (cat.contains('prime') || cat.contains('amazon')) {
      final items = <CatalogItem>[];
      final seen = <String>{};
      for (final s in allShelves) {
        for (final item in s.items) {
          if (!seen.add(item.id)) continue;
          final match = item.genres.any((g) => g.toLowerCase().contains('prime') || g.toLowerCase().contains('amazon')) ||
              s.title.toLowerCase().contains('prime');
          if (match) items.add(item);
        }
      }
      if (items.length >= 4) {
        return _buildAmazonPrimeShelves(items);
      }
    }

    // ── JIOHOTSTAR ───────────────────────────────────────────────────────────
    if (cat.contains('hotstar') || cat.contains('jio')) {
      final items = <CatalogItem>[];
      final seen = <String>{};
      for (final s in allShelves) {
        for (final item in s.items) {
          if (!seen.add(item.id)) continue;
          final isMovieOrSeries = item.isSeries || item.type == 'movie' || item.type == 'series';
          if (!isMovieOrSeries) continue;
          if (_isSportsOrNonFiction(item)) continue;
          final match = item.genres.any((g) => g.toLowerCase().contains('hotstar') || g.toLowerCase().contains('jio')) ||
              s.title.toLowerCase().contains('hotstar');
          if (match) items.add(item);
        }
      }
      if (items.length >= 4) {
        return _buildJioHotstarShelves(items);
      }
    }

    // ── CRUNCHYROLL / ANIME ──────────────────────────────────────────────────
    if (cat.contains('crunchyroll') || cat == 'anime') {
      final items = <CatalogItem>[];
      final seen = <String>{};
      for (final s in allShelves) {
        for (final item in s.items) {
          if (!seen.add(item.id)) continue;
          final match = item.genres.any((g) => g.toLowerCase().contains('anime') || g.toLowerCase().contains('animation')) ||
              s.title.toLowerCase().contains('anime');
          if (match) items.add(item);
        }
      }
      if (items.length >= 4) {
        return _buildCrunchyrollShelves(items);
      }
    }

    // ── BOLLYWOOD & HINDI MOVIES ─────────────────────────────────────────────
    if (cat == 'bollywood' || cat == 'hindi movies' || cat == 'hindi') {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return (t.contains('bollywood') || t.contains('hindi') || t.contains('india')) &&
            s.items.length >= 4;
      }).toList();
      if (res.isNotEmpty) return res;
    }

    // ── HOLLYWOOD & ENGLISH MOVIES ───────────────────────────────────────────
    if (cat == 'hollywood' || cat == 'english movies' || cat == 'english') {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return (t.contains('hollywood') || t.contains('english') || t.contains('dual audio')) &&
            s.items.length >= 4;
      }).toList();
      if (res.isNotEmpty) return res;
    }

    // ── SOUTH HINDI DUBBED ───────────────────────────────────────────────────
    if (cat.contains('south')) {
      final res = allShelves.where((s) {
        final t = s.title.toLowerCase();
        return s.items.length >= 4 && (t.contains('south') || t.contains('tamil') || t.contains('telugu'));
      }).toList();
      if (res.isNotEmpty) return res;
    }

    // ── SPECIFIC GENRES (Action, Comedy, Romance, etc.) ──────────────────────
    final matched = allShelves.where((s) {
      if (s.items.length < 4) return false;
      final t = s.title.toLowerCase();
      if (cat.contains('comed') && t.contains('comed')) return true;
      if (cat == 'action' && t.contains('action')) return true;
      if (cat == 'romance' && t.contains('romance')) return true;
      if (cat.contains('horror') && (t.contains('horror') || t.contains('supernatural'))) return true;
      if (cat.contains('thriller') && (t.contains('thriller') || t.contains('suspense'))) return true;
      if (cat.contains('sci-fi') && (t.contains('sci-fi') || t.contains('fantasy'))) return true;
      if (cat.contains('crime') && (t.contains('crime') || t.contains('mystery'))) return true;
      return t.contains(cat);
    }).toList();

    if (matched.isNotEmpty) return matched;

    // Filter matching items across all shelves
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final s in allShelves) {
      for (final item in s.items) {
        if (!seen.add(item.id)) continue;
        final gMatch = item.genres.any((g) => g.toLowerCase().contains(cat));
        final lMatch = item.audioLanguages.any((l) => l.toLowerCase().contains(cat));
        final tMatch = item.title.toLowerCase().contains(cat);
        if (gMatch || lMatch || tMatch) {
          items.add(item);
        }
      }
    }

    if (items.length >= 4) {
      return _buildGenericCategoryShelves(categoryName, items);
    }

    return [];
  }

  /// Incrementally checks for newly added movies and series in OTT sections without reloading existing items
  Future<void> _checkNewOttContentOnly(String ottSlug) async {
    try {
      final cached = _ottPlatformCache[ottSlug];
      if (cached == null) return;

      final res = await ApiClient.instance.getOttCatalog(ottSlug, 1, 30);
      if (!mounted) return;

      final rawItems = res['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        final updatedIds = Set<String>.from(cached.itemIds);
        final List<CatalogItem> newItems = [];
        for (final j in rawItems) {
          if (j is Map<String, dynamic>) {
            try {
              final item = CatalogItem.fromJson(j);
              if (item.id.isNotEmpty && updatedIds.add(item.id)) {
                newItems.add(item);
              }
            } catch (_) {}
          }
        }

        if (newItems.isNotEmpty && _ottItems.isNotEmpty) {
          setState(() {
            _ottItems = <CatalogItem>[
              ...newItems,
              ..._ottItems.where((i) => !newItems.any((n) => n.id == i.id)),
            ];
            _ottPlatformCache[ottSlug] = _OttCachedCatalog(
              items: List<CatalogItem>.from(_ottItems),
              itemIds: updatedIds,
              currentPage: _ottCurrentPage,
              hasMore: _ottHasMore,
              lastFetchTime: DateTime.now(),
            );
          });
        } else {
          _ottPlatformCache[ottSlug] = _OttCachedCatalog(
            items: cached.items,
            itemIds: cached.itemIds,
            currentPage: cached.currentPage,
            hasMore: cached.hasMore,
            lastFetchTime: DateTime.now(),
          );
        }
      }
    } catch (_) {
      // Quiet background check; never disrupt displayed grid content
    }
  }

  /// Loads next batch of pages from 4khdhub.one OTT category as user scrolls
  Future<void> _loadMoreOttPage(String ottSlug) async {
    if (_isLoadingMoreOtt || !_ottHasMore) return;
    setState(() => _isLoadingMoreOtt = true);

    try {
      final nextPage = _ottCurrentPage + 1;
      final res = await ApiClient.instance.getOttCatalog(ottSlug, nextPage, 100);
      if (!mounted) return;

      final cached = _ottPlatformCache[ottSlug];
      final existingIds = Set<String>.from(cached?.itemIds ?? _ottItems.map((e) => e.id));
      final List<CatalogItem> appended = [];

      final rawItems = res['items'];
      if (rawItems is List) {
        for (final j in rawItems) {
          if (j is Map<String, dynamic>) {
            try {
              final item = CatalogItem.fromJson(j);
              if (item.id.isNotEmpty && existingIds.add(item.id)) {
                appended.add(item);
              }
            } catch (_) {}
          }
        }
      }

      final hasMore = res['hasMore'] == true;
      setState(() {
        if (appended.isNotEmpty) {
          _ottItems = [..._ottItems, ...appended];
        }
        _ottCurrentPage = nextPage;
        _ottHasMore = hasMore;
        _isLoadingMoreOtt = false;
      });

      _ottPlatformCache[ottSlug] = _OttCachedCatalog(
        items: List<CatalogItem>.from(_ottItems),
        itemIds: existingIds,
        currentPage: _ottCurrentPage,
        hasMore: _ottHasMore,
        lastFetchTime: cached?.lastFetchTime ?? DateTime.now(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMoreOtt = false);
      }
    }
  }

  Future<void> _fetchCategoryContent({bool isRefresh = false}) async {
    if (!mounted) return;
    final ottSlug = _getOtt4kSlug(widget.categoryName);
    final isCurrentlyEmpty = ottSlug != null ? _ottItems.isEmpty : _shelves.isEmpty;
    if (isCurrentlyEmpty || isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // ── Dedicated OTT 4K Mode: Strictly flat full catalog from 4khdhub.one (no shelves) ──
      if (ottSlug != null) {
        final res = await ApiClient.instance.getOttCatalog(ottSlug, 1, 100);
        if (!mounted) return;

        final List<CatalogItem> items = [];
        final Set<String> seenIds = <String>{};
        final rawItems = res['items'];
        if (rawItems is List) {
          for (final j in rawItems) {
            if (j is Map<String, dynamic>) {
              try {
                final item = CatalogItem.fromJson(j);
                if (item.id.isNotEmpty && seenIds.add(item.id)) {
                  items.add(item);
                }
              } catch (_) {}
            }
          }
        }

        final hasMore = res['hasMore'] == true;
        if (items.isNotEmpty) {
          _ottPlatformCache[ottSlug] = _OttCachedCatalog(
            items: List<CatalogItem>.from(items),
            itemIds: seenIds,
            currentPage: 1,
            hasMore: hasMore,
            lastFetchTime: DateTime.now(),
          );
        }

        setState(() {
          _ottItems = items;
          _ottCurrentPage = 1;
          _ottHasMore = hasMore;
          _isLoading = false;
          _errorMessage = null;
        });
        return;
      }

      // ── Standard Categories (Movies, Series, Bollywood, Hollywood, Genres, Anime) ──
      final slug = _getCategorySlug(widget.categoryName);
      final catLower = widget.categoryName.toLowerCase().trim();
      final List<CatalogItem> fetchedItems = [];
      final Set<String> seenIds = <String>{};
      List<ShelfData>? remoteShelves;

      try {
        final pageResults = await Future.wait([
          ApiClient.instance.getCategory(slug, 1, 100).catchError((_) => <String, dynamic>{}),
          ApiClient.instance.getCategory(slug, 2, 100).catchError((_) => <String, dynamic>{}),
          ApiClient.instance.getCategory(slug, 3, 100).catchError((_) => <String, dynamic>{}),
        ]);

        for (final res in pageResults) {
          final rawItems = res['items'];
          if (rawItems is List) {
            for (final j in rawItems) {
              if (j is Map<String, dynamic>) {
                try {
                  final item = CatalogItem.fromJson(j);
                  if (item.id.isNotEmpty && seenIds.add(item.id)) {
                    fetchedItems.add(item);
                  }
                } catch (_) {}
              }
            }
          }

          if (remoteShelves == null && res['shelves'] is List && (res['shelves'] as List).isNotEmpty) {
            try {
              final list = <ShelfData>[];
              for (final s in res['shelves']) {
                if (s is Map<String, dynamic>) {
                  final t = s['title']?.toString() ?? '';
                  final itemsList = <CatalogItem>[];
                  if (s['items'] is List) {
                    for (final it in s['items']) {
                      if (it is Map<String, dynamic>) {
                        try {
                          final item = CatalogItem.fromJson(it);
                          if (item.id.isNotEmpty) {
                            itemsList.add(item);
                            if (seenIds.add(item.id)) {
                              fetchedItems.add(item);
                            }
                          }
                        } catch (_) {}
                      }
                    }
                  }
                  if (itemsList.length >= 4) {
                    list.add(ShelfData(title: t, items: itemsList));
                  }
                }
              }
              if (list.isNotEmpty) {
                remoteShelves = list;
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[CategoryScreen] Multi-page ApiClient.getCategory failed: $e');
      }

      if (fetchedItems.length < 15) {
        try {
          final sRes = await ApiClient.instance.search(widget.categoryName);
          final rawItems = sRes['items'];
          if (rawItems is List) {
            for (final j in rawItems) {
              if (j is Map<String, dynamic>) {
                try {
                  final item = CatalogItem.fromJson(j);
                  if (item.id.isNotEmpty && seenIds.add(item.id)) {
                    fetchedItems.add(item);
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      final homeShelves = ref.read(homeProvider).data?.shelves;
      if (homeShelves != null) {
        for (final s in homeShelves) {
          for (final item in s.items) {
            if (item.id.isEmpty || seenIds.contains(item.id)) continue;
            bool match = false;
            if (catLower.contains('crunchyroll') || catLower == 'anime') {
              match = item.genres.any((g) => g.toLowerCase().contains('anime') || g.toLowerCase().contains('animation'));
            }
            if (match && seenIds.add(item.id)) {
              fetchedItems.add(item);
            }
          }
        }
      }

      if (!mounted) return;

      List<ShelfData> builtShelves;
      if (catLower.contains('crunchyroll') || catLower == 'anime') {
        builtShelves = _buildCrunchyrollShelves(fetchedItems);
      } else {
        builtShelves = _buildGenericCategoryShelves(widget.categoryName, fetchedItems);
      }

      if (builtShelves.isEmpty && homeShelves != null) {
        builtShelves = _extractInitialShelves(widget.categoryName, homeShelves);
      }

      setState(() {
        _shelves = builtShelves;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      final ottSlug = _getOtt4kSlug(widget.categoryName);
      final isEmptyNow = ottSlug != null ? _ottItems.isEmpty : _shelves.isEmpty;
      if (isEmptyNow) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load ${widget.categoryName}. Please check your connection.';
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const headerBarHeight = 52.0;
    final totalHeaderHeight = statusBarHeight + headerBarHeight;
    final ottSlug = _getOtt4kSlug(widget.categoryName);
    final isOttMode = ottSlug != null;
    final isEmptyContent = isOttMode ? _ottItems.isEmpty : _shelves.isEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gridCrossAxisCount = screenWidth >= 900 ? 6 : (screenWidth >= 600 ? 5 : 3);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          // ── Scrollable Body Content (Posters slide under frosted glass, no pull-to-refresh) ─────
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Top spacing so content begins cleanly below transparent header
              SliverToBoxAdapter(
                child: SizedBox(height: totalHeaderHeight + 8.0),
              ),

                // Shimmer loading placeholder
                if (_isLoading && isEmptyContent) ...[
                  if (isOttMode)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridCrossAxisCount,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: gridCrossAxisCount * 5,
                        itemBuilder: (_, __) => const ShimmerCard(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: 10,
                        ),
                      ),
                    )
                  else ...[
                    const SliverToBoxAdapter(child: ShimmerShelf()),
                    const SliverToBoxAdapter(child: ShimmerShelf()),
                    const SliverToBoxAdapter(child: ShimmerShelf()),
                  ],
                ] else if (_errorMessage != null && isEmptyContent) ...[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 44,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 14.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            CupertinoButton(
                              color: const Color(0xFF2C2E36),
                              borderRadius: BorderRadius.circular(20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              onPressed: () => _fetchCategoryContent(isRefresh: true),
                              child: Text(
                                'Retry',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else if (isEmptyContent) ...[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.film,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No titles found in ${widget.categoryName}',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (isOttMode) ...[
                  // All available 4khdhub.one titles in a clean vertical grid (no category catalogues)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridCrossAxisCount,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2 / 3,
                      ),
                      itemCount: _ottItems.length,
                      itemBuilder: (context, index) {
                        final item = _ottItems[index];
                        return RepaintBoundary(
                          child: PosterCard(
                            item: item,
                            width: double.infinity,
                            onTap: () => _openDetails(item),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_isLoadingMoreOtt)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                            ),
                          ),
                        ),
                      ),
                    ),
                ] else ...[
                  // Virtualized Horizontal Shelf Rows for standard categories
                  SliverList.builder(
                    itemCount: _shelves.length,
                    itemBuilder: (context, index) {
                      final shelf = _shelves[index];
                      return RepaintBoundary(
                        child: ShelfRow(
                          title: shelf.title,
                          items: shelf.items,
                          onItemTap: _openDetails,
                        ),
                      );
                    },
                  ),
                ],

                // Bottom padding to clear floating Liquid Glass bottom navigation bar
                const SliverToBoxAdapter(
                  child: SizedBox(height: 110),
                ),
              ],
            ),

          // ── Scroll-Based Apple Liquid Glass Top Bar ──────────────────────────
          // When at top (offset == 0): completely transparent background layer
          // When scrolled down: frosted blur + dark translucent glass fades in smoothly
          ValueListenableBuilder<double>(
            valueListenable: _headerOpacity,
            builder: (context, opacity, child) {
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 25.0 * opacity,
                        sigmaY: 25.0 * opacity,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF09090D).withValues(
                            alpha: 0.74 * opacity,
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
              child: SizedBox(
                height: headerBarHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centered Title across full screen width
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 64.0),
                      child: Text(
                        widget.categoryName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),

                    // Circular Apple-Style Liquid Glass Back Button on left
                    Positioned(
                      left: 16,
                      child: _GlassBackButton(
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular Apple-style Liquid Glass Back Button matching Reference Image 1 & 2
class _GlassBackButton extends StatefulWidget {
  final VoidCallback onTap;

  const _GlassBackButton({required this.onTap});

  @override
  State<_GlassBackButton> createState() => _GlassBackButtonState();
}

class _GlassBackButtonState extends State<_GlassBackButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: _isPressed ? 0.28 : 0.20),
                    Colors.white.withValues(alpha: _isPressed ? 0.08 : 0.04),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                CupertinoIcons.chevron_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
