import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/api_config.dart';

void main() {
  test('shop app uses a baked-in API URL, not a Server screen', () {
    expect(ApiConfig.url, contains('8080'));
    expect(ApiConfig.useLocalDb, isFalse);
    expect(ApiConfig.enabled, isTrue);
  });
}
