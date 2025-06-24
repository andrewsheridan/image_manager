import 'package:flutter_test/flutter_test.dart';

import 'mock_task_snapshot.dart';
import 'mock_upload_task.dart';

void main() {
  test("Testing a MockUploadTask", () async {
    final snapshot = MockTaskSnapshot();
    final task = MockUploadTask(snapshot: snapshot);

    final result = await task;
    expect(result, snapshot);
  });
}
