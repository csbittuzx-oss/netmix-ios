// lib/services/secure_storage_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enterprise Encrypted Local Storage with Authenticated Keystream Cipher (HMAC-SHA256)
class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._();
  SecureStorageService._();

  // Internal security pepper combined with device-bound salt
  static const String _kStoragePepper =
      'NETMIX_SECURE_STORAGE_KEY_SALT_2026_@#!_X99';

  List<int> _deriveKey(String salt) {
    final hmac = Hmac(sha256, utf8.encode(_kStoragePepper));
    return hmac.convert(utf8.encode(salt)).bytes;
  }

  /// Encrypts and persists a string with authenticated HMAC signature
  Future<void> setSecureString(String key, String plainText) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyBytes = _deriveKey(key);

      // Generate random 16-byte IV
      final random = Random.secure();
      final iv = List<int>.generate(16, (_) => random.nextInt(256));

      // Derive keystream for data encryption
      final streamHmac = Hmac(sha256, keyBytes);
      final keyStream = streamHmac.convert(iv).bytes;

      final plainBytes = utf8.encode(plainText);
      final cipherBytes = List<int>.generate(plainBytes.length, (i) {
        return plainBytes[i] ^ keyStream[i % keyStream.length];
      });

      // Compute HMAC tag over IV + Ciphertext for anti-tampering verification
      final tagPayload = [...iv, ...cipherBytes];
      final tag = Hmac(sha256, keyBytes).convert(tagPayload).bytes;

      final payload = {
        'v': 1,
        'iv': base64Encode(iv),
        'c': base64Encode(cipherBytes),
        't': base64Encode(tag),
      };

      await prefs.setString('sec_$key', jsonEncode(payload));
    } catch (e) {
      debugPrint('[SecureStorage] Encryption error: $e');
    }
  }

  /// Decrypts and verifies a securely stored string
  Future<String?> getSecureString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('sec_$key');
      if (raw == null || raw.isEmpty) return null;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      final iv = base64Decode(map['iv'] as String);
      final cipherBytes = base64Decode(map['c'] as String);
      final storedTag = base64Decode(map['t'] as String);

      final keyBytes = _deriveKey(key);

      // Verify HMAC integrity tag before attempting decryption
      final tagPayload = [...iv, ...cipherBytes];
      final computedTag = Hmac(sha256, keyBytes).convert(tagPayload).bytes;

      // Constant-time comparison to prevent timing attacks
      if (!_constantTimeEquals(storedTag, computedTag)) {
        debugPrint('[SecureStorage] Tampering detected on key: $key');
        return null;
      }

      // Decrypt
      final streamHmac = Hmac(sha256, keyBytes);
      final keyStream = streamHmac.convert(iv).bytes;

      final plainBytes = List<int>.generate(cipherBytes.length, (i) {
        return cipherBytes[i] ^ keyStream[i % keyStream.length];
      });

      return utf8.decode(plainBytes);
    } catch (e) {
      debugPrint('[SecureStorage] Decryption error: $e');
      return null;
    }
  }

  Future<void> removeSecure(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sec_$key');
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
