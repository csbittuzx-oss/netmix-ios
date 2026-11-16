// lib/widgets/quality_menu.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/stream_info.dart';

class QualityMenu extends StatelessWidget {
  final List<StreamInfo> activeStreams;
  final StreamInfo currentStream;
  final List<String> availableQualities;
  final ValueChanged<StreamInfo> onStreamSelected;
  final bool isLandscape;

  const QualityMenu({
    super.key,
    required this.activeStreams,
    required this.currentStream,
    this.availableQualities = const [],
    required this.onStreamSelected,
    this.isLandscape = false,
  });

  static const List<String> qualityOrder = ['4k', '1080p', '720p', '480p', '360p'];

  static String normalizeQuality(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower == '2160p' || lower == '4k' || lower.contains('4k')) return '4k';
    if (lower.contains('1080')) return '1080p';
    if (lower.contains('720')) return '720p';
    if (lower.contains('480')) return '480p';
    if (lower.contains('360')) return '360p';
    return lower.isNotEmpty ? lower : '720p';
  }

  static String getQualityLabel(String quality, {bool isDefault = false}) {
    final q = normalizeQuality(quality);
    switch (q) {
      case '4k':
        return '4K Ultra HD';
      case '1080p':
        return isDefault ? '1080p Full HD (Default)' : '1080p Full HD';
      case '720p':
        return '720p HD';
      case '480p':
        return '480p SD';
      case '360p':
        return '360p SD';
      default:
        return '${quality.toUpperCase()} HD';
    }
  }

  List<String> get _computedQualities {
    if (availableQualities.isNotEmpty) {
      final normalizedSet = availableQualities.map(normalizeQuality).toSet();
      final ordered = qualityOrder.where((q) => normalizedSet.contains(q)).toList();
      if (ordered.isNotEmpty) return ordered;
    }
    final detected = qualityOrder
        .where((q) => activeStreams.any((s) => normalizeQuality(s.quality) == q))
        .toList();
    if (detected.isNotEmpty) return detected;
    final allSet = activeStreams.map((s) => normalizeQuality(s.quality)).toSet();
    return allSet.isNotEmpty ? allSet.toList() : ['1080p', '720p', '480p'];
  }

  StreamInfo? _findMatchingStream(String targetQ) {
    final matches = activeStreams
        .where((s) => normalizeQuality(s.quality) == targetQ)
        .toList();
    if (matches.isEmpty) return null;
    // Prefer higher file size or bitrate
    matches.sort((a, b) => (b.sizeMb ?? 0).compareTo(a.sizeMb ?? 0));
    return matches.first;
  }

  static Future<void> show(
    BuildContext context, {
    required List<StreamInfo> streams,
    required StreamInfo current,
    required ValueChanged<StreamInfo> onSelected,
    List<String> availableQualities = const [],
    bool isLandscape = false,
  }) async {
    if (isLandscape) {
      // Apple Liquid Glass Dialog in Landscape
      await showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        barrierDismissible: true,
        builder: (ctx) => Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: 380,
                  constraints: const BoxConstraints(maxHeight: 340),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xCC121218),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.8,
                    ),
                  ),
                  child: QualityMenu(
                    activeStreams: streams,
                    currentStream: current,
                    availableQualities: availableQualities,
                    isLandscape: true,
                    onStreamSelected: (s) {
                      Navigator.of(ctx).pop();
                      onSelected(s);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // Liquid Glass Bottom Sheet in Portrait
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xDD121218),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 0.8,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: QualityMenu(
                activeStreams: streams,
                currentStream: current,
                availableQualities: availableQualities,
                isLandscape: false,
                onStreamSelected: (s) {
                  Navigator.of(ctx).pop();
                  onSelected(s);
                },
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final qualities = _computedQualities;
    final currentQ = normalizeQuality(currentStream.quality);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isLandscape)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Video Quality',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (isLandscape)
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: qualities.map((q) {
                final isActive = q == currentQ;
                final label = getQualityLabel(q, isDefault: q == '1080p');
                final match = _findMatchingStream(q);

                String? subText;
                if (match != null) {
                  if (match.size != null && match.size!.isNotEmpty) {
                    subText = match.size!;
                    if (match.cdn != null && match.cdn!.isNotEmpty) {
                      subText += ' · ${match.cdn!}';
                    }
                  } else if (match.sizeMb != null && match.sizeMb! > 0) {
                    subText = '${match.sizeMb!.toStringAsFixed(0)} MB';
                    if (match.cdn != null && match.cdn!.isNotEmpty) {
                      subText += ' · ${match.cdn!}';
                    }
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.28)
                          : Colors.transparent,
                      width: 0.8,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final selectedStream = match ??
                          activeStreams.firstWhere(
                            (s) => normalizeQuality(s.quality) == q,
                            orElse: () => activeStreams.isNotEmpty
                                ? activeStreams.first
                                : currentStream,
                          );
                      onStreamSelected(selectedStream);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            q == '4k'
                                ? Icons.four_k_rounded
                                : (q == '1080p'
                                    ? Icons.hd_rounded
                                    : Icons.tune_rounded),
                            size: 18,
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 13.5,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                if (subText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      subText,
                                      style: GoogleFonts.inter(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 11,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Active',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              'Select',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
