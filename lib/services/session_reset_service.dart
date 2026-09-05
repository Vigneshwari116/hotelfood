import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/printer_service.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/services/repository.dart';

/// Clears UI preferences and resets demo sales/purchase data.
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

  static Future<void> clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _sessionKeys) {
      await prefs.remove(key);
    }
  }

  /// Deletes sales/purchases and restores imported stock values for the
  /// current location (or all locations for admin). Clears printer prefs.
  static Future<void> resetDemoData() async {
    await Repository.instance.resetDemoTransactionData();
    await clearSessionData();
  }
}
