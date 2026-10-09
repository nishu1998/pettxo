import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/image_crop_service.dart';

Future<void> _deleteOwnedCrop(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Cropper cache cleanup is best effort.
  }
}

class ChatImagePreviewDialog extends StatefulWidget {
  const ChatImagePreviewDialog({
    super.key,
    required this.original,
    this.cropService,
    this.cropper,
  });

  final XFile original;
  final ImageCropService? cropService;
  final Future<XFile?> Function(XFile source)? cropper;

  @override
  State<ChatImagePreviewDialog> createState() => _ChatImagePreviewDialogState();
}

class _ChatImagePreviewDialogState extends State<ChatImagePreviewDialog> {
  late final ImageCropService _cropService;
  late XFile _selected;
  bool _cropping = false;
  final Set<String> _ownedCropPaths = <String>{};
  String _returnedPath = '';

  @override
  void dispose() {
    for (final path in _ownedCropPaths.where((path) => path != _returnedPath)) {
      unawaited(_deleteOwnedCrop(path));
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cropService = widget.cropService ?? ImageCropService();
    _selected = widget.original;
  }

  Future<void> _crop() async {
    if (_cropping) return;
    setState(() => _cropping = true);
    final croppedFile = widget.cropper == null
        ? await _cropService.cropChatImage(source: _selected)
        : null;
    final cropped = widget.cropper == null
        ? (croppedFile == null ? null : XFile(croppedFile.path))
        : await widget.cropper!(_selected);
    if (!mounted) return;
    setState(() {
      _cropping = false;
      if (cropped != null) {
        final previousPath = _selected.path;
        if (cropped.path.isNotEmpty && cropped.path != widget.original.path) {
          _ownedCropPaths.add(cropped.path);
        }
        _selected = cropped;
        if (_ownedCropPaths.remove(previousPath)) {
          unawaited(_deleteOwnedCrop(previousPath));
        }
      }
    });
    if (cropped == null && _cropService.hadLastError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to crop this photo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _cropping ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const Expanded(
                  child: Text(
                    'Preview photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Image.file(
                  File(_selected.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white70,
                    size: 52,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cropping ? null : _crop,
                      icon: const Icon(Icons.crop_rounded),
                      label: const Text('Crop'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cropping
                          ? null
                          : () {
                              final paths = _ownedCropPaths.toList();
                              _ownedCropPaths.clear();
                              for (final path in paths) {
                                unawaited(_deleteOwnedCrop(path));
                              }
                              setState(() => _selected = widget.original);
                            },
                      child: const Text('Use original'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: _cropping
                          ? null
                          : () {
                              _returnedPath = _selected.path;
                              Navigator.pop(context, _selected);
                            },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
