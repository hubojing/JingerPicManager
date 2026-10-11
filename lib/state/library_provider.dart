import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/settings_store.dart';
import '../models/album.dart';
import '../models/photo.dart';
import '../services/face_service.dart';
import '../services/importer.dart';

/// Application-wide state: the photo index, albums, import progress and theme.
/// Lightweight metadata used by the sidebar / album cards.
class AlbumMeta {
  final String? coverPath;
  final int count;
  const AlbumMeta(this.coverPath, this.count);
}

class LibraryProvider extends ChangeNotifier {
  List<Photo> _photos = [];
  List<Album> _albums = [];
  Map<int, AlbumMeta> _albumMeta = {};

  bool _loading = false;
  bool _importing = false;
  int _importDone = 0;
  int _importTotal = 0;
  String _importCurrent = '';
  String? _search;

  ThemeMode _themeMode = ThemeMode.dark;

  SortMode _sortMode = SettingsStore.instance.sortMode;
  bool _groupByDate = SettingsStore.instance.groupByDate;

  List<Map<String, dynamic>> _persons = [];
  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;
  bool _faceEngineAvailable = false;

  List<Photo> get photos => _photos;
  SortMode get sortMode => _sortMode;
  bool get groupByDate => _groupByDate;
  List<Album> get albums => _albums;
  Map<int, AlbumMeta> get albumMeta => _albumMeta;

  List<Map<String, dynamic>> get persons => _persons;
  bool get scanning => _scanning;
  int get scanDone => _scanDone;
  int get scanTotal => _scanTotal;
  bool get faceEngineAvailable => _faceEngineAvailable;

  bool get loading => _loading;
  bool get importing => _importing;
  int get importDone => _importDone;
  int get importTotal => _importTotal;
  String get importCurrent => _importCurrent;
  String? get search => _search;
  ThemeMode get themeMode => _themeMode;

