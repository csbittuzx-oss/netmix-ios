// lib/core/security_vault.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Cryptographic vault that conceals all critical endpoints, TMDB keys,
/// and backend tokens from static strings extraction, Ghidra, Jadx, and binary analyzers.
class SecurityVault {
  SecurityVault._();

  // Multi-byte key used for dynamic bit-shift XOR deobfuscation
  static const String _k = 'NetmixSecurityKey_997_Shield';

  static String _deobfuscate(List<int> bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      final kByte = (_k.codeUnitAt(i % _k.length) + (i * 7) % 256) & 0xFF;
      result.add(bytes[i] ^ kByte);
    }
    return utf8.decode(result);
  }

  static bool _isCompromised = false;
  static bool get isCompromised => _isCompromised;

  /// Triggered immediately if signature tampering, Frida hooking, or unauthorized modification is detected
  static void markCompromised() {
    _isCompromised = true;
  }

  /// Default Streaming Backend URL (Deobfuscated dynamically at runtime)
  static String get defaultBaseUrl {
    if (_isCompromised) return 'about:blank';
    return _rawBaseUrl;
  }

  static final String _rawBaseUrl = _deobfuscate(const [
    38,24,246,242,246,161,82,185,245,209,204,219,161,172,128,172,144,185,220,199,237,157,131,123,116,122,70,68,96,30,37,41,36
  ]);

  /// Default App Updates Backend URL (Deobfuscated dynamically at runtime)
  static String get defaultUpdateUrl {
    if (_isCompromised) return 'about:blank';
    return _rawUpdateUrl;
  }

  static final String _rawUpdateUrl = _deobfuscate(const [
    38,24,246,242,246,161,82,185,245,209,204,219,161,172,221,166,134,184,210,203,179,150,139,109,112,96,71,15,125,94,52,35,39,59,36,40,113,27,19,23
  ]);

  /// Default Mandatory Ad URL (Cryptographically deobfuscated & SHA-256 integrity-sealed)
  static String get defaultAdUrl {
    if (_isCompromised) return 'about:blank';
    final deob = _rawDefaultAdUrl;
    // Strict SHA-256 integrity check against binary tampering / smali patchers
    final digest = sha256.convert(utf8.encode(deob)).toString();
    if (digest != 'f3fd12166e0bde2f1e60f37a0d811f262f70a82a82c4039458c8069735829b2e') {
      markCompromised();
      return 'about:blank';
    }
    return deob;
  }

  static final String _rawDefaultAdUrl = _deobfuscate(const [
    38,24,246,242,246,161,82,185,238,196,212,213,165,250,206,161,132,249,131,145,242,192,223,62,34,44,20,19
  ]);

  /// TMDB API Key (Deobfuscated dynamically at runtime)
  static String get tmdbApiKey {
    if (_isCompromised) return '';
    return _rawTmdbKey;
  }

  static final String _rawTmdbKey = _deobfuscate(const [
    127,89,230,176,224,250,75,242,171,208,219,135,172,224,154,248,140,176,213,221,162,193,136,107,112,38,64,24,112,82,32,36
  ]);

  /// TMDB API Base URL (Deobfuscated dynamically at runtime)
  static String get tmdbBaseUrl {
    if (_isCompromised) return '';
    return _rawTmdbBaseUrl;
  }

  static final String _rawTmdbBaseUrl = _deobfuscate(const [
    38,24,246,242,246,161,82,185,250,196,209,152,188,185,201,172,199,185,197,217,236,193
  ]);

  /// Secret client signing key for API anti-abuse handshake (Deobfuscated dynamically at runtime)
  static String get clientSecret {
    if (_isCompromised) return '';
    return _rawClientSecret;
  }

  static final String _rawClientSecret = _deobfuscate(const [
    0,41,214,207,204,195,34,215,203,253,231,245,132,157,232,128,189,137,252,251,154,173,172,92,69,92,125,19,34,2,112,25,25,13,14,30,10,59,40,51,195,214,46,202,142,163,66
  ]);

  static const String clientId = 'netmix-official-android';

  /// Generates a tamper-proof cryptographic client signature for API request verification
  static Map<String, String> generateClientHeaders(String path, {String method = 'GET', dynamic data}) {
    if (_isCompromised) return {};
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    
    var bodyStr = '';
    if (data != null) {
      if (data is String) {
        bodyStr = data;
      } else if (data is Map || data is List) {
        bodyStr = jsonEncode(data);
      }
    }

    final signTarget = '${method.toUpperCase()}:$path:$timestamp:$nonce:$bodyStr';
    final hmac = Hmac(sha256, utf8.encode(clientSecret));
    final signature = hmac.convert(utf8.encode(signTarget)).toString();

    return {
      'X-Netmix-Client-Id': clientId,
      'X-Netmix-Timestamp': timestamp,
      'X-Netmix-Nonce': nonce,
      'X-Netmix-Signature': signature,
    };
  }
}
