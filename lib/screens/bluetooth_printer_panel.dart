import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/receipt_profile.dart';
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

  final _shopController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shopController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await BluetoothThermalPrinter.loadSaved();
    final profile = await ReceiptProfile.load();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _shopController.text = profile.shopName;
      _addressController.text = profile.address;
      _phoneController.text = profile.phone;
      _emailController.text = profile.email;
      _loading = false;
    });
  }

  Future<void> _saveProfile() async {
    final profile = ReceiptProfile(
      shopName: _shopController.text,
      address: _addressController.text,
      phone: _phoneController.text,
      email: _emailController.text,
    );
    await profile.save();
    if (!mounted) return;
    _toast('Bill header saved.', ok: true);
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
        saleId: 11,
        lines: [
          CartLine(name: 'Veg Burger', qty: 1, price: 478),
          CartLine(name: 'Chicken Burger', qty: 1, price: 50),
        ],
        subtotal: 528,
        tax: 26.4,
        discount: 0,
        grandTotal: 554.4,
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
                  'No vendor driver is required. This printer speaks ESC/POS over Bluetooth. '
                  'Pair PSFKP206 in the phone Bluetooth list, then select it below.',
                  style: TextStyle(
                    color: Colors.teal.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bill header',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Printed at the top of the 58mm slip, like the FIVE STAR sample.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _shopController,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saveProfile,
                    child: const Text('Save header'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
