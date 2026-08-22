import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ThermalDevice {
  final String name;
  final String mac;

  const ThermalDevice({required this.name, required this.mac});
}

Future<bool> bluetoothOn() {
  return PrintBluetoothThermal.bluetoothEnabled;
}

Future<bool> permissionGranted() {
  return PrintBluetoothThermal.isPermissionBluetoothGranted;
}

Future<bool> connectionStatus() {
  return PrintBluetoothThermal.connectionStatus;
}

Future<List<ThermalDevice>> pairedDevices() async {
  final devices = await PrintBluetoothThermal.pairedBluetooths;
  return [
    for (final device in devices)
      ThermalDevice(
        name: device.name,
        mac: device.macAdress,
      ),
  ];
}

Future<bool> connect(String mac) {
  return PrintBluetoothThermal.connect(macPrinterAddress: mac);
}

Future<bool> disconnect() {
  return PrintBluetoothThermal.disconnect;
}

Future<bool> writeBytes(List<int> bytes) {
  return PrintBluetoothThermal.writeBytes(bytes);
}
