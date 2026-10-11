import 'dart:convert';

/// A single indexed media file (photo / raw / video) in the library.
///
/// The original file is never moved or modified; this record only stores an
/// index plus a generated thumbnail path and extracted metadata.
class Photo {
  final int? id;
  final String path;
  final String directory;
  final String filename;
  final String extension;
  final int fileSize;
  final int? width;
  final int? height;
  final DateTime? dateTaken;
  final DateTime dateModified;
  final DateTime importDate;
  final String? thumbnailPath;
  final int orientation;
  final Map<String, dynamic>? exif;
  final String? hash;

  Photo({
    this.id,
    required this.path,
    required this.directory,
    required this.filename,
    required this.extension,
    required this.fileSize,
    this.width,
    this.height,
    this.dateTaken,
    required this.dateModified,
    required this.importDate,
    this.thumbnailPath,
    this.orientation = 1,
    this.exif,
    this.hash,
  });

  factory Photo.fromMap(Map<String, dynamic> m) {
    return Photo(
      id: m['id'] as int?,
      path: m['path'] as String,
      directory: m['directory'] as String,
      filename: m['filename'] as String,
      extension: m['extension'] as String,
      fileSize: m['file_size'] as int,
      width: m['width'] as int?,
      height: m['height'] as int?,
      dateTaken:
          m['date_taken'] == null ? null : DateTime.parse(m['date_taken'] as String),
      dateModified: DateTime.parse(m['date_modified'] as String),
      importDate: DateTime.parse(m['import_date'] as String),
      thumbnailPath: m['thumbnail_path'] as String?,
      orientation: (m['orientation'] as int?) ?? 1,
      exif: m['exif_json'] == null
          ? null
          : (jsonDecode(m['exif_json'] as String) as Map<String, dynamic>),
      hash: m['hash'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path': path,
      'directory': directory,
      'filename': filename,
      'extension': extension,
      'file_size': fileSize,
      'width': width,
      'height': height,
      'date_taken': dateTaken?.toIso8601String(),
      'date_modified': dateModified.toIso8601String(),
      'import_date': importDate.toIso8601String(),
      'thumbnail_path': thumbnailPath,
      'orientation': orientation,
      'exif_json': exif == null ? null : jsonEncode(exif),
      'hash': hash,
    };
  }

  Photo copyWith({
    int? id,
    String? thumbnailPath,
    int? orientation,
  }) {
    return Photo(
      id: id ?? this.id,
      path: path,
      directory: directory,
      filename: filename,
      extension: extension,
      fileSize: fileSize,
      width: width,
      height: height,
      dateTaken: dateTaken,
      dateModified: dateModified,
      importDate: importDate,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      orientation: orientation ?? this.orientation,
      exif: exif,
      hash: hash,
    );
  }

  /// Whether a real thumbnail could be generated for this file type.
  bool get hasRenderedThumbnail => thumbnailPath != null;
}
