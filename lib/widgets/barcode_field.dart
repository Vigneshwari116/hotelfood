import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';


class BarcodeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool isDense;

  const BarcodeField({
    super.key,
    required this.controller,
    this.label = 'Barcode',
    this.onSubmitted,
    this.isDense = false,
  });

  bool get _canUseCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        isDense: isDense,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.qr_code_scanner),
        suffixIcon: _canUseCamera
            ? IconButton(
          icon: const Icon(Icons.camera_alt),
          tooltip: 'Scan with camera',
          onPressed: () async {
            final code = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const _ScannerPage()),
            );
            if (code != null) {
              controller.text = code;
              onSubmitted?.call(code);
            }
          },
        )
            : null,
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _ScannerPage extends StatelessWidget {
  const _ScannerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            Navigator.pop(context, barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}
