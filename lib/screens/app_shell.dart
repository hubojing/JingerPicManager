import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../nav_target.dart';
import '../state/library_provider.dart';
import 'album_detail_screen.dart';
import 'albums_screen.dart';
import 'library_screen.dart';
import 'people_screen.dart';
import 'settings_screen.dart';

/// Desktop shell: a fixed left navigation sidebar plus the active page.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NavTarget _target = const NavTarget.library();

  void _navigate(NavTarget target) => setState(() => _target = target);

  Widget _pageFor(NavTarget target) {
    switch (target.kind) {
      case NavKind.library:
        return LibraryScreen(
          onNavigate: _navigate,
          onImport: () => _navigate(const NavTarget.library()),
        );
      case NavKind.albums:
        return AlbumsScreen(onOpenAlbum: (a) => _navigate(NavTarget.album(a)));
      case NavKind.album:
        return AlbumDetailScreen(
          album: target.album!,
          onNavigate: _navigate,
        );
      case NavKind.people:
        return PeopleScreen(onNavigate: _navigate);
      case NavKind.person:
        return PersonDetailScreen(
          personId: target.personId!,
          onNavigate: _navigate,
        );
      case NavKind.settings:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final sidebarBg = isDark
        ? const Color(0xFF121216)
        : const Color(0xFFFBFBFD);
    return Row(
      children: [
        Container(
          width: 252,
          color: sidebarBg,
          child: _Sidebar(
            target: _target,
            onNavigate: _navigate,
            onSearch: (v) {
              _navigate(const NavTarget.library());
              Provider.of<LibraryProvider>(context, listen: false)
                  .setSearch(v.trim().isEmpty ? null : v.trim());
            },
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: scheme.outline),
        Expanded(child: _pageFor(_target)),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  final NavTarget target;
  final void Function(NavTarget) onNavigate;
  final void Function(String) onSearch;

  const _Sidebar({
    required this.target,
    required this.onNavigate,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = Provider.of<LibraryProvider>(context);
    final isDark = scheme.brightness == Brightness.dark;

    return Column(
      children: [
        // Brand
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF7C9CFF), const Color(0xFF5A7BF0)]
                        : [const Color(0xFF3B6EF6), const Color(0xFF6C8CFF)],
                  ),
                ),
                child: const Icon(Icons.photo_library_rounded,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'JingerPic',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Global search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索照片',
              prefixIcon: const Icon(Icons.search, size: 18),
              isCollapsed: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
            onChanged: onSearch,
          ),
        ),

        const SizedBox(height: 6),

        // Scrollable nav + album list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              _NavItem(
                icon: Icons.photo_library_outlined,
                selectedIcon: Icons.photo_library,
                label: '图片库',
                selected: target.kind == NavKind.library,
                onTap: () => onNavigate(const NavTarget.library()),
              ),
              _NavItem(
                icon: Icons.collections_outlined,
                selectedIcon: Icons.collections,
                label: '相册',
                selected: target.kind == NavKind.albums,
                onTap: () => onNavigate(const NavTarget.albums()),
              ),
              _NavItem(
                icon: Icons.face_outlined,
                selectedIcon: Icons.face,
                label: '人物',
                selected: target.kind == NavKind.people,
                onTap: () => onNavigate(const NavTarget.people()),
              ),
              if (provider.albums.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding:
                      const EdgeInsets.only(left: 12, right: 12, bottom: 6),
                  child: Text(
                    '我的相册',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                ...provider.albums.map((a) {
                  final meta = provider.albumMeta[a.id];
                  final selected = target.kind == NavKind.album &&
                      target.album?.id == a.id;
                  return _AlbumItem(
                    album: a,
                    coverPath: meta?.coverPath,
                    count: meta?.count ?? 0,
                    selected: selected,
                    onTap: () => onNavigate(NavTarget.album(a)),
                  );
                }),
              ],
            ],
          ),
        ),

        Divider(height: 1, thickness: 1, color: scheme.outline),
        _NavItem(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: '设置',
          selected: target.kind == NavKind.settings,
          onTap: () => onNavigate(const NavTarget.settings()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 20,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumItem extends StatelessWidget {
  final Album album;
  final String? coverPath;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _AlbumItem({
    required this.album,
    required this.coverPath,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final cover =
        coverPath != null ? FileImage(File(coverPath!)) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark
                        ? const Color(0xFF2A2A31)
                        : const Color(0xFFE4E4EC),
                    image: cover != null
                        ? DecorationImage(image: cover, fit: BoxFit.cover)
                        : null,
                  ),
                  child: cover == null
                      ? Icon(Icons.collections_outlined,
                          size: 16, color: scheme.onSurfaceVariant)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    album.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
