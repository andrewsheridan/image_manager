import 'package:path/path.dart' as p;

extension StringExtensions on String {
  String withFallback(String placeholder) => isEmpty ? placeholder : this;

  String toUnixStyleSeparators() => replaceAll("\\", "/");

  String toLocalPlatformSeparators() =>
      replaceAll("\\", p.separator).replaceAll("/", p.separator);
}
