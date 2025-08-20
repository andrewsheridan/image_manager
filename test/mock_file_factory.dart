import 'dart:io';

import 'package:image_manager/src/file_factory.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_file.dart';

class StubbedFileFactory implements FileFactory {
  final MockFile file;

  StubbedFileFactory({required this.file});

  @override
  File fromPath(String path) {
    return file;
  }
}

class MockFileFactory extends Mock implements FileFactory {}
