import 'dart:convert';

/// A virtual album. Photos are associated without moving the original files.
class Album {
  final int? id;
  final String name;
  final DateTime createdAt;
  final int? coverPhotoId;

  Album({
    this.id,
    required this.name,
    required this.createdAt,
    this.coverPhotoId,
  });

  factory Album.fromMap(Map<String, dynamic> m) {
    return Album(
      id: m['id'] as int?,
      name: m['name'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      coverPhotoId: m['cover_photo_id'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'cover_photo_id': coverPhotoId,
    };
  }

  Album copyWith({String? name, int? coverPhotoId}) {
    return Album(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
    );
  }

  @override
  String toString() => 'Album($id, $name)';
}
