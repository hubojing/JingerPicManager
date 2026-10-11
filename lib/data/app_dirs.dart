import 'dart:io';

import 'package:path/path.dart' as p;

/// Folder (directly under the roaming app data root) that holds the database,
/// settings and the default thumbnail cache.
const String kSupportFolderName = 'jingerpicmanager';

/// Resolves the directory where the app keeps its local data.
///
/// The app targets Windows only, so the location is derived from the standard
/// Windows environment variables instead of pulling in a platform plugin:
/// this keeps the native build free of plugin registration (a missing plugin
/// registration makes the app crash on startup before any window shows).
///
/// [environment] and [folderName] are injectable so the resolution can be unit
/// tested without touching the real file system.
Directory resolveSupportDirectory({
  Map<String, String>? environment,
  String? folderName,
}) {
  final env = environment ?? Platform.environment;
  final name = folderName ?? kSupportFolderName;
  return Directory(p.join(_baseDirectory(env), name));
}

/// Picks the per-user data root, falling back to safer locations when the
/// usual variables are missing.
String _baseDirectory(Map<String, String> env) {
  final candidates = <String?>[
    _nonEmpty(env['APPDATA']),
    _nonEmpty(env['LOCALAPPDATA']),
    _profileRoaming(env['USERPROFILE']),
  ];
  for (final candidate in candidates) {
    if (candidate != null) return candidate;
  }
  return Directory.systemTemp.path;
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _profileRoaming(String? profile) {
  final trimmed = _nonEmpty(profile);
  if (trimmed == null) return null;
  return p.join(trimmed, 'AppData', 'Roaming');
}
