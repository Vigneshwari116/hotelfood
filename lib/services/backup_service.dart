import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  Future<Directory> _dataDir() => getApplicationSupportDirectory();

  Future<String> backupToFolder(String folderPath) async {
    final db = await DBHelper.instance.database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}

    final dataDir = await _dataDir();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final dest = Directory(p.join(folderPath, 'Shilpa_backup_$stamp'));
    await dest.create(recursive: true);

    final dbFile = File(p.join(dataDir.path, 'restopos.db'));
    if (!await dbFile.exists()) {
      throw StateError('Database file was not found.');
    }
    await dbFile.copy(p.join(dest.path, 'restopos.db'));

    for (final extra in ['restopos.db-wal', 'restopos.db-shm']) {
      final f = File(p.join(dataDir.path, extra));
      if (await f.exists()) {
        await f.copy(p.join(dest.path, extra));
      }
    }

    final images = Directory(p.join(dataDir.path, 'images'));
    if (await images.exists()) {
      await _copyDirectory(images, Directory(p.join(dest.path, 'images')));
    }

    return dest.path;
  }

  Future<void> restoreFromPath(String sourcePath) async {
    final source = File(sourcePath);
    Directory backupDir;
    File dbSource;

    if (await FileSystemEntity.isDirectory(sourcePath)) {
      backupDir = Directory(sourcePath);
      dbSource = File(p.join(sourcePath, 'restopos.db'));
    } else {
      dbSource = source;
      backupDir = source.parent;
    }

    if (!await dbSource.exists()) {
      throw StateError('Choose a restopos.db file or a backup folder.');
    }

    await DBHelper.instance.close();

    final dataDir = await _dataDir();
    await Directory(dataDir.path).create(recursive: true);

    await dbSource.copy(p.join(dataDir.path, 'restopos.db'));

    for (final extra in ['restopos.db-wal', 'restopos.db-shm']) {
      final from = File(p.join(backupDir.path, extra));
      final to = File(p.join(dataDir.path, extra));
      if (await from.exists()) {
        await from.copy(to.path);
      } else if (await to.exists()) {
        await to.delete();
      }
    }

    final imageSrc = Directory(p.join(backupDir.path, 'images'));
    final imageDest = Directory(p.join(dataDir.path, 'images'));
    if (await imageSrc.exists()) {
      if (await imageDest.exists()) {
        await imageDest.delete(recursive: true);
      }
      await _copyDirectory(imageSrc, imageDest);
    }
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: from.path);
      final target = p.join(to.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
