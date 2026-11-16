// lib/widgets/shelf_row.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/catalog_item.dart';
import 'poster_card.dart';

class ShelfRow extends StatelessWidget {
  final String title;
  final List<CatalogItem> items;
  final void Function(CatalogItem) onItemTap;

  const ShelfRow({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
  });

  /// Strips emojis, decorative symbols, and leading punctuation from category names
  static String cleanCategoryTitle(String raw) {
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

  /// Identifies if this shelf is specifically the "Top 10 Shows Today" category
  bool get isTop10Shelf {
    final t = cleanCategoryTitle(title)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t == 'top 10 shows today' ||
        t == 'top 10 show today' ||
        t.contains('top 10 show');
  }

  @override
  Widget build(BuildContext context) {
    final cleanHeading = cleanCategoryTitle(title);
    final isTop10 = isTop10Shelf;
    const posterWidth = 115.0;
    const posterHeight = posterWidth * 1.5; // 172.5

    final displayItems = isTop10 ? items.take(10).toList() : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clean text heading without emojis, using clean Inter typography
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            cleanHeading,
            style: GoogleFonts.inter(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF0F0F5),
              letterSpacing: -0.2,
            ),
          ),
        ),

        // Smooth horizontal scrolling list
        SizedBox(
          height: posterHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];

              // Render Netflix-style Top 10 with giant outlined numbers ONLY for Top 10 Shows Today
              if (isTop10) {
                return _Top10PosterItem(
                  rank: index + 1,
                  item: item,
                  onTap: onItemTap,
                  posterWidth: posterWidth,
                  posterHeight: posterHeight,
                );
              }

              // Standard shelf poster for all other categories
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PosterCard(
                  item: item,
                  onTap: () => onItemTap(item),
                  width: posterWidth,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Top 10 Poster Item with Giant Outlined Number Behind the Poster
// ─────────────────────────────────────────────────────────────────────────────

class _Top10PosterItem extends StatelessWidget {
  final int rank;
  final CatalogItem item;
  final void Function(CatalogItem) onTap;
  final double posterWidth;
  final double posterHeight;

  const _Top10PosterItem({
    required this.rank,
    required this.item,
    required this.onTap,
    required this.posterWidth,
    required this.posterHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Number width varies: 1 is narrower, 2-9 standard, 10 has 2 digits
    final double numberVisibleWidth =
        rank >= 10 ? 68.0 : (rank == 1 ? 38.0 : 48.0);
    final double totalItemWidth = numberVisibleWidth + posterWidth;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => onTap(item),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: totalItemWidth,
          height: posterHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── 1. Giant Outlined Number (Behind Poster, on the Left) ───────
              Positioned(
                left: 0,
                bottom: -15, // Aligns number baseline with bottom of poster
                child: _Top10RankNumber(rank: rank),
              ),

              // ── 2. Movie/Show Poster (In Front, on the Right) ───────────────
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: posterWidth,
                child: PosterCard(
                  item: item,
                  onTap: () => onTap(item),
                  width: posterWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Giant Outlined Rank Number (Crisp White Stroke, Dark Fill)
// ─────────────────────────────────────────────────────────────────────────────

class _Top10RankNumber extends StatelessWidget {
  final int rank;

  const _Top10RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    const double fontSize = 142.0;

    return Stack(
      children: [
        // 1. Black outer shadow stroke for high contrast
        Text(
          '$rank',
          style: GoogleFonts.bebasNeue(
            fontSize: fontSize,
            height: 1.0,
            letterSpacing: -2.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF000000),
          ),
        ),
        // 2. Pure white outline stroke matching Netflix style
        Text(
          '$rank',
          style: GoogleFonts.bebasNeue(
            fontSize: fontSize,
            height: 1.0,
            letterSpacing: -2.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.2
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFFFFFFFF),
          ),
        ),
        // 3. Dark interior fill matching the black background
        Text(
          '$rank',
          style: GoogleFonts.bebasNeue(
            fontSize: fontSize,
            height: 1.0,
            letterSpacing: -2.0,
            color: const Color(0xFF000000),
          ),
        ),
      ],
    );
  }
}
