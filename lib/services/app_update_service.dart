// lib/services/app_update_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/security_vault.dart';
import 'ad_verification_service.dart';

class UpdateInfo {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String changelog;
  final String apkUrl;
  final int fileSize;
  final String? sha256Checksum;
  final bool mandatory;

  const UpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.changelog,
    required this.apkUrl,
    required this.fileSize,
    this.sha256Checksum,
    this.mandatory = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, String currentVer) {
    return UpdateInfo(
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      currentVersion: currentVer,
      latestVersion: json['latestVersion']?.toString() ?? currentVer,
      title: json['title']?.toString() ?? 'New Update Available',
      changelog: json['changelog']?.toString() ??
          'Performance and stability improvements.',
      apkUrl: json['apkUrl']?.toString() ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256Checksum:
          json['sha256']?.toString() ?? json['sha256Checksum']?.toString(),
      mandatory: json['mandatory'] as bool? ?? false,
    );
  }
}

class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService instance = AppUpdateService._();
  AppUpdateService._();

  static final String defaultUpdateUrl = SecurityVault.defaultUpdateUrl;

  // SharedPreferences Keys
  static const String keyInstalledVersion = 'netmix_installed_update_version';
  static const String keyAcknowledgedVersion = 'netmix_acknowledged_update_version';
  static const String keyDismissedVersion = 'netmix_dismissed_update_version';
  static const String keyLastOfferedVersion = 'netmix_last_offered_version';
  static const String keyTelegramUrl = 'netmix_telegram_channel_url';
  static const String keyRemoteStreamingUrl = 'netmix_remote_streaming_url';
  static const String defaultTelegramUrl = 'https://t.me/Netmix_official';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'Netmix-Android-Client/1.0'},
    ),
  );

  static const MethodChannel _securityChannel =
      MethodChannel('com.netmix.security/integrity');

  String _cachedVersion = '1.0.0';
  String _telegramUrl = defaultTelegramUrl;
  bool _initialized = false;

  /// Synchronous access to the currently confirmed installed version
  String get currentInstalledVersion => _cachedVersion;

  /// Dynamic Telegram community link loaded from update backend
  String get telegramUrl => _telegramUrl;

  /// Launch the active Telegram community channel
  Future<void> openTelegram() async {
    final uri = Uri.parse(_telegramUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error opening Telegram: $e');
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  /// Initialize and detect the active installed version on startup
  Future<String> init() async {
    if (_initialized) return _cachedVersion;
    final version = await getInstalledVersion();
    _cachedVersion = version;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTg = prefs.getString(keyTelegramUrl);
      if (savedTg != null && savedTg.trim().isNotEmpty) {
        _telegramUrl = savedTg.trim();
      }
      fetchRemoteConfig();
    } catch (_) {}

    _initialized = true;
    notifyListeners();
    return _cachedVersion;
  }

  /// Fetch remote configuration (dynamic Telegram URL, streaming backend URL, etc.)
  Future<void> fetchRemoteConfig({String? customBaseUrl}) async {
    final rawBase = customBaseUrl ?? defaultUpdateUrl;
    final baseUrl = rawBase.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _dio.get('$baseUrl/api/config');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();

        // 1. Update Telegram URL
        final remoteTg = data['telegramUrl']?.toString();
        if (remoteTg != null && remoteTg.trim().isNotEmpty) {
          _telegramUrl = remoteTg.trim();
          await prefs.setString(keyTelegramUrl, _telegramUrl);
        }

        // 2. Update streaming backend URL remotely
        final remoteStreamingUrl = data['streamingBackendUrl']?.toString();
        if (remoteStreamingUrl != null && remoteStreamingUrl.trim().isNotEmpty) {
          final cleanUrl = remoteStreamingUrl.trim();
          final savedStreamUrl = prefs.getString(keyRemoteStreamingUrl);
          // Only apply if actually changed to avoid unnecessary Dio rebuild
          if (savedStreamUrl != cleanUrl) {
            await prefs.setString(keyRemoteStreamingUrl, cleanUrl);
            // Also persist to ApiClient's setting so it survives restarts
            await prefs.setString(AppConstants.prefBaseUrl, cleanUrl);
            // Hot-swap the live ApiClient Dio instance
            await ApiClient.instance.updateBaseUrl(cleanUrl);
            debugPrint('[AppUpdateService] Streaming backend updated remotely to: $cleanUrl');
          }
        }

        // 3. Update Ad URL remotely
        final remoteAdUrl = data['adUrl']?.toString();
        if (remoteAdUrl != null && remoteAdUrl.trim().isNotEmpty) {
          AdVerificationService.instance.updateAdUrl(remoteAdUrl.trim());
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error fetching remote config: $e');
    }
  }

  /// Fetch installed app version combining PackageInfo with persisted update state
  Future<String> getInstalledVersion() async {
    final prefs = await SharedPreferences.getInstance();
    String detectedVersion = '1.0.0';

    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        detectedVersion = info.version;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error reading PackageInfo: $e');
    }

    // Check if an update was installed that has a higher version
    final persistedVer = prefs.getString(keyInstalledVersion);
    if (persistedVer != null && persistedVer.trim().isNotEmpty) {
      if (compareVersions(persistedVer, detectedVersion) > 0) {
        // User successfully upgraded to persistedVer
        detectedVersion = persistedVer.trim();
      } else {
        // PackageInfo has caught up or surpassed persistedVer, sync storage
        await prefs.setString(keyInstalledVersion, detectedVersion);
      }
    } else {
      await prefs.setString(keyInstalledVersion, detectedVersion);
    }

    _cachedVersion = detectedVersion;
    return detectedVersion;
  }

  /// Check backend for available updates with client-side verification
  Future<UpdateInfo> checkUpdate({String? customBaseUrl}) async {
    final currentVer = await getInstalledVersion();
    final rawBase = customBaseUrl ?? defaultUpdateUrl;
    final baseUrl = rawBase.replaceAll(RegExp(r'/+$'), '');

    try {
      final response = await _dio.get(
        '$baseUrl/api/updates/check',
        queryParameters: {'version': currentVer},
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final latestVer = data['latestVersion']?.toString() ?? currentVer;

        final prefs = await SharedPreferences.getInstance();
        final installedVer = prefs.getString(keyInstalledVersion) ?? currentVer;
        final acknowledgedVer = prefs.getString(keyAcknowledgedVersion);

        // Client-side verification:
        // 1. Is latestVersion mathematically strictly newer than currentVer?
        final bool isNewerThanCurrent = compareVersions(latestVer, currentVer) > 0;

        // 2. Has this specific latestVersion already been installed or acknowledged?
        final bool isAlreadyInstalled = compareVersions(latestVer, installedVer) <= 0;
        final bool isAlreadyAcknowledged = acknowledgedVer != null &&
            compareVersions(latestVer, acknowledgedVer) <= 0;

        // An update is ONLY available if strictly newer AND not already installed/acknowledged
        final bool shouldPromptUpdate = isNewerThanCurrent &&
            !isAlreadyInstalled &&
            !isAlreadyAcknowledged;

        final remoteTg = data['telegramUrl']?.toString();
        if (remoteTg != null && remoteTg.trim().isNotEmpty) {
          _telegramUrl = remoteTg.trim();
          await prefs.setString(keyTelegramUrl, _telegramUrl);
        }

        // Apply remote streaming backend URL if admin has updated it
        final remoteStreamUrl = data['streamingBackendUrl']?.toString();
        if (remoteStreamUrl != null && remoteStreamUrl.trim().isNotEmpty) {
          final cleanUrl = remoteStreamUrl.trim();
          final savedStreamUrl = prefs.getString(keyRemoteStreamingUrl);
          if (savedStreamUrl != cleanUrl) {
            await prefs.setString(keyRemoteStreamingUrl, cleanUrl);
            await prefs.setString(AppConstants.prefBaseUrl, cleanUrl);
            await ApiClient.instance.updateBaseUrl(cleanUrl);
            debugPrint('[AppUpdateService] Streaming backend updated via check: $cleanUrl');
          }
        }

        // Apply remote ad URL if admin has updated it
        final remoteAdUrl = data['adUrl']?.toString();
        if (remoteAdUrl != null && remoteAdUrl.trim().isNotEmpty) {
          AdVerificationService.instance.updateAdUrl(remoteAdUrl.trim());
        }

        final info = UpdateInfo(
          updateAvailable: shouldPromptUpdate,
          currentVersion: currentVer,
          latestVersion: latestVer,
          title: data['title']?.toString() ?? 'New Update Available',
          changelog: data['changelog']?.toString() ??
              'Performance and stability improvements.',
          apkUrl: data['apkUrl']?.toString() ?? '',
          fileSize: (data['fileSize'] as num?)?.toInt() ?? 0,
          sha256Checksum:
              data['sha256']?.toString() ?? data['sha256Checksum']?.toString(),
          mandatory: data['mandatory'] as bool? ?? false,
        );

        if (shouldPromptUpdate) {
          showUpdateNotificationIfPermitted(info);
        }

        return info;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking updates: $e');
    }

    return UpdateInfo(
      updateAvailable: false,
      currentVersion: currentVer,
      latestVersion: currentVer,
      title: 'Up to Date',
      changelog: 'You are using the latest version of Netmix.',
      apkUrl: '',
      fileSize: 0,
    );
  }

  /// Displays an Android system notification if notification permission is granted
  Future<void> showUpdateNotificationIfPermitted(UpdateInfo info) async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        final title = 'Netmix Update v${info.latestVersion} Available';
        final content = info.changelog.isNotEmpty
            ? info.changelog
            : 'A new version with latest streams and fixes is ready to download.';
        await _securityChannel.invokeMethod('showUpdateNotification', {
          'title': title,
          'content': content,
        });
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Notification show error: $e');
    }
  }

  /// Mark an update version as successfully installed and refresh state everywhere
  Future<void> markUpdateInstalled(String version) async {
    final cleanVer = version.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyInstalledVersion, cleanVer);
    await prefs.setString(keyAcknowledgedVersion, cleanVer);
    _cachedVersion = cleanVer;
    notifyListeners();
  }

  /// Dismiss an update version prompt so user is not repeatedly nagged
  Future<void> dismissUpdate(String version) async {
    final cleanVer = version.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDismissedVersion, cleanVer);
  }

  /// Safely open update download in user's browser, persist version state & prevent duplicate prompts
  Future<void> downloadAndInstall({
    required String apkUrl,
    required String version,
    String? expectedSha256,
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    // Record version state so it persists across restarts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastOfferedVersion, version);
    await markUpdateInstalled(version);

    // Launch official download URL in external browser (Google Play Protect safe)
    final targetUrl = apkUrl.isNotEmpty
        ? apkUrl
        : 'https://csbittuzx-oss.github.io/netmix-apk-download/';
    final uri = Uri.parse(targetUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Robust SemVer + Build Number comparison
  /// Returns:
  ///   1 if v1 > v2
  ///  -1 if v1 < v2
  ///   0 if v1 == v2
  static int compareVersions(String v1, String v2) {
    if (v1.trim() == v2.trim()) return 0;

    // Clean leading 'v' / 'V' and spaces
    final s1 = v1.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final s2 = v2.trim().replaceFirst(RegExp(r'^[vV]'), '');

    // Extract build numbers if present (after '+')
    final plus1 = s1.split('+');
    final plus2 = s2.split('+');

    final semver1 = plus1[0].split('-')[0].trim();
    final semver2 = plus2[0].split('-')[0].trim();

    final build1 = plus1.length > 1 ? (int.tryParse(plus1[1].trim()) ?? 0) : 0;
    final build2 = plus2.length > 1 ? (int.tryParse(plus2[1].trim()) ?? 0) : 0;

    // Compare numeric dot-separated segments
    final segs1 =
        semver1.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final segs2 =
        semver2.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();

    final maxLen = segs1.length > segs2.length ? segs1.length : segs2.length;
    for (int i = 0; i < maxLen; i++) {
      final num1 = i < segs1.length ? segs1[i] : 0;
      final num2 = i < segs2.length ? segs2[i] : 0;
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }

    // Semver segments are identical; compare build numbers
    if (build1 > build2) return 1;
    if (build1 < build2) return -1;

    return 0;
  }
}
