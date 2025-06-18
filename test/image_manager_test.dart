import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_manager/image_manager.dart';
import 'package:image_manager/string_extensions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';

import 'mock_directory.dart';
import 'mock_file.dart';
import 'mock_file_factory.dart';
import 'mock_firebase_storage.dart';
import 'mock_storage_directory_provider.dart';

void main() {
  late MockFirebaseStorage storage;
  late MockStorageDirectoryProvider storageDirectoryProvider;
  late MockReference reference;
  late MockDirectory directory;
  late MockFileFactory fileFactory;
  late MockFile file;

  final data = Uint8List(16);

  setUp(() {
    storage = MockFirebaseStorage();
    storageDirectoryProvider = MockStorageDirectoryProvider();
    reference = MockReference();
    directory = MockDirectory();
    file = MockFile();
    fileFactory = MockFileFactory(file: file);

    registerFallbackValue(data);

    when(() => directory.path).thenReturn("directory");
    when(() => storage.ref(any())).thenReturn(reference);
    when(() => reference.getData()).thenAnswer((_) async => data);
    when(() => reference.delete()).thenAnswer((_) async {});
    when(() => storageDirectoryProvider.directory).thenReturn(directory);
    when(() => file.delete()).thenAnswer((_) async => file);
    when(
      () => file.create(recursive: true, exclusive: false),
    ).thenAnswer((_) async => file);
    when(() => file.readAsBytes()).thenAnswer((_) async => data);
    when(() => file.writeAsBytes(data)).thenAnswer((_) async => file);
    when(() => storageDirectoryProvider.relativePath(any())).thenAnswer(
      (invocation) =>
          join(directory.path, invocation.positionalArguments.first.toString()),
    );
  });

  ImageManager build() => ImageManager(
    storage: storage,
    storageDirectoryProvider: storageDirectoryProvider,
    fileFactory: fileFactory,
  );

  void setupFileExists(bool exists) {
    when(() => file.exists()).thenAnswer((_) async => exists);
  }

  void setupFilePath(String path) {
    when(
      () => storageDirectoryProvider.fileAtRelativePath(path),
    ).thenReturn(file);
  }

  group("Testing different platform separators.", () {
    for (final fileName in [
      "something.png",
      "directory/filename.png",
      "directory\\filename.png",
    ]) {
      final platformPath = fileName.toLocalPlatformSeparators();
      final unixPath = fileName.toUnixStyleSeparators();

      test(
        "$fileName Given the local file is not yet in cache, when getLocalSync called, then null will be returned and the retrieval process will be initiated.",
        () async {
          when(
            () => storageDirectoryProvider.fileAtRelativePath(platformPath),
          ).thenReturn(file);
          setupFilePath(platformPath);
          setupFileExists(true);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          final fileName = "something.png";

          expect(cache.getLocalSync(fileName), null);
          expect(notifies, 0);

          await pumpEventQueue();

          expect(cache.getLocalSync(fileName), data);
          expect(notifies, 1);
          verify(() => file.readAsBytes());

          expect(cache.getLocalSync(fileName), data);
          expect(notifies, 1);
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is not yet in cache, and not in local stoage, when getFirebaseSync is called, then null will be returned and the retrieval process will be initiated.",
        () async {
          setupFilePath(platformPath);
          setupFileExists(false);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          final fileName = "sessions/abcdef/something.png";

          expect(cache.getFirebaseSync(fileName), null);
          expect(notifies, 0);

          await pumpEventQueue();

          expect(cache.getFirebaseSync(fileName), data);
          expect(notifies, 1);

          verify(() => file.create(recursive: true, exclusive: false));
          verify(() => file.writeAsBytes(data));
          verify(() => storage.ref(fileName));
          verify(() => reference.getData());
          verifyNever(() => file.readAsBytes());

          expect(cache.getFirebaseSync(fileName), data);
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is in local storage but not memory, when getFirebaseSync is called, then null will be returned and the file will be retrivied from storage.",
        () async {
          setupFilePath(platformPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          setupFileExists(true);

          final fileName = "sessions/abcdef/something.png";

          expect(cache.getFirebaseSync(fileName), null);
          expect(notifies, 0);

          await pumpEventQueue();

          expect(cache.getFirebaseSync(fileName), data);
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verify(() => file.readAsBytes());

          expect(cache.getFirebaseSync(fileName), data);
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the local file is not yet in cache, when getLocalAsync called, then the file will be retrieved, cached and returned.",
        () async {
          setupFilePath(platformPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          setupFileExists(true);

          var result = await cache.getLocalAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verify(() => file.readAsBytes());

          result = await cache.getLocalAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is not yet in cache, and not in local stoage, when getFirebaseSync is called, then the value will be retrieved, cached, and stored locally.",
        () async {
          setupFilePath(platformPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          setupFileExists(false);

          var result = await cache.getFirebaseAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verify(() => file.create(recursive: true, exclusive: false));
          verify(() => file.writeAsBytes(data));
          verify(() => storage.ref(unixPath));
          verify(() => reference.getData());
          verifyNever(() => file.readAsBytes());

          result = await cache.getFirebaseAsync(fileName);

          expect(result, data);
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(unixPath));
          verifyNever(() => reference.getData());
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is in local storage but not memory, when getFirebaseAsync is called, then the file will be retrieved and cached from storage.",
        () async {
          setupFilePath(platformPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          setupFileExists(true);

          var result = await cache.getFirebaseAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verify(() => file.readAsBytes());

          result = await cache.getFirebaseAsync(fileName);

          expect(result, data);
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verifyNever(() => file.readAsBytes());
        },
      );
    }
  });
}
