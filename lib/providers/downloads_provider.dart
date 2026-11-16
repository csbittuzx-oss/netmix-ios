// lib/providers/downloads_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/security_vault.dart';
import '../models/download_item.dart';

class DownloadsNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadsNotifier() : super([]) {
    _init();
  }

  static const _securityChannel = MethodChannel('com.netmix.security/integrity');

  // Dedicated Dio instance optimized for large streaming media downloads
  late final Dio _downloadDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: null, // No timeout on long stream pipes
      responseType: ResponseType.stream,
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  final Map<String, CancelToken> _activeTokens = {};
  final Map<String, int> _retryAttempts = {};
  final Map<String, int> _lastSpeedBytes = {};
  final Map<String, DateTime> _lastSpeedTime = {};
  final Map<String, DateTime> _lastNotifTime = {};

  Future<void> _init() async {
    await _loadFromPrefs();

    // Check existing tasks: if app was closed while downloading, mark as paused
    // so user can seamlessly resume right from where they left off
    bool modified = false;
    final updatedList = state.map((item) {
      if (item.status == DownloadStatus.downloading ||
          item.status == DownloadStatus.queued) {
        modified = true;
        // Verify partial file on disk
        int downloaded = item.downloadedBytes ?? 0;
        if (item.filePath != null) {
          final partFile = File('${item.filePath}.part');
          if (partFile.existsSync()) {
            downloaded = partFile.lengthSync();
          }
        }
        return item.copyWith(
          status: DownloadStatus.paused,
          downloadedBytes: downloaded,
          speedText: null,
          etaText: 'Paused',
        );
      }
      return item;
    }).toList();

    if (modified) {
      state = updatedList;
      await _saveToPrefs();
    }

    _checkAndReleaseWakeLock();
  }

  Future<Directory> _getDownloadDir() async {
    Directory? downloadDir;
    if (Platform.isAndroid) {
      try {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          downloadDir = publicDownload;
        }
      } catch (_) {}
      if (downloadDir == null) {
        try {
          final extList = await getExternalStorageDirectories(
              type: StorageDirectory.downloads);
          if (extList != null && extList.isNotEmpty) {
            downloadDir = extList.first;
          }
        } catch (_) {}
      }
    }
    downloadDir ??= await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  Future<void> startDownload({
    required String itemId,
    required String title,
    required String? poster,
    required String downloadUrl,
    required String quality,
    required String contentType,
    int? seasonNumber,
    int? episodeNumber,
    int? estimatedTotalBytes,
  }) async {
    try {
      final dir = await _getDownloadDir();
      final cleanTitle = title
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' - ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cleanQuality = quality.toUpperCase().trim();
      final fileName = '$cleanTitle ($cleanQuality).mp4';
      final destinationFilePath = '${dir.path}/$fileName';

      String effectiveUrl = downloadUrl.trim();
      if (!effectiveUrl.startsWith('http://') &&
          !effectiveUrl.startsWith('https://')) {
        effectiveUrl = ApiClient.instance.buildProxyUrl(effectiveUrl);
      }
      if (effectiveUrl.contains('ugotnothing.onrender.com') ||
          effectiveUrl.contains('netmix-play.onrender.com')) {
        effectiveUrl = effectiveUrl
            .replaceAll('ugotnothing.onrender.com', 'netmix-byoky.onrender.com')
            .replaceAll('netmix-play.onrender.com', 'netmix-byoky.onrender.com');
      }

      // If already downloading or queued for this itemId, cancel previous one
      final existingIdx = state.indexWhere((d) => d.itemId == itemId);
      if (existingIdx != -1) {
        final existingItem = state[existingIdx];
        if (_activeTokens.containsKey(existingItem.id)) {
          _activeTokens[existingItem.id]?.cancel('restarted');
          _activeTokens.remove(existingItem.id);
        }
        state = state.where((d) => d.id != existingItem.id).toList();
      }

      final taskId = 'dl_${itemId}_${DateTime.now().millisecondsSinceEpoch}';
      final item = DownloadItem(
        id: taskId,
        itemId: itemId,
        title: title,
        poster: poster,
        quality: quality,
        filePath: destinationFilePath,
        totalBytes: estimatedTotalBytes,
        downloadedBytes: 0,
        progressPercent: 0,
        status: DownloadStatus.downloading,
        contentType: contentType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        addedAt: DateTime.now(),
        downloadUrl: effectiveUrl,
        speedText: 'Connecting...',
        etaText: 'Calculating...',
      );

      state = [item, ...state];
      await _saveToPrefs();

      // Launch native stream engine
      _executeDownload(item);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DownloadsProvider] startDownload error: $e');
      }
    }
  }

  Future<void> _executeDownload(DownloadItem item) async {
    final taskId = item.id;
    if (_activeTokens.containsKey(taskId)) {
      // Already running
      return;
    }

    final cancelToken = CancelToken();
    _activeTokens[taskId] = cancelToken;

    // 1. Acquire Android Partial Wake Lock & Start Foreground Download Service to prevent OS sleep when minimized
    try {
      await _securityChannel.invokeMethod('acquireWakeLock');
      await _securityChannel.invokeMethod('startBackgroundDownloadService', {
        'title': item.title,
        'content': 'Downloading in background...',
      });
    } catch (_) {}

    final destinationPath = item.filePath;
    if (destinationPath == null) {
      _markFailed(taskId, 'Invalid destination path');
      return;
    }

    final finalFile = File(destinationPath);
    final partFile = File('$destinationPath.part');

    // If final file already exists and is non-empty, mark completed
    if (finalFile.existsSync() && finalFile.lengthSync() > 1024 * 1024) {
      _markCompleted(taskId, finalFile.lengthSync());
      return;
    }

    // Check existing bytes for resumption (HTTP Range header)
    int existingBytes = 0;
    if (partFile.existsSync()) {
      existingBytes = partFile.lengthSync();
    }

    final headers = <String, dynamic>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    if (existingBytes > 0) {
      headers['Range'] = 'bytes=$existingBytes-';
    }

    String effectiveUrl = item.downloadUrl ?? '';
    if (effectiveUrl.isEmpty) {
      _markFailed(taskId, 'Download URL is empty');
      return;
    }

    // Attach security verification headers if connecting through Render backend proxy
    if (effectiveUrl.contains('netmix-byoky.onrender.com') ||
        effectiveUrl.contains('netmix-play.onrender.com')) {
      try {
        final uri = Uri.parse(effectiveUrl);
        final secHeaders =
            SecurityVault.generateClientHeaders(uri.path, method: 'GET');
        headers.addAll(secHeaders);
      } catch (_) {}
    }

    // Ensure parent directory exists
    try {
      final parentDir = partFile.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }
    } catch (_) {}

    IOSink? sink;
    try {
      final response = await _downloadDio.get<ResponseBody>(
        effectiveUrl,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null && (status == 200 || status == 206),
        ),
        cancelToken: cancelToken,
      );

      final statusCode = response.statusCode ?? 200;
      final responseHeaders = response.headers;

      // Determine total file size from server response
      int totalBytes = item.totalBytes ?? 0;
      final contentRange = responseHeaders.value('content-range');
      final contentLengthStr = responseHeaders.value('content-length');

      if (statusCode == 206 && contentRange != null) {
        // e.g., "bytes 1048576-197576875/197576876"
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (match != null) {
          totalBytes = int.tryParse(match.group(1) ?? '') ?? totalBytes;
        }
      } else if (statusCode == 200) {
        // Server responded with 200 instead of 206 (does not support Range or fresh file)
        if (contentLengthStr != null) {
          totalBytes = int.tryParse(contentLengthStr) ?? totalBytes;
        }
        // If we had existing bytes but server returned 200, restart from 0
        existingBytes = 0;
        if (partFile.existsSync()) {
          partFile.deleteSync();
        }
      }

      // Open part file in append mode (or create fresh)
      sink = partFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      int currentDownloaded = existingBytes;
      _lastSpeedBytes[taskId] = currentDownloaded;
      _lastSpeedTime[taskId] = DateTime.now();
      _lastNotifTime[taskId] = DateTime.now();

      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) {
          break;
        }

        sink.add(chunk);
        currentDownloaded += chunk.length;

        final now = DateTime.now();
        final lastTime = _lastSpeedTime[taskId] ?? now;
        final deltaMs = now.difference(lastTime).inMilliseconds;

        // Throttle UI and state calculations to every 650ms to ensure smooth 60fps rendering
        if (deltaMs >= 650) {
          final lastBytes = _lastSpeedBytes[taskId] ?? currentDownloaded;
          final deltaBytes = currentDownloaded - lastBytes;
          final speedSec = deltaBytes / (deltaMs / 1000.0);

          _lastSpeedBytes[taskId] = currentDownloaded;
          _lastSpeedTime[taskId] = now;

          final speedStr = _formatSpeed(speedSec);
          final etaStr = totalBytes > currentDownloaded && speedSec > 1024
              ? _formatEta(((totalBytes - currentDownloaded) / speedSec).round())
              : null;

          final progressPct = totalBytes > 0
              ? ((currentDownloaded / totalBytes) * 100).clamp(0, 100).toInt()
              : 0;

          _updateProgress(
            taskId: taskId,
            downloaded: currentDownloaded,
            total: totalBytes,
            progress: progressPct,
            speed: speedStr,
            eta: etaStr,
          );

          // Update Android notification bar
          final lastNotif = _lastNotifTime[taskId] ?? DateTime(2000);
          if (now.difference(lastNotif).inMilliseconds >= 1400) {
            _lastNotifTime[taskId] = now;
            _notifyAndroid(
              item: item,
              downloaded: currentDownloaded,
              total: totalBytes,
              progress: progressPct,
              speed: speedStr,
            );
          }
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (cancelToken.isCancelled) {
        return;
      }

      // Download completed successfully
      if (partFile.existsSync()) {
        final finalBytes = partFile.lengthSync();
        // Rename .part to .mp4
        if (finalFile.existsSync()) {
          finalFile.deleteSync();
        }
        await partFile.rename(destinationPath);

        _markCompleted(taskId, finalBytes);
      } else {
        _markFailed(taskId, 'Downloaded file missing');
      }
    } catch (e) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}

      if (cancelToken.isCancelled) {
        return;
      }

      // Auto-retry transient socket/network drops up to 5 times seamlessly
      final retries = (_retryAttempts[taskId] ?? 0) + 1;
      _retryAttempts[taskId] = retries;

      if (retries <= 5) {
        if (kDebugMode) {
          debugPrint('[DownloadsProvider] Reconnecting socket (attempt $retries/5): $e');
        }
        _activeTokens.remove(taskId);
        await Future.delayed(const Duration(milliseconds: 1200));
        final currItem = state.firstWhere(
          (d) => d.id == taskId,
          orElse: () => item,
        );
        if (currItem.status == DownloadStatus.downloading) {
          _executeDownload(currItem);
        }
        return;
      }

      _markFailed(taskId, 'Download interrupted');
    } finally {
      _activeTokens.remove(taskId);
      _checkAndReleaseWakeLock();
    }
  }

  void _updateProgress({
    required String taskId,
    required int downloaded,
    required int total,
    required int progress,
    required String speed,
    required String? eta,
  }) {
    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx != -1) {
      final current = state[idx];
      final updated = current.copyWith(
        downloadedBytes: downloaded,
        totalBytes: total > 0 ? total : current.totalBytes,
        progressPercent: progress,
        speedText: speed,
        etaText: eta,
        status: DownloadStatus.downloading,
      );
      state = [...state]..[idx] = updated;
    }
  }

  Future<void> _notifyAndroid({
    required DownloadItem item,
    required int downloaded,
    required int total,
    required int progress,
    required String speed,
  }) async {
    try {
      final dlStr = _formatBytes(downloaded);
      final totStr = _formatBytes(total);
      final contentStr = '$dlStr of $totStr · $speed';

      await _securityChannel.invokeMethod('updateDownloadNotification', {
        'id': item.id.hashCode,
        'title': item.title,
        'content': contentStr,
        'progress': progress,
        'isDone': false,
        'isFailed': false,
        'isPaused': false,
      });
    } catch (_) {}
  }

  Future<void> _markCompleted(String taskId, int finalBytes) async {
    _activeTokens.remove(taskId);
    _retryAttempts.remove(taskId);
    _lastSpeedBytes.remove(taskId);
    _lastSpeedTime.remove(taskId);
    _lastNotifTime.remove(taskId);

    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx != -1) {
      final current = state[idx];
      final now = DateTime.now();
      final updated = current.copyWith(
        status: DownloadStatus.done,
        progressPercent: 100,
        downloadedBytes: finalBytes,
        totalBytes: finalBytes,
        completedAt: now,
        speedText: null,
        etaText: null,
      );
      state = [...state]..[idx] = updated;
      await _saveToPrefs();

      // Scan file into MediaStore so VLC, MX Player, and Gallery recognize it
      if (updated.filePath != null) {
        try {
          await _securityChannel.invokeMethod('scanMediaFile', {
            'filePath': updated.filePath,
          });
        } catch (_) {}
      }

      // Update notification to completed
      try {
        await _securityChannel.invokeMethod('updateDownloadNotification', {
          'id': taskId.hashCode,
          'title': updated.title,
          'content': 'Download complete · ${_formatBytes(finalBytes)}',
          'progress': 100,
          'isDone': true,
          'isFailed': false,
          'isPaused': false,
        });
      } catch (_) {}
    }

    _checkAndReleaseWakeLock();
  }

  Future<void> _markFailed(String taskId, String reason) async {
    _activeTokens.remove(taskId);
    _retryAttempts.remove(taskId);
    _lastSpeedBytes.remove(taskId);
    _lastSpeedTime.remove(taskId);
    _lastNotifTime.remove(taskId);

    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx != -1) {
      final current = state[idx];
      final updated = current.copyWith(
        status: DownloadStatus.failed,
        speedText: null,
        etaText: reason,
      );
      state = [...state]..[idx] = updated;
      await _saveToPrefs();

      try {
        await _securityChannel.invokeMethod('updateDownloadNotification', {
          'id': taskId.hashCode,
          'title': current.title,
          'content': 'Download interrupted. Tap to retry.',
          'progress': current.progressPercent,
          'isDone': false,
          'isFailed': true,
          'isPaused': false,
        });
      } catch (_) {}
    }

    _checkAndReleaseWakeLock();
  }

  Future<void> pauseDownload(String taskId) async {
    if (_activeTokens.containsKey(taskId)) {
      _activeTokens[taskId]?.cancel('paused');
      _activeTokens.remove(taskId);
    }
    _retryAttempts.remove(taskId);
    _lastSpeedBytes.remove(taskId);
    _lastSpeedTime.remove(taskId);

    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx != -1) {
      final current = state[idx];
      final updated = current.copyWith(
        status: DownloadStatus.paused,
        speedText: null,
        etaText: 'Paused',
      );
      state = [...state]..[idx] = updated;
      await _saveToPrefs();

      try {
        await _securityChannel.invokeMethod('updateDownloadNotification', {
          'id': taskId.hashCode,
          'title': current.title,
          'content': 'Download paused · ${current.displayProgress}',
          'progress': current.progressPercent,
          'isDone': false,
          'isFailed': false,
          'isPaused': true,
        });
      } catch (_) {}
    }

    _checkAndReleaseWakeLock();
  }

  Future<void> resumeDownload(String taskId) async {
    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx == -1) return;

    final current = state[idx];
    _retryAttempts.remove(taskId);

    final updated = current.copyWith(
      status: DownloadStatus.downloading,
      speedText: 'Resuming...',
      etaText: 'Connecting...',
    );
    state = [...state]..[idx] = updated;
    await _saveToPrefs();

    _executeDownload(updated);
  }

  Future<void> cancelDownload(String taskId) async {
    if (_activeTokens.containsKey(taskId)) {
      _activeTokens[taskId]?.cancel('cancelled');
      _activeTokens.remove(taskId);
    }
    _retryAttempts.remove(taskId);
    _lastSpeedBytes.remove(taskId);
    _lastSpeedTime.remove(taskId);

    final idx = state.indexWhere((d) => d.id == taskId);
    if (idx != -1) {
      final item = state[idx];
      _deletePhysicalFiles(item);
      state = state.where((d) => d.id != taskId).toList();
      await _saveToPrefs();

      try {
        await _securityChannel.invokeMethod('cancelDownloadNotification', {
          'id': taskId.hashCode,
        });
      } catch (_) {}
    }

    _checkAndReleaseWakeLock();
  }

  Future<void> deleteDownload(String taskId) async {
    await cancelDownload(taskId);
  }

  void _deletePhysicalFiles(DownloadItem item) {
    if (item.filePath != null && item.filePath!.isNotEmpty) {
      try {
        final f = File(item.filePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      try {
        final part = File('${item.filePath}.part');
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
    final fileName = item.filePath?.split('/').last ??
        '${item.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' - ')} (${item.quality}).mp4';
    try {
      final pub = File('/storage/emulated/0/Download/$fileName');
      if (pub.existsSync()) pub.deleteSync();
    } catch (_) {}
    try {
      final pubPart = File('/storage/emulated/0/Download/$fileName.part');
      if (pubPart.existsSync()) pubPart.deleteSync();
    } catch (_) {}
  }

  Future<void> retryDownload(String taskId) async {
    await resumeDownload(taskId);
  }

  Future<void> pauseAllActive() async {
    for (final taskId in _activeTokens.keys.toList()) {
      _activeTokens[taskId]?.cancel('paused');
    }
    _activeTokens.clear();

    state = state.map((d) {
      if (d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued) {
        return d.copyWith(
          status: DownloadStatus.paused,
          speedText: null,
          etaText: 'Paused',
        );
      }
      return d;
    }).toList();

    await _saveToPrefs();
    _checkAndReleaseWakeLock();
  }

  Future<void> restoreDownload(DownloadItem item, {int? index}) async {
    if (index != null && index >= 0 && index <= state.length) {
      state = [...state]..insert(index, item);
    } else {
      state = [item, ...state];
    }
    await _saveToPrefs();
  }

  void _checkAndReleaseWakeLock() {
    final hasActive = _activeTokens.isNotEmpty ||
        state.any((d) => d.status == DownloadStatus.downloading);
    if (!hasActive) {
      try {
        _securityChannel.invokeMethod('releaseWakeLock');
        _securityChannel.invokeMethod('stopBackgroundDownloadService');
      } catch (_) {}
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  static String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  static String _formatEta(int remainingSeconds) {
    if (remainingSeconds < 60) {
      return '${remainingSeconds}s left';
    } else if (remainingSeconds < 3600) {
      final mins = remainingSeconds ~/ 60;
      final secs = remainingSeconds % 60;
      return '${mins}m ${secs}s left';
    } else {
      final hrs = remainingSeconds ~/ 3600;
      final mins = (remainingSeconds % 3600) ~/ 60;
      return '${hrs}h ${mins}m left';
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.prefDownloads);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        state = list
            .map((j) => DownloadItem.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(state.map((d) => d.toJson()).toList());
      await prefs.setString(AppConstants.prefDownloads, json);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final token in _activeTokens.values) {
      token.cancel('disposed');
    }
    _activeTokens.clear();
    _checkAndReleaseWakeLock();
    super.dispose();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadItem>>(
  (ref) => DownloadsNotifier(),
);
