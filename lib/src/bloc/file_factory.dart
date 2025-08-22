import 'dart:io';

import 'package:image_manager/src/bloc/string_extensions.dart';

class FileFactory {
  File fromPath(String path) => File(path.toLocalPlatformSeparators());
}
