import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/api_config.dart';

void main() {
  test('shop server URL is baked in for remote builds', () {
    expect(ApiConfig.url, contains('8080'));
  });

  test('mobile builds default to local sqlite unless remote is requested', () {
    expect(ApiConfig.forceRemoteDb, isFalse);
    if (Platform.isAndroid || Platform.isIOS) {
      expect(ApiConfig.useLocalDb, isTrue);
      expect(ApiConfig.enabled, isFalse);
    }
  });

  test('desktop builds default to remote db unless local is forced', () {
    if (Platform.isAndroid || Platform.isIOS) return;
    expect(ApiConfig.forceLocalDb, isFalse);
    expect(ApiConfig.useLocalDb, isFalse);
    expect(ApiConfig.enabled, isTrue);
  });
}
