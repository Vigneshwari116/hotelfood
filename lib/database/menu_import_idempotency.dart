import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:foodstock/database/app_db.dart';

/// Fingerprints a menu import payload so post-process side effects run once per file.
String menuImportContentFingerprint(
  List<List<String>> rows,
  int? locationId,
) {
  final buffer = StringBuffer('loc:${locationId ?? 0}\n');
  for (final row in rows) {
    buffer.write(row.map((cell) => cell.trim()).join('\t'));
    buffer.write('\n');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}

Future<bool> importPostProcessAlreadyApplied(
  AppDb db, {
  required String contentFingerprint,
  int? locationId,
}) async {
  final rows = locationId == null
      ? await db.query(
          'menu_import_batches',
          columns: ['id'],
          where: 'content_fingerprint = ? AND location_id IS NULL',
          whereArgs: [contentFingerprint],
          limit: 1,
        )
      : await db.query(
          'menu_import_batches',
          columns: ['id'],
          where: 'content_fingerprint = ? AND location_id = ?',
          whereArgs: [contentFingerprint, locationId],
          limit: 1,
        );
  return rows.isNotEmpty;
}

/// Returns false if another import already recorded this batch (race-safe).
Future<bool> tryRecordImportPostProcess(
  AppDb db, {
  required String contentFingerprint,
  int? locationId,
}) async {
  try {
    await db.insert('menu_import_batches', {
      'location_id': locationId,
      'content_fingerprint': contentFingerprint,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  } catch (_) {
    return false;
  }
}
