import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/album.dart';
import '../models/photo.dart';
import 'app_dirs.dart';

/// Local SQLite index of the photo library. Original files are never touched;
/// this database only stores an index, generated thumbnails and metadata.
class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  AppDatabase._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  Future<void> init() async {
    if (_db != null) return;
    final support = resolveSupportDirectory();
    final dbDir = Directory(p.join(support.path, 'db'));
    await dbDir.create(recursive: true);
    _db = await openDatabase(
      p.join(dbDir.path, 'jingerpicmanager.db'),
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT UNIQUE NOT NULL,
        directory TEXT NOT NULL,
        filename TEXT NOT NULL,
        extension TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        date_taken TEXT,
        date_modified TEXT NOT NULL,
        import_date TEXT NOT NULL,
        thumbnail_path TEXT,
        orientation INTEGER NOT NULL DEFAULT 1,
        exif_json TEXT,
        hash TEXT
      );
    ''');
    await db.execute('CREATE INDEX idx_photos_directory ON photos(directory);');
    await db.execute('CREATE INDEX idx_photos_date ON photos(date_taken);');

    await db.execute('''
      CREATE TABLE albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        cover_photo_id INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE photo_albums (
        photo_id INTEGER NOT NULL,
        album_id INTEGER NOT NULL,
        PRIMARY KEY (photo_id, album_id),
        FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      );
    ''');

    await _createPeopleTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPeopleTables(db);
    }
  }

  Future<void> _createPeopleTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        cover_photo_id INTEGER,
        created_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS faces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        photo_id INTEGER NOT NULL,
        person_id INTEGER NOT NULL,
        x REAL, y REAL, w REAL, h REAL, score REAL,
        FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
        FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_faces_photo ON faces(photo_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_faces_person ON faces(person_id);');
  }

  // ---------- Photos ----------

  /// Insert a photo, skipping it if the path is already indexed.
  /// Returns the existing or new row id.
  Future<int> insertPhoto(Photo photo) async {
    final d = await db;
    final existing = await d.query(
      'photos',
      columns: ['id'],
      where: 'path = ?',
      whereArgs: [photo.path],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return d.insert('photos', photo.toMap());
  }

  Future<Photo?> getPhoto(int id) async {
    final d = await db;
    final rows = await d.query('photos', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  Future<List<Photo>> getPhotos({
    int? albumId,
    String? search,
    String? orderBy,
  }) async {
    final d = await db;
    String? where;
    List<Object?>? whereArgs;
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where = 'filename LIKE ? OR directory LIKE ? OR exif_json LIKE ?';
      whereArgs = [like, like, like];
    }
    final String effectiveOrderBy =
        orderBy ?? 'COALESCE(date_taken, date_modified) DESC';

    late final List<Map<String, dynamic>> rows;
    if (albumId != null) {
      rows = await d.rawQuery(
        'SELECT p.* FROM photos p '
        'JOIN photo_albums pa ON pa.photo_id = p.id '
        'WHERE pa.album_id = ? '
        '${where == null ? '' : 'AND $where '}'
        'ORDER BY $effectiveOrderBy',
        [albumId, ...?whereArgs],
      );
    } else {
      rows = await d.query(
        'photos',
        where: where,
        whereArgs: whereArgs,
        orderBy: effectiveOrderBy,
      );
    }
    return rows.map(Photo.fromMap).toList();
  }

  Future<void> updateThumbnail(int id, String thumbnailPath) async {
    final d = await db;
    await d.update(
      'photos',
      {'thumbnail_path': thumbnailPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePhoto(int id) async {
    final d = await db;
    await d.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countPhotos() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) AS c FROM photos');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Clear all stored thumbnail paths (call after wiping the cache directory).
  Future<void> resetThumbnails() async {
    final d = await db;
    await d.update('photos', {'thumbnail_path': null});
  }

  // ---------- Albums ----------

  Future<int> createAlbum(String name) async {
    final d = await db;
    return d.insert('albums', Album(
      name: name,
      createdAt: DateTime.now(),
    ).toMap());
  }

  Future<List<Album>> getAlbums() async {
    final d = await db;
    final rows = await d.query('albums', orderBy: 'created_at DESC');
    return rows.map(Album.fromMap).toList();
  }

  Future<Album?> getAlbum(int id) async {
    final d = await db;
    final rows = await d.query('albums', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Album.fromMap(rows.first);
  }

  Future<void> setAlbumCover(int albumId, int? photoId) async {
    final d = await db;
    await d.update(
      'albums',
      {'cover_photo_id': photoId},
      where: 'id = ?',
      whereArgs: [albumId],
    );
  }

  Future<void> deleteAlbum(int id) async {
    final d = await db;
    await d.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addPhotoToAlbum(int photoId, int albumId) async {
    final d = await db;
    await d.insert(
      'photo_albums',
      {'photo_id': photoId, 'album_id': albumId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removePhotoFromAlbum(int photoId, int albumId) async {
    final d = await db;
    await d.delete(
      'photo_albums',
      where: 'photo_id = ? AND album_id = ?',
      whereArgs: [photoId, albumId],
    );
  }

  Future<List<int>> getAlbumPhotoIds(int albumId) async {
    final d = await db;
    final rows = await d.query(
      'photo_albums',
      columns: ['photo_id'],
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
    return rows.map((r) => r['photo_id'] as int).toList();
  }

  /// Returns the best cover thumbnail path for an album (preferring the
  /// explicitly set cover, then the first photo) plus the photo count.
  Future<Map<String, dynamic>> albumCoverAndCount(int albumId) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT p.thumbnail_path AS thumb, p.path AS path '
      'FROM photo_albums pa '
      'JOIN photos p ON p.id = pa.photo_id '
      'WHERE pa.album_id = ? '
      'ORDER BY (CASE WHEN p.id = (SELECT cover_photo_id FROM albums WHERE id = ?) '
      'THEN 0 ELSE 1 END) '
      'LIMIT 1',
      [albumId, albumId],
    );
    final countRows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM photo_albums WHERE album_id = ?',
      [albumId],
    );
    final count = (countRows.first['c'] as int?) ?? 0;
    String? cover;
    if (rows.isNotEmpty) {
      cover = (rows.first['thumb'] as String?) ?? (rows.first['path'] as String?);
    }
    return {'cover': cover, 'count': count};
  }

  // ---------- People (face recognition) ----------

  /// Each entry: {id, name, cover (thumbnail or path), count}.
  Future<List<Map<String, dynamic>>> getPersons() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT p.id AS id, p.name AS name, p.cover_photo_id AS cover_photo_id,
             COUNT(f.id) AS count
      FROM persons p
      LEFT JOIN faces f ON f.person_id = p.id
      GROUP BY p.id
      ORDER BY count DESC, p.created_at ASC
    ''');
    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      String? cover;
      final coverId = r['cover_photo_id'] as int?;
      if (coverId != null) {
        final ph = await getPhoto(coverId);
        cover = ph?.thumbnailPath ?? ph?.path;
      }
      if (cover == null) {
        // fall back to the first photo of this person
        final first = await d.rawQuery(
          'SELECT p.thumbnail_path AS t, p.path AS p '
          'FROM faces f JOIN photos p ON p.id = f.photo_id '
          'WHERE f.person_id = ? LIMIT 1',
          [r['id']],
        );
        if (first.isNotEmpty) {
          cover = (first.first['t'] as String?) ?? (first.first['p'] as String?);
        }
      }
      result.add({
        'id': r['id'],
        'name': r['name'],
        'cover': cover,
        'count': (r['count'] as int?) ?? 0,
      });
    }
    return result;
  }

  Future<int> createPerson(String name) async {
    final d = await db;
    return d.insert('persons',
        {'name': name, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> renamePerson(int id, String name) async {
    final d = await db;
    await d.update('persons', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setPersonCover(int personId, int? photoId) async {
    final d = await db;
    await d.update('persons', {'cover_photo_id': photoId},
        where: 'id = ?', whereArgs: [personId]);
  }

  Future<List<Photo>> getPersonPhotos(int personId) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT p.* FROM photos p '
      'JOIN faces f ON f.photo_id = p.id '
      'WHERE f.person_id = ? '
      'ORDER BY COALESCE(p.date_taken, p.date_modified) DESC',
      [personId],
    );
    return rows.map(Photo.fromMap).toList();
  }

  Future<void> clearFacesForPhotos(List<int> photoIds) async {
    if (photoIds.isEmpty) return;
    final d = await db;
    final placeholders = List.filled(photoIds.length, '?').join(',');
    await d.delete('faces', where: 'photo_id IN ($placeholders)',
        whereArgs: photoIds);
  }

  Future<void> clearAllFaces() async {
    final d = await db;
    await d.delete('faces');
    await d.delete('persons');
  }

  Future<void> insertFace({
    required int photoId,
    required int personId,
    required double x,
    required double y,
    required double w,
    required double h,
    required double score,
  }) async {
    final d = await db;
    await d.insert('faces', {
      'photo_id': photoId,
      'person_id': personId,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'score': score,
    });
  }

  Future<int> countPersons() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) AS c FROM persons');
    return (r.first['c'] as int?) ?? 0;
  }
}
