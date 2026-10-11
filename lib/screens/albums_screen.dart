import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../state/library_provider.dart';

class AlbumsScreen extends StatelessWidget {
  final void Function(Album) onOpenAlbum;

  const AlbumsScreen({super.key, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final albums = provider.albums;

    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建相册',
            onPressed: () => _createAlbum(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: albums.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 14),
                  const Text('还没有相册'),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('新建相册'),
                    onPressed: () => _createAlbum(context),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1,
              ),
              itemCount: albums.length,
              itemBuilder: (ctx, i) =>
                  _AlbumCard(album: albums[i], onOpen: onOpenAlbum),
            ),
    );
  }

  Future<void> _createAlbum(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建相册'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '相册名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await Provider.of<LibraryProvider>(context, listen: false)
          .createAlbum(name);
    }
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final void Function(Album) onOpen;

  const _AlbumCard({required this.album, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final meta = provider.albumMeta[album.id];
    final coverPath = meta?.coverPath;
    final count = meta?.count ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(album),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverPath != null)
              Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withOpacity(0.5),
                        scheme.primary.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.collections_outlined,
                        size: 40, color: scheme.onSurface),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withOpacity(0.5),
                      scheme.primary.withOpacity(0.2),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(Icons.collections_outlined,
                      size: 40, color: scheme.onSurface),
                ),
              ),
            // gradient + caption
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.78),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        album.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
