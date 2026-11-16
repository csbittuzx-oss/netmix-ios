// lib/services/ad_verification_service.dart
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/security_vault.dart';
import 'secure_storage_service.dart';

class AdVerificationResult {
  final bool success;
  final String? error;
  final int remainingSeconds;
  final DateTime? expiresAt;

  const AdVerificationResult({
    required this.success,
    this.error,
    this.remainingSeconds = 0,
    this.expiresAt,
  });
}

/// Mandatory Server-Side Ad Verification & 12-Hour Access Manager
class AdVerificationService extends ChangeNotifier {
  static final AdVerificationService instance = AdVerificationService._();
  AdVerificationService._();

  static const String _kDeviceIdKey = 'ad_device_unique_id';
  static const String _kAccessPassKey = 'ad_server_access_pass';
  static const String _kExpiresAtKey = 'ad_server_expires_at';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Netmix-Android-Security/2.0',
      },
    ),
  );

  String? _deviceId;
  String? _accessPass;
  DateTime? _expiresAt;
  bool _isAccessGranted = false;
  String? _activeSessionId;
  DateTime? _sessionStartTime;
  String _activeAdUrl = SecurityVault.defaultAdUrl;
  int _requiredDurationSeconds = 30;
  Timer? _expiryTimer;
  bool _isVerifying = false;
  String? _lastVerificationError;

  bool get isAccessGranted => _isAccessGranted;
  bool get isVerifying => _isVerifying;
  String? get lastVerificationError => _lastVerificationError;
  String get activeAdUrl => _activeAdUrl.trim().isNotEmpty ? _activeAdUrl : SecurityVault.defaultAdUrl;
  int get requiredDurationSeconds => _requiredDurationSeconds;
  DateTime? get expiresAt => _expiresAt;
  String? get activeSessionId => _activeSessionId;
  DateTime? get sessionStartTime => _sessionStartTime;

  String get _updateBaseUrl {
    final raw = SecurityVault.defaultUpdateUrl;
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  /// Dynamically update ad URL from backend sync with fallback to sealed default
  void updateAdUrl(String newUrl) {
    final clean = newUrl.trim();
    final effective = clean.isNotEmpty ? clean : SecurityVault.defaultAdUrl;
    if (_activeAdUrl != effective) {
      _activeAdUrl = effective;
      notifyListeners();
    }
  }

  /// Synchronize dynamic ad URL and duration from remote backend config
  Future<void> syncAdConfigFromBackend() async {
    try {
      final res = await _dio.get('$_updateBaseUrl/api/config');
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (data['adUrl'] != null && data['adUrl'].toString().trim().isNotEmpty) {
          _activeAdUrl = data['adUrl'].toString().trim();
        } else {
          _activeAdUrl = SecurityVault.defaultAdUrl;
        }
        if (data['adDurationSeconds'] != null) {
          _requiredDurationSeconds = (data['adDurationSeconds'] as num).toInt();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AdVerificationService] syncAdConfigFromBackend error: $e');
    }
  }

  /// Initialize device identity and load cached credentials
  Future<void> init() async {
    try {
      // 1. Load or generate stable cryptographically random device ID
      _deviceId = await SecureStorageService.instance.getSecureString(_kDeviceIdKey);
      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = _generateUuidV4();
        await SecureStorageService.instance.setSecureString(_kDeviceIdKey, _deviceId!);
      }

      // 2. Load cached access pass
      _accessPass = await SecureStorageService.instance.getSecureString(_kAccessPassKey);
      final expStr = await SecureStorageService.instance.getSecureString(_kExpiresAtKey);
      if (expStr != null && expStr.isNotEmpty) {
        final expMs = int.tryParse(expStr);
        if (expMs != null) {
          _expiresAt = DateTime.fromMillisecondsSinceEpoch(expMs);
        }
      }

      // 3. If cached pass exists and not expired locally, schedule timer tentatively
      if (_accessPass != null && _expiresAt != null && _expiresAt!.isAfter(DateTime.now())) {
        _isAccessGranted = true;
        _scheduleExpiryTimer(_expiresAt!.difference(DateTime.now()));
      } else {
        _isAccessGranted = false;
        _accessPass = null;
      }

      // 4. Synchronize dynamic ad configuration from backend
      syncAdConfigFromBackend();
    } catch (e) {
      debugPrint('[AdVerificationService] Init error: $e');
    }
  }

  /// Check server-side access status (validates HMAC signature on backend)
  Future<bool> checkAccessStatus() async {
    await init();
    try {
      final res = await _dio.post(
        '$_updateBaseUrl/api/ad/status',
        data: {
          'deviceId': _deviceId,
          'accessPass': _accessPass,
        },
      );

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final hasAccess = data['hasAccess'] == true;

        if (data['adUrl'] != null && data['adUrl'].toString().trim().isNotEmpty) {
          _activeAdUrl = data['adUrl'].toString().trim();
        } else {
          _activeAdUrl = SecurityVault.defaultAdUrl;
        }
        if (data['minDurationSeconds'] != null) {
          _requiredDurationSeconds = (data['minDurationSeconds'] as num).toInt();
        }

        if (hasAccess) {
          _isAccessGranted = true;
          if (data['expiresAt'] != null) {
            final expMs = (data['expiresAt'] as num).toInt();
            _expiresAt = DateTime.fromMillisecondsSinceEpoch(expMs);
            _scheduleExpiryTimer(_expiresAt!.difference(DateTime.now()));
          }
          notifyListeners();
          return true;
        } else {
          // Access expired or revoked on server
          await _revokeAccess();
          return false;
        }
      }
    } catch (e) {
      debugPrint('[AdVerificationService] checkAccessStatus error: $e');
      // If network fails but local pass is legitimately unexpired, allow grace
      if (_accessPass != null && _expiresAt != null && _expiresAt!.isAfter(DateTime.now())) {
        _isAccessGranted = true;
        return true;
      }
    }

    _isAccessGranted = false;
    notifyListeners();
    return false;
  }

  /// Start a new ad session on backend and launch Google Chrome
  Future<bool> startAdSession() async {
    _lastVerificationError = null;
    notifyListeners();

    try {
      final res = await _dio.post(
        '$_updateBaseUrl/api/ad/start',
        data: {
          'deviceId': _deviceId,
        },
      );

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (data['success'] == true) {
          _activeSessionId = data['sessionId']?.toString();
          _sessionStartTime = DateTime.now();
          if (data['adUrl'] != null && data['adUrl'].toString().trim().isNotEmpty) {
            _activeAdUrl = data['adUrl'].toString().trim();
          } else {
            _activeAdUrl = SecurityVault.defaultAdUrl;
          }
          if (data['minDurationSeconds'] != null) {
            _requiredDurationSeconds = (data['minDurationSeconds'] as num).toInt();
          }

          notifyListeners();
          // Open ad URL in Google Chrome (with external application fallback)
          return await _openInGoogleChrome(_activeAdUrl);
        }
      }
    } catch (e) {
      debugPrint('[AdVerificationService] startAdSession error: $e');
      _lastVerificationError = 'Network error contacting ad server. Please check your connection.';
      notifyListeners();
    }
    return false;
  }

  /// Verify ad session strictly server-side (enforces >= 30 seconds)
  Future<AdVerificationResult> verifyAdSession() async {
    if (_activeSessionId == null) {
      return const AdVerificationResult(
        success: false,
        error: 'No active ad session. Please tap Click Here to open the ad.',
      );
    }

    _isVerifying = true;
    notifyListeners();

    try {
      final res = await _dio.post(
        '$_updateBaseUrl/api/ad/verify',
        data: {
          'deviceId': _deviceId,
          'sessionId': _activeSessionId,
        },
      );

      _isVerifying = false;

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;

        if (data['success'] == true && data['completed'] == true) {
          final pass = data['accessPass']?.toString();
          final expMs = (data['expiresAt'] as num?)?.toInt();

          if (pass != null && expMs != null) {
            _accessPass = pass;
            _expiresAt = DateTime.fromMillisecondsSinceEpoch(expMs);
            _isAccessGranted = true;
            _activeSessionId = null;
            _sessionStartTime = null;
            _lastVerificationError = null;

            // Persist verified cryptographic credentials
            await SecureStorageService.instance.setSecureString(_kAccessPassKey, pass);
            await SecureStorageService.instance.setSecureString(_kExpiresAtKey, expMs.toString());

            _scheduleExpiryTimer(_expiresAt!.difference(DateTime.now()));
            notifyListeners();

            return AdVerificationResult(
              success: true,
              expiresAt: _expiresAt,
            );
          }
        }

        // Verification failed (user returned too early or invalid session)
        final errMsg = data['error']?.toString() ??
            "You didn't complete the ad. Please reopen it, watch for 30 seconds, and return to the Netmix app.";
        final remaining = (data['remainingSeconds'] as num?)?.toInt() ?? 0;

        _lastVerificationError = errMsg;
        notifyListeners();

        return AdVerificationResult(
          success: false,
          error: errMsg,
          remainingSeconds: remaining,
        );
      }
    } catch (e) {
      debugPrint('[AdVerificationService] verifyAdSession error: $e');
      _isVerifying = false;
      _lastVerificationError = 'Connection error during verification. Please tap Reload.';
      notifyListeners();
    }

    return AdVerificationResult(
      success: false,
      error: _lastVerificationError,
    );
  }

  /// Launch the URL directly in Google Chrome on Android
  Future<bool> _openInGoogleChrome(String url) async {
    final uri = Uri.parse(url);

    // 1. Try launching specifically via Chrome intent
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;
    } catch (e) {
      debugPrint('[AdVerificationService] LaunchMode.externalApplication error: $e');
    }

    // 2. Fallback to platform default
    try {
      return await launchUrl(uri);
    } catch (e) {
      debugPrint('[AdVerificationService] launchUrl fallback error: $e');
      return false;
    }
  }

  void _scheduleExpiryTimer(Duration duration) {
    _expiryTimer?.cancel();
    if (duration.isNegative || duration == Duration.zero) {
      _revokeAccess();
      return;
    }

    _expiryTimer = Timer(duration, () {
      debugPrint('[AdVerificationService] 12-Hour Access Expired! Revoking access.');
      _revokeAccess();
    });
  }

  Future<void> _revokeAccess() async {
    _isAccessGranted = false;
    _accessPass = null;
    _expiresAt = null;
    _activeSessionId = null;
    _sessionStartTime = null;
    _expiryTimer?.cancel();

    await SecureStorageService.instance.removeSecure(_kAccessPassKey);
    await SecureStorageService.instance.removeSecure(_kExpiresAtKey);
    notifyListeners();
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant RFC4122
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
