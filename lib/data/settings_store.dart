import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_dirs.dart';

/// Ordering options offered in the library toolbar.
enum SortMode {
  dateNewest('date_desc', 'COALESCE(date_taken, date_modified) DESC', '拍摄时间（新→旧）'),
  dateOldest('date_asc', 'COALESCE(date_taken, date_modified) ASC', '拍摄时间（旧→新）'),
  nameAsc('name_asc', 'filename COLLATE NOCASE ASC', '文件名（A→Z）'),
  importNewest('import_desc', 'import_date DESC', '导入时间（新→旧）');

  const SortMode(this.key, this.sql, this.label);

  /// Stable identifier persisted to settings (never the SQL text itself).
  final String key;

  /// A valid SQL `ORDER BY` expression (used verbatim by the query layer).
  final String sql;
  final String label;

  static SortMode fromKey(String? key) {
    for (final m in SortMode.values) {
      if (m.key == key) return m;
    }
    return SortMode.dateNewest;
  }
}

/// Persisted user preferences. Stored as a small JSON file next to the
/// application support directory so no extra plugin dependency is needed.
class SettingsStore {
  static final SettingsStore instance = SettingsStore._();
  SettingsStore._();

  String? _thumbnailCacheDir;
  SortMode _sortMode = SortMode.dateNewest;
  bool _groupByDate = true;

  /// User-chosen thumbnail cache directory; null means "use the default".
  String? get thumbnailCacheDir => _thumbnailCacheDir;
  SortMode get sortMode => _sortMode;
  bool get groupByDate => _groupByDate;

  Future<File> get _file async {
    final support = resolveSupportDirectory();
    return File(p.join(support.path, 'settings.json'));
  }

  /// Load persisted settings. Safe to call repeatedly; failures keep defaults.
  Future<void> load() async {
    try {
      final f = await _file;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      _thumbnailCacheDir = decoded['thumbnailCacheDir'] as String?;
      _sortMode = SortMode.fromKey(decoded['sortMode'] as String?);
      _groupByDate = (decoded['groupByDate'] as bool?) ?? true;
    } catch (_) {
      // Corrupt or unreadable settings simply fall back to defaults.
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'thumbnailCacheDir': _thumbnailCacheDir,
        'sortMode': _sortMode.key,
        'groupByDate': _groupByDate,
      }));
    } catch (_) {
      // Persisting preferences is best-effort.
    }
  }

  Future<void> setThumbnailCacheDir(String? dir) async {
    _thumbnailCacheDir = (dir == null || dir.trim().isEmpty) ? null : dir.trim();
    await _save();
  }

  Future<void> setSortMode(SortMode mode) async {
    _sortMode = mode;
    await _save();
  }

  Future<void> setGroupByDate(bool value) async {
    _groupByDate = value;
    await _save();
  }
}
