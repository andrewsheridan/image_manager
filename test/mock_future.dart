import 'package:mocktail/mocktail.dart';

class MockFuture<T> extends Mock implements Future<T> {
  void setupValue(T value) {
    when(() => then<T>(any(), onError: any(named: 'onError'))).thenAnswer((
      invocation,
    ) {
      final onValue = invocation.positionalArguments[0] as dynamic Function(T);
      return Future.value(onValue(value));
    });

    // Optionally support `.catchError`, `.whenComplete`, etc. if used
    when(() => catchError(any())).thenReturn(Future.value(value));
    when(() => whenComplete(any())).thenReturn(Future.value(value));
  }
}
