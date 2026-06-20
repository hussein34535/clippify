import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/core/api/api_client.dart';

void main() {
  group('ApiResult sealed class', () {
    test('Success carries data', () {
      const result = Success('hello');
      expect(result.data, 'hello');
    });

    test('Failure carries message', () {
      const result = Failure('not found');
      expect(result.message, 'not found');
    });

    test('Failure can carry statusCode and endpoint', () {
      const result = Failure('server error', statusCode: 500, endpoint: '/api/test');
      expect(result.statusCode, 500);
      expect(result.endpoint, '/api/test');
    });

    test('pattern matching with switch', () {
      ApiResult<int> make(bool ok) => ok ? const Success(42) : const Failure('fail');

      String describe(ApiResult<int> r) {
        return switch (r) {
          Success(data: final d) => 'got $d',
          Failure(message: final m) => 'error: $m',
        };
      }

      expect(describe(make(true)), 'got 42');
      expect(describe(make(false)), 'error: fail');
    });

    test('ApiClient is singleton', () {
      final a = ApiClient();
      final b = ApiClient();
      expect(identical(a, b), true);
    });
  });
}
