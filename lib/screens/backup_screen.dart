import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/item_import_service.dart';
import '../services/repository.dart';
import '../widgets/responsive_shell.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _lastMessage;

  Future<void> _downloadExcelBackup() async {
    final locationId = Repository.instance.sessionLocationId;
    final locationName = Repository.instance.sessionLocationName;
    if (locationId == null || locationName == null) {
      setState(() {
        _lastMessage =
            'Log in with a location account to download menu and combo Excel backup.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _lastMessage = null;
    });

    try {
      final bytes =
          await ItemImportService().exportBackupWorkbookForLocation(locationId);
      final fileName = '$locationName backup.xlsx';
      String? path;
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save shop Excel backup',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
        );
      }
      path ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );
      if (!path.toLowerCase().endsWith('.xlsx')) {
        path = '$path.xlsx';
      }
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _lastMessage =
            'Excel backup saved to:\n$path\n\n'
            'This file has two sheets: "Menu Items" (grid) and "Combos" (grouped list).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Excel backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: ListView(
        children: [
          const Text(
            'Backup',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Download a copy of the menu grid and combos as an Excel workbook '
            'with two sheets: Menu Items and Combos.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _downloadExcelBackup,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download Excel backup (menu + combos)'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_lastMessage != null) ...[
            const SizedBox(height: 24),
            Text(_lastMessage!),
          ],
        ],
      ),
    );
  }
}
