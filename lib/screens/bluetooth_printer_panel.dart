import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/receipt_document.dart';
import 'package:foodstock/services/thermal/thermal_bridge.dart';

class BluetoothPrinterPanel extends StatefulWidget {
  const BluetoothPrinterPanel({super.key});

  @override
  State<BluetoothPrinterPanel> createState() =>
      _BluetoothPrinterPanelState();
}

class _BluetoothPrinterPanelState extends State<BluetoothPrinterPanel> {
  SavedThermalPrinter? _saved;
  List<ThermalDevice> _devices = [];

  bool _loading = true;
  bool _scanning = false;
  bool _printing = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await BluetoothThermalPrinter.loadSaved();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loading = false;
    });
    await _askPermission();
  }

  Future<void> _askPermission() async {
    try {
      await BluetoothThermalPrinter.ensurePermission();
      if (!mounted) return;
      setState(() {
        _permissionDenied = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
      });
    }
  }

  Future<void> _openAppSettings() async {
    await ThermalBridge.openAppSettings();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
    });
    try {
      final devices = await BluetoothThermalPrinter.scan();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _scanning = false;
        _permissionDenied = false;
      });
      if (devices.isEmpty) {
        _toast(
          'No paired printers found. On the phone, pair POSiFLOW / PSFKP206 in Bluetooth settings first, then scan here.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _permissionDenied = e.toString().contains('Nearby devices');
      });
      _toast(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _select(ThermalDevice device) async {
    await BluetoothThermalPrinter.save(device);
    if (!mounted) return;
    setState(() {
      _saved = SavedThermalPrinter(name: device.name, mac: device.mac);
    });
    _toast('${device.name} saved. Paper set to 58mm.', ok: true);
  }

  Future<void> _clear() async {
    await BluetoothThermalPrinter.clear();
    if (!mounted) return;
    setState(() {
      _saved = null;
    });
    _toast('Bluetooth printer cleared.');
  }

  Future<void> _testPrint() async {
    if (_saved == null) {
      _toast('Select the POSiFLOW printer first.');
      return;
    }
    setState(() {
      _printing = true;
    });
    try {
      await BluetoothThermalPrinter.printSale(
        document: ReceiptDocument(
          saleId: 11,
          lines: [
            CartLine(name: 'Veg Burger', qty: 1, price: 478),
            CartLine(name: 'Chicken Burger', qty: 1, price: 50),
          ],
          paymentType: 'Cash',
          subtotal: 528,
          tax: 26.4,
          discount: 0,
          grandTotal: 554.4,
          customerName: 'Test Customer',
          customerPhone: '9876543210',
        ),
        testBanner: true,
      );
      if (!mounted) return;
      _toast('Test bill sent to ${_saved!.name}.', ok: true);
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  void _toast(String message, {bool ok = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phone printer (POSiFLOW 58mm)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Do not type printer commands. Pair Bluetooth on the phone, then pick the printer here.',
                  style: TextStyle(
                    color: Colors.teal.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Switch the POSiFLOW printer on.\n'
                  '2. Phone Settings → Bluetooth → pair POSiFLOW / PSFKP206 '
                  '(PIN is usually 0000 or 1234).\n'
                  '3. Open this screen. When Android asks for Nearby devices, tap Allow.\n'
                  '4. Tap Scan paired, select the printer, then Test 58mm bill.',
                  style: TextStyle(
                    color: Colors.teal.shade900,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                if (_permissionDenied) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          BluetoothThermalPrinter.permissionDeniedMessage,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _askPermission,
                              child: const Text('Ask again'),
                            ),
                            FilledButton(
                              onPressed: _openAppSettings,
                              child: const Text('Open app settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_saved == null)
                  const Text('No Bluetooth printer selected')
                else
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_connected, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_saved!.name}\n${_saved!.mac}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _clear,
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bluetooth_searching),
                        label: Text(_scanning ? 'Scanning...' : 'Scan paired'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _printing || _saved == null ? null : _testPrint,
                        icon: const Icon(Icons.print),
                        label: Text(_printing ? 'Printing...' : 'Test 58mm bill'),
                      ),
                    ),
                  ],
                ),
                if (_devices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Paired devices',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  for (final device in _devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _saved?.mac == device.mac
                            ? Icons.check_circle
                            : Icons.print,
                        color: _saved?.mac == device.mac
                            ? Colors.green
                            : null,
                      ),
                      title: Text(device.name.isEmpty ? 'Printer' : device.name),
                      subtitle: Text(device.mac),
                      onTap: () => _select(device),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
