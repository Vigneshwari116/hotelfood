import 'env.dart';

/// Server-side trial/license enforcement via LICENSE_EXPIRES_AT env var.
class License {
  static const warningDays = 5;

  static DateTime? get expiresAt => Env.licenseExpiresAt;

  static bool get isConfigured => expiresAt != null;

  static bool get isExpired {
    final at = expiresAt;
    if (at == null) return false;
    return DateTime.now().toUtc().isAfter(at);
  }

  static int? get daysRemaining {
    final at = expiresAt;
    if (at == null) return null;

    final now = DateTime.now().toUtc();
    if (now.isAfter(at)) return 0;

    final expiryDay = DateTime.utc(at.year, at.month, at.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    return expiryDay.difference(today).inDays;
  }

  static bool get showWarning {
    final days = daysRemaining;
    if (days == null || isExpired) return false;
    return days <= warningDays;
  }

  static bool blocksDbMethod(String method, Map<String, dynamic> body) {
    if (!isExpired) return false;

    switch (method) {
      case 'insert':
      case 'update':
      case 'delete':
        return true;
      case 'rawQuery':
        return isWriteRawQuery('${body['sql'] ?? ''}');
      case 'query':
        return '${body['table'] ?? ''}' == 'users';
      default:
        return false;
    }
  }

  static bool blocksTransaction(String path) {
    if (!isExpired) return false;
    return path.contains('tx/begin') || path.contains('tx/commit');
  }

  static bool isWriteRawQuery(String sql) {
    final normalized = sql.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('SELECT')) return false;
    if (normalized.startsWith('WITH')) return false;
    if (normalized.startsWith('EXPLAIN')) return false;
    return true;
  }
}
