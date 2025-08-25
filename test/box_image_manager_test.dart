import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_manager/image_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_box.dart';
import 'mock_firebase_storage.dart';
import 'mock_image_picker.dart';
import 'mock_task_snapshot.dart';
import 'mock_upload_task.dart';

void main() {
  late MockFirebaseStorage storage;
  late MockReference reference;
  late MockTaskSnapshot snapshot;
  late MockUploadTask uploadTask;
  late MockBox box;
  late MockImagePicker imagePicker;

  final data = Uint8List(16);

  late Map<dynamic, dynamic> boxData;

  late final File testImage;
  late final Uint8List testImageBytes;

  final firebaseCollectionPath = "users/12345/characters";

  setUpAll(() async {
    testImage = File('test/rockerboy.png');
    testImageBytes = await testImage.readAsBytes();
  });

  setUp(() {
    storage = MockFirebaseStorage();
    box = MockBox();
    reference = MockReference();
    snapshot = MockTaskSnapshot();
    uploadTask = MockUploadTask(snapshot: snapshot);
    boxData = {};
    imagePicker = MockImagePicker();

    registerFallbackValue(data);

    when(() => box.put(any(), any())).thenAnswer((invocation) async {
      boxData[invocation.positionalArguments.first] =
          invocation.positionalArguments[1];
    });
    when(
      () => box.get(any()),
    ).thenAnswer((invocation) => boxData[invocation.positionalArguments.first]);

    when(() => box.delete(any())).thenAnswer(
      (invocation) => boxData.remove(invocation.positionalArguments.first),
    );

    when(() => reference.getData()).thenAnswer((_) async => data);
    when(() => reference.delete()).thenAnswer((_) async {});
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
    when(() => imagePicker.pickImage(source: ImageSource.gallery)).thenAnswer(
      (invocation) async => XFile.fromData(
        testImageBytes,
        name: "rockerboy.png",
        path: "test/rockerboy.png",
      ),
    );
  });

  BoxImageManager build() => BoxImageManager(
    storage: storage,
    imageCacheBox: box,
    imagePicker: imagePicker,
  );

  void setupRefPath(String path) {
    when(() => storage.ref(path)).thenReturn(reference);
  }

  test("Saving, loading and deleting a local image", () async {
    final manager = build();
    final fileName = "filename.png";
    final result = await manager.saveImageLocal(data, filePath: fileName);
    expect(
      result,
      ImageResult(fileName: fileName, imagePath: fileName, bytes: data),
    );

    verify(() => box.put(fileName, data));

    final loaded = manager.getLocalImage(fileName);

    expect(loaded, data);
    verifyNever(() => box.get(fileName));

    await manager.deleteLocalImage(fileName);

    final deleted = manager.getLocalImage(fileName);

    expect(deleted, null);
    verify(() => box.delete(fileName));
  });

  test("Pick and copy image.", () async {
    final manager = build();
    final picked = await manager.pickAndCopyImage();
    expect(picked!.bytes, testImageBytes);
  });

  test("Saving an image to cloud.", () async {
    final fileName = "$firebaseCollectionPath/filename.png";
    setupRefPath(fileName);

    final manager = build();
    await manager.insertFirebaseImage(data, fileName);

    verify(() => box.put(fileName, data));
    verify(() => reference.putData(data, any()));
  });

  test(
    "Given an image is already stored in memory, when getFirebaseImage() called, data retrieved locally.",
    () async {
      final fileName = "$firebaseCollectionPath/filename.png";
      setupRefPath(fileName);

      final manager = build();
      await manager.saveImageLocal(data, filePath: fileName);

      verify(() => box.put(fileName, data));
      verifyNever(() => reference.putData(data, any()));

      final result = await manager.getFirebaseImage(fileName);
      verifyNever(() => reference.getData());
      verifyNever(() => box.get(fileName));
      expect(result, data);
    },
  );

  test(
    "Given an image is already stored in local storage, when getFirebaseImage() called, data retrieved locally.",
    () async {
      final fileName = "$firebaseCollectionPath/filename.png";
      setupRefPath(fileName);
      boxData[fileName] = data;

      final manager = build();

      final result = await manager.getFirebaseImage(fileName);
      verifyNever(() => reference.getData());
      verify(() => box.get(fileName));
      expect(result, data);
    },
  );

  test(
    "Given an image is not stored in memory or local storage, when getFirebaseImage() called, data retrieved from firebase.",
    () async {
      final fileName = "$firebaseCollectionPath/filename.png";
      setupRefPath(fileName);

      final manager = build();

      final result = await manager.getFirebaseImage(fileName);
      verify(() => reference.getData());
      verify(() => box.get(fileName));
      verify(() => box.put(fileName, data));
      expect(result, data);
    },
  );

  test("Deleting an image from cloud.", () async {
    final fileName = "$firebaseCollectionPath/filename.png";
    setupRefPath(fileName);

    final manager = build();
    await manager.deleteFirebaseImage(fileName);
    verify(() => reference.delete());
    verify(() => box.delete(fileName));
  });
}
