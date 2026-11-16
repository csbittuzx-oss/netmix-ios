// lib/core/constants.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'security_vault.dart';

class AppConstants {
  // ── API ───────────────────────────────────────────────────────────────────
  static final String defaultBaseUrl = SecurityVault.defaultBaseUrl;

  // Shared-prefs key that lets users override the base URL from Settings.
  static const String prefBaseUrl = 'setting_base_url';

  // ── API paths ─────────────────────────────────────────────────────────────
  static const String pathHome = '/api/home';
  static const String pathCategory = '/api/category';
  static const String pathSearch = '/api/search';
  static const String pathDetails = '/api/details';
  static const String pathStreams = '/api/streams';
  static const String pathOttCatalog = '/api/ott/catalog';
  static const String pathOttDetails = '/api/ott/details';
  static const String pathOttStreams = '/api/ott/streams';
  static const String pathProxy = '/api/proxy-stream';
  static const String pathPing = '/api/ping';

  // ── Cache ─────────────────────────────────────────────────────────────────
  static const Duration homeCacheDuration = Duration(minutes: 5);

  // ── Shared-Prefs Keys ─────────────────────────────────────────────────────
  static const String prefQuality = 'setting_quality';
  static const String prefAudioLang = 'setting_audio_lang';
  static const String prefWatchProgress = 'watch_progress_'; // + itemId
  static const String prefDownloads = 'downloads_list';
  static const String prefAutoPlayNextEpisode = 'setting_autoplay_next_episode';

  // ── Playback ──────────────────────────────────────────────────────────────
  static const List<double> playbackSpeeds = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];
  static const Duration autoHideControlsDuration = Duration(milliseconds: 2800);
  static const Duration saveProgressInterval = Duration(seconds: 3);
  static const Duration doubleTapSeekDuration = Duration(seconds: 10);

  // ── Hero banner ───────────────────────────────────────────────────────────
  static const Duration heroCycleDuration = Duration(seconds: 6);

  // ── Search debounce ───────────────────────────────────────────────────────
  static const Duration searchDebounce = Duration(milliseconds: 300);
}

// ── Colour palette ────────────────────────────────────────────────────────────
class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF111118);
  static const Color surfaceVariant = Color(0xFF1A1A24);
  static const Color accent = Color(0xFFE50914);
  static const Color accentDark = Color(0xFFB0070F);
  static const Color onSurface = Color(0xFFE8E8F0);
  static const Color onSurfaceMuted = Color(0xFF8888AA);
  static const Color shimmerBase = Color(0xFF1C1C28);
  static const Color shimmerHighlight = Color(0xFF2A2A3A);
  static const Color badge = Color(0xFF252535);
  static const Color divider = Color(0xFF222232);
  static const Color overlay = Color(0xCC000000);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
}

// ── Text styles ───────────────────────────────────────────────────────────────
class AppTextStyles {
  static TextStyle get heroTitle => GoogleFonts.inter(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    letterSpacing: -0.3,
    decoration: TextDecoration.none,
  );
  static TextStyle get shelfTitle => GoogleFonts.inter(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
    letterSpacing: -0.2,
    decoration: TextDecoration.none,
  );
  static TextStyle get cardTitle => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurface,
    decoration: TextDecoration.none,
  );
  static TextStyle get badge => GoogleFonts.inter(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    decoration: TextDecoration.none,
  );
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14,
    color: AppColors.onSurfaceMuted,
    height: 1.5,
    decoration: TextDecoration.none,
  );
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    color: AppColors.onSurfaceMuted,
    decoration: TextDecoration.none,
  );
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
    decoration: TextDecoration.none,
  );
}
