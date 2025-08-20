import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_manager/src/image_manager.dart';
import 'package:image_manager/src/string_extensions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';

import 'mock_directory.dart';
import 'mock_file.dart';
import 'mock_file_factory.dart';
import 'mock_firebase_storage.dart';
import 'mock_task_snapshot.dart';
import 'mock_upload_task.dart';

void main() {
  late MockFirebaseStorage storage;
  late MockReference reference;
  late MockDirectory directory;
  late MockFileFactory fileFactory;
  late MockFile file;
  late MockTaskSnapshot snapshot;
  late MockUploadTask uploadTask;

  final data = Uint8List(16);

  setUp(() {
    storage = MockFirebaseStorage();
    reference = MockReference();
    directory = MockDirectory();
    file = MockFile();
    fileFactory = MockFileFactory();
    snapshot = MockTaskSnapshot();
    uploadTask = MockUploadTask(snapshot: snapshot);

    registerFallbackValue(data);

    when(
      () => directory.path,
    ).thenReturn("~/documents".toLocalPlatformSeparators());
    when(() => reference.getData()).thenAnswer((_) async => data);
    when(() => reference.delete()).thenAnswer((_) async {});
    when(() => reference.putFile(file)).thenAnswer((_) {
      return uploadTask;
    });
    when(
      () => reference.putData(data, any(that: isA<SettableMetadata>())),
    ).thenAnswer((_) {
      return uploadTask;
    });
    when(
      () => reference.putData(data, any(that: isA<SettableMetadata>())),
    ).thenAnswer((_) {
      return uploadTask;
    });
    when(() => file.delete()).thenAnswer((_) async => file);

    when(
      () => file.create(recursive: true, exclusive: false),
    ).thenAnswer((_) async => file);
    when(() => file.readAsBytes()).thenAnswer((_) async => data);
    when(() => file.writeAsBytes(data)).thenAnswer((_) async => file);
  });

  ImageManager build() => ImageManager(
    storage: storage,
    directory: directory,
    fileFactory: fileFactory,
  );

  String setupFilePath(String filePathRelativeToDirectory, bool exists) {
    final fullPath = join(
      directory.path,
      filePathRelativeToDirectory.toLocalPlatformSeparators(),
    );
    when(() => fileFactory.fromPath(fullPath)).thenReturn(file);
    when(() => file.path).thenReturn(fullPath);
    when(() => file.exists()).thenAnswer((_) async => exists);

    return fullPath;
  }

  void setupRefPath(String path) {
    when(() => storage.ref(path)).thenReturn(reference);
  }

  group("Testing different platform separators.", () {
    for (final fileName in [
      "filename.png",
      "sessions/123456/filename.jpeg",
      "sessions\\123456\\filename.png",
    ]) {
      final unixPath = fileName.toUnixStyleSeparators();

      test(
        "$fileName Given the local file is not yet in cache, when getLocalSync called, then null will be returned and the retrieval process will be initiated.",
        () async {
          setupFilePath(fileName, true);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          expect(
            cache.getLocalSync(fileName: fileName, retrieveIfMissing: true),
            null,
          );
          expect(notifies, 0);

          await pumpEventQueue();

          expect(
            cache.getLocalSync(fileName: fileName, retrieveIfMissing: true),
            data,
          );
          expect(notifies, 1);
          verify(() => file.readAsBytes());

          expect(
            cache.getLocalSync(fileName: fileName, retrieveIfMissing: true),
            data,
          );
          expect(notifies, 1);
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is not yet in cache, and not in local stoage, when getFirebaseSync is called, then null will be returned and the retrieval process will be initiated.",
        () async {
          setupFilePath(fileName, false);
          setupRefPath(unixPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            null,
          );
          expect(notifies, 0);

          await pumpEventQueue();

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            data,
          );
          expect(notifies, 1);

          verify(() => file.create(recursive: true, exclusive: false));
          verify(() => file.writeAsBytes(data));
          verify(() => storage.ref(unixPath));
          verify(() => reference.getData());
          verifyNever(() => file.readAsBytes());

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            data,
          );
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(unixPath));
          verifyNever(() => reference.getData());
          verifyNever(() => file.readAsBytes());
        },
      );

      test(
        "$fileName Given the firebase file is in local storage but not memory, when getFirebaseSync is called, then null will be returned and the file will be retrivied from storage.",
        () async {
          setupFilePath(fileName, true);
          setupRefPath(unixPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            null,
          );
          expect(notifies, 0);

          await pumpEventQueue();

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            data,
          );
          expect(notifies, 1);

          verifyNever(() => file.create(recursive: true, exclusive: false));
          verifyNever(() => file.writeAsBytes(data));
          verifyNever(() => storage.ref(fileName));
          verifyNever(() => reference.getData());
          verify(() => file.readAsBytes());

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: true,
            ),
            data,
          );
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
          setupFilePath(fileName, true);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

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
          setupFilePath(fileName, false);
          setupRefPath(unixPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

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
          setupFilePath(fileName, true);
          setupRefPath(unixPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

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

      test(
        "$fileName - Given a file exists locally and is in memory, when removeLocalFileCalled, both local and cache instance removed.",
        () async {
          setupFilePath(fileName, true);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          var result = await cache.getLocalAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verify(() => file.readAsBytes());

          await cache.removeLocalFile(fileName);

          expect(notifies, 2);
          verify(() => file.delete());
        },
      );

      test(
        "$fileName Path Given a file exists locally and is in memory, when removeLocalFileCalled, both local and cache instance removed.",
        () async {
          setupFilePath(fileName, false);
          setupRefPath(unixPath);
          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          var result = await cache.getFirebaseAsync(fileName);

          expect(result, data);
          expect(notifies, 1);
          verify(() => file.create(recursive: true, exclusive: false));
          verify(() => file.writeAsBytes(data));
          verify(() => storage.ref(unixPath));
          verify(() => reference.getData());
          verifyNever(() => file.readAsBytes());

          setupFilePath(fileName, true);

          await cache.removeFirebaseFile(fileName);

          expect(notifies, 2);
          verify(() => file.delete());
          verify(() => reference.delete());
        },
      );

      test(
        "$fileName - Uploading a file will stick that file in cache and in firebase.",
        () async {
          setupFilePath(fileName, true);
          setupRefPath(unixPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          await cache.uploadFile(file, fileName);

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: false,
            ),
            data,
          );
          expect(notifies, 1);
          verify(() => reference.putFile(file));
        },
      );

      test(
        "$fileName - Uploading data will stick that file in cache and in firebase.",
        () async {
          setupFilePath(fileName, true);
          setupRefPath(unixPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          final contentType = ImageManager.getImageContentType(fileName);

          await cache.uploadData(data, fileName, contentType);

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: false,
            ),
            data,
          );
          expect(notifies, 1);
          verify(
            () => reference.putData(
              data,
              any(
                that: isA<SettableMetadata>().having(
                  (m) => m.contentType,
                  "Has Content Type Match",
                  contentType,
                ),
              ),
            ),
          );
        },
      );

      test(
        "$fileName - Uploading image will stick that file in cache and in firebase.",
        () async {
          setupFilePath(fileName, true);
          setupRefPath(unixPath);

          var notifies = 0;

          final cache = build();
          cache.addListener(() => notifies++);

          final contentType = ImageManager.getImageContentType(fileName);

          await cache.uploadImage(data, fileName);

          expect(
            cache.getFirebaseSync(
              firebasePath: fileName,
              retrieveIfMissing: false,
            ),
            data,
          );
          expect(notifies, 1);

          verify(
            () => reference.putData(
              data,
              any(
                that: isA<SettableMetadata>().having(
                  (m) => m.contentType,
                  "Has Content Type Match",
                  contentType,
                ),
              ),
            ),
          );
        },
      );
    }
  });
}
