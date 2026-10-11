import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/photo.dart';
import '../nav_target.dart';
import '../state/library_provider.dart';
import '../widgets/photo_tile.dart';
import 'viewer_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  final void Function(NavTarget) onNavigate;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.onNavigate,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Photo> _photos = [];
  bool _loading = true;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    _photos = await provider.loadAlbumPhotos(widget.album.id!);
    if (mounted) setState(() => _loading = false);
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

  Future<void> _removeSelected() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    for (final id in _selected) {
      await provider.removeFromAlbum(id, widget.album.id!);
    }
    _selected.clear();
    await _load();
  }

  Future<void> _addPhotos() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final candidates = await provider.photosNotInAlbum(widget.album.id!);
    if (!mounted) return;

    final picked = await showDialog<List<Photo>>(
      context: context,
      builder: (ctx) {
        final sel = <int>{};
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('从图库添加'),
            content: SizedBox(
              width: 460,
              height: 460,
              child: candidates.isEmpty
                  ? const Text('没有可添加的照片。')
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 110,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: candidates.length,
                      itemBuilder: (c, i) {
                        final p = candidates[i];
                        final isSel = sel.contains(p.id);
                        return InkWell(
                          onTap: () => setSt(() => isSel
                              ? sel.remove(p.id)
                              : sel.add(p.id!)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: PhotoThumbnail(photo: p),
                              ),
                              if (isSel)
                                Positioned(
                                  top: 5,
                                  left: 5,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    child: const Icon(Icons.check,
                                        size: 16, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  candidates.where((p) => sel.contains(p.id)).toList(),
                ),
                child: const Text('添加'),
              ),
            ],
          ),
        );
      },
    );

    if (picked != null) {
      for (final p in picked) {
        await provider.addToAlbum(p.id!, widget.album.id!);
      }
      await _load();
    }
  }

  Future<void> _deleteAlbum() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除相册'),
        content: const Text('确定删除该相册？（照片文件不会被删除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Provider.of<LibraryProvider>(context, listen: false)
          .deleteAlbum(widget.album.id!);
      if (mounted) widget.onNavigate(const NavTarget.albums());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectionActive = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: selectionActive
            ? Text('已选 ${_selected.length} 张')
            : Text(widget.album.name),
        actions: [
          if (selectionActive) ...[
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              label: const Text('移出相册'),
              onPressed: _removeSelected,
            ),
            const SizedBox(width: 8),
          ] else ...[
            Text('${_photos.length} 张',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加照片',
              onPressed: _addPhotos,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除相册',
              onPressed: _deleteAlbum,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.collections_outlined,
                          size: 56,
                          color: scheme.onSurfaceVariant),
                      const SizedBox(height: 14),
                      const Text('相册为空'),
                      const SizedBox(height: 6),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('从图库添加'),
                        onPressed: _addPhotos,
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (ctx, i) {
                    final p = _photos[i];
                    final id = p.id;
                    return PhotoGridTile(
                      photo: p,
                      selected: id != null && _selected.contains(id),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ViewerScreen(
                            photos: _photos,
                            initialIndex: i,
                          ),
                        ),
                      ),
                      onToggleSelect: id != null
                          ? () => _toggleSelect(id)
                          : () {},
                    );
                  },
                ),
    );
  }
}
