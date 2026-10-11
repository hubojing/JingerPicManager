import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/thumbnail_cache.dart';
import '../models/photo.dart';

/// Recursively scans a folder, builds the photo index, extracts metadata and
/// generates thumbnails. The original files are never modified.
class Importer {
  static const Set<String> _rasterExts = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tif', 'tiff',
  };
  static const Set<String> _heicExts = {'heic', 'heif'};
  static const Set<String> _rawExts = {
    'cr2', 'cr3', 'arw', 'nef', 'raw', 'dng', 'raf', 'orf', 'rw2', 'sr2',
    'pef', 'mrw', 'srw', 'erf', 'kdc', 'dcr',
  };
  static const Set<String> _videoExts = {
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv',
  };

  static bool isMediaFile(String path) {
    final ext = p.extension(path).replaceAll('.', '').toLowerCase();
    return _rasterExts.contains(ext) ||
        _heicExts.contains(ext) ||
        _rawExts.contains(ext) ||
        _videoExts.contains(ext);
  }

  /// Scans [folderPath] and indexes every media file found.
  ///
  /// [onProgress] is called as each file is processed. Returns a summary.
  static Future<ImportResult> importFolder(
    String folderPath, {
    required void Function(int done, int total, String current) onProgress,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      return ImportResult(imported: 0, skipped: 0, total: 0);
    }

    final media = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (isMediaFile(entity.path)) media.add(entity);
    }

    final total = media.length;
    int imported = 0;
    int skipped = 0;

    for (var i = 0; i < media.length; i++) {
      final file = media[i];
      onProgress(i + 1, total, file.path);
      try {
        final photo = await _processFile(file);
        if (photo == null) {
          skipped++;
          continue;
        }
        final id = await AppDatabase.instance.insertPhoto(photo);
        final thumbnail =
            await ThumbnailCache.instance.generate(photo.copyWith(id: id));
        if (thumbnail != null) {
          await AppDatabase.instance.updateThumbnail(id, thumbnail);
        }
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    return ImportResult(imported: imported, skipped: skipped, total: total);
  }

  static Future<Photo?> _processFile(File file) async {
    final stat = await file.stat();
    final ext = p.extension(file.path).replaceAll('.', '').toLowerCase();

    int? width;
    int? height;
    Map<String, dynamic>? exif;
    int orientation = 1;
    DateTime? dateTaken;

    final isRaster = _rasterExts.contains(ext) || _heicExts.contains(ext);
    if (isRaster) {
      try {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
          exif = _extractExif(decoded);
          orientation = _orientationFromExif(exif);
          dateTaken = _dateFromExif(exif) ?? stat.modified;
        }
      } catch (_) {
        // keep null metadata; thumbnail generation will also fall back
      }
    }

    if (dateTaken == null) dateTaken = stat.modified;

    final hash = await _quickHash(file, stat.size);

    return Photo(
      path: file.path,
      directory: p.dirname(file.path),
      filename: p.basename(file.path),
      extension: ext,
      fileSize: stat.size,
      width: width,
      height: height,
      dateTaken: dateTaken,
      dateModified: stat.modified,
      importDate: DateTime.now(),
      orientation: orientation,
      exif: exif,
      hash: hash,
    );
  }

  /// Extract EXIF into a flat, JSON-serialisable map. Best-effort and defensive.
  ///
  /// Keys are "<IFD name>.<tag id>" (e.g. "ifd0.274" for orientation).
  static Map<String, dynamic> _extractExif(img.Image image) {
    final result = <String, dynamic>{};
    try {
      final exif = image.exif;
      for (final ifdName in exif.keys) {
        final ifd = exif[ifdName];
        for (final tagId in ifd.data.keys) {
          final value = ifd.data[tagId];
          if (value == null) continue;
          result['$ifdName.$tagId'] = value.toString().trim();
        }
      }
    } catch (_) {
      // ignore malformed EXIF
    }
    return result;
  }

  static int _orientationFromExif(Map<String, dynamic> exif) {
    // IFD0 orientation tag id = 274 (0x0112)
    for (final key in exif.keys) {
      if (key.toLowerCase().endsWith('.274')) {
        return int.tryParse(exif[key].toString()) ?? 1;
      }
    }
    return 1;
  }

  static DateTime? _dateFromExif(Map<String, dynamic> exif) {
    // DateTimeOriginal (tag 36867) preferred, then DateTime (tag 306)
    for (final suffix in const ['.36867', '.306']) {
      for (final key in exif.keys) {
        if (key.toLowerCase().endsWith(suffix)) {
          final parsed = _parseExifDate(exif[key].toString());
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  static DateTime? _parseExifDate(String raw) {
    try {
      final trimmed = raw.trim();
      final parts = trimmed.split(' ');
      if (parts.length != 2) return null;
      final date = parts[0].split(':');
      final time = parts[1].split(':');
      if (date.length < 3 || time.length < 3) return null;
      return DateTime(
        int.parse(date[0]),
        int.parse(date[1]),
        int.parse(date[2]),
        int.parse(time[0]),
        int.parse(time[1]),
        int.parse(time[2]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Cheap content fingerprint: SHA-256 over the first 1 MB plus the file size.
  /// Good enough to surface exact duplicates without reading the whole file.
  static Future<String> _quickHash(File file, int size) async {
    final bytes = await file.readAsBytes();
    final head = bytes.length > 1024 * 1024
        ? bytes.sublist(0, 1024 * 1024)
        : bytes;
    final digest = sha256.convert([...head, size & 0xFF]);
    return digest.toString();
  }
}

class ImportResult {
  final int imported;
  final int skipped;
  final int total;

  ImportResult({required this.imported, required this.skipped, required this.total});

  @override
  String toString() =>
      'ImportResult(imported: $imported, skipped: $skipped, total: $total)';
}
