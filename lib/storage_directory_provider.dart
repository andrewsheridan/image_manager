import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_manager/string_extensions.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

class StorageDirectoryProvider {
  final Logger _logger = Logger("StorageDirectoryProvider");

  final Directory _directory;
  Directory get directory => _directory;

  StorageDirectoryProvider({
    required Directory releaseDirectory,
    Directory? debugDirectory,
  }) : _directory = kReleaseMode
           ? releaseDirectory
           : debugDirectory ?? releaseDirectory {
    _logger.finest("Storage directory set to ${_directory.path}");
  }

  File fileAtRelativePath(String path) => File(relativePath(path));
  String relativePath(String path) {
    final output = join(directory.path, path).toLocalPlatformSeparators();
    return output;
  }
}
