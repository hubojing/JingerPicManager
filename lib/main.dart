import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/database.dart';
import 'data/settings_store.dart';
import 'data/thumbnail_cache.dart';
import 'screens/app_shell.dart';
import 'state/library_provider.dart';

// --- Modern, compact, dark-first visual language -------------------------

const _kDarkBg = Color(0xFF0E0E11);
const _kDarkSurface = Color(0xFF17171B);
const _kDarkPanel = Color(0xFF121216);
const _kDarkElevated = Color(0xFF202026);
const _kAccent = Color(0xFF7C9CFF);
const _kAccentLight = Color(0xFF3B6EF6);

final _darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  visualDensity: VisualDensity.compact,
  scaffoldBackgroundColor: _kDarkBg,
  colorScheme: const ColorScheme.dark(
    brightness: Brightness.dark,
    primary: _kAccent,
    onPrimary: Color(0xFF0B1020),
    surface: _kDarkSurface,
    onSurface: Color(0xFFECECF2),
    onSurfaceVariant: Color(0xFF9A9AA8),
    outline: Color(0xFF2C2C34),
  ),
  cardTheme: CardTheme(
    color: _kDarkSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    centerTitle: false,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF23232A),
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _kDarkElevated,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: _kDarkElevated,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

final _lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  visualDensity: VisualDensity.compact,
  scaffoldBackgroundColor: const Color(0xFFF5F5F8),
  colorScheme: const ColorScheme.light(
    brightness: Brightness.light,
    primary: _kAccentLight,
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1B1B20),
    onSurfaceVariant: Color(0xFF5A5A66),
    outline: Color(0xFFDCDCE2),
  ),
  cardTheme: CardTheme(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFE6E6EC)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    centerTitle: false,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFFE6E6EC),
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFEDEDF2),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop platforms use the FFI SQLite implementation.
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Preferences must be loaded before anything resolves paths from them.
  await SettingsStore.instance.load();
  await AppDatabase.instance.init();
  await ThumbnailCache.instance.warm();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LibraryProvider()..loadAll(),
      child: Consumer<LibraryProvider>(
        builder: (context, provider, _) {
          return MaterialApp(
            title: 'JingerPicManager',
            debugShowCheckedModeBanner: false,
            themeMode: provider.themeMode,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
