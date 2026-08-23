import 'thermal_bridge_stub.dart'
    if (dart.library.io) 'thermal_bridge_io.dart' as impl;

class ThermalDevice {
  final String name;
  final String mac;

  const ThermalDevice({required this.name, required this.mac});
}

class ThermalBridge {
  static Future<bool> bluetoothOn() => impl.bluetoothOn();

  static Future<bool> permissionGranted() => impl.permissionGranted();

  /// Shows the Android/iOS Nearby devices (Bluetooth) prompt when needed.
  static Future<bool> requestPermission() => impl.requestPermission();

  static Future<void> openAppSettings() => impl.openSystemAppSettings();

  static Future<bool> connectionStatus() => impl.connectionStatus();

  static Future<List<ThermalDevice>> pairedDevices() async {
    final devices = await impl.pairedDevices();
    return [
      for (final device in devices)
        ThermalDevice(name: device.name, mac: device.mac),
    ];
  }

  static Future<bool> connect(String mac) => impl.connect(mac);

  static Future<bool> disconnect() => impl.disconnect();

  static Future<bool> writeBytes(List<int> bytes) => impl.writeBytes(bytes);
}
