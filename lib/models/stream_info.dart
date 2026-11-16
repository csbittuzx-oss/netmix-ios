// lib/models/stream_info.dart
import 'package:equatable/equatable.dart';
import '../core/api_client.dart';
import '../core/constants.dart';

class StreamInfo extends Equatable {
  final String url;
  final String quality; // '4k' | '1080p' | '720p' | '480p'
  final String label;
  final String format; // 'hls' | 'mp4' | 'mkv' | 'webm'
  final String? size;
  final double? sizeMb;
  final List<String> audioLanguages;
  final String audioCodec;
  final bool isBrowserCompatibleAudio;
  final bool isFast;
  final String? rawUrl;
  final String? directUrl;
  final String? cdn;

  const StreamInfo({
    required this.url,
    required this.quality,
    required this.label,
    required this.format,
    this.size,
    this.sizeMb,
    this.audioLanguages = const ['Original Audio'],
    this.audioCodec = 'aac',
    this.isBrowserCompatibleAudio = true,
    this.isFast = false,
    this.rawUrl,
    this.directUrl,
    this.cdn,
  });

  String get fullUrl => url;

  /// High-speed direct playback URL for native mobile players (libmpv).
  /// Connects directly to high-speed CDNs (Google CDN, R2, Pixeldrain) with zero reverse-proxy overhead.
  /// For protected / anti-hotlink servers (e.g. ravok.buzz, abyssplayer),
  /// ALWAYS route through the verified authenticated backend proxy (url) to prevent 403 Forbidden errors.
  String get playUrl {
    final candidate = directUrl ?? rawUrl;
    if (candidate != null && candidate.trim().isNotEmpty) {
      final lower = candidate.toLowerCase();
      final isProtectedHost = lower.contains('ravok.buzz') ||
          lower.contains('abyssplayer') ||
          lower.contains('megacloud') ||
          lower.contains('rapid-cloud') ||
          lower.contains('fireplayer');
      if (isProtectedHost) {
        return url;
      }
      if ((candidate.startsWith('http://') || candidate.startsWith('https://')) &&
          !candidate.contains('localhost') &&
          !candidate.contains('/api/proxy-stream')) {
        return candidate.trim();
      }
    }
    return url;
  }

  bool get isHls =>
      format.toLowerCase() == 'hls' ||
      url.contains('.m3u8') ||
      url.contains('/hls/') ||
      (rawUrl?.contains('.m3u8') ?? false) ||
      (rawUrl?.contains('/hls/') ?? false);

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    List<String> parseStrList(dynamic v) {
      if (v == null) return ['Original Audio'];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return [v];
      return ['Original Audio'];
    }

    String resolveFullUrl(dynamic val) {
      if (val == null) return '';
      final str = val.toString().trim();
      if (str.isEmpty) return '';
      if (str.startsWith('http://') || str.startsWith('https://')) return str;
      String activeBase = AppConstants.defaultBaseUrl;
      try {
        final current = ApiClient.instance.baseUrl;
        if (current.isNotEmpty) activeBase = current;
      } catch (_) {}
      final base = activeBase.replaceAll(RegExp(r'/+$'), '');
      if (str.startsWith('/')) return '$base$str';
      return '$base/$str';
    }

    final fullUrlRaw = json['fullUrl']?.toString();
    final String resolvedUrl;
    if (fullUrlRaw != null &&
        fullUrlRaw.trim().isNotEmpty &&
        (fullUrlRaw.startsWith('http://') || fullUrlRaw.startsWith('https://'))) {
      resolvedUrl = fullUrlRaw.trim();
    } else {
      final raw = json['url']?.toString() ?? json['proxyUrl']?.toString() ?? '';
      resolvedUrl = resolveFullUrl(raw);
    }

    final String? directUrlRaw = (json['directUrl'] ?? json['rawUrl'])?.toString().trim();
    final String? directUrl = (directUrlRaw != null && directUrlRaw.startsWith('http')) ? directUrlRaw : null;

    final detectedFormat = json['format']?.toString() ??
        ((resolvedUrl.contains('.m3u8') || resolvedUrl.contains('/hls/'))
            ? 'hls'
            : 'mp4');

    return StreamInfo(
      url: resolvedUrl,
      quality: json['quality']?.toString() ?? '720p',
      label: json['label']?.toString() ?? json['quality']?.toString() ?? '720p',
      format: detectedFormat,
      size: json['size']?.toString(),
      sizeMb: (json['sizeMb'] as num?)?.toDouble(),
      audioLanguages: parseStrList(json['audioLanguages']),
      audioCodec: json['audioCodec']?.toString() ?? 'aac',
      isBrowserCompatibleAudio: json['isBrowserCompatibleAudio'] != false,
      isFast: json['isFast'] == true,
      rawUrl: json['rawUrl']?.toString() ?? resolvedUrl,
      directUrl: directUrl,
      cdn: json['cdn']?.toString(),
    );
  }

  @override
  List<Object?> get props => [url, quality, cdn, directUrl];
}
