import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---------------------------------------------------------------------------
  // SQLite in-memory check
  // ---------------------------------------------------------------------------
  //
  // NOTE: SQLite does not enforce PostgreSQL's strict GROUP BY rule
  // (error 42803: selected columns must appear in GROUP BY or an aggregate).
  // The original production bug — selecting `si.sub_item` while grouping only
  // by `si.combo_id` and `COALESCE(si.sub_item, '')` — crashed on Postgres but
  // would still pass this SQLite execution test. Use the source-shape test below
  // as the real regression guard for that bug.
  //
  test('item sales combo query aggregates correctly in SQLite', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            is_voided INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            combo_id INTEGER,
            item_name TEXT NOT NULL,
            sub_item TEXT,
            qty REAL NOT NULL,
            amount REAL NOT NULL
          )
        ''');
      },
    );

    await db.insert('sales', {'is_voided': 0});
    await db.insert('sale_items', {
      'sale_id': 1,
      'combo_id': 1,
      'item_name': 'Snack Box',
      'sub_item': 'Large',
      'qty': 2,
      'amount': 200,
    });
    await db.insert('sale_items', {
      'sale_id': 1,
      'combo_id': 1,
      'item_name': 'Snack Box',
      'sub_item': null,
      'qty': 1,
      'amount': 100,
    });

    final rows = await db.rawQuery('''
      SELECT
        si.item_name AS item_name,
        MAX(si.sub_item) AS sub_item,
        SUM(si.qty) AS sold_qty,
        SUM(si.amount) AS total_amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.is_voided = 0
        AND si.combo_id IS NOT NULL
      GROUP BY si.combo_id, si.item_name
    ''');

    expect(rows.length, 1);
    expect((rows.first['sold_qty'] as num).toDouble(), 3);
    expect((rows.first['total_amount'] as num).toDouble(), 300);

    await db.close();
  });

  test(
    'itemSalesReport combo section uses Postgres-safe MAX(si.sub_item)',
    () {
      final source = File('lib/services/repository.dart').readAsStringSync();

      // Fixed query shape required on Postgres (GROUP BY si.combo_id, si.item_name).
      expect(
        source,
        contains('MAX(si.sub_item) AS sub_item'),
        reason:
            'combo rows must aggregate sub_item; bare si.sub_item breaks Postgres',
      );

      // Guard against reverting to the broken query that caused error 42803.
      expect(
        source,
        isNot(
          contains(
            "si.sub_item AS sub_item,\n        SUM(si.qty) AS sold_qty",
          ),
        ),
        reason: 'bare si.sub_item in grouped combo SELECT is not Postgres-safe',
      );
    },
  );
}
