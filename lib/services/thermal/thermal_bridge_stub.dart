class ThermalDevice {
  final String name;
  final String mac;

  const ThermalDevice({required this.name, required this.mac});
}

Future<bool> bluetoothOn() async => false;

Future<bool> permissionGranted() async => false;

Future<bool> requestPermission() async => false;

Future<void> openSystemAppSettings() async {}

Future<bool> connectionStatus() async => false;

Future<List<ThermalDevice>> pairedDevices() async => const [];

Future<bool> connect(String mac) async => false;

Future<bool> disconnect() async => false;

Future<bool> writeBytes(List<int> bytes) async => false;
