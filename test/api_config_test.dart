import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/api_config.dart';

void main() {
  test('shop app uses shared VPS database by default', () {
    expect(ApiConfig.url, contains('8080'));
    expect(ApiConfig.useLocalDb, isFalse);
    expect(ApiConfig.enabled, isTrue);
  });

  test('request timeout defaults to 8 seconds', () {
    expect(ApiConfig.requestTimeoutSeconds, 8);
    expect(ApiConfig.requestTimeout, const Duration(seconds: 8));
  });
}
