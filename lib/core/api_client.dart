// lib/core/api_client.dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_security.dart';
import 'constants.dart';

class ApiClient {
  static ApiClient? _instance;
  late Dio _dio;

  ApiClient._();

  static ApiClient get instance {
    _instance ??= ApiClient._();
    return _instance!;
  }

  /// Call once on startup (or whenever the base URL setting changes).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConstants.prefBaseUrl);
    final isStale = saved == null ||
        saved.contains('netmix-3auk') ||
        saved.contains('netmix-play') ||
        saved.contains('ugotnothing') ||
        !saved.startsWith('http') ||
        !saved.contains('netmix-byoky');
    final baseUrl = isStale ? AppConstants.defaultBaseUrl : saved;
    if (saved != null && isStale) {
      await prefs.setString(AppConstants.prefBaseUrl, AppConstants.defaultBaseUrl);
    }
    _buildDio(baseUrl);
  }

  void _buildDio(String baseUrl) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    _dio = Dio(
      BaseOptions(
        baseUrl: cleanBase,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 35),
        sendTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'Netmix/1.0 (Android; Linux; Mobile)',
        },
      ),
    );

    // Configure IOHttpClientAdapter to prevent stale socket reuse (avoids "Connection reset by peer")
    final adapter = _dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        // Render / cloud reverse proxies drop idle connections after 5-10s.
        // Setting idleTimeout to 4s ensures Dart never reuses a dead socket.
        client.idleTimeout = const Duration(seconds: 4);
        client.connectionTimeout = const Duration(seconds: 15);
        return client;
      };
    }

    _dio.interceptors.addAll([
      ApiSecurityInterceptor(),
      _LogInterceptor(),
      _RetryInterceptor(dio: _dio),
    ]);
  }

  Dio get dio => _dio;
  String get baseUrl => _dio.options.baseUrl;

  /// Hot-reload base URL (from Settings screen).
  Future<void> updateBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefBaseUrl, url);
    _buildDio(url);
  }

  Future<String> currentBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConstants.prefBaseUrl);
    if (saved == null || saved.contains('netmix-3auk') || !saved.startsWith('http')) {
      return AppConstants.defaultBaseUrl;
    }
    return saved;
  }

  // ── Convenience methods ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getHome() async {
    final r = await _dio.get(AppConstants.pathHome);
    return r.data as Map<String, dynamic>;
  }

  bool _isOtt4kItem(String? id, String? permalink) {
    return (id != null && id.startsWith('4kott_')) ||
        (permalink != null && permalink.contains('4khdhub.one'));
  }

  Future<Map<String, dynamic>> getCategory(
      String category, int page, int limit) async {
    final r = await _dio.get(AppConstants.pathCategory, queryParameters: {
      'category': category,
      'page': page,
      'limit': limit,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOttCatalog(
      String category, int page, int limit) async {
    final r = await _dio.get(AppConstants.pathOttCatalog, queryParameters: {
      'category': category,
      'page': page,
      'limit': limit,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> search(String query) async {
    final r = await _dio.get(AppConstants.pathSearch, queryParameters: {'q': query});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDetails(
      {String? id, String? permalink, String? title}) async {
    final endpoint = _isOtt4kItem(id, permalink)
        ? AppConstants.pathOttDetails
        : AppConstants.pathDetails;
    final r = await _dio.get(endpoint, queryParameters: {
      if (id != null) 'id': id,
      if (permalink != null) 'permalink': permalink,
      if (title != null && title.isNotEmpty) 'title': title,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStreams({
    String? id,
    String? permalink,
    bool isSeries = false,
    int season = 1,
    int episode = 1,
    String? title,
  }) async {
    final endpoint = _isOtt4kItem(id, permalink)
        ? AppConstants.pathOttStreams
        : AppConstants.pathStreams;
    final r = await _dio.get(endpoint, queryParameters: {
      if (id != null) 'id': id,
      if (permalink != null) 'permalink': permalink,
      if (title != null && title.isNotEmpty) 'title': title,
      'isSeries': isSeries.toString(),
      'season': season,
      'episode': episode,
    });
    return r.data as Map<String, dynamic>;
  }

  /// Build a full proxy stream URL from the relative proxyUrl token path.
  String buildProxyUrl(String relativeOrAbsolute) {
    if (relativeOrAbsolute.startsWith('http')) return relativeOrAbsolute;
    final base = _dio.options.baseUrl;
    return '$base$relativeOrAbsolute';
  }
}

// ── Interceptors ──────────────────────────────────────────────────────────────

class _LogInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}

class _RetryInterceptor extends Interceptor {
  final Dio dio;
  static const int _maxRetries = 3;

  _RetryInterceptor({required this.dio});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retries = (extra['retries'] as int?) ?? 0;

    final errStr = err.toString().toLowerCase();
    final isConnectionReset = err.error is SocketException ||
        err.error is HttpException ||
        errStr.contains('connection reset') ||
        errStr.contains('software caused connection abort') ||
        errStr.contains('connection closed while receiving data') ||
        errStr.contains('broken pipe') ||
        errStr.contains('connection refused');

    final isTransient = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.unknown ||
        isConnectionReset;

    final isServerError = err.response != null &&
        [500, 502, 503, 504, 429].contains(err.response!.statusCode);

    if (retries < _maxRetries && (isTransient || isServerError)) {
      err.requestOptions.extra['retries'] = retries + 1;
      final backoffMs = 500 * (1 << retries); // 500ms, 1000ms, 2000ms
      if (kDebugMode) {
        debugPrint('[ApiClient] Transient error: ${err.message}. Retrying (${retries + 1}/$_maxRetries) in ${backoffMs}ms...');
      }
      await Future.delayed(Duration(milliseconds: backoffMs));
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        if (e is DioException) {
          onError(e, handler);
          return;
        }
      }
    }
    handler.next(err);
  }
}
