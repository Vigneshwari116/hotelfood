import 'package:foodstock/database/app_db.dart';

Future<void> logInventorySave(
  AppDb db, {
  required String operation,
  int? rawMaterialId,
  required bool success,
  String? errorMessage,
}) async {
  try {
    await db.insert('inventory_save_log', {
      'operation': operation,
      'raw_material_id': rawMaterialId,
      'success': success ? 1 : 0,
      'error_message': errorMessage,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (_) {
    // Logging must never block inventory writes.
  }
}