  Future<void> _refreshAlbumMeta() async {
    final map = <int, AlbumMeta>{};
    for (final a in _albums) {
      if (a.id == null) continue;
      final r = await AppDatabase.instance.albumCoverAndCount(a.id!);
      map[a.id!] = AlbumMeta(r['cover'] as String?, r['count'] as int);
    }
    _albumMeta = map;
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      await reloadPhotos();
      _albums = await AppDatabase.instance.getAlbums();
      await _refreshAlbumMeta();
      _persons = await AppDatabase.instance.getPersons();
    } catch (_) {
      // A failure in one step must not block the others or lock the UI.
    }
    try {
      _faceEngineAvailable = await FaceService.instance.isSupported();
    } catch (_) {
      _faceEngineAvailable = false;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> reloadPhotos() async {
    _photos = await AppDatabase.instance.getPhotos(
      search: _search,
      orderBy: _sortMode.sql,
    );
    notifyListeners();
  }

  Future<void> setSortMode(SortMode mode) async {
    if (_sortMode == mode) return;
    _sortMode = mode;
    await SettingsStore.instance.setSortMode(mode);
    await reloadPhotos();
  }

  Future<void> setGroupByDate(bool value) async {
    if (_groupByDate == value) return;
    _groupByDate = value;
    await SettingsStore.instance.setGroupByDate(value);
    notifyListeners();
  }

  void setSearch(String? value) {
    _search = value;
    reloadPhotos();
  }

  Future<void> importFolder(String folderPath) async {
    _importing = true;
    _importDone = 0;
    _importTotal = 0;
    _importCurrent = '';
    notifyListeners();

    await Importer.importFolder(
      folderPath,
      onProgress: (done, total, current) {
        _importDone = done;
        _importTotal = total;
        _importCurrent = current;
        notifyListeners();
      },
    );

    await reloadPhotos();
    _albums = await AppDatabase.instance.getAlbums();
    await _refreshAlbumMeta();
    _importing = false;
    notifyListeners();
  }

  Future<int> createAlbum(String name) async {
    final id = await AppDatabase.instance.createAlbum(name);
    _albums = await AppDatabase.instance.getAlbums();
    await _refreshAlbumMeta();
    notifyListeners();
    return id;
  }

  Future<void> deleteAlbum(int albumId) async {
    await AppDatabase.instance.deleteAlbum(albumId);
    _albums = await AppDatabase.instance.getAlbums();
    await _refreshAlbumMeta();
    notifyListeners();
  }

  Future<void> addToAlbum(int photoId, int albumId) async {
    await AppDatabase.instance.addPhotoToAlbum(photoId, albumId);
    // keep the album's cover fresh when it has none yet
    final album = await AppDatabase.instance.getAlbum(albumId);
    if (album != null && album.coverPhotoId == null) {
      await AppDatabase.instance.setAlbumCover(albumId, photoId);
    }
    await _refreshAlbumMeta();
    notifyListeners();
  }

  Future<void> removeFromAlbum(int photoId, int albumId) async {
    await AppDatabase.instance.removePhotoFromAlbum(photoId, albumId);
    await _refreshAlbumMeta();
    notifyListeners();
  }

  Future<List<Photo>> loadAlbumPhotos(int albumId) async {
    return AppDatabase.instance.getPhotos(albumId: albumId);
  }

  Future<List<Photo>> photosNotInAlbum(int albumId) async {
    final all = await AppDatabase.instance.getPhotos();
    final inAlbum = await AppDatabase.instance.getAlbumPhotoIds(albumId);
    final set = inAlbum.toSet();
    return all.where((p) => !set.contains(p.id)).toList();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  // ---------- People (face recognition) ----------

  Future<void> refreshPersons() async {
    _persons = await AppDatabase.instance.getPersons();
    notifyListeners();
  }

  Future<List<Photo>> personPhotos(int personId) async {
    return AppDatabase.instance.getPersonPhotos(personId);
  }

  Future<void> renamePerson(int id, String name) async {
    await AppDatabase.instance.renamePerson(id, name);
    await refreshPersons();
  }

  /// Detects faces across the whole library, clusters them into people, and
  /// writes the result to the database. Replaces any previous scan.
  Future<void> scanFaces() async {
    if (_scanning) return;
    _scanning = true;
    _scanDone = 0;
    _scanTotal = 0;
    notifyListeners();

    try {
      final photos = await AppDatabase.instance.getPhotos();
      _scanTotal = photos.length;
      final embeddings = <List<double>>[];
      final records = <_PendingFace>[];
      for (final ph in photos) {
        final faces = await FaceService.instance.detect(File(ph.path));
        for (final f in faces) {
          embeddings.add(f.embedding);
          records.add(_PendingFace(ph.id!, f));
        }
        _scanDone++;
        if (_scanDone % 25 == 0) notifyListeners();
      }
      notifyListeners();

      if (embeddings.isEmpty) {
        await AppDatabase.instance.clearAllFaces();
        _persons = [];
        notifyListeners();
        return;
      }

      final labels = clusterFaces(embeddings, threshold: 0.4);
      await AppDatabase.instance.clearAllFaces();

      final byLabel = <int, List<_PendingFace>>{};
      for (int i = 0; i < records.length; i++) {
        byLabel.putIfAbsent(labels[i], () => []).add(records[i]);
      }

      final persons = <Map<String, dynamic>>[];
      for (final entry in byLabel.entries) {
        final label = entry.key;
        final pid = await AppDatabase.instance.createPerson('人物 ${label + 1}');
        for (final fr in entry.value) {
          await AppDatabase.instance.insertFace(
            photoId: fr.photoId,
            personId: pid,
            x: fr.face.x,
            y: fr.face.y,
            w: fr.face.w,
            h: fr.face.h,
            score: fr.face.score,
          );
        }
        final firstPhoto = photos.firstWhere((p) => p.id == entry.value.first.photoId);
        await AppDatabase.instance.setPersonCover(pid, firstPhoto.id);
        persons.add({
          'id': pid,
          'name': '人物 ${label + 1}',
          'cover': firstPhoto.thumbnailPath ?? firstPhoto.path,
          'count': entry.value.length,
        });
      }
      _persons = persons;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }
}

class _PendingFace {
  _PendingFace(this.photoId, this.face);
  final int photoId;
  final RawFace face;
}
