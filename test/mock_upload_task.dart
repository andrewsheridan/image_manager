import 'package:firebase_storage/firebase_storage.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_future.dart';

class MockUploadTask extends MockFuture<TaskSnapshot> implements UploadTask {
  MockUploadTask();

  // @override
  // Future<S> then<S>(
  //   FutureOr<S> Function(TaskSnapshot p1) onValue, {
  //   Function? onError,
  // }) {
  //   try {

  //   }
  //   return onValue(snapshot);
  // }
}

class MockTaskSnapshot extends Mock implements TaskSnapshot {}
