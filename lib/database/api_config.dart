import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class ApiConfig {
  static const url = String.fromEnvironment(
    'SHILPA_API_URL',
    defaultValue: 'http://187.127.180.135:8080',
  );

  static const apiKey = String.fromEnvironment(
    'SHILPA_API_KEY',
    defaultValue: 'shilpa-enterprise-api',
  );

  /// Force local SQLite even on builds that would otherwise use the VPS API.
  static const forceLocalDb = bool.fromEnvironment(
    'SHILPA_LOCAL_DB',
    defaultValue: false,
  );

  /// Force the VPS HTTP database on mobile builds.
  static const forceRemoteDb = bool.fromEnvironment(
    'SHILPA_REMOTE_DB',
    defaultValue: false,
  );

  /// POS phones/tablets store data locally unless a build explicitly opts in
  /// to the shared VPS database.
  static bool get useLocalDb {
    if (forceLocalDb) return true;
    if (forceRemoteDb) return false;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return true;
    }
    return false;
  }

  static bool get enabled => !useLocalDb && url.isNotEmpty;
}
