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
  static const menuSeedVersion = 11;
  static const locationMenuSeedKey = 'location_menu_seed';
  static const locationMenuSeedVersion = 1;

  static const bundledLocationFiles = [
    'Gt world mall',
    'Magadi road',
    'Subbanna garden',
  ];

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

    await _importBundledLocationMenusIfNeeded();

    await Repository.instance.writeOffExpiredStock();
  }

  static Future<int> _readSeedVersion(String key) async {
    final remote = ApiConfig.enabled;
    if (remote) {
      final db = await DBHelper.instance.appDb;
      final rows = await db.query(
        'app_meta',
        where: 'key = ?',
        whereArgs: [key],
      );
      return rows.isEmpty
          ? 0
          : int.tryParse(rows.first['value']?.toString() ?? '') ?? 0;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 0;
  }

  static Future<void> _writeSeedVersion(String key, int version) async {
    final remote = ApiConfig.enabled;
    if (remote) {
      final db = await DBHelper.instance.appDb;
      await db.delete('app_meta', where: 'key = ?', whereArgs: [key]);
      await db.insert('app_meta', {
        'key': key,
        'value': '$version',
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, version);
  }

  /// Imports each location's bundled Excel (named after the location) so
  /// opening stock and prices apply per location.
  static Future<void> _importBundledLocationMenusIfNeeded() async {
    final seeded = await _readSeedVersion(locationMenuSeedKey);
    if (seeded >= locationMenuSeedVersion) return;

    final previous = await AuthSession.load();
    try {
      final locations = await Repository.instance.locations();
      final locationByName = <String, int>{
        for (final row in locations)
          if (row['name'] != null && row['id'] != null)
            row['name']!.toString(): row['id'] as int,
      };

      for (final locationName in bundledLocationFiles) {
        final locationId = locationByName[locationName];
        if (locationId == null) continue;

        try {
          final bytes = (await rootBundle.load(
            'assets/templates/locations/$locationName.xlsx',
          )).buffer.asUint8List();

          Repository.instance.bindSession(
            role: 'admin',
            locationId: locationId,
            locationName: locationName,
          );

          await ItemImportService().importXlsxBytes(
            bytes,
            updateExisting: true,
            replaceCatalog: false,
          );
        } catch (_) {}
      }

      await _writeSeedVersion(
        locationMenuSeedKey,
        locationMenuSeedVersion,
      );
    } finally {
      if (previous != null) {
        Repository.instance.bindSession(
          role: previous.role,
          locationId: previous.locationId,
          locationName: previous.locationName,
        );
      } else {
        Repository.instance.clearSession();
      }
    }
  }
}
