// lib/core/api_security.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'security_vault.dart';

/// Anti-Abuse & API Request Signing Interceptor
class ApiSecurityInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce(16);
    final path = options.path;

    // Body fingerprint
    var bodyStr = '';
    if (options.data != null) {
      if (options.data is String) {
        bodyStr = options.data as String;
      } else if (options.data is Map || options.data is List) {
        bodyStr = jsonEncode(options.data);
      }
    }

    // Sign payload: method + path + timestamp + nonce + bodyStr
    final signTarget = '${options.method}:$path:$timestamp:$nonce:$bodyStr';
    final hmac = Hmac(sha256, utf8.encode(SecurityVault.clientSecret));
    final signature = hmac.convert(utf8.encode(signTarget)).toString();

    options.headers['X-Netmix-Client-Id'] = SecurityVault.clientId;
    options.headers['X-Netmix-Timestamp'] = timestamp;
    options.headers['X-Netmix-Nonce'] = nonce;
    options.headers['X-Netmix-Signature'] = signature;

    super.onRequest(options, handler);
  }

  String _generateNonce(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
