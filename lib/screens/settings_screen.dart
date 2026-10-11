import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../data/database.dart';
import '../data/settings_store.dart';
import '../data/thumbnail_cache.dart';
import '../state/library_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Directory? _cacheDir;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCacheDir();
  }

  Future<void> _loadCacheDir() async {
    final d = await ThumbnailCache.instance.dir;
    if (!mounted) return;
    setState(() => _cacheDir = d);
  }

  /// Copy already-generated thumbnails into [target] so the new location is
  /// usable immediately, instead of forcing a full regeneration.
  Future<int> _migrate(Directory from, Directory to) async {
    if (!await from.exists()) return 0;
    await to.create(recursive: true);
    var moved = 0;
    await for (final entity in from.list()) {
      if (entity is! File) continue;
      try {
        await entity.copy(
            '${to.path}${Platform.pathSeparator}${entity.uri.pathSegments.last}');
        moved++;
      } catch (_) {
        // A single unreadable thumbnail should not abort the migration.
      }
    }
    return moved;
  }

  Future<void> _pickCacheDir() async {
    final oldDir = await ThumbnailCache.instance.dir;
    final picked = await getDirectoryPath();
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final target = Directory(picked);
    final moved = await _migrate(oldDir, target);
    await SettingsStore.instance.setThumbnailCacheDir(picked);
    ThumbnailCache.instance.invalidate();
    await _loadCacheDir();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('缓存目录已切换到：$picked（迁移 $moved 个缩略图）')),
    );
  }

  Future<void> _resetCacheDir() async {
    if (SettingsStore.instance.thumbnailCacheDir == null) return;
    setState(() => _busy = true);
    await SettingsStore.instance.setThumbnailCacheDir(null);
    ThumbnailCache.instance.invalidate();
    await _loadCacheDir();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复为默认缓存目录')),
    );
  }

  /// Opens the author's homepage in the default browser.
  Future<void> _openAuthorUrl(BuildContext context) async {
    final cmd = externalOpenCommand(AppInfo.authorUrl);
    try {
      await Process.run(cmd.first, cmd.sublist(1));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final isCustom = SettingsStore.instance.thumbnailCacheDir != null;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionTitle('外观'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('主题'),
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        selected: {provider.themeMode},
                        onSelectionChanged: (s) => provider.setThemeMode(s.first),
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.light, label: Text('浅色')),
                          ButtonSegment(
                              value: ThemeMode.dark, label: Text('深色')),
                          ButtonSegment(
                              value: ThemeMode.system, label: Text('系统')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('库'),
              Card(
                child: Column(
                  children: [
                    FutureBuilder<int>(
                      future: AppDatabase.instance.countPhotos(),
                      builder: (c, s) => ListTile(
                        leading: Icon(Icons.photo_library_outlined,
                            color: scheme.primary),
                        title: const Text('已索引照片'),
                        trailing: Text('${s.data ?? 0}'),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.folder_outlined,
                          color: scheme.primary),
                      title: const Text('缩略图缓存目录'),
                      subtitle: Text(
                        _cacheDir?.path ?? '加载中…',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _pickCacheDir,
                                  child: const Text('更改'),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: isCustom ? _resetCacheDir : null,
                                  child: const Text('恢复默认'),
                                ),
                              ],
                            ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.delete_outline,
                          color: scheme.primary),
                      title: const Text('清除缩略图缓存'),
                      subtitle: const Text('不会删除原始照片，重新导入可重建'),
                      onTap: () async {
                        await ThumbnailCache.instance.clear();
                        await AppDatabase.instance.resetThumbnails();
                        await provider.reloadPhotos();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('缓存已清除')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('关于'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text(AppInfo.name),
                      subtitle: Text(
                          '${AppInfo.version} · ${AppInfo.description}'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('作者'),
                      subtitle: Text(AppInfo.authorName),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.link, color: scheme.primary),
                      title: const Text('作者主页'),
                      subtitle: const Text(AppInfo.authorUrl),
                      onTap: () => _openAuthorUrl(context),
                      trailing: Icon(Icons.open_in_new,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
