import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class PickAndCopyImageResult extends Equatable {
  final String fileName;
  final String imagePath;
  final Uint8List bytes;

  const PickAndCopyImageResult({
    required this.fileName,
    required this.imagePath,
    required this.bytes,
  });

  @override
  List<Object?> get props => [fileName, imagePath, bytes];
}
