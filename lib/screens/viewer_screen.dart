import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/photo.dart';
import '../state/library_provider.dart';
import '../widgets/photo_tile.dart';

/// Immersive, dark full-screen viewer with a filmstrip and metadata panel.
class ViewerScreen extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;

  const ViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late PageController _pageController;
  late int _current;
  bool _showInfo = false;
  final _filmstrip = ScrollController();

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _filmstrip.dispose();
    super.dispose();
  }

  Photo get photo => widget.photos[_current];

  void _goTo(int index) {
    if (index < 0 || index >= widget.photos.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    setState(() => _current = index);
    _scrollFilmstripTo(index);
  }

  void _scrollFilmstripTo(int index) {
    if (!_filmstrip.hasClients) return;
    _filmstrip.animateTo(
      (index * 76).toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _goTo(_current + 1);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _goTo(_current - 1);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            // Pager
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (i) {
                setState(() => _current = i);
                _scrollFilmstripTo(i);
              },
              itemBuilder: (ctx, i) {
                final p = widget.photos[i];
                final canPreview = p.thumbnailPath != null;
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: canPreview
                        ? Image.file(
                            File(p.path),
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => _unavailable(p),
                          )
                        : _unavailable(p),
                  ),
                );
              },
            ),

            // prev / next arrows
            _EdgeButton(
              left: true,
              enabled: _current > 0,
              onTap: () => _goTo(_current - 1),
            ),
            _EdgeButton(
              left: false,
              enabled: _current < widget.photos.length - 1,
              onTap: () => _goTo(_current + 1),
            ),

            // top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: '返回 (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        photo.filename,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showInfo
                            ? Icons.info
                            : Icons.info_outline,
                        color: Colors.white,
                      ),
                      tooltip: '信息',
                      onPressed: () => setState(() => _showInfo = !_showInfo),
                    ),
                    IconButton(
                      icon: const Icon(Icons.collections_outlined,
                          color: Colors.white),
                      tooltip: '加入相册',
                      onPressed: _addToAlbum,
                    ),
                  ],
                ),
              ),
            ),

            // bottom filmstrip
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 96,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  ),
                ),
                child: ListView.builder(
                  controller: _filmstrip,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: widget.photos.length,
                  itemBuilder: (ctx, i) {
                    final p = widget.photos[i];
                    final active = i == _current;
                    return GestureDetector(
                      onTap: () => _goTo(i),
                      child: Container(
                        width: 64,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: active
                              ? Border.all(color: scheme.primary, width: 2.5)
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(active ? 6 : 8),
                          child: PhotoThumbnail(photo: p),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // info panel
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              top: 0,
              bottom: 0,
              right: _showInfo ? 0 : -320,
              width: 320,
              child: _InfoPanel(photo: photo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailable(Photo p) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 64, color: Colors.white54),
          const SizedBox(height: 12),
          Text(
            '该格式（${p.extension.toUpperCase()}）暂不支持内嵌预览，'
            '需后续接入原生解码器（见 V1 计划）。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Future<void> _addToAlbum() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final albums = provider.albums;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入相册'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: albums.isEmpty
              ? const Text('还没有相册，请先在左侧“相册”中创建。')
              : ListView(
                  children: albums
                      .map((a) => ListTile(
                            title: Text(a.name),
                            onTap: () => Navigator.pop(ctx, a.id),
                          ))
                      .toList(),
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
    if (selected != null && photo.id != null) {
      await provider.addToAlbum(photo.id!, selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入相册')),
        );
      }
    }
  }
}

class _EdgeButton extends StatelessWidget {
  final bool left;
  final bool enabled;
  final VoidCallback onTap;

  const _EdgeButton({
    required this.left,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.25,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: Colors.black.withOpacity(0.35),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  left ? Icons.chevron_left : Icons.chevron_right,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final Photo photo;
  const _InfoPanel({required this.photo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exif = photo.exif;
    final items = <MapEntry<String, String>>[
      if (photo.width != null)
        MapEntry('尺寸', '${photo.width} × ${photo.height}'),
      if (photo.dateTaken != null)
        MapEntry('拍摄时间', photo.dateTaken.toString()),
      if (photo.fileSize > 0)
        MapEntry('大小', '${(photo.fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
    ];
    if (exif != null) {
      for (final e in exif.entries) {
        items.add(MapEntry(e.key, e.value.toString()));
      }
    }
    return Material(
      color: scheme.surface,
      elevation: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '信息',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              photo.path,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        items[i].key,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(
                        items[i].value,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
