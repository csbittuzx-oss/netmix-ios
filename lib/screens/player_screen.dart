// lib/screens/player_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/catalog_item.dart';
import '../models/stream_info.dart';
import '../services/auth_service.dart';
import '../services/netflix_metadata_service.dart';
import '../services/watch_progress_service.dart';
import '../utils/track_language_helper.dart';
import '../widgets/player_controls.dart';
import '../widgets/quality_menu.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../widgets/episode_selector_drawer.dart';

/// Video Aspect Ratio & Viewport Fit Mode
enum VideoFitMode {
  contain('Fit to Screen', BoxFit.contain, null, CupertinoIcons.arrow_down_right_arrow_up_left),
  cover('Fill (Zoom)', BoxFit.cover, null, CupertinoIcons.arrow_up_left_arrow_down_right),
  stretch('Stretch', BoxFit.fill, null, CupertinoIcons.arrow_right_arrow_left),
  widescreen('16:9 Standard', BoxFit.contain, 16.0 / 9.0, CupertinoIcons.tv),
  original('Original', BoxFit.scaleDown, null, Icons.crop_original_rounded);

  final String label;
  final BoxFit boxFit;
  final double? aspectRatio;
  final IconData icon;
  const VideoFitMode(this.label, this.boxFit, this.aspectRatio, this.icon);

  VideoFitMode next() {
    const values = VideoFitMode.values;
    return values[(index + 1) % values.length];
  }
}

class PlayerScreen extends StatefulWidget {
  final List<StreamInfo> streams;
  final String title;
  final String subtitle;
  final Duration startPosition;
  final String itemId;
  final String? contentId;
  final String? permalink;
  final String? poster;
  final String? backdrop;
  final bool isSeries;
  final int season;
  final int episode;
  final CatalogItem? catalogItem;
  final List<EpisodeData>? episodes;

