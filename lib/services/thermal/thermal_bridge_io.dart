import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ThermalDevice {
  final String name;
  final String mac;

  const ThermalDevice({required this.name, required this.mac});
}

Future<bool> bluetoothOn() {
  return PrintBluetoothThermal.bluetoothEnabled;
}

Future<bool> permissionGranted() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return true;
  }
  if (Platform.isAndroid) {
    final connect = await Permission.bluetoothConnect.status;
    final scan = await Permission.bluetoothScan.status;
    final legacy = await Permission.bluetooth.status;
    if (connect.isGranted || scan.isGranted || legacy.isGranted) {
      return true;
    }
  }
  if (Platform.isIOS) {
    final status = await Permission.bluetooth.status;
    if (status.isGranted || status.isLimited) return true;
  }
  return PrintBluetoothThermal.isPermissionBluetoothGranted;
}

Future<bool> requestPermission() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return true;
  }
  if (Platform.isAndroid) {
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
    ].request();
    final connect = statuses[Permission.bluetoothConnect];
    final scan = statuses[Permission.bluetoothScan];
    final legacy = statuses[Permission.bluetooth];
    if (connect?.isGranted == true ||
        scan?.isGranted == true ||
        legacy?.isGranted == true) {
      return true;
    }
  }
  if (Platform.isIOS) {
    final status = await Permission.bluetooth.request();
    if (status.isGranted || status.isLimited) return true;
  }
  return permissionGranted();
}

Future<void> openSystemAppSettings() async {
  await openAppSettings();
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
