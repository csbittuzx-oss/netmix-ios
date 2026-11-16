// lib/utils/track_language_helper.dart

class TrackLanguageHelper {
  TrackLanguageHelper._();

  static const Map<String, String> _codeToName = {
    'hi': 'Hindi',
    'hin': 'Hindi',
    'en': 'English',
    'eng': 'English',
    'ta': 'Tamil',
    'tam': 'Tamil',
    'te': 'Telugu',
    'tel': 'Telugu',
    'ml': 'Malayalam',
    'mal': 'Malayalam',
    'kn': 'Kannada',
    'kan': 'Kannada',
    'bn': 'Bengali',
    'ben': 'Bengali',
    'mr': 'Marathi',
    'mar': 'Marathi',
    'gu': 'Gujarati',
    'guj': 'Gujarati',
    'pa': 'Punjabi',
    'pan': 'Punjabi',
    'ur': 'Urdu',
    'urd': 'Urdu',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'zh': 'Chinese',
    'zho': 'Chinese',
    'chi': 'Chinese',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fra': 'French',
    'fre': 'French',
    'de': 'German',
    'deu': 'German',
    'ger': 'German',
    'it': 'Italian',
    'ita': 'Italian',
    'ru': 'Russian',
    'rus': 'Russian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'th': 'Thai',
    'tha': 'Thai',
    'vi': 'Vietnamese',
    'vie': 'Vietnamese',
    'id': 'Indonesian',
    'ind': 'Indonesian',
    'tr': 'Turkish',
    'tur': 'Turkish',
    'fa': 'Persian',
    'fas': 'Persian',
    'per': 'Persian',
  };

  static final List<String> _knownLanguages = [
    'Hindi',
    'English',
    'Tamil',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Bengali',
    'Marathi',
    'Gujarati',
    'Punjabi',
    'Urdu',
    'Japanese',
    'Korean',
    'Chinese',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Russian',
    'Portuguese',
    'Arabic',
    'Thai',
    'Vietnamese',
    'Indonesian',
    'Turkish',
  ];

  /// Detects if a string is a spam website / domain name / provider watermark
  static bool isSpamProvider(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.contains('.ms') ||
        lower.contains('.lat') ||
        lower.contains('.com') ||
        lower.contains('.org') ||
        lower.contains('.net') ||
        lower.contains('.in') ||
        lower.contains('.me') ||
        lower.contains('.cc') ||
        lower.contains('.to') ||
        lower.contains('hdhub4u') ||
        lower.contains('hdhub') ||
        lower.contains('vegamovies') ||
        lower.contains('1xbet') ||
        lower.contains('tamilrockers') ||
        lower.contains('moviesmod') ||
        lower.contains('bolly4u') ||
        lower.contains('netmix') ||
        lower.contains('worldfree4u') ||
        lower.contains('filmyzilla')) {
      return true;
    }
    return false;
  }

  /// Normalizes an audio track into a clear, clean human-readable language name.
  static String normalizeAudioTrackName({
    required String? rawTitle,
    required String? rawLang,
    required int index,
    List<String>? streamAudioLanguages,
    dynamic channels,
  }) {
    String? detectedLang;

    // 1. Check ISO language code
    if (rawLang != null && rawLang.trim().isNotEmpty) {
      final code = rawLang.trim().toLowerCase();
      if (_codeToName.containsKey(code)) {
        detectedLang = _codeToName[code];
      }
    }

    // 2. If not detected or is 'und', scan rawTitle for known language words
    if (detectedLang == null && rawTitle != null && rawTitle.trim().isNotEmpty) {
      final t = rawTitle.trim();
      for (final lang in _knownLanguages) {
        final regex = RegExp('\\b$lang\\b', caseSensitive: false);
        if (regex.hasMatch(t)) {
          detectedLang = lang;
          break;
        }
      }
    }

    // 3. Fallback to stream-level audioLanguages list (from Netmix backend)
    if (detectedLang == null &&
        streamAudioLanguages != null &&
        streamAudioLanguages.isNotEmpty) {
      if (index < streamAudioLanguages.length) {
        final candidate = streamAudioLanguages[index].trim();
        if (candidate.isNotEmpty && !isSpamProvider(candidate)) {
          detectedLang = candidate;
        }
      }
    }

    // 4. Default fallback if still unknown
    if (detectedLang == null) {
      // If rawTitle was provided and is not a spam provider, use cleaned rawTitle
      if (rawTitle != null &&
          rawTitle.trim().isNotEmpty &&
          !isSpamProvider(rawTitle) &&
          rawTitle.toLowerCase() != 'audio') {
        detectedLang = rawTitle.trim();
      } else {
        detectedLang = 'Audio Track ${index + 1}';
      }
    }

    // 5. Append clean audio characteristics (e.g. 5.1 Surround, Stereo) if available
    String suffix = '';
    final titleLower = (rawTitle ?? '').toLowerCase();
    final chStr = (channels ?? '').toString();
    if (chStr == '6' || chStr.contains('5.1') || titleLower.contains('5.1')) {
      suffix = ' (5.1 Surround)';
    } else if (chStr == '8' || chStr.contains('7.1') || titleLower.contains('7.1')) {
      suffix = ' (7.1 Surround)';
    } else if (titleLower.contains('commentary')) {
      suffix = ' (Commentary)';
    }

    return '$detectedLang$suffix';
  }

  /// Normalizes subtitle track into a clear human-readable language name.
  static String normalizeSubtitleTrackName({
    required String? rawTitle,
    required String? rawLang,
    required int index,
  }) {
    String? detectedLang;

    if (rawLang != null && rawLang.trim().isNotEmpty) {
      final code = rawLang.trim().toLowerCase();
      if (_codeToName.containsKey(code)) {
        detectedLang = _codeToName[code];
      }
    }

    if (detectedLang == null && rawTitle != null && rawTitle.trim().isNotEmpty) {
      final t = rawTitle.trim();
      for (final lang in _knownLanguages) {
        final regex = RegExp('\\b$lang\\b', caseSensitive: false);
        if (regex.hasMatch(t)) {
          detectedLang = lang;
          break;
        }
      }
    }

    if (detectedLang == null) {
      if (rawTitle != null &&
          rawTitle.trim().isNotEmpty &&
          !isSpamProvider(rawTitle) &&
          rawTitle.toLowerCase() != 'subtitle') {
        detectedLang = rawTitle.trim();
      } else {
        detectedLang = 'Subtitle ${index + 1}';
      }
    }

    final titleLower = (rawTitle ?? '').toLowerCase();
    if (titleLower.contains('sdh') || titleLower.contains('cc')) {
      return '$detectedLang [CC]';
    } else if (titleLower.contains('forced')) {
      return '$detectedLang (Forced)';
    }

    return detectedLang;
  }

  /// Resolves duplicates by appending distinct index labels (e.g. Hindi (Track 1), Hindi (Track 2))
  static List<String> deduplicateLabels(List<String> labels) {
    final counts = <String, int>{};
    for (final l in labels) {
      counts[l] = (counts[l] ?? 0) + 1;
    }

    final indexMap = <String, int>{};
    final result = <String>[];
    for (final l in labels) {
      if ((counts[l] ?? 0) > 1) {
        final currentIdx = (indexMap[l] ?? 0) + 1;
        indexMap[l] = currentIdx;
        result.add('$l (Track $currentIdx)');
      } else {
        result.add(l);
      }
    }
    return result;
  }
}
