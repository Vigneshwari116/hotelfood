import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<double> bumpStock(
    Database db,
    int rawMaterialId,
    double delta,
  ) async {
    final rows = await db.query(
      'raw_materials',
      columns: ['current_stock'],
      where: 'id = ?',
      whereArgs: [rawMaterialId],
      limit: 1,
    );
    final current = (rows.first['current_stock'] as num).toDouble();
    final next = current + delta;
    final safeNext = next.abs() < 0.000001 ? 0.0 : next;
    await db.update(
      'raw_materials',
      {'current_stock': safeNext},
      where: 'id = ?',
      whereArgs: [rawMaterialId],
    );
    return safeNext;
  }

  Future<Database> openTestDb() {
    return openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            current_stock REAL NOT NULL DEFAULT 0,
            qty_needed REAL NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  test('sale can reduce stock below zero', () async {
    final db = await openTestDb();
    final now = DateTime.now().toIso8601String();

    await db.insert('raw_materials', {
      'name': 'Chicken',
      'current_stock': 0,
      'created_at': now,
    });

    final afterSale = await bumpStock(db, 1, -1);
    expect(afterSale, -1);

    await db.close();
  });

  test('purchase adds to negative stock instead of replacing it', () async {
    final db = await openTestDb();
    final now = DateTime.now().toIso8601String();

    await db.insert('raw_materials', {
      'name': 'Chicken',
      'current_stock': -1,
      'created_at': now,
    });

    final afterPurchase = await bumpStock(db, 1, 20);
    expect(afterPurchase, 19);

    await db.close();
  });

  test('repeated overselling continues into deeper negative stock', () async {
    final db = await openTestDb();
    final now = DateTime.now().toIso8601String();

    await db.insert('raw_materials', {
      'name': 'Chicken',
      'current_stock': 0,
      'created_at': now,
    });

    var stock = await bumpStock(db, 1, -1);
    expect(stock, -1);

    stock = await bumpStock(db, 1, -1);
    expect(stock, -2);

    await db.close();
  });
}
