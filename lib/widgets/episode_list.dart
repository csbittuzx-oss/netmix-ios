// lib/widgets/episode_list.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';

class EpisodeList extends StatefulWidget {
  final Season season;
  final void Function(Episode) onWatch;
  final void Function(Episode) onDownload;

  const EpisodeList({
    super.key,
    required this.season,
    required this.onWatch,
    required this.onDownload,
  });

  @override
  State<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<EpisodeList>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  static const _staggerMs = 35;
  static const _staggerCount = 12;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _staggerMs * _staggerCount + 230),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Animation<double> _animForIndex(int i) {
    if (i >= _staggerCount) return const AlwaysStoppedAnimation(1.0);
    final total = (_staggerMs * _staggerCount + 230).toDouble();
    final start = (i * _staggerMs) / total;
    final end = ((i * _staggerMs) + 230) / total;
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.season.episodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No episodes available.',
              style: TextStyle(color: AppColors.onSurfaceMuted)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.season.episodes.length,
      itemBuilder: (_, i) {
        final ep = widget.season.episodes[i];
        final anim = _animForIndex(i);
        return AnimatedBuilder(
          animation: anim,
          builder: (_, child) => Opacity(
            opacity: anim.value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - anim.value)),
              child: child,
            ),
          ),
          child: _EpisodeTile(
            episode: ep,
            index: i,
            onWatch: () => widget.onWatch(ep),
            onDownload: () => widget.onDownload(ep),
          ),
        );
      },
    );
  }
}

// ── Episode Tile ──────────────────────────────────────────────────────────────

class _EpisodeTile extends StatefulWidget {
  final Episode episode;
  final int index;
  final VoidCallback onWatch;
  final VoidCallback onDownload;

  const _EpisodeTile({
    required this.episode,
    required this.index,
    required this.onWatch,
    required this.onDownload,
  });

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) { _pressCtrl.reverse(); widget.onWatch(); },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              // ── Thumbnail with play overlay ──────────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 62,
                      child: ep.thumbnail != null
                          ? CachedNetworkImage(
                              imageUrl: ep.thumbnail!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // ── Info ───────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'E${ep.number}${ep.isBonus ? " ✦" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ep.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                        decoration: TextDecoration.none,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ep.duration != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        ep.duration!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.onSurfaceMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Download action ────────────────────────────────────
              _DownloadIconButton(onTap: widget.onDownload),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.onSurfaceMuted, size: 22),
      );
}

// ── Download icon with press feedback ─────────────────────────────────────────

class _DownloadIconButton extends StatefulWidget {
  final VoidCallback onTap;
  const _DownloadIconButton({required this.onTap});

  @override
  State<_DownloadIconButton> createState() => _DownloadIconButtonState();
}

class _DownloadIconButtonState extends State<_DownloadIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.80).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.download_outlined,
              color: AppColors.onSurfaceMuted, size: 18),
        ),
      ),
    );
  }
}
