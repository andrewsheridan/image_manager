import 'package:flutter_image_compress/flutter_image_compress.dart';

enum CompressionFormat {
  jpeg(CompressFormat.jpeg),
  png(CompressFormat.png),

  /// - iOS: Supported from iOS11+.
  /// - Android: Supported from API 28+ which require hardware encoder supports,
  ///   Use [HeifWriter](https://developer.android.com/reference/androidx/heifwriter/HeifWriter.html)
  heic(CompressFormat.heic),

  /// Only supported on Android.
  webp(CompressFormat.webp);

  final CompressFormat format;
  const CompressionFormat(this.format);
}
