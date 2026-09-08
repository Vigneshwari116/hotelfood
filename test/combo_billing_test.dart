import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_layout.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Combo.resolveStoredPrice', () {
    test('prefers price when it is set', () {
      expect(
        Combo.resolveStoredPrice({
          'price': 210,
          'selling_price': 60,
        }),
        210,
      );
    });

    test('falls back to selling_price when price is zero', () {
      expect(
        Combo.resolveStoredPrice({
          'price': 0,
          'selling_price': 210,
        }),
        210,
      );
    });
  });

  test('combo receipt shows combo line at combo price with item names', () {
    final lines = expandReceiptLines([
      CartLine(
        comboId: 1,
        name: 'Star burger combo',
        componentLabels: const [
          'Burger Bun With Sesame',
          'Crispy Chicken Patty',
        ],
        qty: 1,
        price: 210,
      ),
    ]);

    expect(lines.length, 3);
    expect(lines.first.label, 'Star burger combo');
    expect(lines.first.amount, 210);
    expect(lines[1].label, '  Burger Bun With Sesame');
    expect(lines[1].amount, isNull);
    expect(lines[2].label, '  Crispy Chicken Patty');
    expect(lines[2].amount, isNull);

    final subtotal = lines
        .where((line) => line.amount != null)
        .fold<double>(0, (sum, line) => sum + line.amount!);
    expect(subtotal, 210);
  });

  test('raw material receipt shows item name not stock name', () {
    final lines = expandReceiptLines([
      CartLine(
        rawMaterialId: 5,
        name: 'star burger',
        subItem: 'Crispy Chicken Patty',
        qty: 2,
        price: 85,
      ),
    ]);

    expect(lines.length, 1);
    expect(lines.single.label, 'star burger');
    expect(lines.single.amount, 170);
  });

  group('normalizeCheckoutLines', () {
    late Database database;
    late SqliteAppDb appDb;

    setUp(() async {
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          final now = DateTime.now().toIso8601String();
          await db.execute('''
            CREATE TABLE combos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              price REAL NOT NULL DEFAULT 0,
              selling_price REAL NOT NULL DEFAULT 0,
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
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              selling_price REAL,
              qty_needed REAL NOT NULL DEFAULT 1,
              current_stock REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('raw_materials', {
            'name': 'Burger Bun With Sesame',
            'sub_item': 'Bun',
            'selling_price': 0,
            'current_stock': 20,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'name': 'Crispy Chicken Patty',
            'sub_item': 'Crispy Chicken Patty',
            'selling_price': 60,
            'current_stock': 20,
            'created_at': now,
          });
          await db.insert('combos', {
            'name': 'Star burger combo',
            'price': 0,
            'selling_price': 210,
            'created_at': now,
          });
          await db.insert('combo_raw_materials', {
            'combo_id': 1,
            'raw_material_id': 1,
            'qty': 1,
          });
          await db.insert('combo_raw_materials', {
            'combo_id': 1,
            'raw_material_id': 2,
            'qty': 1,
          });
        },
      );

      appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      Repository.instance.bindSession(
        role: 'location',
        locationId: 1,
        locationName: 'Test location',
      );
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      Repository.instance.bindSession(role: 'admin');
      await database.close();
    });

    test('uses combo price instead of component selling prices', () async {
      final normalized = await Repository.instance.normalizeCheckoutLines([
        CartLine(
          comboId: 1,
          name: 'Star burger combo',
          componentLabels: const [
            'Burger Bun With Sesame',
            'Crispy Chicken Patty',
          ],
          qty: 1,
          price: 60,
        ),
      ]);

      expect(normalized.length, 1);
      expect(normalized.single.comboId, 1);
      expect(normalized.single.price, 210);
      expect(normalized.single.amount, 210);

      final receiptLines = expandReceiptLines(normalized);
      expect(receiptLines.first.amount, 210);
      expect(
        receiptLines
            .where((line) => line.amount != null)
            .fold<double>(0, (sum, line) => sum + line.amount!),
        210,
      );
    });
  });
}
