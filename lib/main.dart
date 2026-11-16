import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'core/api_client.dart';
import 'core/constants.dart';
import 'core/router.dart';
import 'services/app_update_service.dart';
import 'services/security_service.dart';
import 'widgets/offline_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Liquid Glass shaders safely (non-blocking on legacy/32-bit devices)
  try {
    await LiquidGlassWidgets.initialize().timeout(const Duration(milliseconds: 1200));
  } catch (_) {}

  // Initialise media_kit for native video playback
  try {
    MediaKit.ensureInitialized();
  } catch (_) {}

  // Initialise flutter_downloader with SSL resilience for media mirrors
  try {
    await FlutterDownloader.initialize(debug: false, ignoreSsl: true).timeout(const Duration(milliseconds: 1200));
  } catch (_) {}

  // Configure API client (reads saved base URL from SharedPreferences)
  try {
    await ApiClient.instance.init().timeout(const Duration(milliseconds: 1000));
  } catch (_) {}

  // Allow portrait + landscape (player handles rotation)
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } catch (_) {}

  // Memory optimization for low-end devices: cap raster image cache
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20; // 40MB max image RAM cache

  // Run security & anti-tampering verification on startup
  try {
    await SecurityService.instance.runSecurityCheck().timeout(const Duration(milliseconds: 1200));
  } catch (_) {}

  // Initialize app update service and detect installed version
  try {
    await AppUpdateService.instance.init().timeout(const Duration(milliseconds: 1200));
  } catch (_) {}

  // Edge-to-edge, dark status bar & transparent navigation bar so liquid glass floats above system bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      respectSystemAccessibility: true,
      child: const ProviderScope(child: NetmixApp()),
      brightnessResolver: Theme.maybeBrightnessOf,
    ),
  );
}

class NetmixApp extends StatelessWidget {
  const NetmixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Netmix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          error: AppColors.error,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accent.withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              );
            }
            return const TextStyle(
              color: AppColors.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.accent, size: 24);
            }
            return const IconThemeData(color: AppColors.onSurfaceMuted, size: 24);
          }),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceVariant,
          contentTextStyle: const TextStyle(color: AppColors.onSurface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          modalBackgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: AppTextStyles.shelfTitle,
        ),
        tabBarTheme: const TabBarThemeData(
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.onSurfaceMuted,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      routerConfig: appRouter,
      builder: (context, child) {
        return OfflineOverlay(
          child: DefaultTextStyle(
            style: GoogleFonts.inter(
              decoration: TextDecoration.none,
              color: Colors.white,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
