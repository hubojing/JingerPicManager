import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_store.dart';
import '../models/photo.dart';
import '../nav_target.dart';
import '../state/library_provider.dart';
import '../widgets/photo_tile.dart';
import 'viewer_screen.dart';

/// One date bucket rendered as a section header plus its own grid.
class _PhotoGroup {
  final DateTime date;
  final List<Photo> photos;
  final int startIndex;
  const _PhotoGroup(this.date, this.photos, this.startIndex);
}

class LibraryScreen extends StatefulWidget {
  final void Function(NavTarget) onNavigate;
  final VoidCallback onImport;

  const LibraryScreen({
    super.key,
    required this.onNavigate,
    required this.onImport,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<int> _selected = {};
  int _density = 1; // 0 small, 1 medium, 2 large
  static const _densityExtent = [150.0, 200.0, 260.0];

  Future<void> _pickAndImport() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    await provider.importFolder(path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成：共处理 ${provider.importTotal} 个文件')),
      );
    }
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _addSelectedToAlbum() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final albums = provider.albums;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入相册'),
        content: SizedBox(
          width: 320,
          child: albums.isEmpty
              ? const Text('还没有相册，请先在左侧“相册”中创建。')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: albums.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => ListTile(
                    title: Text(albums[i].name),
                    onTap: () => Navigator.pop(ctx, albums[i].id),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked != null) {
      for (final id in _selected) {
        await provider.addToAlbum(id, picked);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入相册')),
        );
        setState(() => _selected.clear());
      }
    }
  }

  /// Grouping only makes sense while the list is ordered by date; any other
  /// ordering would scatter the same day across many tiny sections.
  bool _canGroup(LibraryProvider provider) =>
      provider.sortMode == SortMode.dateNewest ||
      provider.sortMode == SortMode.dateOldest;

  List<_PhotoGroup> _groupPhotos(List<Photo> photos) {
    final groups = <_PhotoGroup>[];
    DateTime? key;
    final bucket = <Photo>[];
    var start = 0;
    for (var i = 0; i < photos.length; i++) {
      final d = photos[i].dateTaken ?? photos[i].dateModified;
      final k = DateTime(d.year, d.month, d.day);
      if (key == null || k != key) {
        if (bucket.isNotEmpty) {
          groups.add(_PhotoGroup(key!, List<Photo>.of(bucket), start));
        }
        key = k;
        bucket
          ..clear()
          ..add(photos[i]);
        start = i;
      } else {
        bucket.add(photos[i]);
      }
    }
    if (bucket.isNotEmpty && key != null) {
      groups.add(_PhotoGroup(key, List<Photo>.of(bucket), start));
    }
    return groups;
  }

  String _groupTitle(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (d.year == now.year) return '${d.month}月${d.day}日';
    return '${d.year}年${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final selectionActive = _selected.isNotEmpty;
    final canGroup = _canGroup(provider);

    return Scaffold(
      appBar: AppBar(
        title: selectionActive
            ? Text('已选 ${_selected.length} 张')
            : const Text('图片库'),
        actions: [
          if (selectionActive) ...[
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.collections_outlined, size: 18),
              label: const Text('加入相册'),
              onPressed: _addSelectedToAlbum,
            ),
            const SizedBox(width: 8),
          ] else ...[
            Text(
              '${provider.photos.length} 张',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<SortMode>(
              icon: const Icon(Icons.sort_outlined),
              tooltip: '排序方式',
              onSelected: (m) => provider.setSortMode(m),
              itemBuilder: (_) => SortMode.values
                  .map((m) => PopupMenuItem<SortMode>(
                        value: m,
                        child: Text(m.label),
                      ))
                  .toList(),
            ),
            IconButton(
              icon: Icon(
                provider.groupByDate
                    ? Icons.calendar_month
                    : Icons.calendar_month_outlined,
              ),
              tooltip: canGroup ? '按日期分组' : '仅在按时间排序时可分组',
              color: provider.groupByDate && canGroup ? scheme.primary : null,
              onPressed: canGroup
                  ? () => provider.setGroupByDate(!provider.groupByDate)
                  : null,
            ),
            PopupMenuButton<int>(
              icon: const Icon(Icons.view_comfy_outlined),
              tooltip: '网格大小',
              onSelected: (v) => setState(() => _density = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('紧凑')),
                PopupMenuItem(value: 1, child: Text('标准')),
                PopupMenuItem(value: 2, child: Text('宽松')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_outlined),
              tooltip: '导入文件夹',
              onPressed: _pickAndImport,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: Column(
        children: [
          if (provider.importing)
            LinearProgressIndicator(
              value: provider.importTotal == 0
                  ? null
                  : provider.importDone / provider.importTotal,
            ),
          if (provider.importing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '导入中 ${provider.importDone}/${provider.importTotal}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody(provider)),
        ],
      ),
    );
  }

  Widget _buildBody(LibraryProvider provider) {
    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final photos = provider.photos;
    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            const Text('还没有照片'),
            const SizedBox(height: 6),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('导入文件夹'),
              onPressed: _pickAndImport,
            ),
          ],
        ),
      );
    }

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _densityExtent[_density],
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
    );

    if (provider.groupByDate && _canGroup(provider)) {
      final groups = _groupPhotos(photos);
      return CustomScrollView(
        slivers: [
          for (final g in groups) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                child: Row(
                  children: [
                    Text(
                      _groupTitle(g.date),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${g.photos.length} 张',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _tile(photos, g.startIndex + i),
                  childCount: g.photos.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: gridDelegate,
      itemCount: photos.length,
      itemBuilder: (ctx, i) => _tile(photos, i),
    );
  }

  Widget _tile(List<Photo> photos, int index) {
    final photo = photos[index];
    final id = photo.id;
    if (id == null) {
      return PhotoGridTile(
        photo: photo,
        selected: false,
        onTap: () => _openViewer(photos, index),
        onToggleSelect: () {},
      );
    }
    return PhotoGridTile(
      photo: photo,
      selected: _selected.contains(id),
      onTap: () => _openViewer(photos, index),
      onToggleSelect: () => _toggleSelect(id),
    );
  }

  void _openViewer(List<Photo> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(photos: photos, initialIndex: index),
      ),
    );
  }
}
