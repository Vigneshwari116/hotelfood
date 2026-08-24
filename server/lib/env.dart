import 'dart:io';

class Env {
  static String get pgHost =>
      Platform.environment['PGHOST'] ?? '127.0.0.1';
  static int get pgPort =>
      int.tryParse(Platform.environment['PGPORT'] ?? '') ?? 5434;
  static String get pgDatabase =>
      Platform.environment['PGDATABASE'] ?? 'shilpa_enterprise';
  static String get pgUser => Platform.environment['PGUSER'] ?? 'postgres';
  static String get pgPassword => Platform.environment['PGPASSWORD'] ?? '';
  static String get apiKey =>
      Platform.environment['API_KEY'] ?? 'shilpa-enterprise-api';
  static int get port =>
      int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
}