  const PlayerScreen({
    super.key,
    required this.streams,
    required this.title,
    required this.subtitle,
    required this.startPosition,
    required this.itemId,
    this.contentId,
    this.permalink,
    this.poster,
    this.backdrop,
    this.isSeries = false,
    this.season = 1,
    this.episode = 1,
    this.catalogItem,
    this.episodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  List<StreamInfo> _streams = [];
  List<String> _availableQualities = [];
  late StreamInfo _currentStream;
  String _currentAudioTrack = 'Original Audio';
  String _currentSubtitleTrack = 'Off';
  double _speed = 1.0;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  bool _isBuffering = true;
  bool _isLoadingStreams = false;
  String? _streamError;
  bool _wasPlayingBeforeDisconnect = false;

  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  Timer? _bufferingTimeoutTimer;
  Timer? _seekDebounceTimer;
  Duration? _pendingSeekTarget;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _videoParamsSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _completedSub;

  Duration? _initialResumeTarget;
  bool _initialResumeSeekSettled = false;
  DateTime? _lastResumeSeekAttempt;

  late int _currentSeason;
  late int _currentEpisode;
  List<EpisodeData> _episodesList = [];
  bool _autoPlayEnabled = true;
  bool _autoPlayCancelled = false;
  bool _hasPreloadedNextEpisode = false;
  List<StreamInfo>? _preloadedNextStreams;
  bool _showNextEpisodeBanner = false;
  bool _isFinishing = false;

  // ── Aspect Ratio & Video Fit State ──────────────────────────────────────────
  VideoFitMode _videoFitMode = VideoFitMode.contain;
  bool _showAspectToast = false;
  Timer? _aspectToastTimer;

  // ── Brightness & Volume Gesture State ─────────────────────────────────────
  double _currentBrightness = 0.5;
  double _currentVolume = 1.0;
  bool _showBrightnessHUD = false;
  bool _showVolumeHUD = false;
  Timer? _brightnessHUDTimer;
  Timer? _volumeHUDTimer;

  EpisodeData? get nextEpisodeData {
    if (!widget.isSeries) return null;
    final nextNum = _currentEpisode + 1;
    if (_episodesList.isNotEmpty) {
      for (final ep in _episodesList) {
        if (ep.number == nextNum) return ep;
      }
    }
    return EpisodeData(
      number: nextNum,
      title: 'Episode $nextNum',
      overview: '',
    );
  }

  Future<void> _loadAutoPlayPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoPlayEnabled =
            prefs.getBool(AppConstants.prefAutoPlayNextEpisode) ?? true;
      });
    }
  }

  List<StreamInfo> _prioritizeStreams(List<StreamInfo> list) {
    final prioritized = List<StreamInfo>.from(list);
    prioritized.sort((a, b) {
      // 1. Deprioritize broken or expired R2 links
      final aR2Dead = (a.cdn == 'r2' || a.url.contains('r2.cloudflarestorage.com')) &&
          (a.url.contains('297de52426dc9b4d861466cc51253577') ||
              a.url.contains('556138dca7367763ed46eecaa4284eca') ||
              a.url.contains('5cf443a1e229c0b4715020b95fafcbc9'));
      final bR2Dead = (b.cdn == 'r2' || b.url.contains('r2.cloudflarestorage.com')) &&
          (b.url.contains('297de52426dc9b4d861466cc51253577') ||
              b.url.contains('556138dca7367763ed46eecaa4284eca') ||
              b.url.contains('5cf443a1e229c0b4715020b95fafcbc9'));
      if (aR2Dead && !bR2Dead) return 1;
      if (!aR2Dead && bR2Dead) return -1;

      // 2. Prioritize high-speed Google CDN & 10Gbps direct streams (<2s startup)
      final aFast = a.cdn == 'google' || a.url.contains('googleusercontent.com') || (a.rawUrl?.contains('googleusercontent.com') ?? false) || a.isFast;
      final bFast = b.cdn == 'google' || b.url.contains('googleusercontent.com') || (b.rawUrl?.contains('googleusercontent.com') ?? false) || b.isFast;
      if (aFast && !bFast) return -1;
      if (!aFast && bFast) return 1;

      // 3. Prioritize direct CDN URLs (zero reverse-proxy hop delay) over proxied endpoints
      final aDirect = (a.directUrl ?? a.rawUrl)?.startsWith('http') == true && !a.url.contains('/api/proxy-stream');
      final bDirect = (b.directUrl ?? b.rawUrl)?.startsWith('http') == true && !b.url.contains('/api/proxy-stream');
      if (aDirect && !bDirect) return -1;
      if (!aDirect && bDirect) return 1;

      // 4. Prefer browser-compatible audio (AAC/MP3)
      if (a.isBrowserCompatibleAudio && !b.isBrowserCompatibleAudio) return -1;
      if (!a.isBrowserCompatibleAudio && b.isBrowserCompatibleAudio) return 1;

      return 0;
    });
    return prioritized;
  }

  @override
  void initState() {
    super.initState();
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _episodesList = widget.episodes != null
        ? List<EpisodeData>.from(widget.episodes!)
        : [];
    _loadAutoPlayPref();
    _streams = _prioritizeStreams(widget.streams);
    if (_streams.isNotEmpty) {
      const qualityOrder = ['4k', '1080p', '720p', '480p', '360p'];
      final detected = qualityOrder
          .where((q) => _streams.any((s) => QualityMenu.normalizeQuality(s.quality) == q))
          .toList();
      _availableQualities = detected.isNotEmpty
          ? detected
          : _streams.map((s) => QualityMenu.normalizeQuality(s.quality)).toSet().toList();
    }
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024, // 16 MB buffer for smooth seeking and continuous playback
        logLevel: MPVLogLevel.error,
      ),
    );
    _controller = VideoController(_player);

    WakelockPlus.enable();
    _startHideTimer();
    _startProgressSave();

    // Initialize screen brightness safely
    ScreenBrightness().application.then((b) {
      if (mounted) setState(() => _currentBrightness = b.clamp(0.01, 1.0));
    }).catchError((_) {});

    // Monitor connectivity for automatic network interruption recovery
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (isOffline) {
        debugPrint('[PlayerScreen] Offline detected, pausing playback safely...');
        _wasPlayingBeforeDisconnect = _player.state.playing;
        _player.pause();
        if (mounted) setState(() => _isBuffering = true);
      } else {
        debugPrint('[PlayerScreen] Online restored, resuming stream from timestamp...');
        if (_wasPlayingBeforeDisconnect) {
          _player.play();
        }
      }
    });

    if (_streams.isNotEmpty) {
      _currentStream = _streams.first;
      _currentAudioTrack = _currentStream.audioLanguages.isNotEmpty
          ? _currentStream.audioLanguages.first
          : 'Original Audio';
      _initPlayer();
    } else if (widget.contentId != null || widget.permalink != null) {
      _currentStream = _emptyStream();
      _isLoadingStreams = true;
      _fetchStreamsAndPlay();
    } else {
      _currentStream = _emptyStream();
      _streamError = 'No stream information provided.';
      _isLoadingStreams = false;
    }
  }

  StreamInfo _emptyStream() => const StreamInfo(
        url: '',
        quality: '720p',
        label: '720p',
        format: 'mp4',
      );

  Future<void> _preloadNextEpisodeStreams() async {
    final nextEp = _currentEpisode + 1;
    debugPrint('[PlayerScreen] 1 minute remaining: Preloading next episode (S$_currentSeason:E$nextEp)...');
    try {
      final json = await ApiClient.instance.getStreams(
        id: widget.contentId,
        permalink: widget.permalink,
        isSeries: true,
        season: _currentSeason,
        episode: nextEp,
      );
      final rawList = json['streams'] as List? ?? [];
      if (rawList.isNotEmpty && mounted) {
        _preloadedNextStreams = _prioritizeStreams(
          rawList
              .map((s) => StreamInfo.fromJson(s as Map<String, dynamic>))
              .toList(),
        );
        debugPrint('[PlayerScreen] Successfully preloaded ${_preloadedNextStreams?.length} streams for episode $nextEp');
      }
    } catch (e) {
      debugPrint('[PlayerScreen] Preload error: $e');
    }
  }

  Future<void> _playNextEpisode() async {
    final nextEp = _currentEpisode + 1;
    debugPrint('[PlayerScreen] Playing next episode: S$_currentSeason:E$nextEp');
    setState(() {
      _currentEpisode = nextEp;
      _hasPreloadedNextEpisode = false;
      _showNextEpisodeBanner = false;
      _isLoadingStreams = true;
      _streamError = null;
    });

    List<StreamInfo> targetStreams = _preloadedNextStreams ?? [];
    if (targetStreams.isEmpty) {
      try {
        final json = await ApiClient.instance.getStreams(
          id: widget.contentId,
          permalink: widget.permalink,
          isSeries: true,
          season: _currentSeason,
          episode: nextEp,
        );
        final rawList = json['streams'] as List? ?? [];
        targetStreams = _prioritizeStreams(
          rawList
              .map((s) => StreamInfo.fromJson(s as Map<String, dynamic>))
              .toList(),
        );
      } catch (e) {
        debugPrint('[PlayerScreen] Error fetching next episode streams: $e');
      }
    }

    if (!mounted) return;

    if (targetStreams.isNotEmpty) {
      const qualityOrder = ['4k', '1080p', '720p', '480p', '360p'];
      final detected = qualityOrder
          .where((q) => targetStreams
              .any((s) => QualityMenu.normalizeQuality(s.quality) == q))
          .toList();

      setState(() {
        _streams = targetStreams;
        _availableQualities = detected.isNotEmpty
            ? detected
            : targetStreams
                .map((s) => QualityMenu.normalizeQuality(s.quality))
                .toSet()
                .toList();
        _currentStream = targetStreams.first;
        _currentAudioTrack = _currentStream.audioLanguages.isNotEmpty
            ? _currentStream.audioLanguages.first
            : 'Original Audio';
        _isLoadingStreams = false;
      });
      await _initPlayer(startPositionOverride: Duration.zero);
    } else {
      _returnToDetails();
    }
  }

  Future<void> _handlePlaybackFinished() async {
    if (_isFinishing) return;
    _isFinishing = true;

    // Save current progress as completed
    await _saveCurrentProgress(forceCompleted: true);

    if (widget.isSeries &&
        _autoPlayEnabled &&
        !_autoPlayCancelled &&
        nextEpisodeData != null) {
      await _playNextEpisode();
      _isFinishing = false;
    } else {
      _returnToDetails();
    }
  }

  void _returnToDetails() {
    if (!mounted) return;
    if (_isFullscreen) {
      _toggleFullscreen();
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (widget.catalogItem != null) {
      context.go('/details', extra: widget.catalogItem);
    }
  }

  String _sanitizeErrorMessage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Unable to stream this content. Please check your network or try again.';
    }
    // Strictly strip any video links, proxy paths, tokens or URLs
    var clean = raw.replaceAll(RegExp(r'https?://[^\s]+'), '');
    clean = clean.replaceAll(RegExp(r'/api/[^\s]+'), '');
    clean = clean.replaceAll(RegExp(r'\?[^\s]+'), '');
    clean = clean.replaceAll(RegExp(r'\.m3u8[^\s]*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\.mp4[^\s]*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\.mkv[^\s]*', caseSensitive: false), '');
    clean = clean.trim();
    if (clean.isEmpty || clean.contains('Exception') || clean.contains('DioException') || clean.contains('SocketException')) {
      return 'Unable to stream this content. The media server did not respond. Please try another source or episode.';
    }
    return clean;
  }

  void _toggleAspectMode() {
    HapticFeedback.selectionClick();
    _aspectToastTimer?.cancel();
    setState(() {
      _videoFitMode = _videoFitMode.next();
      _showAspectToast = true;
    });
    _aspectToastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _showAspectToast = false);
      }
    });
  }

  void _openEpisodeDrawer() {
    EpisodeSelectorDrawer.show(
      context,
      catalogItem: widget.catalogItem,
      title: widget.title,
      currentSeason: _currentSeason,
      currentEpisode: _currentEpisode,
      initialEpisodes: _episodesList,
      isLandscape: _isFullscreen,
      onEpisodeSelected: (season, episode, data) {
        _playSpecificEpisode(season, episode, epData: data);
      },
      onFetchSeasonEpisodes: (season) async {
        if (widget.catalogItem != null) {
          return await NetflixMetadataService.instance.getSeasonEpisodes(
            item: widget.catalogItem!,
            seasonNumber: season,
          );
        }
        return [];
      },
    );
  }

  Future<void> _playSpecificEpisode(int season, int episode, {EpisodeData? epData}) async {
    if (_currentSeason == season && _currentEpisode == episode) return;
    HapticFeedback.mediumImpact();
    // Save current progress before switching
    final lastPos = _player.state.position;
    final lastDur = _player.state.duration;
    if (lastPos.inSeconds >= 3) {
      _saveProgressSync(lastPos, lastDur);
    }
    setState(() {
      _currentSeason = season;
      _currentEpisode = episode;
      _hasPreloadedNextEpisode = false;
      _preloadedNextStreams = null;
      _showNextEpisodeBanner = false;
      _isLoadingStreams = true;
      _streamError = null;
    });

    try {
      final json = await ApiClient.instance.getStreams(
        id: widget.contentId,
        permalink: widget.permalink,
        isSeries: true,
        season: season,
        episode: episode,
      );
      final rawList = json['streams'] as List? ?? [];
      final parsed = _prioritizeStreams(
        rawList
            .map((s) => StreamInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

      if (!mounted) return;

      if (parsed.isNotEmpty) {
        const qualityOrder = ['4k', '1080p', '720p', '480p', '360p'];
        final rawQualities = (json['availableQualities'] as List?)
                ?.map((e) => QualityMenu.normalizeQuality(e.toString()))
                .toSet() ??
            {};
        final detected = qualityOrder.where((q) {
          return parsed.any((s) => QualityMenu.normalizeQuality(s.quality) == q) ||
              rawQualities.contains(q);
        }).toList();

        setState(() {
          _streams = parsed;
          _availableQualities = detected.isNotEmpty
              ? detected
              : parsed.map((s) => QualityMenu.normalizeQuality(s.quality)).toSet().toList();
          _currentStream = parsed.first;
          _currentAudioTrack = _currentStream.audioLanguages.isNotEmpty
              ? _currentStream.audioLanguages.first
              : 'Original Audio';
          _isLoadingStreams = false;
        });
        _initPlayer();
      } else {
        setState(() {
          _isLoadingStreams = false;
          _streamError = json['error']?.toString() ??
              'No streams available for S$season:E$episode.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStreams = false;
          _streamError = 'Unable to load streams for S$season:E$episode. Please try again.';
        });
      }
    }
  }

  Future<void> _fetchStreamsAndPlay() async {
    setState(() {
      _isLoadingStreams = true;
      _streamError = null;
    });

    try {
      final json = await ApiClient.instance.getStreams(
        id: widget.contentId,
        permalink: widget.permalink,
        isSeries: widget.isSeries,
        season: widget.season,
        episode: widget.episode,
      );

      final rawList = json['streams'] as List? ?? [];
      final parsed = _prioritizeStreams(
        rawList
            .map((s) => StreamInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

      if (!mounted) return;

      if (parsed.isNotEmpty) {
        const qualityOrder = ['4k', '1080p', '720p', '480p', '360p'];
        final rawQualities = (json['availableQualities'] as List?)
                ?.map((e) => QualityMenu.normalizeQuality(e.toString()))
                .toSet() ??
            {};
        final detected = qualityOrder.where((q) {
          return parsed.any((s) => QualityMenu.normalizeQuality(s.quality) == q) ||
              rawQualities.contains(q);
        }).toList();

        setState(() {
          _streams = parsed;
          _availableQualities = detected.isNotEmpty
              ? detected
              : parsed.map((s) => QualityMenu.normalizeQuality(s.quality)).toSet().toList();
          _currentStream = parsed.first;
          _currentAudioTrack = _currentStream.audioLanguages.isNotEmpty
              ? _currentStream.audioLanguages.first
              : 'Original Audio';
          _isLoadingStreams = false;
        });
        _initPlayer();
      } else {
        setState(() {
          _isLoadingStreams = false;
          _streamError = json['error']?.toString() ??
              'No streams available for this content.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStreams = false;
          _streamError = 'Unable to stream this content. Please check your network or try again.';
        });
      }
    }
  }

  String _resolveAbsoluteUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    String base = AppConstants.defaultBaseUrl;
    try {
      final current = ApiClient.instance.baseUrl;
      if (current.isNotEmpty) base = current;
    } catch (_) {}
    final cleanBase = base.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.startsWith('/')) {
      return '$cleanBase$trimmed';
    }
    return '$cleanBase/$trimmed';
  }

  void _tryNextStream({String? errorReason}) {
    if (!mounted) return;
    final currentIdx = _streams.indexOf(_currentStream);
    final savedPos = (_initialResumeTarget != null && !_initialResumeSeekSettled)
        ? _initialResumeTarget!
        : _player.state.position;

    // Skip consecutive streams with identical URLs so we don't repeat the exact same failure
    int nextIdx = currentIdx + 1;
    while (nextIdx < _streams.length && _streams[nextIdx].url == _currentStream.url) {
      nextIdx++;
    }

    if (nextIdx < _streams.length) {
      final nextStream = _streams[nextIdx];
      debugPrint('[PlayerScreen] Failing over to next stream ($savedPos): ${nextStream.cdn ?? nextStream.label}');
      _switchStream(nextStream, startPosition: savedPos);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Switching to backup stream server...',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E1E26),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _isBuffering = false;
        _isLoadingStreams = false;
        _streamError = 'Unable to stream this content. The media source is temporarily unavailable. Please try another source or episode.';
      });
    }
  }

  void _triggerResumeSeekIfNeeded() {
    if (_initialResumeTarget == null || _initialResumeSeekSettled) return;
    final target = _initialResumeTarget!;
    final currentPos = _player.state.position;

    // 1. If player position has already reached or passed target, mark settled
    if (currentPos >= target - const Duration(seconds: 4)) {
      debugPrint('[PlayerScreen] Resume target reached: ${currentPos.inSeconds}s (target: ${target.inSeconds}s)');
      _initialResumeSeekSettled = true;
      _initialResumeTarget = null;
      return;
    }

    // 2. Ensure media pipeline has active duration or dimensions before seeking
    final dur = _player.state.duration;
    final width = _player.state.width ?? 0;
    final isReady = dur > Duration.zero || width > 0 || currentPos > Duration.zero;
    if (!isReady) return;

    // 3. Debounce seeks so we don't spam mpv while a seek is in flight
    final now = DateTime.now();
    if (_lastResumeSeekAttempt != null &&
        now.difference(_lastResumeSeekAttempt!).inMilliseconds < 1200) {
      return;
    }
    _lastResumeSeekAttempt = now;

    debugPrint('[PlayerScreen] Executing resume seek to ${target.inSeconds}s (current: ${currentPos.inSeconds}s, dur: ${dur.inSeconds}s)');
    _player.seek(target).catchError((e) {
      debugPrint('[PlayerScreen] Resume seek error: $e');
    });
  }

  Future<void> _initPlayer({Duration? startPositionOverride}) async {
    if (_currentStream.url.isEmpty) return;

    final currentItemId = widget.isSeries
        ? '${widget.contentId ?? widget.itemId}_s${_currentSeason}e$_currentEpisode'
        : widget.itemId;

    final prefs = await SharedPreferences.getInstance();
    int? savedMs = startPositionOverride != null
        ? null
        : prefs.getInt('${AppConstants.prefWatchProgress}$currentItemId');

    // Comprehensive fallback: check per-episode key & active user watch progress
    if (savedMs == null && startPositionOverride == null) {
      final userId = AuthService.instance.currentUser.id;
      if (widget.isSeries) {
        final epKey = 'netmix_ep_prog_${userId}_${widget.contentId ?? widget.itemId}_s${_currentSeason}e$_currentEpisode';
        final raw = prefs.getString(epKey);
        if (raw != null && raw.isNotEmpty) {
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            savedMs = (data['pos'] as num?)?.toInt();
          } catch (_) {}
        }
      }
      if (savedMs == null) {
        final p = await WatchProgressService.instance.getProgress(userId, widget.contentId ?? widget.itemId);
        if (p != null && (!widget.isSeries || (p.season == _currentSeason && p.episode == _currentEpisode))) {
          if (!p.isCompleted && p.positionMs >= 5000) {
            savedMs = p.positionMs;
          }
        }
      }
    }

    _bufferingSub?.cancel();
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _isBuffering = b);
      if (b) {
        _bufferingTimeoutTimer?.cancel();
        _bufferingTimeoutTimer = Timer(const Duration(seconds: 7), () {
          if (mounted && _isBuffering && _player.state.position == Duration.zero && (_player.state.width ?? 0) == 0 && !_player.state.playing) {
            debugPrint('[PlayerScreen] Buffering connection timeout (7s) on ${_currentStream.cdn ?? _currentStream.label}');
            _tryNextStream(errorReason: 'Connection timed out (>7s)');
          }
        });
      } else {
        _bufferingTimeoutTimer?.cancel();
        _bufferingTimeoutTimer = null;
      }
    });

    _durationSub?.cancel();
    _durationSub = _player.stream.duration.listen((dur) {
      if (!mounted) return;
      if (dur > Duration.zero) {
        _triggerResumeSeekIfNeeded();
      }
    });

    _positionSub?.cancel();
    _positionSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      if (pos > Duration.zero) {
        _bufferingTimeoutTimer?.cancel();
        _bufferingTimeoutTimer = null;
        if (_isBuffering || _streamError != null) {
          setState(() {
            _isBuffering = false;
            _streamError = null;
          });
        }
      }

      _triggerResumeSeekIfNeeded();

      final dur = _player.state.duration;
      if (dur > Duration.zero) {
        final remaining = dur - pos;

        // 1. Preload next episode when 1 minute remains
        if (remaining <= const Duration(seconds: 60) &&
            !_hasPreloadedNextEpisode &&
            _autoPlayEnabled &&
            !_autoPlayCancelled &&
            widget.isSeries &&
            nextEpisodeData != null) {
          _hasPreloadedNextEpisode = true;
          _preloadNextEpisodeStreams();
        }

        // 2. Show Apple liquid glass preview banner when 5 seconds remain
        if (remaining <= const Duration(seconds: 5) &&
            remaining > Duration.zero &&
            _autoPlayEnabled &&
            !_autoPlayCancelled &&
            widget.isSeries &&
            nextEpisodeData != null) {
          if (!_showNextEpisodeBanner) {
            setState(() => _showNextEpisodeBanner = true);
          }
        } else if (remaining > const Duration(seconds: 5) && _showNextEpisodeBanner) {
          setState(() => _showNextEpisodeBanner = false);
        }

        // 3. Playback completion failsafe
        if (pos >= dur - const Duration(milliseconds: 350)) {
          _handlePlaybackFinished();
        }
      }
    });

    _completedSub?.cancel();
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed && mounted) {
        _handlePlaybackFinished();
      }
    });

    _playingSub?.cancel();
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing && mounted) {
        if ((_player.state.width ?? 0) > 0 || _player.state.position > Duration.zero) {
          _bufferingTimeoutTimer?.cancel();
          _bufferingTimeoutTimer = null;
        }
        if (_isBuffering || _streamError != null) {
          setState(() {
            _isBuffering = false;
            _streamError = null;
          });
        }
        _triggerResumeSeekIfNeeded();
      }
    });

    _videoParamsSub?.cancel();
    _videoParamsSub = _player.stream.videoParams.listen((params) {
      if ((params.w ?? 0) > 0 && mounted) {
        _bufferingTimeoutTimer?.cancel();
        _bufferingTimeoutTimer = null;
        if (_isBuffering || _streamError != null) {
          setState(() {
            _isBuffering = false;
            _streamError = null;
          });
        }
        _triggerResumeSeekIfNeeded();
      }
    });

    _errorSub?.cancel();
    _errorSub = _player.stream.error.listen((err) {
      final errStr = err.toString().toLowerCase();
      debugPrint('[PlayerScreen] libmpv error: $err');
      // Only failover on genuine fatal stream errors — ignore harmless mpv info.
      final isFatal = errStr.contains('failed') ||
          errStr.contains('unavailable') ||
          errStr.contains('403') ||
          errStr.contains('404') ||
          errStr.contains('timeout') ||
          errStr.contains('abort') ||
          errStr.contains('connection refused') ||
          errStr.contains('no such file') ||
          errStr.contains('invalid data');
      if (!isFatal) return;
      // If stream has already played >5 s it is healthy, ignore blips.
      if (_player.state.position > const Duration(seconds: 5)) return;
      _tryNextStream(errorReason: 'Playback failed');
    });

    Duration resumePos = startPositionOverride ?? widget.startPosition;
    if (startPositionOverride == null && savedMs != null && savedMs > 5000 && resumePos == Duration.zero) {
      resumePos = Duration(milliseconds: savedMs);
    }

    if (resumePos >= const Duration(seconds: 5)) {
      _initialResumeTarget = resumePos;
      _initialResumeSeekSettled = false;
      _lastResumeSeekAttempt = null;
      debugPrint('[PlayerScreen] Configured initial resume target: ${resumePos.inSeconds}s');
    } else {
      _initialResumeTarget = null;
      _initialResumeSeekSettled = true;
    }

    // Set low-latency startup properties BEFORE opening media
    // This allows mpv to apply them before demuxer initializes
    try {
      final platform = _player.platform as dynamic;
      // Fast startup, burst streaming & instant playback without stalls
      await platform?.setProperty('demuxer-lavf-probesize', '524288');       // 512 KB probe (fast header read)
      await platform?.setProperty('demuxer-lavf-analyzeduration', '1.0');    // 1.0s analyze
      await platform?.setProperty('demuxer-readahead-secs', '2.0');          // Start playing after 2.0s buffered
      await platform?.setProperty('cache-pause-initial', 'no');              // Render video immediately without pausing
      await platform?.setProperty('cache-pause-wait', '0.5');                // Resume fast after any rebuffering
      await platform?.setProperty('network-timeout', '10');                  // 10s network socket timeout
      await platform?.setProperty('tcp-nodelay', 'yes');                     // Disable Nagle's for fast initial burst
      await platform?.setProperty('demuxer-max-bytes', '33554432');         // 32 MB demuxer cache

      // --- Seeking: keep existing smooth seek behaviour ---
      await platform?.setProperty('demuxer-max-back-bytes', '16777216');     // 16 MB backward cache
      await platform?.setProperty('hr-seek', 'default');
      await platform?.setProperty('hr-seek-framedrop', 'yes');
    } catch (_) {}

    final playableUrl = _resolveAbsoluteUrl(_currentStream.playUrl);
    debugPrint('[PlayerScreen] Opening media: $playableUrl');

    await _player.open(
      Media(
        playableUrl,
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
        },
        start: resumePos > Duration.zero ? resumePos : null,
      ),
    );

    // Initial seek attempts for fast resumption
    _triggerResumeSeekIfNeeded();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _triggerResumeSeekIfNeeded();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _triggerResumeSeekIfNeeded();
    });

    await _player.setRate(_speed);

    // Immediately synchronize subtitle state with player
    if (_currentSubtitleTrack == 'Off') {
      await _applySubtitleTrack('Off');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(AppConstants.autoHideControlsDuration, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _saveCurrentProgress({bool forceCompleted = false}) async {
    // Guard against overwriting existing progress before initial resume seek has settled
    if (_initialResumeTarget != null && !_initialResumeSeekSettled && !forceCompleted) {
      return;
    }
    final pos = forceCompleted ? _player.state.duration : _player.state.position;
    final dur = _player.state.duration;
    if (pos.inSeconds < 3 && !forceCompleted) return;

    final currentItemId = widget.isSeries
        ? '${widget.contentId ?? widget.itemId}_s${_currentSeason}e$_currentEpisode'
        : widget.itemId;

    // Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '${AppConstants.prefWatchProgress}$currentItemId',
        pos.inMilliseconds,
      );
    } catch (_) {}

    // Save to active user account watch history
    try {
      final userId = AuthService.instance.currentUser.id;
      await WatchProgressService.instance.saveProgress(
        userId: userId,
        contentId: widget.contentId ?? widget.itemId,
        title: widget.title,
        poster: widget.poster,
        backdrop: widget.backdrop,
        isSeries: widget.isSeries,
        season: _currentSeason,
        episode: _currentEpisode,
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
        permalink: widget.permalink,
      );
    } catch (e) {
      debugPrint('[PlayerScreen] Progress save error: $e');
    }
  }

  void _startProgressSave() {
    _progressSaveTimer =
        Timer.periodic(AppConstants.saveProgressInterval, (_) async {
      await _saveCurrentProgress();
    });
  }

  void _onTapScreen() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startHideTimer();
  }

  Future<void> _seekTo(Duration target) async {
    _seekDebounceTimer?.cancel();
    _pendingSeekTarget = null;
    _initialResumeSeekSettled = true;
    _initialResumeTarget = null;
    final dur = _player.state.duration;
    Duration safeTarget = target;
    if (safeTarget < Duration.zero) safeTarget = Duration.zero;
    if (dur > Duration.zero && safeTarget > dur) safeTarget = dur;

    try {
      await _player.seek(safeTarget);
    } catch (e) {
      debugPrint('[PlayerScreen] Seek error: $e');
    }
    _startHideTimer();
  }

  void _seekRelative(Duration delta) {
    final dur = _player.state.duration;
    final base = _pendingSeekTarget ?? _player.state.position;
    var target = base + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;

    _pendingSeekTarget = target;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 140), () {
      final finalTarget = _pendingSeekTarget;
      _pendingSeekTarget = null;
      if (finalTarget != null && mounted) {
        _seekTo(finalTarget);
      }
    });
    _startHideTimer();
  }

  void _onDoubleTapLeft() {
    _seekRelative(-AppConstants.doubleTapSeekDuration);
  }

  void _onDoubleTapRight() {
    _seekRelative(AppConstants.doubleTapSeekDuration);
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _switchStream(StreamInfo stream, {Duration? startPosition}) async {
    // 1. Save current position & wasPlaying state
    final currentPosition = startPosition ??
        ((_initialResumeTarget != null && !_initialResumeSeekSettled)
            ? _initialResumeTarget!
            : _player.state.position);
    final wasPlaying = _player.state.playing;

    if (currentPosition >= const Duration(seconds: 5)) {
      _initialResumeTarget = currentPosition;
      _initialResumeSeekSettled = false;
      _lastResumeSeekAttempt = null;
    }

    setState(() {
      _currentStream = stream;
      _isBuffering = true;
      _streamError = null;
    });

    _bufferingTimeoutTimer?.cancel();
    _bufferingTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isBuffering && _player.state.position == Duration.zero && (_player.state.width ?? 0) == 0 && !_player.state.playing) {
        debugPrint('[PlayerScreen] Buffering timeout (8s) on ${_currentStream.cdn ?? _currentStream.label}');
        _tryNextStream(errorReason: 'Connection timed out (>8s)');
      }
    });

    // 2. Swap player media source to nextStream.playUrl
    final playableUrl = _resolveAbsoluteUrl(stream.playUrl);
    debugPrint('[PlayerScreen] Switching stream to: $playableUrl');
    await _player.open(
      Media(
        playableUrl,
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
        },
      ),
      play: wasPlaying,
    );

    // 3. Immediately seek back to currentPosition and resume playback
    if (currentPosition > Duration.zero) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _player.seek(currentPosition);
    }
    if (wasPlaying) {
      await _player.play();
    }
    await _player.setRate(_speed);

    // Configure mpv for ultra-smooth forward/backward seeking & instant keyframe rendering
    try {
      final platform = _player.platform as dynamic;
      await platform?.setProperty('demuxer-max-back-bytes', '16777216'); // 16 MB backward cache for instant backward seek
      await platform?.setProperty('hr-seek', 'default');
      await platform?.setProperty('hr-seek-framedrop', 'yes');
    } catch (_) {}

    // Immediately synchronize subtitle state with player
    if (_currentSubtitleTrack == 'Off') {
      await _applySubtitleTrack('Off');
    }
  }

  Future<void> _setSpeed(double speed) async {
    await _player.setRate(speed);
    setState(() => _speed = speed);
  }

  void _handleBack() async {
    await _saveCurrentProgress();
    _returnToDetails();
  }

  void _saveProgressSync(Duration pos, Duration dur, {bool forceCompleted = false}) {
    final finalPos = forceCompleted ? dur : pos;
    final currentItemId = widget.isSeries
        ? '${widget.contentId ?? widget.itemId}_s${_currentSeason}e$_currentEpisode'
        : widget.itemId;

    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('${AppConstants.prefWatchProgress}$currentItemId', finalPos.inMilliseconds);
    }).catchError((_) {});

    final userId = AuthService.instance.currentUser.id;
    WatchProgressService.instance.saveProgress(
      userId: userId,
      contentId: widget.contentId ?? widget.itemId,
      title: widget.title,
      poster: widget.poster,
      backdrop: widget.backdrop,
      isSeries: widget.isSeries,
      season: _currentSeason,
      episode: _currentEpisode,
      positionMs: finalPos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      permalink: widget.permalink,
    ).catchError((_) {});
  }

  @override
  void dispose() {
    final lastPos = _player.state.position;
    final lastDur = _player.state.duration;
    if (_initialResumeTarget != null && !_initialResumeSeekSettled) {
      debugPrint('[PlayerScreen] dispose: Initial resume seek had not settled, preserving saved progress');
    } else if (lastPos.inSeconds >= 3) {
      _saveProgressSync(lastPos, lastDur);
    }
    _seekDebounceTimer?.cancel();
    _aspectToastTimer?.cancel();
    _brightnessHUDTimer?.cancel();
    _volumeHUDTimer?.cancel();
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    _completedSub?.cancel();
    _hideTimer?.cancel();
    _progressSaveTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _videoParamsSub?.cancel();
    _errorSub?.cancel();
    _connectivitySub?.cancel();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _applySubtitleTrack(String track, [Map<String, SubtitleTrack>? map]) async {
    if (track == 'Off') {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      try {
        final platform = _player.platform as dynamic;
        await platform?.setProperty('sub-visibility', 'no');
        await platform?.setProperty('sid', 'no');
        await platform?.setProperty('secondary-sid', 'no');
      } catch (_) {}
      if (mounted) {
        setState(() => _currentSubtitleTrack = 'Off');
      }
    } else {
      try {
        final platform = _player.platform as dynamic;
        await platform?.setProperty('sub-visibility', 'yes');
      } catch (_) {}
      final match = map?[track];
      if (match != null) {
        await _player.setSubtitleTrack(match);
      } else {
        await _player.setSubtitleTrack(SubtitleTrack.auto());
      }
      if (mounted) {
        setState(() => _currentSubtitleTrack = track);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _isFullscreen) await _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _onTapScreen,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // ── Video Surface with Aspect Ratio / Viewport Fit ──────────────
              Center(
                child: Video(
                  controller: _controller,
                  fill: Colors.black,
                  fit: _videoFitMode.boxFit,
                  aspectRatio: _videoFitMode.aspectRatio,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    visible: _currentSubtitleTrack != 'Off',
                  ),
                ),
              ),

              // ── Double-tap Seek & Vertical Swipe Gestures (Brightness / Volume) ───
              Positioned.fill(
                child: Row(
                  children: [
                    // Left Half: Double-tap -10s & Vertical Drag Screen Brightness
                    Expanded(
                      child: GestureDetector(
                        onTap: _onTapScreen,
                        onDoubleTap: _onDoubleTapLeft,
                        onVerticalDragStart: (details) async {
                          _hideTimer?.cancel();
                          try {
                            final b = await ScreenBrightness().application;
                            _currentBrightness = b.clamp(0.01, 1.0);
                          } catch (_) {}
                          _brightnessHUDTimer?.cancel();
                          setState(() {
                            _showBrightnessHUD = true;
                            _showVolumeHUD = false;
                          });
                        },
                        onVerticalDragUpdate: (details) {
                          final screenHeight = MediaQuery.of(context).size.height;
                          final delta = -details.primaryDelta! / (screenHeight * 0.7);
                          final newBrightness = (_currentBrightness + delta).clamp(0.01, 1.0);
                          _currentBrightness = newBrightness;
                          try {
                            ScreenBrightness().setApplicationScreenBrightness(newBrightness);
                          } catch (_) {}
                          setState(() => _showBrightnessHUD = true);
                        },
                        onVerticalDragEnd: (details) {
                          _brightnessHUDTimer?.cancel();
                          _brightnessHUDTimer = Timer(const Duration(milliseconds: 1200), () {
                            if (mounted) setState(() => _showBrightnessHUD = false);
                          });
                          _startHideTimer();
                        },
                        behavior: HitTestBehavior.translucent,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    // Right Half: Double-tap +10s & Vertical Drag Media Volume
                    Expanded(
                      child: GestureDetector(
                        onTap: _onTapScreen,
                        onDoubleTap: _onDoubleTapRight,
                        onVerticalDragStart: (details) {
                          _hideTimer?.cancel();
                          _currentVolume = (_player.state.volume / 100.0).clamp(0.0, 1.0);
                          _volumeHUDTimer?.cancel();
                          setState(() {
                            _showVolumeHUD = true;
                            _showBrightnessHUD = false;
                          });
                        },
                        onVerticalDragUpdate: (details) {
                          final screenHeight = MediaQuery.of(context).size.height;
                          final delta = -details.primaryDelta! / (screenHeight * 0.7);
                          final newVolume = (_currentVolume + delta).clamp(0.0, 1.0);
                          _currentVolume = newVolume;
                          _player.setVolume(newVolume * 100.0);
                          setState(() => _showVolumeHUD = true);
                        },
                        onVerticalDragEnd: (details) {
                          _volumeHUDTimer?.cancel();
                          _volumeHUDTimer = Timer(const Duration(milliseconds: 1200), () {
                            if (mounted) setState(() => _showVolumeHUD = false);
                          });
                          _startHideTimer();
                        },
                        behavior: HitTestBehavior.translucent,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Stream Error Overlay (Only shown when all recovery attempts fail) ─
              if (_streamError != null)
                Container(
                  color: const Color(0xF00A0A0F),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.white70,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Playback Error',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sanitizeErrorMessage(_streamError),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: Colors.white60,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: _handleBack,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Back'),
                            ),
                            const SizedBox(width: 14),
                            ElevatedButton(
                              onPressed: _fetchStreamsAndPlay,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Player Controls Overlay (ALWAYS MOUNTED & INTERACTIVE) ──────
              if (_streamError == null)
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  builder: (context, posSnap) {
                    return StreamBuilder<Duration>(
                      stream: _player.stream.duration,
                      builder: (context, durSnap) {
                        return StreamBuilder<bool>(
                          stream: _player.stream.playing,
                          builder: (context, playSnap) {
                          // Build mapped audio tracks with human-readable language names
                          final Map<String, AudioTrack> audioTrackMap = {};
                          for (int i = 0; i < _player.state.tracks.audio.length; i++) {
                            final a = _player.state.tracks.audio[i];
                            final cleanName = TrackLanguageHelper.normalizeAudioTrackName(
                              rawTitle: a.title,
                              rawLang: a.language,
                              index: i,
                              streamAudioLanguages: _currentStream.audioLanguages,
                              channels: a.channels,
                            );
                            String finalKey = cleanName;
                            int dup = 2;
                            while (audioTrackMap.containsKey(finalKey)) {
                              finalKey = '$cleanName (Track $dup)';
                              dup++;
                            }
                            audioTrackMap[finalKey] = a;
                          }

                          // Build mapped subtitle tracks
                          final Map<String, SubtitleTrack> subtitleTrackMap = {};
                          for (int i = 0; i < _player.state.tracks.subtitle.length; i++) {
                            final s = _player.state.tracks.subtitle[i];
                            final cleanName = TrackLanguageHelper.normalizeSubtitleTrackName(
                              rawTitle: s.title,
                              rawLang: s.language,
                              index: i,
                            );
                            String finalKey = cleanName;
                            int dup = 2;
                            while (subtitleTrackMap.containsKey(finalKey)) {
                              finalKey = '$cleanName (Track $dup)';
                              dup++;
                            }
                            subtitleTrackMap[finalKey] = s;
                          }

                          // Determine active audio label
                          String activeAudio = _currentAudioTrack;
                          final currentMpvAudio = _player.state.track.audio;
                          for (final entry in audioTrackMap.entries) {
                            if (entry.value.id == currentMpvAudio.id) {
                              activeAudio = entry.key;
                              break;
                            }
                          }
                          if ((activeAudio.isEmpty || activeAudio == 'Original Audio') &&
                              audioTrackMap.isNotEmpty) {
                            activeAudio = audioTrackMap.keys.first;
                          }

                          // Determine active subtitle label
                          String activeSubtitle = _currentSubtitleTrack;
                          final currentMpvSub = _player.state.track.subtitle;
                          if (currentMpvSub.id == 'no' || currentMpvSub.id == 'auto') {
                            activeSubtitle = 'Off';
                          } else {
                            for (final entry in subtitleTrackMap.entries) {
                              if (entry.value.id == currentMpvSub.id) {
                                activeSubtitle = entry.key;
                                break;
                              }
                            }
                          }

                          return PlayerControls(
                            isPlaying: playSnap.data ?? false,
                            isBuffering: _isBuffering || _isLoadingStreams,
                            isFullscreen: _isFullscreen,
                            position: posSnap.data ?? Duration.zero,
                            duration: durSnap.data ?? Duration.zero,
                            speed: _speed,
                            title: widget.title,
                            subtitle: widget.isSeries
                                ? 'S$_currentSeason:E$_currentEpisode'
                                : widget.subtitle,
                            streams: _streams,
                            currentStream: _currentStream,
                            availableQualities: _availableQualities,
                            currentAudioTrack: activeAudio,
                            currentSubtitleTrack: activeSubtitle,
                            audioTracks: audioTrackMap.keys.toList(),
                            subtitleTracks: subtitleTrackMap.keys.toList(),
                            isVisible: _controlsVisible,
                            isSeries: widget.isSeries,
                            fitModeLabel: _videoFitMode.label,
                            onToggleFitMode: _toggleAspectMode,
                            onOpenEpisodes: widget.isSeries ? _openEpisodeDrawer : null,
                            onPlayPause: () => _player.playOrPause(),
                            onSeekBack10: _onDoubleTapLeft,
                            onSeekForward10: _onDoubleTapRight,
                            onSeek: (fraction) {
                              final total = durSnap.data ?? Duration.zero;
                              _seekTo(Duration(
                                  milliseconds:
                                      (total.inMilliseconds * fraction)
                                          .round()));
                            },
                            onToggleFullscreen: _toggleFullscreen,
                            onBack: _handleBack,
                            onQualityChanged: (stream) =>
                                _switchStream(stream),
                            onSpeedChanged: _setSpeed,
                            onAudioTrackChanged: (track) {
                              setState(() => _currentAudioTrack = track);
                              final match = audioTrackMap[track];
                              if (match != null) {
                                _player.setAudioTrack(match);
                              } else {
                                _player.setAudioTrack(AudioTrack.auto());
                              }
                            },
                            onSubtitleTrackChanged: (track) =>
                                _applySubtitleTrack(track, subtitleTrackMap),
                          );
                          },
                        );
                      },
                    );
                  },
                ),

              // ── Apple Liquid Glass Next Episode Preview Banner (5s remaining) ──
              if (_showNextEpisodeBanner && nextEpisodeData != null && !_autoPlayCancelled)
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = _player.state.duration;
                    final rem = (dur - pos).inSeconds.clamp(1, 5);
                    return Positioned(
                      bottom: _controlsVisible ? 100 : 28,
                      right: 20,
                      child: SafeArea(
                        child: _NextEpisodeAppleBanner(
                          episode: nextEpisodeData!,
                          season: _currentSeason,
                          remainingSeconds: rem,
                          onCancel: () {
                            setState(() {
                              _autoPlayCancelled = true;
                              _showNextEpisodeBanner = false;
                            });
                          },
                          onPlayNow: () => _playNextEpisode(),
                        ),
                      ),
                    );
                  },
                ),

              // ── Aspect Ratio Floating Toast Indicator ───────────────────────
              if (_showAspectToast)
                Positioned(
                  top: 36,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SafeArea(
                      child: _AppleAspectToast(mode: _videoFitMode),
                    ),
                  ),
                ),

              // ── Apple Liquid Glass Brightness HUD (Left vertical swipe) ─────
              if (_showBrightnessHUD)
                Positioned(
                  left: 32,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ApplePlayerVerticalHUD(
                      icon: CupertinoIcons.sun_max_fill,
                      value: _currentBrightness,
                      label: '${(_currentBrightness * 100).round()}%',
                      accentColor: Colors.amberAccent,
                    ),
                  ),
                ),

              // ── Apple Liquid Glass Volume HUD (Right vertical swipe) ─────────
              if (_showVolumeHUD)
                Positioned(
                  right: 32,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ApplePlayerVerticalHUD(
                      icon: _currentVolume <= 0.01
                          ? CupertinoIcons.speaker_slash_fill
                          : (_currentVolume > 0.5
                              ? CupertinoIcons.speaker_3_fill
                              : CupertinoIcons.speaker_2_fill),
                      value: _currentVolume,
                      label: '${(_currentVolume * 100).round()}%',
                      accentColor: const Color(0xFF007AFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Apple Liquid Glass Next Episode Preview Banner ────────────────────────────

class _NextEpisodeAppleBanner extends StatelessWidget {
  final EpisodeData episode;
  final int season;
  final int remainingSeconds;
  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  const _NextEpisodeAppleBanner({
    required this.episode,
    required this.season,
    required this.remainingSeconds,
    required this.onCancel,
    required this.onPlayNow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 290,
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          decoration: BoxDecoration(
            color: const Color(0xCC14141E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Liquid glass circular Play badge / Countdown
              GestureDetector(
                onTap: onPlayNow,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE50914).withValues(alpha: 0.20),
                    border: Border.all(
                      color: const Color(0xFFE50914).withValues(alpha: 0.60),
                      width: 1.2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.play_fill,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              // Episode Info
              Expanded(
                child: GestureDetector(
                  onTap: onPlayNow,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'UP NEXT · ${remainingSeconds}s',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFF5252),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'S$season:E${episode.number} ${episode.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Close (×) button to cancel autoplay
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(28),
                onPressed: onCancel,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 0.8,
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Apple Liquid Glass Vertical Player HUD (Brightness & Volume) ───────────────

class _ApplePlayerVerticalHUD extends StatelessWidget {
  final IconData icon;
  final double value; // 0.0 to 1.0
  final String label;
  final Color accentColor;

  const _ApplePlayerVerticalHUD({
    required this.icon,
    required this.value,
    required this.label,
    this.accentColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final clampedVal = value.clamp(0.0, 1.0);
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            width: 52,
            height: 190,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xCC161622),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.60),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Colors.white,
                ),
                // Apple-style vertical level indicator pill
                Container(
                  width: 7,
                  height: 104,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(3.5),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 7,
                    height: 104 * clampedVal,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          accentColor,
                          Colors.white,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3.5),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Apple Liquid Glass Aspect Ratio Toast Indicator ───────────────────────────

class _AppleAspectToast extends StatelessWidget {
  final VideoFitMode mode;

  const _AppleAspectToast({required this.mode});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xCC161622),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mode.icon,
                  size: 16,
                  color: const Color(0xFF007AFF), // Apple Blue
                ),
                const SizedBox(width: 9),
                Text(
                  mode.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
