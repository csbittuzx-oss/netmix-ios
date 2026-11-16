// lib/widgets/player_controls.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/stream_info.dart';
import 'speed_menu.dart';
import 'audio_menu.dart';
import 'quality_menu.dart';

class PlayerControls extends StatefulWidget {
  final bool isPlaying;
  final bool isBuffering;
  final bool isFullscreen;
  final Duration position;
  final Duration duration;
  final double speed;
  final String title;
  final String subtitle;
  final List<StreamInfo> streams;
  final StreamInfo currentStream;
  final List<String> availableQualities;
  final String currentAudioTrack;
  final String currentSubtitleTrack;
  final List<String> audioTracks;
  final List<String> subtitleTracks;
  final bool isVisible;
  final bool isSeries;
  final String fitModeLabel;

  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack10;
  final VoidCallback onSeekForward10;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<String> onAudioTrackChanged;
  final ValueChanged<String> onSubtitleTrackChanged;
  final ValueChanged<StreamInfo> onQualityChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onBack;
  final VoidCallback? onToggleFitMode;
  final VoidCallback? onOpenEpisodes;

  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.isBuffering,
    required this.isFullscreen,
    required this.position,
    required this.duration,
    required this.speed,
    required this.title,
    required this.subtitle,
    required this.streams,
    required this.currentStream,
    this.availableQualities = const [],
    required this.currentAudioTrack,
    this.currentSubtitleTrack = 'Off',
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    required this.isVisible,
    this.isSeries = false,
    this.fitModeLabel = 'Fit',
    required this.onPlayPause,
    required this.onSeekBack10,
    required this.onSeekForward10,
    required this.onSeek,
    required this.onSpeedChanged,
    required this.onAudioTrackChanged,
    required this.onSubtitleTrackChanged,
    required this.onQualityChanged,
    required this.onToggleFullscreen,
    required this.onBack,
    this.onToggleFitMode,
    this.onOpenEpisodes,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible && !widget.isBuffering) return const SizedBox.shrink();

    final totalMs = widget.duration.inMilliseconds;
    // Guard: prevent divide-by-zero when duration is not yet known
    final hasDuration = totalMs > 0;
    final currentPosRatio = hasDuration
        ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final sliderValue = _isDragging ? _dragValue : currentPosRatio;
    final displayPosition = _isDragging
        ? Duration(milliseconds: (totalMs * _dragValue).round())
        : widget.position;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xD9000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0xE6000000),
            ],
            stops: [0.0, 0.22, 0.72, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Buffering spinner
            if (widget.isBuffering)
              const IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              ),

            if (widget.isVisible) ...[
              // ── Top Bar ───────────────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 24),
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle.isNotEmpty)
                                Text(
                                  widget.subtitle,
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    decoration: TextDecoration.none,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Center Play/Pause & Seek 10s ──────────────────────────────
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SeekBtn(
                      icon: Icons.replay_10_rounded,
                      onTap: widget.onSeekBack10,
                    ),
                    const SizedBox(width: 36),
                    GestureDetector(
                      onTap: widget.onPlayPause,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                    _SeekBtn(
                      icon: Icons.forward_10_rounded,
                      onTap: widget.onSeekForward10,
                    ),
                  ],
                ),
              ),

              // ── Bottom Controls & Progress Slider ──────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Slider with decoupled smooth dragging
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                            trackHeight: 3,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor:
                                Colors.white.withValues(alpha: 0.22),
                            thumbColor: Colors.white,
                            overlayColor:
                                Colors.white.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: sliderValue.clamp(0.0, 1.0),
                            // Disable seek interaction until duration is known
                            onChangeStart: hasDuration ? (val) {
                              setState(() {
                                _isDragging = true;
                                _dragValue = val;
                              });
                            } : null,
                            onChanged: hasDuration ? (val) {
                              setState(() {
                                _dragValue = val;
                              });
                            } : null,
                            onChangeEnd: hasDuration ? (val) {
                              setState(() {
                                _isDragging = false;
                              });
                              widget.onSeek(val);
                            } : null,
                          ),
                        ),

                        // Time & Bottom Action Buttons
                        Row(
                          children: [
                            Text(
                              '${_fmt(displayPosition)} / ${_fmt(widget.duration)}',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const Spacer(),

                            // Episodes Drawer (For Series)
                            if (widget.isSeries && widget.onOpenEpisodes != null)
                              _CtrlBtn(
                                icon: CupertinoIcons.square_stack_3d_up_fill,
                                tooltip: 'Episodes',
                                isFullscreen: widget.isFullscreen,
                                onTap: widget.onOpenEpisodes!,
                              ),

                            // Audio & Subtitles
                            _CtrlBtn(
                              icon: Icons.subtitles_rounded,
                              tooltip: 'Audio & Subtitles',
                              isFullscreen: widget.isFullscreen,
                              onTap: () {
                                final combinedTracks = widget.audioTracks.isNotEmpty
                                    ? widget.audioTracks
                                    : (widget.currentStream.audioLanguages.isNotEmpty
                                        ? widget.currentStream.audioLanguages
                                        : ['Original Audio']);
                                AudioMenu.show(
                                  context,
                                  audioTracks: combinedTracks,
                                  currentAudio: widget.currentAudioTrack,
                                  onAudioSelected: widget.onAudioTrackChanged,
                                  subtitleTracks: widget.subtitleTracks.isNotEmpty
                                      ? ['Off', ...widget.subtitleTracks]
                                      : const [],
                                  currentSubtitle: widget.currentSubtitleTrack,
                                  onSubtitleSelected: widget.onSubtitleTrackChanged,
                                  isLandscape: widget.isFullscreen,
                                );
                              },
                            ),

                            // Video Quality
                            if (widget.streams.isNotEmpty)
                              _CtrlBtn(
                                icon: Icons.tune_rounded,
                                tooltip: 'Quality',
                                isFullscreen: widget.isFullscreen,
                                onTap: () => QualityMenu.show(
                                  context,
                                  streams: widget.streams,
                                  current: widget.currentStream,
                                  availableQualities: widget.availableQualities,
                                  onSelected: widget.onQualityChanged,
                                  isLandscape: widget.isFullscreen,
                                ),
                              ),

                            // Playback Speed
                            _CtrlBtn(
                              icon: Icons.speed_rounded,
                              tooltip: 'Speed',
                              isFullscreen: widget.isFullscreen,
                              onTap: () => SpeedMenu.show(
                                context,
                                current: widget.speed,
                                onSelected: widget.onSpeedChanged,
                              ),
                            ),

                            // Aspect Ratio / Video Fit Toggle
                            if (widget.onToggleFitMode != null)
                              _CtrlBtn(
                                icon: Icons.aspect_ratio_rounded,
                                tooltip: 'Aspect: ${widget.fitModeLabel}',
                                isFullscreen: widget.isFullscreen,
                                onTap: widget.onToggleFitMode!,
                              ),

                            // Fullscreen Toggle
                            _CtrlBtn(
                              icon: widget.isFullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              tooltip: 'Fullscreen',
                              isFullscreen: widget.isFullscreen,
                              onTap: widget.onToggleFullscreen,
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _SeekBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SeekBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isFullscreen;

  const _CtrlBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}
