import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/main_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: AiAAlbumApp()));
}

class AiAAlbumApp extends StatelessWidget {
  const AiAAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AiA Album Professional',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3), 
          brightness: Brightness.dark,
          background: const Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      themeMode: ThemeMode.dark, 
      home: const PhotoBookHome(),
    );
  }
}
