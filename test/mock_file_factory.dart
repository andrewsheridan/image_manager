import 'dart:io';

import 'package:image_manager/file_factory.dart';

import 'mock_file.dart';

class MockFileFactory implements FileFactory {
  final MockFile file;

  MockFileFactory({required this.file});

  @override
  File fromPath(String path) {
    return file;
  }
}
