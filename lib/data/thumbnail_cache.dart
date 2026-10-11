import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/photo.dart';
import 'app_dirs.dart';
import 'settings_store.dart';

/// Formats the pure-Dart `image` package can actually decode into a raster.
const Set<String> _decodableExts = {
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tif', 'tiff',
};

/// Generates and caches thumbnail images on disk.
///
/// Supported raster formats (jpg/png/webp/gif/bmp/tiff) get a real downscaled
/// JPEG. Formats the pure-Dart `image` package cannot decode (RAW / HEIC /
/// video) are left without a rendered thumbnail; the UI shows a placeholder for
/// those. Native decoders for those formats are a later-phase enhancement.
class ThumbnailCache {
  static final ThumbnailCache instance = ThumbnailCache._();
  ThumbnailCache._();

  Directory? _dir;

  /// Forget the resolved directory so it is re-derived from settings.
  void invalidate() => _dir = null;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final custom = SettingsStore.instance.thumbnailCacheDir;
    if (custom != null && custom.isNotEmpty) {
      _dir = Directory(custom);
    } else {
      final support = resolveSupportDirectory();
      _dir = Directory(p.join(support.path, 'thumbnails'));
    }
    await _dir!.create(recursive: true);
    return _dir!;
  }

  /// Pre-create the cache directory.
  Future<void> warm() async {
    await dir;
  }

  /// Path the thumbnail for [photo] would live at (does not guarantee it exists).
  Future<String> pathFor(Photo photo) async {
    final d = await dir;
    return p.join(d.path, '${photo.id}.jpg');
  }

  /// Generate (or reuse) the thumbnail for a photo. Returns the file path, or
  /// null when the source cannot be decoded into a raster thumbnail.
  Future<String?> generate(Photo photo) async {
    if (photo.id == null) return null;
    // Skip formats the pure-Dart decoder cannot handle without reading the file.
    if (!_decodableExts.contains(photo.extension.toLowerCase())) return null;
    final targetPath = await pathFor(photo);
    final target = File(targetPath);
    if (await target.exists()) return targetPath;

    final source = File(photo.path);
    if (!await source.exists()) return null;

    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null; // unsupported container

      final thumbnail = img.copyResize(decoded, width: 320);
      await target.writeAsBytes(img.encodeJpg(thumbnail, quality: 82));
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  /// Remove a single cached thumbnail (e.g. when its photo is deleted).
  Future<void> remove(int photoId) async {
    final d = await dir;
    final file = File(p.join(d.path, '$photoId.jpg'));
    if (await file.exists()) await file.delete();
  }

  /// Delete every cached thumbnail.
  Future<void> clear() async {
    final d = await dir;
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
    await warm();
  }
}
