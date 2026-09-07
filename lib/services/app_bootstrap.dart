import 'package:flutter/services.dart';
import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/services/auth_session.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fast path before the first frame: open DB, seed users, restore session.
class AppBootstrap {
  static const menuSeedKey = 'menu_csv_seed';
  static const menuSeedVersion = 10;

  static Future<AuthSession?> runEssentialInit() async {
    await DBHelper.instance.appDb;
    await Repository.instance.ensureDefaultUsers();
    final session = await AuthSession.load();
    if (session != null) {
      Repository.instance.bindSession(
        role: session.role,
        locationId: session.locationId,
        locationName: session.locationName,
      );
    }
    return session;
  }

  /// Heavier work that can run after login/shell is visible.
  static Future<void> runDeferredInit() async {
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.ensureDefaultCategories();
    await Repository.instance.consolidateMenuCategories();

    try {
      final remote = ApiConfig.enabled;
      int seeded;
      if (remote) {
        final db = await DBHelper.instance.appDb;
        final rows = await db.query(
          'app_meta',
          where: 'key = ?',
          whereArgs: [menuSeedKey],
        );
        seeded = rows.isEmpty
            ? 0
            : int.tryParse(rows.first['value']?.toString() ?? '') ?? 0;
      } else {
        final prefs = await SharedPreferences.getInstance();
        seeded = prefs.getInt(menuSeedKey) ?? 0;
      }

      if (seeded < menuSeedVersion) {
        await ItemImportService().importCsvText(
          await rootBundle.loadString(
            'assets/templates/menu_items_import.csv',
          ),
          updateExisting: true,
          replaceCatalog: true,
        );
        if (remote) {
          final db = await DBHelper.instance.appDb;
          await db.delete('app_meta', where: 'key = ?', whereArgs: [menuSeedKey]);
          await db.insert('app_meta', {
            'key': menuSeedKey,
            'value': '$menuSeedVersion',
          });
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(menuSeedKey, menuSeedVersion);
        }
      }
    } catch (_) {}

    await Repository.instance.writeOffExpiredStock();
  }
}
