import 'dart:typed_data';

import 'package:flutter/material.dart';

class FutureImageBuilder extends StatefulWidget {
  const FutureImageBuilder({
    super.key,
    required this.builder,
    required this.getImage,
  });

  final Future<Uint8List?> Function() getImage;
  final Widget Function(BuildContext context, Uint8List? bytes) builder;

  @override
  State<FutureImageBuilder> createState() => _FutureImageBuilderState();
}

class _FutureImageBuilderState extends State<FutureImageBuilder> {
  Uint8List? _image;

  @override
  void initState() {
    super.initState();

    widget.getImage().then((bytes) {
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
