import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/bluetooth_thermal_printer.dart';

void main() {
  test('permission denied copy tells the user to allow Nearby devices', () {
    expect(
      BluetoothThermalPrinter.permissionDeniedMessage,
      contains('Nearby devices'),
    );
    expect(
      BluetoothThermalPrinter.permissionDeniedMessage,
      contains('Allow'),
    );
  });
}
