// lib/providers/streams_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/stream_info.dart';

class StreamsState {
  final List<StreamInfo> streams;
  final bool isLoading;
  final String? error;

  const StreamsState({
    this.streams = const [],
    this.isLoading = false,
    this.error,
  });

  StreamsState copyWith({
    List<StreamInfo>? streams,
    bool? isLoading,
    String? error,
  }) =>
      StreamsState(
        streams: streams ?? this.streams,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class StreamsKey {
  final String id;
  final String permalink;
  final bool isSeries;
  final int season;
  final int episode;

  const StreamsKey({
    required this.id,
    required this.permalink,
    required this.isSeries,
    required this.season,
    required this.episode,
  });

  @override
  bool operator ==(Object other) =>
      other is StreamsKey &&
      id == other.id &&
      permalink == other.permalink &&
      isSeries == other.isSeries &&
      season == other.season &&
      episode == other.episode;

  @override
  int get hashCode =>
      Object.hash(id, permalink, isSeries, season, episode);
}

class StreamsNotifier extends StateNotifier<StreamsState> {
  StreamsNotifier() : super(const StreamsState());

  Future<void> load({
    required String id,
    required String permalink,
    required bool isSeries,
    required int season,
    required int episode,
    String? title,
  }) async {
    state = const StreamsState(isLoading: true);
    try {
      final json = await ApiClient.instance.getStreams(
        id: id,
        permalink: permalink,
        isSeries: isSeries,
        season: season,
        episode: episode,
        title: title,
      );
      final raw = json['streams'] as List? ?? [];
      final streams = raw
          .map((j) {
            try {
              return StreamInfo.fromJson(j as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<StreamInfo>()
          .toList();

      // Resolve proxy URL base
      final client = ApiClient.instance;
      final resolved = streams.map((s) {
        final fullUrl = client.buildProxyUrl(s.url);
        return StreamInfo(
          url: fullUrl,
          quality: s.quality,
          label: s.label,
          format: s.format,
          size: s.size,
          sizeMb: s.sizeMb,
          audioLanguages: s.audioLanguages,
          audioCodec: s.audioCodec,
          isBrowserCompatibleAudio: s.isBrowserCompatibleAudio,
          isFast: s.isFast,
          rawUrl: s.rawUrl,
          directUrl: s.directUrl,
          cdn: s.cdn,
        );
      }).toList();

      resolved.sort((a, b) {
        final aR2 = a.cdn == 'r2' || a.url.contains('r2.cloudflarestorage.com');
        final bR2 = b.cdn == 'r2' || b.url.contains('r2.cloudflarestorage.com');
        if (aR2 && !bR2) return 1;
        if (!aR2 && bR2) return -1;
        return 0;
      });

      state = StreamsState(streams: resolved);
    } catch (e) {
      state = StreamsState(error: e.toString());
    }
  }
}

final streamsProvider =
    StateNotifierProvider.family<StreamsNotifier, StreamsState, StreamsKey>(
  (ref, key) => StreamsNotifier(),
);
