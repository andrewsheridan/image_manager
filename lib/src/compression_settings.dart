import 'package:image_manager/src/compression_format.dart';

class CompressionSettings {
  final int? minHeight;
  final int? minWidth;
  final double? sizeRatio;
  final int quality;
  final CompressionFormat format;

  CompressionSettings({
    required this.quality,
    required this.format,
    this.minHeight,
    this.minWidth,
    this.sizeRatio,
  });
}
