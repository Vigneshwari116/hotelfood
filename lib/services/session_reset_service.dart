import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/printer_service.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/services/repository.dart';

/// Clears UI preferences and wipes shop records (sales, stock, menu, etc.).
class SessionResetService {
  SessionResetService._();

  static const _sessionKeys = <String>[
    'selected_printer',
    ReceiptPaper.prefsKey,
    BluetoothThermalPrinter.macKey,
    BluetoothThermalPrinter.nameKey,
    ReceiptProfile.shopNameKey,
    ReceiptProfile.addressKey,
    ReceiptProfile.phoneKey,
    ReceiptProfile.emailKey,
  ];

  static const _menuSeedKey = 'menu_csv_seed';
  static const _menuSeedVersion = 7;

  static Future<void> clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _sessionKeys) {
      await prefs.remove(key);
    }
  }

  /// Deletes all shop data on the server/local DB, clears screen prefs,
  /// then restores default units, categories, and menu CSV.
  static Future<void> clearAllShopData() async {
    await Repository.instance.factoryResetShopData();
    await clearSessionData();
    await _reseedDefaults();
  }

  static Future<void> _reseedDefaults() async {
    await Repository.instance.ensureStandardUnits();
    await Repository.instance.ensureDefaultCategories();

    final remote = ApiConfig.enabled;
    if (remote) {
      final db = await DBHelper.instance.appDb;
      await db.delete(
        'app_meta',
        where: 'key = ?',
        whereArgs: [_menuSeedKey],
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_menuSeedKey);
    }

    try {
      final csv = await rootBundle.loadString(
        'assets/templates/menu_items_import.csv',
      );
      await ItemImportService().importCsvText(
        csv,
        updateExisting: true,
        replaceCatalog: true,
      );
      if (remote) {
        final db = await DBHelper.instance.appDb;
        await db.insert('app_meta', {
          'key': _menuSeedKey,
          'value': '$_menuSeedVersion',
        });
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_menuSeedKey, _menuSeedVersion);
      }
    } catch (_) {}
  }
}
