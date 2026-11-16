// lib/widgets/poster_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';
import 'shimmer_card.dart';

class PosterCard extends StatelessWidget {
  final CatalogItem item;
  final VoidCallback onTap;
  final double width;

  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 115,
  });

  @override
  Widget build(BuildContext context) {
    final isFiniteWidth = width.isFinite;
    final height = isFiniteWidth ? width * 1.5 : double.infinity; // 2:3 aspect ratio
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final memWidth = isFiniteWidth ? (width * dpr).round() : 360;
    final memHeight = isFiniteWidth ? (height * dpr).round() : 540;

    final posterUrl = (item.poster != null && item.poster!.trim().isNotEmpty)
        ? item.poster!.trim()
        : (item.backdrop != null && item.backdrop!.trim().isNotEmpty
            ? item.backdrop!.trim()
            : null);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: posterUrl != null
              ? CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: memWidth,
                  memCacheHeight: memHeight,
                  filterQuality: FilterQuality.medium,
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (_, __) => isFiniteWidth
                      ? ShimmerCard(width: width, height: height, borderRadius: 10)
                      : Container(
                          color: const Color(0xFF14141E),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
                              ),
                            ),
                          ),
                        ),
                  errorWidget: (_, __, ___) => _fallbackPoster(height),
                )
              : _fallbackPoster(height),
        ),
      ),
    );
  }

  Widget _fallbackPoster(double height) => Container(
        width: width,
        height: height,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.onSurfaceMuted, size: 32),
      );
}
