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

  /// Trial/license end date. Date-only values (e.g. 2026-10-20) mean end of
  /// that UTC day. Omit or leave empty for no expiry.
  static DateTime? get licenseExpiresAt {
    final raw = Platform.environment['LICENSE_EXPIRES_AT'];
    if (raw == null || raw.trim().isEmpty) return null;

    final value = raw.trim();
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      if (value.length <= 10) {
        return DateTime.utc(parsed.year, parsed.month, parsed.day, 23, 59, 59);
      }
      return parsed.toUtc();
    }

    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return DateTime.utc(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
        23,
        59,
        59,
      );
    }

    return null;
  }
}
