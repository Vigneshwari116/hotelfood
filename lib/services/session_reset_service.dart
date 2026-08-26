import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/printer_service.dart';
import 'package:foodstock/services/receipt_profile.dart';

/// Clears in-progress UI preferences and form state markers without
/// touching database records (customers, sales, stock, purchases, etc.).
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
}
