import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_task_snapshot.dart';

class MockUploadTask extends Mock implements UploadTask {
  @override
  final MockTaskSnapshot snapshot;

  MockUploadTask({MockTaskSnapshot? snapshot})
    : snapshot = snapshot ?? MockTaskSnapshot();

  @override
  Future<T> then<T>(
    FutureOr<T> Function(TaskSnapshot value) onValue, {
    Function? onError,
  }) async {
    return onValue(snapshot);
  }
}
