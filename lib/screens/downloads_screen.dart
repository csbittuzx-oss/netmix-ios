// lib/screens/downloads_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../models/download_item.dart';
import '../providers/downloads_provider.dart';

// ── Apple Interactive Press Physics Widget ───────────────────────────────────

class ApplePressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const ApplePressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<ApplePressable> createState() => _ApplePressableState();
}

class _ApplePressableState extends State<ApplePressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _isPressed = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _isPressed = false),
      onTapCancel: () {
        if (_isPressed) setState(() => _isPressed = false);
      },
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ── Main Downloads Screen ────────────────────────────────────────────────────

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _headerOpacity = ValueNotifier<double>(0.0);

  static const MethodChannel _securityChannel =
      MethodChannel('com.netmix.security/integrity');

  // Staged deletion timers for 2-second Undo
  final Map<String, Timer> _pendingDeletionTimers = {};
  final Set<String> _pendingDeletedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final clamped = (offset / 45.0).clamp(0.0, 1.0);
    if (_headerOpacity.value != clamped) {
      _headerOpacity.value = clamped;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerOpacity.dispose();
    for (final timer in _pendingDeletionTimers.values) {
      timer.cancel();
    }
    _pendingDeletionTimers.clear();
    super.dispose();
  }

  /// Unified Apple Toast Notification (swipe-to-dismiss, 2 seconds auto-hide, minimal)
  void _showAppleToast(
    String message, {
    IconData? icon,
    Color? iconColor,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        dismissDirection: DismissDirection.horizontal,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(44, 0, 44, 96),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor: const Color(0xEE161622),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.8,
          ),
        ),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: iconColor ?? const Color(0xFF34C759),
                size: 15,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null)
              GestureDetector(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFD700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Launch downloaded content in phone's available external video players (Gallery, MX Player, VLC, etc.)
  Future<void> _playInExternalPlayer(DownloadItem item) async {
    HapticFeedback.mediumImpact();
    if (item.filePath == null) {
      _showAppleToast('Download file path unavailable', icon: CupertinoIcons.exclamationmark_circle, iconColor: const Color(0xFFFF453A));
      return;
    }

    String? videoFilePath;

    // 1. Direct path check
    if (item.filePath != null && item.filePath!.isNotEmpty) {
      final target = File(item.filePath!);
      if (target.existsSync()) {
        videoFilePath = target.path;
      }
    }

    // 2. Public Downloads candidate check
    if (videoFilePath == null) {
      final fileName = item.filePath != null
          ? item.filePath!.split('/').last
          : '${item.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' - ')} (${item.quality}).mp4';
      final pubCandidate = File('/storage/emulated/0/Download/$fileName');
      if (pubCandidate.existsSync()) {
        videoFilePath = pubCandidate.path;
      }
    }

    // 3. Launch via native chooser Intent with URI permissions
    if (videoFilePath != null && File(videoFilePath).existsSync()) {
      try {
        final launched = await _securityChannel.invokeMethod<bool>(
          'openExternalVideoPlayer',
          {'filePath': videoFilePath},
        );
        if (launched == true) return;
      } catch (_) {}
    }

    _showAppleToast(
      'File not found or external player unavailable',
      icon: CupertinoIcons.exclamationmark_circle,
      iconColor: const Color(0xFFFF453A),
    );
  }

  /// Swipe Left to Delete with 2-second Undo
  void _onSwipeToDelete(DownloadItem item) {
    final taskId = item.id;
    final itemTitle = item.title;

    setState(() {
      _pendingDeletedIds.add(taskId);
    });

    _pendingDeletionTimers[taskId]?.cancel();

    // 2-second timer matching toast duration
    _pendingDeletionTimers[taskId] = Timer(const Duration(seconds: 2), () async {
      _pendingDeletionTimers.remove(taskId);
      _pendingDeletedIds.remove(taskId);
      await ref.read(downloadsProvider.notifier).deleteDownload(taskId);
    });

    _showAppleToast(
      'Deleted: "$itemTitle"',
      icon: CupertinoIcons.trash,
      iconColor: const Color(0xFFFF453A),
      actionLabel: 'Undo',
      onAction: () {
        HapticFeedback.lightImpact();
        if (_pendingDeletionTimers.containsKey(taskId)) {
          _pendingDeletionTimers[taskId]?.cancel();
          _pendingDeletionTimers.remove(taskId);
        }
        setState(() {
          _pendingDeletedIds.remove(taskId);
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      },
    );
  }

  String _formatDateGroup(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(dt.year, dt.month, dt.day);

    if (itemDate == today) {
      return 'Today';
    } else if (itemDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(dt).inDays < 7) {
      return DateFormat('EEEE').format(dt);
    } else {
      return DateFormat('d MMMM yyyy').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDownloads = ref.watch(downloadsProvider);

    // Filter out items staged for deletion
    final visibleList = allDownloads
        .where((d) => !_pendingDeletedIds.contains(d.id))
        .toList();

    // 1. Completed downloads (Download History)
    final completed = visibleList
        .where((d) => d.status == DownloadStatus.done)
        .toList();

    completed.sort((a, b) {
      final tA = a.completedAt ?? a.addedAt;
      final tB = b.completedAt ?? b.addedAt;
      return tB.compareTo(tA);
    });

    // Group completed items by date
    final Map<String, List<DownloadItem>> groupedHistory = {};
    for (final item in completed) {
      final key = _formatDateGroup(item.completedAt ?? item.addedAt);
      groupedHistory.putIfAbsent(key, () => []).add(item);
    }

    // 2. Currently downloading content
    final active = visibleList
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.paused ||
            d.status == DownloadStatus.failed)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Scrollable Body ───────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: visibleList.isEmpty
                ? _buildEmptyState()
                : SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 64, 16, 120),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),

                            // ── Section 1: Download History (Top of Page) ────
                            if (completed.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                                child: Text(
                                  'DOWNLOAD HISTORY',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white
                                        .withValues(alpha: 0.40),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              for (final entry in groupedHistory.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      4, 8, 4, 8),
                                  child: Text(
                                    entry.key,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64D2FF)
                                          .withValues(alpha: 0.90),
                                    ),
                                  ),
                                ),
                                for (final item in entry.value)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildDismissibleItem(
                                      item: item,
                                      isHistoryItem: true,
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 18),
                            ],

                            // ── Section 2: Currently Downloading (Below History)
                            if (active.isNotEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 8, 4, 10),
                                child: Row(
                                  children: [
                                    Text(
                                      'CURRENTLY DOWNLOADING',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white
                                            .withValues(alpha: 0.40),
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6.5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0A84FF)
                                            .withValues(alpha: 0.22),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${active.length}',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF64D2FF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              for (final item in active)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildDismissibleItem(
                                    item: item,
                                    isHistoryItem: false,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),

          // ── Apple-Style Liquid Glass Top Bar (Matches Category UI) ────────
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
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Downloads',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (visibleList.isNotEmpty)
                      Positioned(
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.7,
                            ),
                          ),
                          child: Text(
                            '${visibleList.length} ${visibleList.length == 1 ? 'item' : 'items'}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
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

  Widget _buildDismissibleItem({
    required DownloadItem item,
    required bool isHistoryItem,
  }) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF453A).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.trash, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _onSwipeToDelete(item),
      child: _MinimalDownloadCard(
        item: item,
        isHistoryItem: isHistoryItem,
        onPlay: () => _playInExternalPlayer(item),
        onTogglePauseResume: () {
          HapticFeedback.lightImpact();
          if (item.status == DownloadStatus.downloading) {
            ref.read(downloadsProvider.notifier).pauseDownload(item.id);
          } else {
            ref.read(downloadsProvider.notifier).resumeDownload(item.id);
          }
        },
        onCancel: () {
          HapticFeedback.mediumImpact();
          ref.read(downloadsProvider.notifier).cancelDownload(item.id);
          _showAppleToast('Download cancelled', icon: CupertinoIcons.xmark_circle, iconColor: const Color(0xFFFF453A));
        },
        onRetry: () {
          HapticFeedback.lightImpact();
          ref.read(downloadsProvider.notifier).retryDownload(item.id);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 0.8,
                ),
              ),
              child: const Icon(
                CupertinoIcons.arrow_down_circle,
                size: 28,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloaded content will be saved here for offline playback in your external player.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.50),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ApplePressable(
              onTap: () => context.go('/home'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  'Explore Content',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Redesigned Clean Minimal Apple Download Card ─────────────────────────────

class _MinimalDownloadCard extends StatelessWidget {
  final DownloadItem item;
  final bool isHistoryItem;
  final VoidCallback onPlay;
  final VoidCallback onTogglePauseResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const _MinimalDownloadCard({
    required this.item,
    required this.isHistoryItem,
    required this.onPlay,
    required this.onTogglePauseResume,
    required this.onCancel,
    required this.onRetry,
  });

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == DownloadStatus.done;
    final isPaused = item.status == DownloadStatus.paused;
    final isFailed = item.status == DownloadStatus.failed;
    final isDownloading = item.status == DownloadStatus.downloading;

    final progressVal = item.progress.clamp(0.0, 1.0);

    return ApplePressable(
      onTap: isDone ? onPlay : (isFailed ? onRetry : onTogglePauseResume),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF13131C).withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Thumbnail + Info + Controls
            Row(
              children: [
                // ── Thumbnail (Compact 44x60) ──────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 44,
                    height: 60,
                    child: item.poster != null && item.poster!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.poster!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF20202E),
                              child: const Icon(
                                CupertinoIcons.film,
                                color: Colors.white24,
                                size: 18,
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF20202E),
                            child: const Icon(
                              CupertinoIcons.film,
                              color: Colors.white24,
                              size: 18,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 11),

                // ── Info (Title + Quality / Size / Status) ──────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              isFailed
                                  ? 'FAILED'
                                  : item.quality.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isFailed
                                    ? const Color(0xFFFF453A)
                                    : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (item.displaySize.isNotEmpty) ...[
                            Text(
                              item.displaySize,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (isDone && item.completedAt != null)
                            Text(
                              _formatTime(item.completedAt),
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.40),
                              ),
                            )
                          else if (isPaused)
                            Text(
                              'Paused',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFFF9500),
                              ),
                            )
                          else if (isFailed)
                            Text(
                              'Tap to retry',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFFF453A),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Controls (Clean, Compact, Minimal) ──────────────────────
                if (!isDone) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pause / Resume / Retry Button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(30),
                        onPressed: isFailed
                            ? onRetry
                            : onTogglePauseResume,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFailed
                                ? const Color(0xFFFF453A).withValues(alpha: 0.16)
                                : Colors.white.withValues(alpha: 0.10),
                            border: Border.all(
                              color: isFailed
                                  ? const Color(0xFFFF453A).withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            isFailed
                                ? CupertinoIcons.arrow_clockwise
                                : (isDownloading
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill),
                            size: 13,
                            color: isFailed
                                ? const Color(0xFFFF453A)
                                : (isDownloading
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFF34C759)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Cancel Button
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(30),
                        onPressed: onCancel,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF453A).withValues(alpha: 0.12),
                            border: Border.all(
                              color: const Color(0xFFFF453A).withValues(alpha: 0.28),
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 12,
                            color: Color(0xFFFF453A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Minimal Play icon for completed card
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(30),
                    onPressed: onPlay,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF34C759).withValues(alpha: 0.16),
                        border: Border.all(
                          color: const Color(0xFF34C759).withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.play_fill,
                        size: 13,
                        color: Color(0xFF34C759),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Active Progress & Stats Row (No Emojis, Clean & Compact)
            if (!isDone) ...[
              const SizedBox(height: 8),
              // Stats Line: e.g. "286.4 MB of 829 MB · 34%" (left) | "2.8 MB/s · 3m left" (right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isFailed
                        ? 'Download interrupted'
                        : '${item.displayDownloaded} of ${item.displayTotal} · ${item.displayProgress}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isFailed
                          ? const Color(0xFFFF453A)
                          : (isPaused
                              ? const Color(0xFFFF9500)
                              : Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                  if (!isFailed && !isPaused)
                    Text(
                      '${item.speedText ?? ''}${item.etaText != null && item.etaText != 'Calculating...' ? ' · ${item.etaText}' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF30D158),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              // Slim Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: isPaused
                      ? progressVal
                      : (progressVal > 0 ? progressVal : null),
                  minHeight: 3.5,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPaused
                        ? const Color(0xFFFF9500)
                        : (isFailed
                            ? const Color(0xFFFF453A)
                            : const Color(0xFF30D158)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
