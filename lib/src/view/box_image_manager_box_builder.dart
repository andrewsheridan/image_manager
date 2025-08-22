import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_manager/image_manager.dart';
import 'package:provider/provider.dart';

class BoxImageManagerBoxBuilder extends StatefulWidget {
  const BoxImageManagerBoxBuilder({
    super.key,
    required this.imagePath,
    required this.builder,
  });

  final String imagePath;
  final Widget Function(BuildContext context, Uint8List? bytes) builder;

  @override
  State<BoxImageManagerBoxBuilder> createState() =>
      _BoxImageManagerBoxBuilderState();
}

class _BoxImageManagerBoxBuilderState extends State<BoxImageManagerBoxBuilder> {
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

    _imageManager.getFirebaseImage(widget.imagePath).then((bytes) {
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
