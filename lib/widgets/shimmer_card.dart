// lib/widgets/shimmer_card.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';

class ShimmerCard extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerCard({
    super.key,
    this.width = 110,
    this.height = 165,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class ShimmerShelf extends StatelessWidget {
  const ShimmerShelf({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Shimmer.fromColors(
          baseColor: AppColors.shimmerBase,
          highlightColor: AppColors.shimmerHighlight,
          child: Container(
            width: 140,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        SizedBox(
          height: 172.5,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 6,
            itemBuilder: (_, i) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: ShimmerCard(width: 115, height: 172.5, borderRadius: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class ShimmerHero extends StatelessWidget {
  const ShimmerHero({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = MediaQuery.of(context).size.width > 600;
    final h = isWide
        ? (screenHeight * 0.58).clamp(380.0, 560.0)
        : (screenHeight * 0.52).clamp(360.0, 480.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        child: Container(
          height: h,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
