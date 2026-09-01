import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openTestDb() {
    return openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER,
            sale_date TEXT NOT NULL,
            subtotal REAL NOT NULL,
            tax REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            total REAL NOT NULL,
            payment_type TEXT NOT NULL,
            is_voided INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sub_item TEXT,
            current_stock REAL NOT NULL DEFAULT 0,
            qty_needed REAL NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            raw_material_id INTEGER,
            combo_id INTEGER,
            item_name TEXT NOT NULL,
            sub_item TEXT,
            qty REAL NOT NULL,
            price REAL NOT NULL,
            amount REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE combos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE combo_raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            combo_id INTEGER NOT NULL,
            raw_material_id INTEGER NOT NULL,
            qty REAL NOT NULL DEFAULT 1
          )
        ''');
      },
    );
  }

  test('sale_items accepts combo lines without raw_material_id', () async {
    final db = await openTestDb();

    await db.insert('sales', {
      'sale_date': DateTime.now().toIso8601String(),
      'subtotal': 100,
      'tax': 0,
      'discount': 0,
      'total': 100,
      'payment_type': 'cash',
    });

    await db.insert('combos', {
      'name': 'Snack Box',
      'price': 100,
      'created_at': DateTime.now().toIso8601String(),
    });

    final saleItemId = await db.insert('sale_items', {
      'sale_id': 1,
      'raw_material_id': null,
      'combo_id': 1,
      'item_name': 'Snack Box',
      'qty': 1,
      'price': 100,
      'amount': 100,
    });

    expect(saleItemId, greaterThan(0));

    final row = (await db.query(
      'sale_items',
      where: 'id = ?',
      whereArgs: [saleItemId],
    )).single;

    expect(row['raw_material_id'], isNull);
    expect(row['combo_id'], 1);

    await db.close();
  });

  test('combo component usage query reflects per-component quantities', () async {
    final db = await openTestDb();
    final now = DateTime.now().toIso8601String();

    await db.insert('raw_materials', {
      'name': 'Chicken',
      'current_stock': 10,
      'qty_needed': 1,
      'created_at': now,
    });
    await db.insert('raw_materials', {
      'name': 'Fries',
      'current_stock': 5,
      'qty_needed': 1,
      'created_at': now,
    });
    await db.insert('combos', {
      'name': 'Snack Box',
      'price': 100,
      'created_at': now,
    });
    await db.insert('combo_raw_materials', {
      'combo_id': 1,
      'raw_material_id': 1,
      'qty': 2,
    });
    await db.insert('combo_raw_materials', {
      'combo_id': 1,
      'raw_material_id': 2,
      'qty': 1,
    });
    await db.insert('sales', {
      'sale_date': now,
      'subtotal': 100,
      'tax': 0,
      'discount': 0,
      'total': 100,
      'payment_type': 'cash',
    });
    await db.insert('sale_items', {
      'sale_id': 1,
      'combo_id': 1,
      'item_name': 'Snack Box',
      'qty': 1,
      'price': 100,
      'amount': 100,
    });

    final rows = await db.rawQuery('''
      SELECT
        rm.name AS item_name,
        SUM(crm.qty * si.qty * COALESCE(rm.qty_needed, 1)) AS consumed_qty
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN combo_raw_materials crm ON crm.combo_id = si.combo_id
      JOIN raw_materials rm ON rm.id = crm.raw_material_id
      WHERE s.is_voided = 0
        AND si.combo_id IS NOT NULL
      GROUP BY rm.id, rm.name
      ORDER BY rm.name ASC
    ''');

    expect(rows.length, 2);
    expect(rows[0]['item_name'], 'Chicken');
    expect((rows[0]['consumed_qty'] as num).toDouble(), 2);
    expect(rows[1]['item_name'], 'Fries');
    expect((rows[1]['consumed_qty'] as num).toDouble(), 1);

    await db.close();
  });
}
