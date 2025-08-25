import 'dart:math';

class ByteCountFormatter {
  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return "0B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB"];
    final i = (log(bytes) / log(1024)).floor();
    final size = bytes / pow(1024, i);
    return "${size.toStringAsFixed(decimals)}${suffixes[i]}";
  }
}
