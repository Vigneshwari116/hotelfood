import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/esc_pos_receipt_builder.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/services/thermal/thermal_bridge.dart';

class SavedThermalPrinter {
  final String name;
  final String mac;

  const SavedThermalPrinter({required this.name, required this.mac});
}

/// Bluetooth ESC/POS printer (POSiFLOW KP206 and other 58mm printers).
class BluetoothThermalPrinter {
  static const macKey = 'posiflow_bt_mac';
  static const nameKey = 'posiflow_bt_name';

  static Future<SavedThermalPrinter?> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(macKey);
    final name = prefs.getString(nameKey);
    if (mac == null || mac.isEmpty) return null;
    return SavedThermalPrinter(
      name: (name == null || name.isEmpty) ? 'POSiFLOW 58mm' : name,
      mac: mac,
    );
  }

  static Future<void> save(ThermalDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(macKey, device.mac);
    await prefs.setString(nameKey, device.name);
    await prefs.setString('receipt_paper_size', '58mm');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(macKey);
    await prefs.remove(nameKey);
  }

  static const permissionDeniedMessage =
      'Bluetooth permission was denied. Tap Allow when the phone asks for Nearby devices. '
      'If you already tapped Don\'t allow, open Settings → Apps → Shilpa Enterprise → '
      'Permissions → Nearby devices.';

  static Future<void> ensurePermission() async {
    final requested = await ThermalBridge.requestPermission();
    if (requested) return;
    if (await ThermalBridge.permissionGranted()) return;
    throw StateError(permissionDeniedMessage);
  }

  static Future<List<ThermalDevice>> scan() async {
    await ensurePermission();
    final permitted = await ThermalBridge.permissionGranted();
    if (!permitted) {
      throw StateError(permissionDeniedMessage);
    }
    final on = await ThermalBridge.bluetoothOn();
    if (!on) {
      throw StateError('Turn on Bluetooth, then scan again.');
    }
    return ThermalBridge.pairedDevices();
  }

  static Future<void> ensureConnected(String mac) async {
    await ThermalBridge.disconnect();
    final ok = await ThermalBridge.connect(mac);
    if (!ok) {
      throw StateError(
        'Could not connect to the printer. Pair it in phone Bluetooth settings, then select it here.',
      );
    }
  }

  static Future<void> printBytes(List<int> bytes) async {
    final saved = await loadSaved();
    if (saved == null) {
      throw StateError('No Bluetooth printer selected.');
    }
    await ensurePermission();
    await ensureConnected(saved.mac);
    final ok = await ThermalBridge.writeBytes(bytes);
    if (!ok) {
      throw StateError(
        'Printer did not accept the bill data. Check that it is on and paired, then try again.',
      );
    }
  }

  static Future<void> printSale({
    required int saleId,
    required List<CartLine> lines,
    required double subtotal,
    required double tax,
    required double discount,
    required double grandTotal,
    bool testBanner = false,
  }) async {
    final profile = await ReceiptProfile.load();
    final bytes = await EscPosReceiptBuilder.build(
      profile: profile,
      saleId: saleId,
      lines: lines,
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      grandTotal: grandTotal,
      testBanner: testBanner,
    );
    await printBytes(bytes);
  }
}
