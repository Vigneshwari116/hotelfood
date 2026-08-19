import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  DBHelper._();

  static final DBHelper instance = DBHelper._();

  static Database? _db;

  // ============================================================
  // DESKTOP CHECK
  // ============================================================

  static bool get _isDesktop =>
      !kIsWeb &&
          (Platform.isWindows ||
              Platform.isLinux ||
              Platform.isMacOS);

  // ============================================================
  // INITIALIZE SQLITE FFI FOR DESKTOP
  // ============================================================

  static void init() {
    if (_isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  // ============================================================
  // DATABASE INSTANCE
  // ============================================================

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  // ============================================================
  // DATABASE INITIALIZATION
  // ============================================================

  Future<Database> _initDb() async {
    final dir = await getApplicationSupportDirectory();

    final dbPath = join(
      dir.path,
      'restopos.db',
    );

    return openDatabase(
      dbPath,

      // ========================================================
      // DATABASE VERSION
      // ========================================================
      //
      // Version 10
      //
      // Architecture:
      //
      // raw_materials
      //      |
      //      +---- sale_items
      //      |
      //      +---- combo_items ---- combos
      //
      // There are NO:
      //
      // menu_items
      // recipe_items
      //
      // Combos are built directly from raw materials.
      //
      version: 10,

      onConfigure: (db) async {
        await db.execute(
          'PRAGMA foreign_keys = ON',
        );
      },

      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ============================================================
  // DATABASE CREATION
  // ============================================================

  Future<void> _onCreate(
      Database db,
      int version,
      ) async {
    final batch = db.batch();

    // ==========================================================
    // USERS
    // ==========================================================

    batch.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'admin',
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // CATEGORIES
    // ==========================================================
    //
    // Categories are only for raw materials.
    //
    // Examples:
    //
    // Frozen Snacks
    // Vegetables
    // Dairy
    // Beverages
    // Grocery
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL DEFAULT 'raw_material'
      )
    ''');

    // ==========================================================
    // UNITS
    // ==========================================================

    batch.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        short_code TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // SUPPLIERS
    // ==========================================================

    batch.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT,
        city TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // CUSTOMERS
    // ==========================================================

    batch.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        credit_limit REAL NOT NULL DEFAULT 0,
        opening_balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // RAW MATERIALS
    // ==========================================================
    //
    // This is the MAIN ITEM MASTER.
    //
    // Every sellable item is a raw material.
    //
    // Examples:
    //
    // Chicken Popcorn
    // French Fries
    // Chicken Burger
    // Coke
    // Chicken Momos
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE raw_materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        barcode TEXT UNIQUE,

        name TEXT NOT NULL,

        category_id INTEGER,

        unit_id INTEGER,

        image_path TEXT,

        opening_stock REAL NOT NULL DEFAULT 0,

        current_stock REAL NOT NULL DEFAULT 0,

        reorder_level REAL NOT NULL DEFAULT 0,

        shelf_life_days INTEGER,

        units_per_packet REAL,

        entry_password_hash TEXT,

        cost_price REAL,

        selling_price REAL,

        created_at TEXT NOT NULL,

        FOREIGN KEY (category_id)
          REFERENCES categories (id),

        FOREIGN KEY (unit_id)
          REFERENCES units (id)
      )
    ''');

    // ==========================================================
    // STOCK BATCHES
    // ==========================================================
    //
    // Used for FEFO.
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE stock_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        raw_material_id INTEGER NOT NULL,

        qty_remaining REAL NOT NULL,

        rate REAL,

        expiry_date TEXT,

        purchase_item_id INTEGER,

        created_at TEXT NOT NULL,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_stock_batches_fefo
      ON stock_batches (
        raw_material_id,
        expiry_date
      )
    ''');

    // ==========================================================
    // PURCHASES
    // ==========================================================

    batch.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        supplier_id INTEGER,

        invoice_no TEXT,

        purchase_date TEXT NOT NULL,

        total_amount REAL NOT NULL DEFAULT 0,

        notes TEXT,

        FOREIGN KEY (supplier_id)
          REFERENCES suppliers (id)
      )
    ''');

    // ==========================================================
    // PURCHASE ITEMS
    // ==========================================================

    batch.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        purchase_id INTEGER NOT NULL,

        raw_material_id INTEGER NOT NULL,

        qty REAL NOT NULL,

        rate REAL NOT NULL,

        amount REAL NOT NULL,

        expiry_date TEXT,

        FOREIGN KEY (purchase_id)
          REFERENCES purchases (id)
          ON DELETE CASCADE,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
      )
    ''');

    // ==========================================================
    // STOCK ADJUSTMENTS
    // ==========================================================

    batch.execute('''
      CREATE TABLE stock_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        raw_material_id INTEGER NOT NULL,

        adjust_date TEXT NOT NULL,

        qty REAL NOT NULL,

        reason TEXT,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
      )
    ''');

    // ==========================================================
    // STOCK LEDGER
    // ==========================================================

    batch.execute('''
      CREATE TABLE stock_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        raw_material_id INTEGER NOT NULL,

        entry_date TEXT NOT NULL,

        ref_type TEXT NOT NULL,

        ref_id INTEGER,

        qty_in REAL NOT NULL DEFAULT 0,

        qty_out REAL NOT NULL DEFAULT 0,

        unit_cost REAL,

        balance_after REAL NOT NULL,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
      )
    ''');

    // ==========================================================
    // SALES
    // ==========================================================
    //
    // Sales point directly to raw materials through sale_items.
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        customer_id INTEGER,

        sale_date TEXT NOT NULL,

        subtotal REAL NOT NULL,

        tax REAL NOT NULL DEFAULT 0,

        discount REAL NOT NULL DEFAULT 0,

        total REAL NOT NULL,

        payment_type TEXT NOT NULL,

        is_voided INTEGER NOT NULL DEFAULT 0,

        voided_reason TEXT,

        voided_at TEXT,

        FOREIGN KEY (customer_id)
          REFERENCES customers (id)
      )
    ''');

    // ==========================================================
    // SALE ITEMS
    // ==========================================================
    //
    // Every sale line points directly to raw_materials.
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        sale_id INTEGER NOT NULL,

        raw_material_id INTEGER NOT NULL,

        item_name TEXT NOT NULL,

        qty REAL NOT NULL,

        price REAL NOT NULL,

        amount REAL NOT NULL,

        FOREIGN KEY (sale_id)
          REFERENCES sales (id)
          ON DELETE CASCADE,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
      )
    ''');

    // ==========================================================
    // COMBOS
    // ==========================================================
    //
    // A combo is a collection of RAW MATERIALS.
    //
    // Example:
    //
    // Chicken Snack Box
    //
    //   Chicken Popcorn  x 1
    //   French Fries     x 1
    //   Coke             x 1
    //
    // There is NO menu_items relationship.
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE combos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        name TEXT NOT NULL UNIQUE,

        image_path TEXT,

        selling_price REAL NOT NULL DEFAULT 0,

        is_active INTEGER NOT NULL DEFAULT 1,

        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // COMBO ITEMS
    // ==========================================================
    //
    // Each combo contains raw materials directly.
    //
    // combo_items
    //      |
    //      +-- combo_id
    //      |
    //      +-- raw_material_id
    //      |
    //      +-- qty
    //
    // ==========================================================

    batch.execute('''
      CREATE TABLE combo_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        combo_id INTEGER NOT NULL,

        raw_material_id INTEGER NOT NULL,

        qty REAL NOT NULL DEFAULT 1,

        FOREIGN KEY (combo_id)
          REFERENCES combos (id)
          ON DELETE CASCADE,

        FOREIGN KEY (raw_material_id)
          REFERENCES raw_materials (id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // CUSTOMER LEDGER
    // ==========================================================

    batch.execute('''
      CREATE TABLE customer_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        customer_id INTEGER NOT NULL,

        entry_date TEXT NOT NULL,

        type TEXT NOT NULL,

        amount REAL NOT NULL,

        balance_after REAL NOT NULL,

        ref_sale_id INTEGER,

        FOREIGN KEY (customer_id)
          REFERENCES customers (id)
      )
    ''');

    // ==========================================================
    // INDEXES
    // ==========================================================

    batch.execute('''
      CREATE INDEX idx_raw_materials_name
      ON raw_materials(name)
    ''');

    batch.execute('''
      CREATE INDEX idx_raw_materials_barcode
      ON raw_materials(barcode)
    ''');

    batch.execute('''
      CREATE INDEX idx_sale_items_sale
      ON sale_items(sale_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_sale_items_material
      ON sale_items(raw_material_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_purchase_items_purchase
      ON purchase_items(purchase_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_stock_ledger_material
      ON stock_ledger(raw_material_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_customer_ledger_customer
      ON customer_ledger(customer_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_combo_items_combo
      ON combo_items(combo_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_combo_items_material
      ON combo_items(raw_material_id)
    ''');

    // ==========================================================
    // CREATE ALL TABLES
    // ==========================================================

    await batch.commit(
      noResult: true,
    );

    // ==========================================================
    // NO DEFAULT DATA
    // ==========================================================
    //
    // Categories, units, suppliers, raw materials and combos
    // start empty.
    //
  }

  // ============================================================
  // DATABASE UPGRADE
  // ============================================================

  Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    // ==========================================================
    // VERSION 1 -> 2
    // ==========================================================

    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE stock_batches ADD COLUMN rate REAL',
      );

      await db.execute(
        'ALTER TABLE stock_ledger ADD COLUMN unit_cost REAL',
      );

      await db.execute(
        '''
        CREATE INDEX IF NOT EXISTS idx_stock_batches_fefo
        ON stock_batches (
          raw_material_id,
          expiry_date
        )
        ''',
      );
    }

    // ==========================================================
    // VERSION 2 -> 3
    // ==========================================================

    if (oldVersion < 3) {
      await db.execute(
        '''
        ALTER TABLE sales
        ADD COLUMN is_voided
        INTEGER NOT NULL DEFAULT 0
        ''',
      );

      await db.execute(
        '''
        ALTER TABLE sales
        ADD COLUMN voided_reason TEXT
        ''',
      );

      await db.execute(
        '''
        ALTER TABLE sales
        ADD COLUMN voided_at TEXT
        ''',
      );
    }

    // ==========================================================
    // VERSION 3 -> 4
    // ==========================================================
    //
    // Historical version.
    //
    // No default category seeding.
    //
    // ==========================================================

    if (oldVersion < 4) {
      // Intentionally empty.
    }

    // ==========================================================
    // VERSION 4 -> 5
    // ==========================================================

    if (oldVersion < 5) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(suppliers)',
      );

      final columnNames = columns
          .map((c) => c['name'] as String)
          .toSet();

      if (columnNames.contains('contact') &&
          !columnNames.contains('mobile')) {
        await db.execute(
          'ALTER TABLE suppliers RENAME COLUMN contact TO mobile',
        );
      } else if (!columnNames.contains('mobile')) {
        await db.execute(
          'ALTER TABLE suppliers ADD COLUMN mobile TEXT',
        );
      }

      if (columnNames.contains('address') &&
          !columnNames.contains('city')) {
        await db.execute(
          'ALTER TABLE suppliers RENAME COLUMN address TO city',
        );
      } else if (!columnNames.contains('city')) {
        await db.execute(
          'ALTER TABLE suppliers ADD COLUMN city TEXT',
        );
      }
    }

    // ==========================================================
    // VERSION 5 -> 6
    // ==========================================================

    if (oldVersion < 6) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(raw_materials)',
      );

      final columnNames = columns
          .map((c) => c['name'] as String)
          .toSet();

      if (!columnNames.contains('units_per_packet')) {
        await db.execute(
          '''
          ALTER TABLE raw_materials
          ADD COLUMN units_per_packet REAL
          ''',
        );
      }
    }

    // ==========================================================
    // VERSION 6 -> 7
    // ==========================================================
    //
    // Historical factory reset.
    //
    // This migration is retained for databases that were using
    // the previous application versions.
    //
    // ==========================================================

    if (oldVersion < 7) {
      await db.delete('sale_items');
      await db.delete('sales');

      await db.delete('customer_ledger');
      await db.delete('customers');

      // These tables existed in the old architecture.
      await db.delete('combo_items');
      await db.delete('combos');

      await db.delete('recipe_items');
      await db.delete('menu_items');

      await db.delete('stock_ledger');
      await db.delete('stock_adjustments');

      await db.delete('purchase_items');
      await db.delete('purchases');

      await db.delete('stock_batches');
      await db.delete('raw_materials');

      await db.delete('units');
      await db.delete('categories');
      await db.delete('suppliers');

      await db.delete(
        'sqlite_sequence',
        where: '''
          name IN (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?
          )
        ''',
        whereArgs: [
          'sale_items',
          'sales',
          'customer_ledger',
          'customers',
          'combo_items',
          'combos',
          'recipe_items',
          'menu_items',
          'stock_ledger',
          'stock_adjustments',
          'purchase_items',
          'purchases',
          'stock_batches',
          'raw_materials',
          'units',
          'categories',
          'suppliers',
        ],
      );
    }

    // ==========================================================
    // VERSION 7 -> 8
    // ==========================================================

    if (oldVersion < 8) {
      final columns = await db.rawQuery(
        'PRAGMA table_info(raw_materials)',
      );

      final columnNames = columns
          .map((c) => c['name'] as String)
          .toSet();

      if (!columnNames.contains('cost_price')) {
        await db.execute(
          '''
          ALTER TABLE raw_materials
          ADD COLUMN cost_price REAL
          ''',
        );
      }

      if (!columnNames.contains('selling_price')) {
        await db.execute(
          '''
          ALTER TABLE raw_materials
          ADD COLUMN selling_price REAL
          ''',
        );
      }
    }

    // ==========================================================
    // VERSION 8 -> 9
    // ==========================================================
    //
    // Major architecture change.
    //
    // OLD:
    //
    // raw_materials
    //      |
    // recipe_items
    //      |
    // menu_items
    //      |
    // combo_items
    //      |
    // combos
    //
    // NEW:
    //
    // raw_materials
    //      |
    //      +---- sale_items
    //      |
    //      +---- combo_items
    //                   |
    //                   +---- combos
    //
    // Menu items and recipes are removed.
    //
    // Existing sale-item relationships cannot be converted because
    // they depended on the old menu/recipe architecture.
    //
    // Therefore sale_items is rebuilt.
    //
    // ==========================================================

    if (oldVersion < 9) {
      // --------------------------------------------------------
      // DROP OLD SALE ITEMS
      // --------------------------------------------------------

      await db.execute(
        'DROP TABLE IF EXISTS sale_items',
      );

      // --------------------------------------------------------
      // DROP OLD COMBO ITEMS
      // --------------------------------------------------------
      //
      // The old combo_items table could reference menu_items.
      // It is recreated in version 10 with raw_material_id.
      //
      // --------------------------------------------------------

      await db.execute(
        'DROP TABLE IF EXISTS combo_items',
      );

      // --------------------------------------------------------
      // DROP OLD RECIPE ITEMS
      // --------------------------------------------------------

      await db.execute(
        'DROP TABLE IF EXISTS recipe_items',
      );

      // --------------------------------------------------------
      // DROP OLD COMBOS
      // --------------------------------------------------------
      //
      // Old combos could be based on menu items.
      // They are recreated in version 10.
      //
      // --------------------------------------------------------

      await db.execute(
        'DROP TABLE IF EXISTS combos',
      );

      // --------------------------------------------------------
      // DROP OLD MENU ITEMS
      // --------------------------------------------------------

      await db.execute(
        'DROP TABLE IF EXISTS menu_items',
      );

      // --------------------------------------------------------
      // RECREATE SALE ITEMS
      // --------------------------------------------------------

      await db.execute('''
        CREATE TABLE sale_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,

          sale_id INTEGER NOT NULL,

          raw_material_id INTEGER NOT NULL,

          item_name TEXT NOT NULL,

          qty REAL NOT NULL,

          price REAL NOT NULL,

          amount REAL NOT NULL,

          FOREIGN KEY (sale_id)
            REFERENCES sales (id)
            ON DELETE CASCADE,

          FOREIGN KEY (raw_material_id)
            REFERENCES raw_materials (id)
        )
      ''');

      // --------------------------------------------------------
      // SALE ITEM INDEXES
      // --------------------------------------------------------

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sale_items_sale
        ON sale_items(sale_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sale_items_material
        ON sale_items(raw_material_id)
      ''');

      // --------------------------------------------------------
      // RAW MATERIAL IMAGE
      // --------------------------------------------------------

      final rawMaterialColumns = await db.rawQuery(
        'PRAGMA table_info(raw_materials)',
      );

      final rawMaterialColumnNames = rawMaterialColumns
          .map((c) => c['name'] as String)
          .toSet();

      if (!rawMaterialColumnNames.contains('image_path')) {
        await db.execute(
          '''
          ALTER TABLE raw_materials
          ADD COLUMN image_path TEXT
          ''',
        );
      }
    }

    // ==========================================================
    // VERSION 9 -> 10
    // ==========================================================
    //
    // RESTORE COMBOS USING THE NEW ARCHITECTURE.
    //
    // Combos now belong to Raw Materials.
    //
    // combo_items.raw_material_id
    //
    // There is NO menu_item_id.
    //
    // ==========================================================

    if (oldVersion < 10) {
      // --------------------------------------------------------
      // CREATE COMBOS
      // --------------------------------------------------------

      await db.execute('''
        CREATE TABLE IF NOT EXISTS combos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,

          name TEXT NOT NULL UNIQUE,

          image_path TEXT,

          selling_price REAL NOT NULL DEFAULT 0,

          is_active INTEGER NOT NULL DEFAULT 1,

          created_at TEXT NOT NULL
        )
      ''');

      // --------------------------------------------------------
      // CREATE COMBO ITEMS
      // --------------------------------------------------------

      await db.execute('''
        CREATE TABLE IF NOT EXISTS combo_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,

          combo_id INTEGER NOT NULL,

          raw_material_id INTEGER NOT NULL,

          qty REAL NOT NULL DEFAULT 1,

          FOREIGN KEY (combo_id)
            REFERENCES combos (id)
            ON DELETE CASCADE,

          FOREIGN KEY (raw_material_id)
            REFERENCES raw_materials (id)
            ON DELETE CASCADE
        )
      ''');

      // --------------------------------------------------------
      // CREATE COMBO INDEXES
      // --------------------------------------------------------

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_combo_items_combo
        ON combo_items(combo_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_combo_items_material
        ON combo_items(raw_material_id)
      ''');
    }
  }

  // ============================================================
  // CLOSE DATABASE
  // ============================================================

  Future<void> close() async {
    final db = _db;

    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
