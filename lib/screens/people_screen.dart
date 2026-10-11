import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo.dart';
import '../nav_target.dart';
import '../state/library_provider.dart';
import '../widgets/photo_tile.dart';
import 'viewer_screen.dart';

/// Overview of recognized people, with a button to (re)scan the library.
class PeopleScreen extends StatefulWidget {
  final void Function(NavTarget) onNavigate;

  const PeopleScreen({super.key, required this.onNavigate});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final persons = provider.persons;

    return Scaffold(
      appBar: AppBar(
        title: const Text('人物'),
        actions: [
          if (provider.scanning)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${provider.scanDone}/${provider.scanTotal}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.face, size: 18),
              label: Text(provider.persons.isEmpty ? '扫描人脸' : '重新扫描'),
              onPressed: provider.faceEngineAvailable
                  ? () async {
                      await provider.scanFaces();
                      if (mounted) setState(() {});
                    }
                  : null,
            ),
          const SizedBox(width: 10),
        ],
      ),
      body:             !provider.faceEngineAvailable
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.face_outlined,
                      size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 14),
                  const Text('人脸引擎不可用'),
                  const SizedBox(height: 6),
                  const Text(
                    '请确保使用 Windows 版本，且 onnxruntime.dll 与模型文件'
                    '位于 exe 同目录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          : persons.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.face_outlined,
                      size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 14),
                  const Text('还没有识别到人物'),
                      const SizedBox(height: 6),
                      const Text(
                        '点击右上角“扫描人脸”，对整库进行本地人脸检测与分组。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: persons.length,
                  itemBuilder: (ctx, i) {
                    final p = persons[i];
                    final cover = p['cover'] as String?;
                    final count = p['count'] as int;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => widget.onNavigate(
                        NavTarget.person(p['id'] as int),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: cover != null
                                  ? Image.file(
                                      File(cover),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (_, __, ___) =>
                                          _placeholder(scheme),
                                    )
                                  : _placeholder(scheme),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p['name'] as String,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$count 张',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        color: scheme.surface,
        alignment: Alignment.center,
        child: Icon(Icons.person_outline,
            size: 40, color: scheme.onSurfaceVariant),
      );
}

/// Photos of a single recognized person.
class PersonDetailScreen extends StatefulWidget {
  final int personId;
  final void Function(NavTarget) onNavigate;

  const PersonDetailScreen({
    super.key,
    required this.personId,
    required this.onNavigate,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  List<Photo> _photos = [];
  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    _photos = await provider.personPhotos(widget.personId);
    final persons = provider.persons;
    final match = persons.where((p) => p['id'] == widget.personId);
    _name = match.isNotEmpty ? (match.first['name'] as String) : '人物';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名人物'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '人物名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await Provider.of<LibraryProvider>(context, listen: false)
          .renamePerson(widget.personId, result);
      setState(() => _name = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          Text('${_photos.length} 张',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '重命名',
            onPressed: _rename,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const Center(child: Text('无照片'))
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
                    return PhotoGridTile(
                      photo: p,
                      selected: false,
                      onToggleSelect: () {},
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ViewerScreen(
                            photos: _photos,
                            initialIndex: i,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
