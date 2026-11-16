// lib/models/download_item.dart
import 'package:equatable/equatable.dart';

enum DownloadStatus { queued, downloading, paused, done, failed, cancelled }

class DownloadItem extends Equatable {
  final String id; // unique task id from flutter_downloader
  final String itemId; // catalog item id
  final String title;
  final String? poster;
  final String quality;
  final String? filePath;
  final int? totalBytes;
  final int? downloadedBytes;
  final int progressPercent;
  final DownloadStatus status;
  final String contentType; // 'movie' | 'series' | 'anime'
  final int? seasonNumber;
  final int? episodeNumber;
  final DateTime addedAt;
  final DateTime? completedAt;
  final String? speedText;
  final String? etaText;
  final String? downloadUrl;

  const DownloadItem({
    required this.id,
    required this.itemId,
    required this.title,
    this.poster,
    required this.quality,
    this.filePath,
    this.totalBytes,
    this.downloadedBytes,
    this.progressPercent = 0,
    this.status = DownloadStatus.queued,
    this.contentType = 'movie',
    this.seasonNumber,
    this.episodeNumber,
    required this.addedAt,
    this.completedAt,
    this.speedText,
    this.etaText,
    this.downloadUrl,
  });

  double get progress {
    if (progressPercent > 0) {
      return (progressPercent / 100.0).clamp(0.0, 1.0);
    }
    if (totalBytes != null && totalBytes! > 0 && downloadedBytes != null) {
      return (downloadedBytes! / totalBytes!).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  String get displayProgress {
    if (progressPercent > 0) {
      return '$progressPercent%';
    }
    if (totalBytes != null && totalBytes! > 0 && downloadedBytes != null && downloadedBytes! > 0) {
      final pct = ((downloadedBytes! / totalBytes!) * 100).round();
      return '$pct%';
    }
    return '0%';
  }

  String get displaySize {
    if (totalBytes == null || totalBytes == 0) {
      if (downloadedBytes != null && downloadedBytes! > 0) {
        final mb = downloadedBytes! / (1024 * 1024);
        return '${mb.toStringAsFixed(0)} MB';
      }
      return '';
    }
    final mb = totalBytes! / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get displayDownloaded {
    if (downloadedBytes == null || downloadedBytes == 0) return '0 MB';
    final mb = downloadedBytes! / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get displayTotal {
    if (totalBytes == null || totalBytes == 0) {
      return displaySize.isNotEmpty ? displaySize : '1.2 GB';
    }
    final mb = totalBytes! / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get statusLabel {
    switch (status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.done:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }

  DownloadItem copyWith({
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    int? progressPercent,
    DownloadStatus? status,
    DateTime? completedAt,
    String? speedText,
    String? etaText,
    String? downloadUrl,
  }) {
    return DownloadItem(
      id: id,
      itemId: itemId,
      title: title,
      poster: poster,
      quality: quality,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progressPercent: progressPercent ?? this.progressPercent,
      status: status ?? this.status,
      contentType: contentType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      addedAt: addedAt,
      completedAt: completedAt ?? this.completedAt,
      speedText: speedText ?? this.speedText,
      etaText: etaText ?? this.etaText,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'title': title,
        'poster': poster,
        'quality': quality,
        'filePath': filePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'progressPercent': progressPercent,
        'status': status.index,
        'contentType': contentType,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'downloadUrl': downloadUrl,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id']?.toString() ?? '',
        itemId: json['itemId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        poster: json['poster']?.toString(),
        quality: json['quality']?.toString() ?? '720p',
        filePath: json['filePath']?.toString(),
        totalBytes: json['totalBytes'] as int?,
        downloadedBytes: json['downloadedBytes'] as int?,
        progressPercent: (json['progressPercent'] as int?) ?? 0,
        status: DownloadStatus
            .values[(json['status'] as int?) ?? DownloadStatus.queued.index],
        contentType: json['contentType']?.toString() ?? 'movie',
        seasonNumber: json['seasonNumber'] as int?,
        episodeNumber: json['episodeNumber'] as int?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['addedAt'] as int?) ?? 0),
        completedAt: json['completedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int)
            : null,
        downloadUrl: json['downloadUrl']?.toString(),
      );

  @override
  List<Object?> get props => [id];
}
