import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/api_config.dart';
import '../services/backup_service.dart';
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
          await ItemImportService().exportGridWorkbookForLocation(locationId);
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
            'Excel backup saved from shop server to:\n$path\n\n'
            'This file includes the menu grid and all saved combos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Excel backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    if (ApiConfig.enabled) {
      await _downloadExcelBackup();
      return;
    }
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose folder to save backup',
    );
    if (folder == null) return;

    setState(() {
      _busy = true;
      _lastMessage = null;
    });
    try {
      final path = await BackupService.instance.backupToFolder(folder);
      if (!mounted) return;
      setState(() => _lastMessage = 'Backup saved to:\n$path');
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (ApiConfig.enabled) {
      setState(() {
        _lastMessage =
            'This app uses the shop server. A local restopos.db file cannot replace VPS data.';
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces the current items, stock, and sales with the backup. '
          'It cannot be undone. Close and reopen the app after restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose restopos.db from a backup folder',
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    if (picked == null ||
        picked.files.isEmpty ||
        picked.files.first.path == null) {
      return;
    }

    setState(() {
      _busy = true;
      _lastMessage = null;
    });
    try {
      await BackupService.instance.restoreFromPath(picked.files.first.path!);
      if (!mounted) return;
      setState(() {
        _lastMessage =
            'Restore finished. Close this app and open it again to load the backup.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Restore failed: $e');
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
            'Backup & Restore',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            ApiConfig.enabled
                ? 'Shop data is stored on the VPS. Use Excel backup to save the menu grid '
                  'and combos from the server. The folder backup below only works for local mode.'
                : 'Backup copies the shop database (items, stock, sales) into a folder you pick. '
                  'Restore puts that copy back. Excel import only updates the item list.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _backup,
            icon: Icon(
              ApiConfig.enabled
                  ? Icons.download_outlined
                  : Icons.folder_copy_outlined,
            ),
            label: Text(
              ApiConfig.enabled
                  ? 'Download Excel backup (menu + combos)'
                  : 'Backup — choose folder',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restore — choose restopos.db'),
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
