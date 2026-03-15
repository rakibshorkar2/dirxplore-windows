import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'dart:io';

import 'providers/app_settings_provider.dart';
import 'providers/download_provider.dart';
import 'providers/proxy_provider.dart';
import 'providers/theme_provider.dart';
import 'services/native_bridge.dart';
import 'core/database/db_helper.dart';
import 'ui/shell/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Native Engine
  await NativeBridge().init();
  
  // Media Kit init
  MediaKit.ensureInitialized();
  
  // Database init
  await DatabaseHelper().database;
  
  // Window Manager init for Windows
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(WindowOptions(
      size: const Size(1024, 768),
      minimumSize: const Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    ), () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppProxyProvider()..loadProxy()),
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()..loadTasks()),
      ],
      child: const DirXploreApp(),
    ),
  );
}

class DirXploreApp extends StatelessWidget {
  const DirXploreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        
        // Define base background configurations
        Color lightScaffold = themeProvider.isGlassyUi ? Colors.white.withValues(alpha: 0.85) : Colors.white;
        Color darkScaffold = themeProvider.isGlassyUi ? Colors.black.withValues(alpha: 0.85) : Colors.black;

        return MaterialApp(
          title: 'DirXplore',
          debugShowCheckedModeBanner: false,
          theme: FlexThemeData.light(scheme: FlexScheme.deepBlue, useMaterial3: true).copyWith(
            scaffoldBackgroundColor: lightScaffold,
          ),
          darkTheme: FlexThemeData.dark(scheme: FlexScheme.deepBlue, useMaterial3: true).copyWith(
            scaffoldBackgroundColor: darkScaffold,
          ),
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const MainShell(),
        );
      },
    );
  }
}
