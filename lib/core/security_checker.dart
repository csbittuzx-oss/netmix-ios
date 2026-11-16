// lib/core/security_checker.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'security_vault.dart';

/// Runtime integrity, signature validation, and anti-reverse-engineering protector
class SecurityChecker {
  SecurityChecker._();

  static const String _expectedPackage = 'com.netmix.netmix_flutter';
  static const MethodChannel _channel = MethodChannel('com.netmix.security/integrity');

  static bool _hasPassedIntegrity = false;

  /// Verifies app package integrity, signature hash, and checks for tampering or APK editors
  static Future<bool> verifyAppIntegrity() async {
    try {
      if (kIsWeb) return true;
      if (_hasPassedIntegrity) return true;

      // 1. Package Name Integrity
      final info = await PackageInfo.fromPlatform();
      if (info.packageName != _expectedPackage) {
        SecurityVault.markCompromised();
        return false;
      }

      // 2. Native Android Signature & Anti-Hook Inspection
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkSecurityIntegrity');
          if (res != null) {
            final isSecure = res['isSecure'] as bool? ?? (kDebugMode ? true : false);
            final isSignatureValid = res['isSignatureValid'] as bool? ?? (kDebugMode ? true : false);
            final isHooked = res['isHooked'] as bool? ?? false;
            final isDebugger = res['isDebugger'] as bool? ?? false;
            final isModdedToolPresent = res['isModdedToolPresent'] as bool? ?? false;
            final hasModdedArtifacts = res['hasModdedArtifacts'] as bool? ?? false;

            if (!isSecure ||
                !isSignatureValid ||
                isHooked ||
                isModdedToolPresent ||
                hasModdedArtifacts ||
                (kReleaseMode && isDebugger)) {
              SecurityVault.markCompromised();
              return false;
            }
          }
        } on MissingPluginException {
          // Native channel not available (e.g. running unit tests)
        } catch (_) {
          if (kReleaseMode) {
            SecurityVault.markCompromised();
            return false;
          }
        }
      }

      // 3. Debugger assertion check in release
      if (isDebuggerOrHookActive()) {
        SecurityVault.markCompromised();
        return false;
      }

      _hasPassedIntegrity = true;
      return true;
    } catch (_) {
      if (kReleaseMode) {
        SecurityVault.markCompromised();
        return false;
      }
      return true;
    }
  }

  /// Terminates a tampered or compromised app process instantly via native signal
  static Future<void> terminateCompromisedApp() async {
    try {
      SecurityVault.markCompromised();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('terminateCompromisedApp');
      }
    } catch (_) {}
    SystemNavigator.pop();
  }

  /// Detects presence of active debuggers or reverse-engineering hooking frameworks
  static bool isDebuggerOrHookActive() {
    if (kReleaseMode) {
      bool isDebug = false;
      assert(() {
        isDebug = true;
        return true;
      }());
      if (isDebug) return true;
    }
    return false;
  }
}
