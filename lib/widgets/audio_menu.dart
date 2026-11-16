// lib/widgets/audio_menu.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AudioMenu extends StatelessWidget {
  final List<String> audioTracks;
  final String currentAudioTrack;
  final ValueChanged<String> onAudioSelected;
  final List<String> subtitleTracks;
  final String currentSubtitleTrack;
  final ValueChanged<String>? onSubtitleSelected;
  final bool isLandscape;

  const AudioMenu({
    super.key,
    required this.audioTracks,
    required this.currentAudioTrack,
    required this.onAudioSelected,
    this.subtitleTracks = const [],
    this.currentSubtitleTrack = 'Off',
    this.onSubtitleSelected,
    this.isLandscape = false,
  });

  static Future<void> show(
    BuildContext context, {
    required List<String> audioTracks,
    required String currentAudio,
    required ValueChanged<String> onAudioSelected,
    List<String> subtitleTracks = const [],
    String currentSubtitle = 'Off',
    ValueChanged<String>? onSubtitleSelected,
    bool isLandscape = false,
  }) async {
    // Ensure subtitle list starts with 'Off'
    final cleanSubs = <String>['Off'];
    for (final s in subtitleTracks) {
      if (s.toLowerCase() != 'off' && !cleanSubs.contains(s)) {
        cleanSubs.add(s);
      }
    }

    if (isLandscape) {
      // Landscape Apple Liquid Glass Dialog
      await showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        barrierDismissible: true,
        builder: (ctx) => Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: 580,
                  constraints: const BoxConstraints(maxHeight: 340),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  decoration: BoxDecoration(
                    color: const Color(0xCC121218),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.8,
                    ),
                  ),
                  child: AudioMenu(
                    audioTracks: audioTracks,
                    currentAudioTrack: currentAudio,
                    onAudioSelected: (t) {
                      Navigator.of(ctx).pop();
                      onAudioSelected(t);
                    },
                    subtitleTracks: cleanSubs,
                    currentSubtitleTrack: currentSubtitle,
                    onSubtitleSelected: onSubtitleSelected != null
                        ? (s) {
                            Navigator.of(ctx).pop();
                            onSubtitleSelected(s);
                          }
                        : null,
                    isLandscape: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // Portrait Apple Liquid Glass Bottom Sheet
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
              child: AudioMenu(
                audioTracks: audioTracks,
                currentAudioTrack: currentAudio,
                onAudioSelected: (t) {
                  Navigator.of(ctx).pop();
                  onAudioSelected(t);
                },
                subtitleTracks: cleanSubs,
                currentSubtitleTrack: currentSubtitle,
                onSubtitleSelected: onSubtitleSelected != null
                    ? (s) {
                        Navigator.of(ctx).pop();
                        onSubtitleSelected(s);
                      }
                    : null,
                isLandscape: false,
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLandscape) {
      return _buildLandscapeLayout(context);
    }
    return _buildPortraitLayout(context);
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Audio & Subtitles',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.6), size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Column 1: Audio Tracks ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'AUDIO',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: audioTracks.map((t) {
                            final isSel = t == currentAudioTrack;
                            return _buildTrackTile(
                              title: t,
                              isSelected: isSel,
                              icon: Icons.audiotrack_rounded,
                              onTap: () {
                                onAudioSelected(t);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              VerticalDivider(
                  color: Colors.white.withValues(alpha: 0.08), width: 1),
              const SizedBox(width: 18),

              // ── Column 2: Subtitle Tracks ─────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'SUBTITLES',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: subtitleTracks.map((s) {
                            final isSel = s == currentSubtitleTrack;
                            return _buildTrackTile(
                              title: s,
                              isSelected: isSel,
                              icon: Icons.subtitles_rounded,
                              onTap: () {
                                onSubtitleSelected?.call(s);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Audio & Subtitles',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 12),

          // Audio Section
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'AUDIO',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          ...audioTracks.map((t) {
            final isSel = t == currentAudioTrack;
            return _buildTrackTile(
              title: t,
              isSelected: isSel,
              icon: Icons.audiotrack_rounded,
              onTap: () => onAudioSelected(t),
            );
          }),

          if (subtitleTracks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'SUBTITLES',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            ...subtitleTracks.map((s) {
              final isSel = s == currentSubtitleTrack;
              return _buildTrackTile(
                title: s,
                isSelected: isSel,
                icon: Icons.subtitles_rounded,
                onTap: () => onSubtitleSelected?.call(s),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackTile({
    required String title,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
