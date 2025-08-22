import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_manager/image_manager.dart';
import 'package:provider/provider.dart';

class FutureImageBuilder extends StatefulWidget {
  const FutureImageBuilder({
    super.key,
    required this.imagePath,
    required this.builder,
    this.getImage,
  });

  final String imagePath;
  final Future<Uint8List?> Function(String imagePath)? getImage;
  final Widget Function(BuildContext context, Uint8List? bytes) builder;

  @override
  State<FutureImageBuilder> createState() => _FutureImageBuilderState();
}

class _FutureImageBuilderState extends State<FutureImageBuilder> {
  Uint8List? _image;
  late final BoxImageManager _imageManager;

  @override
  void initState() {
    super.initState();
    _imageManager = context.read<BoxImageManager>();
    final cachedBytes = _imageManager.getLocalImage(widget.imagePath);
    if (cachedBytes != null) {
      _image = cachedBytes;
      return;
    }

    (widget.getImage ?? _imageManager.getFirebaseImage)(widget.imagePath).then((
      bytes,
    ) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _image = bytes;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _image);
  }
}
