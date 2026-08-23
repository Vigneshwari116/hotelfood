import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../database/remote_db_config.dart';
import '../services/backup_service.dart';
import '../widgets/responsive_shell.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _lastMessage;

  Future<void> _backup() async {
    if (await RemoteDbConfig.isEnabled()) {
      setState(() {
        _lastMessage =
            'This device is using the VPS database. Shop data is already on the server. '
            'Use DBeaver / pg_dump on shilpa_enterprise for a server backup.';
      });
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
    if (await RemoteDbConfig.isEnabled()) {
      setState(() {
        _lastMessage =
            'Turn off VPS mode before restoring a local restopos.db file. '
            'Server data is not replaced by a phone SQLite backup.';
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
            'Backup copies the shop database (items, stock, sales) into a folder you pick. '
            'Restore puts that copy back. Excel import only updates the item list.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.folder_copy_outlined),
            label: const Text('Backup — choose folder'),
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
