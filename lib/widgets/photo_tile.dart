import 'dart:io';

import 'package:flutter/material.dart';

import '../models/photo.dart';

Color _placeholderColor(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'tif':
    case 'tiff':
      return const Color(0xFF3A4A5A);
    case 'heic':
    case 'heif':
      return const Color(0xFF5A3A6A);
    case 'cr2':
    case 'cr3':
    case 'arw':
    case 'nef':
    case 'raw':
    case 'dng':
    case 'raf':
    case 'orf':
    case 'rw2':
    case 'sr2':
    case 'pef':
    case 'mrw':
    case 'srw':
    case 'erf':
    case 'kdc':
    case 'dcr':
      return const Color(0xFF7A4A2A);
    default:
      return const Color(0xFF2A4A4A);
  }
}

/// Renders the real thumbnail when available, otherwise a labelled placeholder.
class PhotoThumbnail extends StatelessWidget {
  final Photo photo;
  final BoxFit fit;

  const PhotoThumbnail({super.key, required this.photo, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (photo.thumbnailPath != null) {
      final file = File(photo.thumbnailPath!);
      return Image.file(
        file,
        fit: fit,
        frameBuilder: (ctx, child, frame, _) {
          if (frame == null) {
            return Container(color: Colors.black12);
          }
          return child;
        },
        errorBuilder: (ctx, err, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _placeholderColor(photo.extension),
            _placeholderColor(photo.extension).withOpacity(0.55),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_outlined, size: 20, color: Colors.white70),
            const SizedBox(height: 4),
            Text(
              photo.extension.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A square grid cell with a hover-revealed selection check and an accent ring
/// when selected. Tapping the image opens the viewer; tapping the check toggles
/// selection.
class PhotoGridTile extends StatefulWidget {
  final Photo photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleSelect;

  const PhotoGridTile({
    super.key,
    required this.photo,
    required this.selected,
    required this.onTap,
    required this.onToggleSelect,
  });

  @override
  State<PhotoGridTile> createState() => _PhotoGridTileState();
}

class _PhotoGridTileState extends State<PhotoGridTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showCheck = widget.selected || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: widget.selected
                    ? Border.all(color: scheme.primary, width: 2.5)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                    widget.selected ? 8 : 10),
                child: Hero(
                  tag: 'photo-${widget.photo.id}',
                  child: PhotoThumbnail(photo: widget.photo),
                ),
              ),
            ),
            // top gradient so the check stays legible
            if (showCheck)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.45),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            // selection check
            Positioned(
              top: 6,
              left: 6,
              child: _CheckButton(
                selected: widget.selected,
                visible: showCheck,
                onTap: widget.onToggleSelect,
              ),
            ),
            // hover caption
            if (_hover && !widget.selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    widget.photo.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  final bool selected;
  final bool visible;
  final VoidCallback onTap;

  const _CheckButton({
    required this.selected,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? scheme.primary : Colors.black.withOpacity(0.45),
            border: selected
                ? null
                : Border.all(color: Colors.white70, width: 1.5),
          ),
          child: Icon(
            selected ? Icons.check : Icons.add,
            size: 16,
            color: selected ? scheme.onPrimary : Colors.white,
          ),
        ),
      ),
    );
  }
}
