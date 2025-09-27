import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_manager/image_manager.dart';
import 'package:provider/provider.dart';

class BoxImageManagerBuilder extends StatefulWidget {
  BoxImageManagerBuilder({
    required this.imagePath,
    required this.builder,
    required this.useFirebase,
  }) : super(key: Key("BoxImageManagerBuilder$imagePath"));

  final String imagePath;
  final bool useFirebase;
  final Widget Function(BuildContext context, Uint8List? bytes) builder;

  @override
  State<BoxImageManagerBuilder> createState() => _BoxImageManagerBuilderState();
}

class _BoxImageManagerBuilderState extends State<BoxImageManagerBuilder> {
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

    if (!widget.useFirebase) {
      Future.delayed(Duration(seconds: 1), () {
        setState(() {
          final cachedBytes = _imageManager.getLocalImage(widget.imagePath);
          if (cachedBytes != null) {
            _image = cachedBytes;
            return;
          }
        });
      });
    }

    if (widget.useFirebase) {
      _imageManager.getFirebaseImage(widget.imagePath).then((bytes) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _image = bytes;
          });
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _image);
  }
}
