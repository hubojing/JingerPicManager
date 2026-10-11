import 'package:flutter/material.dart';

import 'models/album.dart';

enum NavKind { library, albums, album, people, person, settings }

/// Describes which page the app shell should display.
class NavTarget {
  final NavKind kind;
  final Album? album;
  final int? personId;
  const NavTarget.library()
      : kind = NavKind.library,
        album = null,
        personId = null;
  const NavTarget.albums()
      : kind = NavKind.albums,
        album = null,
        personId = null;
  const NavTarget.album(Album a)
      : kind = NavKind.album,
        album = a,
        personId = null;
  const NavTarget.people()
      : kind = NavKind.people,
        album = null,
        personId = null;
  const NavTarget.person(int id)
      : kind = NavKind.person,
        album = null,
        personId = id;
  const NavTarget.settings()
      : kind = NavKind.settings,
        album = null,
        personId = null;
}
