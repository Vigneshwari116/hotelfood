// lib/services/repository.dart

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/model/models.dart';

// ============================================================
// PIN / PASSWORD
// ============================================================

String hashPin(String pin) {
      return sha256.convert(utf8.encode(pin)).toString();
}

// ============================================================
// EXCEPTIONS
// ============================================================

class InsufficientStockException implements Exception {
      final String materialName;
      final double needed;
      final double available;

      InsufficientStockException({
            required this.materialName,
            required this.needed,
            required this.available,
      });

      @override
      String toString() {
            return 'Not enough $materialName in stock '
                '(need ${needed.toStringAsFixed(2)}, '
                'have ${available.toStringAsFixed(2)})';
      }
}

class InvalidInventoryException implements Exception {
      final String message;

      InvalidInventoryException(this.message);

      @override
      String toString() => message;
}

// ============================================================
// REPOSITORY
// ============================================================

class Repository {
      Repository._();

      static final Repository instance = Repository._();

      Future<AppDb> get _db async {
            return DBHelper.instance.appDb;
      }

      // ============================================================
      // CATEGORIES
      // ============================================================

      Future<int> addCategory(Category category) async {
            final db = await _db;

            if (category.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Category name cannot be empty.',
                  );
            }

            return db.insert(
                  'categories',
                  category.toMap()..remove('id'),
            );
      }

      Future<List<Category>> categories({
            String? type,
      }) async {
            final db = await _db;

            final rows = await db.query(
                  'categories',
                  where: type == null ? null : 'type = ?',
                  whereArgs: type == null ? null : [type],
                  orderBy: 'name ASC',
            );

            return rows.map(Category.fromMap).toList();
      }

      Future<void> deleteCategory(int categoryId) async {
            final db = await _db;

            await db.transaction((txn) async {
                  final categoryRows = await txn.query(
                        'categories',
                        columns: ['id', 'name'],
                        where: 'id = ?',
                        whereArgs: [categoryId],
                        limit: 1,
                  );

                  if (categoryRows.isEmpty) {
                        throw InvalidInventoryException(
                              'Category does not exist.',
                        );
                  }

                  final categoryName =
                      categoryRows.first['name']?.toString() ?? 'Category';

                  // ----------------------------------------------------------
                  // RAW MATERIAL USAGE
                  // ----------------------------------------------------------

                  final rawMaterialRows = await txn.query(
                        'raw_materials',
                        columns: ['id'],
                        where: 'category_id = ?',
                        whereArgs: [categoryId],
                        limit: 1,
                  );

                  if (rawMaterialRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$categoryName cannot be deleted because it is used '
                                  'by one or more raw materials. Reassign or remove '
                                  'those items first.',
                        );
                  }

                  // ----------------------------------------------------------
                  // COMBO USAGE
                  // ----------------------------------------------------------

                  final comboRows = await txn.query(
                        'combos',
                        columns: ['id'],
                        where: 'category_id = ?',
                        whereArgs: [categoryId],
                        limit: 1,
                  );

                  if (comboRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$categoryName cannot be deleted because it is used '
                                  'by one or more combos. Reassign or remove '
                                  'those combos first.',
                        );
                  }

                  final deleted = await txn.delete(
                        'categories',
                        where: 'id = ?',
                        whereArgs: [categoryId],
                  );

                  if (deleted == 0) {
                        throw InvalidInventoryException(
                              'Unable to delete category.',
                        );
                  }
            });
      }

      // ============================================================
      // UNITS
      // ============================================================

      Future<int> addUnit(UnitM unit) async {
            final db = await _db;

            if (unit.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Unit name cannot be empty.',
                  );
            }

            return db.insert(
                  'units',
                  unit.toMap()..remove('id'),
            );
      }

      Future<List<UnitM>> units() async {
            final db = await _db;

            final rows = await db.query(
                  'units',
                  orderBy: 'name ASC',
            );

            return rows.map(UnitM.fromMap).toList();
      }

      /// Built-in units shown in dropdowns (Raw Materials, etc.).
      /// These are not managed from a separate Units tab.
      Future<void> ensureStandardUnits() async {
            final existing = await units();
            final names = existing
                  .map((u) => u.name.trim().toLowerCase())
                  .toSet();
            final codes = existing
                  .map((u) => u.shortCode.trim().toLowerCase())
                  .toSet();

            const standard = [
                  ('Kilogram', 'kg'),
                  ('Gram', 'g'),
                  ('Litre', 'L'),
                  ('Millilitre', 'ml'),
                  ('Piece', 'pc'),
                  ('Packet', 'pkt'),
                  ('Dozen', 'doz'),
                  ('Box', 'box'),
            ];

            for (final unit in standard) {
                  final nameKey = unit.$1.toLowerCase();
                  final codeKey = unit.$2.toLowerCase();
                  if (names.contains(nameKey) || codes.contains(codeKey)) {
                        continue;
                  }

                  await addUnit(
                        UnitM(
                              name: unit.$1,
                              shortCode: unit.$2,
                        ),
                  );
                  names.add(nameKey);
                  codes.add(codeKey);
            }
      }

      /// Built-in menu categories. Extra names can still be added in Masters.
      Future<void> ensureDefaultCategories() async {
            final existing = await categories(type: 'raw_material');
            final names = existing
                  .map((c) => c.name.trim().toLowerCase())
                  .toSet();

            const defaults = [
                  'Starters',
                  'Fried Items',
                  'Buns',
                  'Fillings',
                  'Gravy',
                  'Tandoor',
                  'Rice',
                  'Breads',
                  'Sauces',
                  'Chinese',
                  'Meals',
                  'Desserts',
                  'Beverages',
            ];

            for (final name in defaults) {
                  if (names.contains(name.toLowerCase())) continue;
                  await addCategory(
                        Category(
                              name: name,
                              type: 'raw_material',
                        ),
                  );
                  names.add(name.toLowerCase());
            }
      }

      Future<void> ensureDefaultUsers() async {
            final db = await _db;
            final now = DateTime.now().toIso8601String();

            Future<void> insertIfMissing({
                  required String username,
                  required String password,
                  required String role,
            }) async {
                  final rows = await db.query(
                        'users',
                        where: 'username = ?',
                        whereArgs: [username],
                        limit: 1,
                  );
                  if (rows.isNotEmpty) return;

                  await db.insert(
                        'users',
                        {
                              'username': username,
                              'password_hash': hashPin(password),
                              'role': role,
                              'created_at': now,
                        },
                  );
            }

            await insertIfMissing(
                  username: 'admin',
                  password: 'admin123',
                  role: 'admin',
            );
            await insertIfMissing(
                  username: 'staff',
                  password: 'staff123',
                  role: 'staff',
            );
      }

      // ============================================================
      // SUPPLIERS
      // ============================================================

      Future<int> addSupplier(Supplier supplier) async {
            final db = await _db;

            if (supplier.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Supplier name cannot be empty.',
                  );
            }

            return db.insert(
                  'suppliers',
                  supplier.toMap()..remove('id'),
            );
      }

      Future<List<Supplier>> suppliers() async {
            final db = await _db;

            final rows = await db.query(
                  'suppliers',
                  orderBy: 'name ASC',
            );

            return rows.map(Supplier.fromMap).toList();
      }

      // ============================================================
      // CUSTOMERS
      // ============================================================

      Future<int> addCustomer(Customer customer) async {
            final db = await _db;

            if (customer.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Customer name cannot be empty.',
                  );
            }

            if (customer.creditLimit < 0) {
                  throw InvalidInventoryException(
                        'Credit limit cannot be negative.',
                  );
            }

            return db.transaction((txn) async {
                  final id = await txn.insert(
                        'customers',
                        customer.toMap()..remove('id'),
                  );

                  if (customer.openingBalance != 0.0) {
                        await txn.insert(
                              'customer_ledger',
                              {
                                    'customer_id': id,
                                    'entry_date': DateTime.now().toIso8601String(),
                                    'type': 'opening',
                                    'amount': customer.openingBalance,
                                    'balance_after': customer.openingBalance,
                              },
                        );
                  }

                  return id;
            });
      }

      Future<List<Customer>> customers() async {
            final db = await _db;

            final rows = await db.query(
                  'customers',
                  orderBy: 'name ASC',
            );

            return rows.map(Customer.fromMap).toList();
      }

      // ============================================================
      // RAW MATERIAL MASTER
      // ============================================================

      Future<int> saveRawMaterial(
          RawMaterial rm, {
                String? pin,
          }) async {
            final db = await _db;

            if (rm.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Raw material name cannot be empty.',
                  );
            }

            if (rm.openingStock < 0.0) {
                  throw InvalidInventoryException(
                        'Opening stock cannot be negative.',
                  );
            }

            if (rm.reorderLevel < 0.0) {
                  throw InvalidInventoryException(
                        'Reorder level cannot be negative.',
                  );
            }

            if (rm.costPrice != null && rm.costPrice! < 0.0) {
                  throw InvalidInventoryException(
                        'Cost price cannot be negative.',
                  );
            }

            if (rm.sellingPrice != null && rm.sellingPrice! < 0.0) {
                  throw InvalidInventoryException(
                        'Selling price cannot be negative.',
                  );
            }

            final map = rm.toMap()..remove('id');

            if (pin != null && pin.trim().isNotEmpty) {
                  map['entry_password_hash'] = hashPin(
                        pin.trim(),
                  );
            }

            // ----------------------------------------------------------
            // NEW MATERIAL
            // ----------------------------------------------------------

            if (rm.id == null) {
                  return db.transaction((txn) async {
                        final double openingStock = rm.openingStock;

                        map['current_stock'] = openingStock;

                        final id = await txn.insert(
                              'raw_materials',
                              map,
                        );

                        if (openingStock > 0.0) {
                              await txn.insert(
                                    'stock_batches',
                                    {
                                          'raw_material_id': id,
                                          'qty_remaining': openingStock,
                                          'rate': rm.costPrice,
                                          'expiry_date': null,
                                          'purchase_item_id': null,
                                          'created_at': DateTime.now().toIso8601String(),
                                    },
                              );

                              await _writeLedger(
                                    txn: txn,
                                    rawMaterialId: id,
                                    refType: 'opening',
                                    qtyIn: openingStock,
                                    unitCost: rm.costPrice,
                                    balanceAfter: openingStock,
                              );
                        }

                        return id;
                  });
            }

            // ----------------------------------------------------------
            // UPDATE EXISTING MATERIAL
            // ----------------------------------------------------------

            await db.update(
                  'raw_materials',
                  {
                        ...map,
                        'current_stock': rm.currentStock,
                        'opening_stock': rm.openingStock,
                  },
                  where: 'id = ?',
                  whereArgs: [rm.id],
            );

            return rm.id!;
      }

      Future<void> hideRawMaterial(int rawMaterialId) async {
            final db = await _db;
            await db.update(
                  'raw_materials',
                  {
                    'listed': 0,
                    'barcode': null,
                  },
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
            );
      }

      Future<bool> verifyRawMaterialPin(
          int rawMaterialId,
          String pin,
          ) async {
            final db = await _db;

            final rows = await db.query(
                  'raw_materials',
                  columns: ['entry_password_hash'],
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
            );

            if (rows.isEmpty) {
                  return false;
            }

            final stored =
            rows.first['entry_password_hash'] as String?;

            if (stored == null || stored.isEmpty) {
                  return true;
            }

            return stored == hashPin(pin);
      }

      Future<List<RawMaterial>> rawMaterials({
            String? search,
            bool includeHidden = false,
      }) async {
            final db = await _db;

            final cleanSearch = search?.trim();
            final filters = <String>[];
            final args = <Object>[];
            if (!includeHidden) {
                  filters.add('(listed IS NULL OR listed = 1)');
            }
            if (cleanSearch != null && cleanSearch.isNotEmpty) {
                  filters.add(
                    '(name LIKE ? OR sub_item LIKE ? OR barcode LIKE ? OR barcode = ?)',
                  );
                  args.addAll([
                    '%$cleanSearch%',
                    '%$cleanSearch%',
                    '%$cleanSearch%',
                    cleanSearch,
                  ]);
            }

            final rows = await db.query(
                  'raw_materials',
                  where: filters.isEmpty ? null : filters.join(' AND '),
                  whereArgs: args.isEmpty ? null : args,
                  orderBy: 'name ASC',
            );

            return rows.map(RawMaterial.fromMap).toList();
      }

      Future<RawMaterial?> rawMaterialById(
          int id,
          ) async {
            final db = await _db;

            final rows = await db.query(
                  'raw_materials',
                  where: 'id = ?',
                  whereArgs: [id],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  return null;
            }

            return RawMaterial.fromMap(rows.first);
      }

      Future<RawMaterial?> rawMaterialByBarcode(
          String barcode,
          ) async {
            final db = await _db;

            final cleanBarcode = barcode.trim();

            if (cleanBarcode.isEmpty) {
                  return null;
            }

            final rows = await db.query(
                  'raw_materials',
                  where: 'barcode = ?',
                  whereArgs: [cleanBarcode],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  return null;
            }

            return RawMaterial.fromMap(rows.first);
      }

      Future<void> deleteRawMaterial(
          int rawMaterialId,
          ) async {
            final db = await _db;

            await db.transaction((txn) async {
                  final rows = await txn.query(
                        'raw_materials',
                        columns: ['id', 'name'],
                        where: 'id = ?',
                        whereArgs: [rawMaterialId],
                        limit: 1,
                  );

                  if (rows.isEmpty) {
                        throw InvalidInventoryException(
                              'Raw material does not exist.',
                        );
                  }

                  final name =
                      rows.first['name']?.toString() ?? 'Raw material';

                  // ----------------------------------------------------------
                  // COMBO USAGE
                  // ----------------------------------------------------------

                  final comboRows = await txn.rawQuery(
                        '''
        SELECT c.name
        FROM combo_raw_materials crm
        JOIN combos c
          ON c.id = crm.combo_id
        WHERE crm.raw_material_id = ?
        LIMIT 1
        ''',
                        [rawMaterialId],
                  );

                  if (comboRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$name cannot be deleted because it is used '
                                  'in combo "${comboRows.first['name']}".',
                        );
                  }

                  // ----------------------------------------------------------
                  // PURCHASE USAGE
                  // ----------------------------------------------------------

                  final purchaseRows = await txn.query(
                        'purchase_items',
                        columns: ['id'],
                        where: 'raw_material_id = ?',
                        whereArgs: [rawMaterialId],
                        limit: 1,
                  );

                  if (purchaseRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$name cannot be deleted because it has '
                                  'purchase history. Deactivate or keep the item instead.',
                        );
                  }

                  // ----------------------------------------------------------
                  // SALE USAGE
                  // ----------------------------------------------------------

                  final saleRows = await txn.query(
                        'sale_items',
                        columns: ['id'],
                        where: 'raw_material_id = ?',
                        whereArgs: [rawMaterialId],
                        limit: 1,
                  );

                  if (saleRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$name cannot be deleted because it has '
                                  'already been used in a sale.',
                        );
                  }

                  await txn.delete(
                        'stock_ledger',
                        where: 'raw_material_id = ?',
                        whereArgs: [rawMaterialId],
                  );

                  await txn.delete(
                        'stock_batches',
                        where: 'raw_material_id = ?',
                        whereArgs: [rawMaterialId],
                  );

                  final deleted = await txn.delete(
                        'raw_materials',
                        where: 'id = ?',
                        whereArgs: [rawMaterialId],
                  );

                  if (deleted == 0) {
                        throw InvalidInventoryException(
                              'Unable to delete raw material.',
                        );
                  }
            });
      }

      // ============================================================
      // COMBOS
      // ============================================================

      Future<int> saveCombo(
          Combo combo,
          List<ComboRawMaterial> items,
          ) async {
            final db = await _db;

            if (combo.name.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Combo name cannot be empty.',
                  );
            }

            if (combo.price < 0.0) {
                  throw InvalidInventoryException(
                        'Combo price cannot be negative.',
                  );
            }

            if (items.isEmpty) {
                  throw InvalidInventoryException(
                        'Combo must contain at least one raw material.',
                  );
            }

            return db.transaction((txn) async {
                  int comboId;

                  // ==========================================================
                  // CREATE
                  // ==========================================================

                  if (combo.id == null) {
                        comboId = await txn.insert(
                              'combos',
                              combo.toMap()..remove('id'),
                        );
                  }

                  // ==========================================================
                  // UPDATE
                  // ==========================================================

                  else {
                        final existing = await txn.query(
                              'combos',
                              columns: ['id'],
                              where: 'id = ?',
                              whereArgs: [combo.id],
                              limit: 1,
                        );

                        if (existing.isEmpty) {
                              throw InvalidInventoryException(
                                    'Combo does not exist.',
                              );
                        }

                        comboId = combo.id!;

                        final map = combo.toMap()
                              ..remove('id')
                              ..remove('created_at');

                        await txn.update(
                              'combos',
                              map,
                              where: 'id = ?',
                              whereArgs: [comboId],
                        );

                        await txn.delete(
                              'combo_raw_materials',
                              where: 'combo_id = ?',
                              whereArgs: [comboId],
                        );
                  }

                  // ==========================================================
                  // INSERT COMPONENTS
                  // ==========================================================

                  final uniqueMaterials = <int>{};

                  for (final item in items) {
                        if (combo.id != null && item.comboId != comboId) {
                              throw InvalidInventoryException(
                                    'Invalid combo ID in combo item.',
                              );
                        }

                        if (item.qty <= 0.0) {
                              throw InvalidInventoryException(
                                    'Combo raw material quantity must be greater than zero.',
                              );
                        }

                        if (!uniqueMaterials.add(item.rawMaterialId)) {
                              throw InvalidInventoryException(
                                    'A raw material cannot appear twice in the same combo.',
                              );
                        }

                        final materialRows = await txn.query(
                              'raw_materials',
                              columns: ['id'],
                              where: 'id = ?',
                              whereArgs: [item.rawMaterialId],
                              limit: 1,
                        );

                        if (materialRows.isEmpty) {
                              throw InvalidInventoryException(
                                    'A raw material in the combo no longer exists.',
                              );
                        }

                        await txn.insert(
                              'combo_raw_materials',
                              {
                                    'combo_id': comboId,
                                    'raw_material_id': item.rawMaterialId,
                                    'qty': item.qty,
                              },
                        );
                  }

                  return comboId;
            });
      }

      Future<List<Combo>> combos({
            bool activeOnly = true,
      }) async {
            final db = await _db;

            final rows = await db.query(
                  'combos',
                  where: activeOnly ? 'is_active = 1' : null,
                  orderBy: 'name ASC',
            );

            return rows.map(Combo.fromMap).toList();
      }

      Future<List<Combo>> combosWithItems({
            bool activeOnly = true,
      }) async {
            final comboList = await combos(
                  activeOnly: activeOnly,
            );

            return Future.wait(
                  comboList.map((combo) async {
                        if (combo.id == null) {
                              return combo;
                        }

                        final items = await comboItems(combo.id!);

                        return Combo(
                              id: combo.id,
                              name: combo.name,
                              barcode: combo.barcode,
                              categoryId: combo.categoryId,
                              price: combo.price,
                              imagePath: combo.imagePath,
                              isActive: combo.isActive,
                              items: items,
                              createdAt: combo.createdAt,
                        );
                  }),
            );
      }

      Future<Combo?> comboById(
          int comboId,
          ) async {
            final db = await _db;

            final rows = await db.query(
                  'combos',
                  where: 'id = ?',
                  whereArgs: [comboId],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  return null;
            }

            return Combo.fromMap(rows.first);
      }

      Future<Combo?> comboByBarcode(
          String barcode,
          ) async {
            final db = await _db;

            final cleanBarcode = barcode.trim();

            if (cleanBarcode.isEmpty) {
                  return null;
            }

            final rows = await db.query(
                  'combos',
                  where: 'barcode = ?',
                  whereArgs: [cleanBarcode],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  return null;
            }

            return Combo.fromMap(rows.first);
      }

      Future<List<ComboItem>> comboItems(
          int comboId,
          ) async {
            final db = await _db;

            final rows = await db.rawQuery(
                  '''
      SELECT
        crm.id,
        crm.combo_id,
        crm.raw_material_id,
        crm.qty,
        rm.name AS material_name,
        rm.current_stock AS current_stock,
        u.short_code AS unit
      FROM combo_raw_materials crm
      JOIN raw_materials rm
        ON rm.id = crm.raw_material_id
      LEFT JOIN units u
        ON u.id = rm.unit_id
      WHERE crm.combo_id = ?
      ORDER BY rm.name ASC
      ''',
                  [comboId],
            );

            return rows.map(ComboItem.fromMap).toList();
      }

      Future<void> deleteCombo(
          int comboId,
          ) async {
            final db = await _db;

            await db.transaction((txn) async {
                  final rows = await txn.query(
                        'combos',
                        columns: ['id', 'name'],
                        where: 'id = ?',
                        whereArgs: [comboId],
                        limit: 1,
                  );

                  if (rows.isEmpty) {
                        throw InvalidInventoryException(
                              'Combo does not exist.',
                        );
                  }

                  final comboName =
                      rows.first['name']?.toString() ?? 'Combo';

                  // ----------------------------------------------------------
                  // SALES USAGE
                  // ----------------------------------------------------------

                  final saleRows = await txn.query(
                        'sale_items',
                        columns: ['id'],
                        where: 'combo_id = ?',
                        whereArgs: [comboId],
                        limit: 1,
                  );

                  if (saleRows.isNotEmpty) {
                        throw InvalidInventoryException(
                              '$comboName cannot be permanently deleted because '
                                  'it has already been used in a sale. Deactivate it instead.',
                        );
                  }

                  await txn.delete(
                        'combo_raw_materials',
                        where: 'combo_id = ?',
                        whereArgs: [comboId],
                  );

                  final deleted = await txn.delete(
                        'combos',
                        where: 'id = ?',
                        whereArgs: [comboId],
                  );

                  if (deleted == 0) {
                        throw InvalidInventoryException(
                              'Unable to delete combo.',
                        );
                  }
            });
      }

      Future<void> deactivateCombo(
          int comboId,
          ) async {
            final db = await _db;

            await db.update(
                  'combos',
                  {
                        'is_active': 0,
                  },
                  where: 'id = ?',
                  whereArgs: [comboId],
            );
      }

      Future<void> activateCombo(
          int comboId,
          ) async {
            final db = await _db;

            await db.update(
                  'combos',
                  {
                        'is_active': 1,
                  },
                  where: 'id = ?',
                  whereArgs: [comboId],
            );
      }

      // ============================================================
      // PURCHASE
      // ============================================================

      Future<int> recordPurchase({
            int? supplierId,
            String? invoiceNo,
            required DateTime date,
            required List<Map<String, dynamic>> lines,
            String? notes,
      }) async {
            final db = await _db;

            if (lines.isEmpty) {
                  throw InvalidInventoryException(
                        'Purchase must contain at least one item.',
                  );
            }

            return db.transaction((txn) async {
                  double total = 0.0;

                  // ----------------------------------------------------------
                  // VALIDATE
                  // ----------------------------------------------------------

                  for (final line in lines) {
                        final double? qty =
                        (line['qty'] as num?)?.toDouble();

                        final double? rate =
                        (line['rate'] as num?)?.toDouble();

                        final rawMaterialId =
                        line['raw_material_id'] as int?;

                        if (rawMaterialId == null) {
                              throw InvalidInventoryException(
                                    'Purchase contains an invalid raw material.',
                              );
                        }

                        if (qty == null || qty <= 0.0) {
                              throw InvalidInventoryException(
                                    'Purchase quantity must be greater than zero.',
                              );
                        }

                        if (rate == null || rate < 0.0) {
                              throw InvalidInventoryException(
                                    'Purchase rate cannot be negative.',
                              );
                        }

                        final materialRows = await txn.query(
                              'raw_materials',
                              columns: ['id'],
                              where: 'id = ?',
                              whereArgs: [rawMaterialId],
                              limit: 1,
                        );

                        if (materialRows.isEmpty) {
                              throw InvalidInventoryException(
                                    'Raw material ID $rawMaterialId does not exist.',
                              );
                        }

                        total += qty * rate;
                  }

                  // ----------------------------------------------------------
                  // SUPPLIER VALIDATION
                  // ----------------------------------------------------------

                  if (supplierId != null) {
                        final supplierRows = await txn.query(
                              'suppliers',
                              columns: ['id'],
                              where: 'id = ?',
                              whereArgs: [supplierId],
                              limit: 1,
                        );

                        if (supplierRows.isEmpty) {
                              throw InvalidInventoryException(
                                    'Selected supplier does not exist.',
                              );
                        }
                  }

                  // ----------------------------------------------------------
                  // PURCHASE HEADER
                  // ----------------------------------------------------------

                  final purchaseId = await txn.insert(
                        'purchases',
                        {
                              'supplier_id': supplierId,
                              'invoice_no': invoiceNo,
                              'purchase_date': date.toIso8601String(),
                              'total_amount': total,
                              'notes': notes,
                        },
                  );

                  // ----------------------------------------------------------
                  // PURCHASE ITEMS
                  // ----------------------------------------------------------

                  for (final line in lines) {
                        final rawMaterialId =
                        line['raw_material_id'] as int;

                        final double qty =
                        (line['qty'] as num).toDouble();

                        final double rate =
                        (line['rate'] as num).toDouble();

                        final expiry =
                        line['expiry_date'] as String?;

                        final purchaseItemId = await txn.insert(
                              'purchase_items',
                              {
                                    'purchase_id': purchaseId,
                                    'raw_material_id': rawMaterialId,
                                    'qty': qty,
                                    'rate': rate,
                                    'amount': qty * rate,
                                    'expiry_date': expiry,
                              },
                        );

                        // --------------------------------------------------------
                        // STOCK BATCH
                        // --------------------------------------------------------

                        await txn.insert(
                              'stock_batches',
                              {
                                    'raw_material_id': rawMaterialId,
                                    'qty_remaining': qty,
                                    'rate': rate,
                                    'expiry_date':
                                    expiry != null && expiry.isNotEmpty
                                        ? expiry
                                        : null,
                                    'purchase_item_id': purchaseItemId,
                                    'created_at': DateTime.now().toIso8601String(),
                              },
                        );

                        // --------------------------------------------------------
                        // UPDATE COST PRICE
                        // --------------------------------------------------------

                        await txn.update(
                              'raw_materials',
                              {
                                    'cost_price': rate,
                              },
                              where: 'id = ?',
                              whereArgs: [rawMaterialId],
                        );

                        // --------------------------------------------------------
                        // UPDATE STOCK
                        // --------------------------------------------------------

                        final double newBalance = await _bumpStock(
                              txn,
                              rawMaterialId,
                              qty,
                        );

                        await _writeLedger(
                              txn: txn,
                              rawMaterialId: rawMaterialId,
                              refType: 'purchase',
                              refId: purchaseId,
                              qtyIn: qty,
                              unitCost: rate,
                              balanceAfter: newBalance,
                        );
                  }

                  return purchaseId;
            });
      }

      Future<List<Map<String, dynamic>>> purchases() async {
            final db = await _db;

            return db.rawQuery(
                  '''
      SELECT
        p.*,
        s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s
        ON s.id = p.supplier_id
      ORDER BY p.purchase_date DESC
      ''',
            );
      }

      // ============================================================
      // STOCK ADJUSTMENT
      // ============================================================

      Future<void> adjustStock(
          int rawMaterialId,
          double qtyDelta,
          String reason,
          ) async {
            final db = await _db;

            if (qtyDelta == 0.0) {
                  throw InvalidInventoryException(
                        'Stock adjustment cannot be zero.',
                  );
            }

            if (reason.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Stock adjustment reason is required.',
                  );
            }

            return db.transaction((txn) async {
                  final rows = await txn.query(
                        'raw_materials',
                        columns: ['name', 'current_stock'],
                        where: 'id = ?',
                        whereArgs: [rawMaterialId],
                        limit: 1,
                  );

                  if (rows.isEmpty) {
                        throw InvalidInventoryException(
                              'Raw material does not exist.',
                        );
                  }

                  final double currentStock =
                  (rows.first['current_stock'] as num).toDouble();

                  if (qtyDelta < 0.0) {
                        final double requested = -qtyDelta;

                        if (currentStock + 1e-9 < requested) {
                              throw InsufficientStockException(
                                    materialName: rows.first['name'] as String,
                                    needed: requested,
                                    available: currentStock,
                              );
                        }
                  }

                  final adjustmentId = await txn.insert(
                        'stock_adjustments',
                        {
                              'raw_material_id': rawMaterialId,
                              'adjust_date': DateTime.now().toIso8601String(),
                              'qty': qtyDelta,
                              'reason': reason.trim(),
                        },
                  );

                  if (qtyDelta < 0.0) {
                        await _deductFEFO(
                              txn,
                              rawMaterialId,
                              -qtyDelta,
                              refType: 'adjustment',
                              refId: adjustmentId,
                        );
                  } else {
                        await txn.insert(
                              'stock_batches',
                              {
                                    'raw_material_id': rawMaterialId,
                                    'qty_remaining': qtyDelta,
                                    'rate': null,
                                    'expiry_date': null,
                                    'purchase_item_id': null,
                                    'created_at': DateTime.now().toIso8601String(),
                              },
                        );

                        final double newBalance = await _bumpStock(
                              txn,
                              rawMaterialId,
                              qtyDelta,
                        );

                        await _writeLedger(
                              txn: txn,
                              rawMaterialId: rawMaterialId,
                              refType: 'adjustment',
                              refId: adjustmentId,
                              qtyIn: qtyDelta,
                              balanceAfter: newBalance,
                        );
                  }
            });
      }

      // ============================================================
      // FEFO STOCK DEDUCTION
      // ============================================================

      Future<double> _deductFEFO(
          AppDb txn,
          int rawMaterialId,
          double qtyNeeded, {
                required String refType,
                int? refId,
                bool allowNegative = false,
          }) async {
            if (qtyNeeded <= 0.0) {
                  return _getCurrentStock(
                        txn,
                        rawMaterialId,
                  );
            }

            final materialRows = await txn.query(
                  'raw_materials',
                  columns: ['name', 'current_stock'],
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
                  limit: 1,
            );

            if (materialRows.isEmpty) {
                  throw InvalidInventoryException(
                        'Raw material does not exist.',
                  );
            }

            final double currentStock =
            (materialRows.first['current_stock'] as num).toDouble();

            if (!allowNegative &&
                currentStock + 1e-9 < qtyNeeded) {
                  throw InsufficientStockException(
                        materialName: materialRows.first['name'] as String,
                        needed: qtyNeeded,
                        available: currentStock,
                  );
            }

            final batches = await txn.query(
                  'stock_batches',
                  where: 'raw_material_id = ? AND qty_remaining > 0',
                  whereArgs: [rawMaterialId],
                  orderBy:
                  'CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, '
                      'expiry_date ASC, id ASC',
            );

            double remaining = qtyNeeded;
            double costedQty = 0.0;
            double costedAmount = 0.0;

            for (final batch in batches) {
                  if (remaining <= 0.0) {
                        break;
                  }

                  final batchId = batch['id'] as int;

                  final double available =
                  (batch['qty_remaining'] as num).toDouble();

                  final double? rate =
                  (batch['rate'] as num?)?.toDouble();

                  final double take =
                  remaining < available ? remaining : available;

                  if (take <= 0.0) {
                        continue;
                  }

                  await txn.update(
                        'stock_batches',
                        {
                              'qty_remaining': available - take,
                        },
                        where: 'id = ?',
                        whereArgs: [batchId],
                  );

                  if (rate != null) {
                        costedQty += take;
                        costedAmount += take * rate;
                  }

                  remaining -= take;
            }

            if (!allowNegative && remaining > 0.000001) {
                  throw InvalidInventoryException(
                        'Stock batch data is inconsistent for '
                            '${materialRows.first['name']}.',
                  );
            }

            final double newBalance = await _bumpStock(
                  txn,
                  rawMaterialId,
                  -qtyNeeded,
            );

            await _writeLedger(
                  txn: txn,
                  rawMaterialId: rawMaterialId,
                  refType: refType,
                  refId: refId,
                  qtyOut: qtyNeeded,
                  unitCost: costedQty > 0.0
                      ? costedAmount / costedQty
                      : null,
                  balanceAfter: newBalance,
            );

            return newBalance;
      }

      // ============================================================
      // CURRENT STOCK
      // ============================================================

      Future<double> _getCurrentStock(
          AppDb txn,
          int rawMaterialId,
          ) async {
            final rows = await txn.query(
                  'raw_materials',
                  columns: ['current_stock'],
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  throw InvalidInventoryException(
                        'Raw material does not exist.',
                  );
            }

            final double stock =
            (rows.first['current_stock'] as num).toDouble();

            return stock;
      }

      Future<double> _bumpStock(
          AppDb txn,
          int rawMaterialId,
          double delta,
          ) async {
            final rows = await txn.query(
                  'raw_materials',
                  columns: ['current_stock'],
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
                  limit: 1,
            );

            if (rows.isEmpty) {
                  throw InvalidInventoryException(
                        'Raw material does not exist.',
                  );
            }

            final double current =
            (rows.first['current_stock'] as num).toDouble();

            final double next = current + delta;

            final double safeNext =
            next.abs() < 0.000001 ? 0.0 : next;

            await txn.update(
                  'raw_materials',
                  {
                        'current_stock': safeNext,
                  },
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
            );

            return safeNext;
      }

      // ============================================================
      // STOCK LEDGER
      // ============================================================

      Future<void> _writeLedger({
            AppDb? txn,
            required int rawMaterialId,
            required String refType,
            int? refId,
            double qtyIn = 0.0,
            double qtyOut = 0.0,
            double? unitCost,
            required double balanceAfter,
      }) async {
            final executor = txn ?? await _db;

            await executor.insert(
                  'stock_ledger',
                  {
                        'raw_material_id': rawMaterialId,
                        'entry_date': DateTime.now().toIso8601String(),
                        'ref_type': refType,
                        'ref_id': refId,
                        'qty_in': qtyIn,
                        'qty_out': qtyOut,
                        'unit_cost': unitCost,
                        'balance_after': balanceAfter,
                  },
            );
      }

      Future<List<Map<String, dynamic>>> stockLedger(
          int rawMaterialId,
          ) async {
            final db = await _db;

            return db.query(
                  'stock_ledger',
                  where: 'raw_material_id = ?',
                  whereArgs: [rawMaterialId],
                  orderBy: 'entry_date DESC, id DESC',
            );
      }

      // ============================================================
      // CURRENT STOCK REPORT
      // ============================================================

      Future<List<Map<String, dynamic>>>
      currentStockReport() async {
            final db = await _db;

            return db.rawQuery(
                  '''
      SELECT
        rm.id,
        rm.name,
        rm.sub_item,
        rm.barcode,
        rm.current_stock,
        rm.reorder_level,
        rm.cost_price,
        rm.selling_price,
        rm.image_path,
        u.short_code AS unit,
        c.name AS category
      FROM raw_materials rm
      LEFT JOIN units u
        ON u.id = rm.unit_id
      LEFT JOIN categories c
        ON c.id = rm.category_id
      ORDER BY rm.name ASC
      ''',
            );
      }

      // ============================================================
      // EXPIRY
      // ============================================================

      Future<List<Map<String, dynamic>>>
      expiringBatches({
            int withinDays = 7,
      }) async {
            final db = await _db;

            if (withinDays < 0) {
                  withinDays = 0;
            }

            final today = DateTime.now();

            final cutoff = DateTime(
                  today.year,
                  today.month,
                  today.day,
            ).add(
                  Duration(days: withinDays),
            );

            final cutoffDate =
            cutoff.toIso8601String().substring(0, 10);

            return db.rawQuery(
                  '''
      SELECT
        sb.*,
        rm.name AS material_name,
        u.short_code AS unit
      FROM stock_batches sb
      JOIN raw_materials rm
        ON rm.id = sb.raw_material_id
      LEFT JOIN units u
        ON u.id = rm.unit_id
      WHERE sb.qty_remaining > 0
        AND sb.expiry_date IS NOT NULL
        AND substr(sb.expiry_date, 1, 10) <= ?
      ORDER BY
        substr(sb.expiry_date, 1, 10) ASC,
        sb.id ASC
      ''',
                  [cutoffDate],
            );
      }

      // ============================================================
      // WRITE OFF EXPIRED STOCK
      // ============================================================

      Future<List<Map<String, dynamic>>>
      writeOffExpiredStock() async {
            final db = await _db;

            final today = DateTime.now()
                .toIso8601String()
                .substring(0, 10);

            return db.transaction((txn) async {
                  final expired = await txn.rawQuery(
                        '''
        SELECT
          sb.*,
          rm.name AS material_name
        FROM stock_batches sb
        JOIN raw_materials rm
          ON rm.id = sb.raw_material_id
        WHERE sb.qty_remaining > 0
          AND sb.expiry_date IS NOT NULL
          AND substr(sb.expiry_date, 1, 10) < ?
        ORDER BY
          substr(sb.expiry_date, 1, 10) ASC
        ''',
                        [today],
                  );

                  final writtenOff =
                  <Map<String, dynamic>>[];

                  for (final batch in expired) {
                        final batchId = batch['id'] as int;

                        final rawMaterialId =
                        batch['raw_material_id'] as int;

                        final double qty =
                        (batch['qty_remaining'] as num).toDouble();

                        final double? rate =
                        (batch['rate'] as num?)?.toDouble();

                        if (qty <= 0.0) {
                              continue;
                        }

                        await txn.update(
                              'stock_batches',
                              {
                                    'qty_remaining': 0.0,
                              },
                              where: 'id = ?',
                              whereArgs: [batchId],
                        );

                        final double newBalance =
                        await _bumpStock(
                              txn,
                              rawMaterialId,
                              -qty,
                        );

                        await _writeLedger(
                              txn: txn,
                              rawMaterialId: rawMaterialId,
                              refType: 'expired_wastage',
                              refId: batchId,
                              qtyOut: qty,
                              unitCost: rate,
                              balanceAfter: newBalance,
                        );

                        writtenOff.add(batch);
                  }

                  return writtenOff;
            });
      }

      // ============================================================
      // POS STOCK AWARENESS
      // ============================================================

      /// Returns the maximum number of units that can currently
      /// be sold for each raw material.
      Future<Map<int, double>>
      maxQuantitiesForRawMaterials() async {
            final db = await _db;

            final rows = await db.query(
                  'raw_materials',
                  columns: [
                        'id',
                        'current_stock',
                        'qty_needed',
                  ],
            );

            final result = <int, double>{};

            for (final row in rows) {
                  final id = (row['id'] as num).toInt();

                  final double stock =
                      (row['current_stock'] as num?)?.toDouble() ?? 0.0;
                  final double needed =
                      (row['qty_needed'] as num?)?.toDouble() ?? 1.0;
                  final perSale = needed <= 0 ? 1.0 : needed;

                  final sellable = stock / perSale;
                  result[id] = sellable;
            }

            return result;
      }

      /// Returns maximum sellable quantities for combos.
      ///
      /// Example:
      ///
      /// Combo:
      ///   2 x Rice
      ///   1 x Chicken
      ///
      /// Stock:
      ///   Rice = 10
      ///   Chicken = 3
      ///
      /// Maximum combo quantity = min(10 / 2, 3 / 1)
      ///                       = 3
      Future<Map<int, double>>
      maxQuantitiesForCombos() async {
            final db = await _db;

            final rows = await db.rawQuery(
                  '''
      SELECT
        crm.combo_id,
        MIN(
          rm.current_stock / crm.qty
        ) AS max_qty
      FROM combo_raw_materials crm
      JOIN raw_materials rm
        ON rm.id = crm.raw_material_id
      WHERE crm.qty > 0
      GROUP BY crm.combo_id
      ''',
            );

            final result = <int, double>{};

            for (final row in rows) {
                  final comboId =
                  (row['combo_id'] as num).toInt();

                  final double maxQty =
                      (row['max_qty'] as num?)?.toDouble() ?? 0.0;

                  result[comboId] = maxQty;
            }

            return result;
      }

      // ============================================================
      // SALES / POS
      // ============================================================

      Future<int> recordSale({
            int? customerId,
            required List<CartLine> lines,
            required double tax,
            required double discount,
            required String paymentType,
      }) async {
            final db = await _db;

            if (lines.isEmpty) {
                  throw InvalidInventoryException(
                        'Sale cannot be empty.',
                  );
            }

            if (tax < 0.0) {
                  throw InvalidInventoryException(
                        'Tax cannot be negative.',
                  );
            }

            if (discount < 0.0) {
                  throw InvalidInventoryException(
                        'Discount cannot be negative.',
                  );
            }

            if (paymentType.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Payment type is required.',
                  );
            }

            return db.transaction((txn) async {
                  // ----------------------------------------------------------
                  // CUSTOMER
                  // ----------------------------------------------------------

                  if (customerId != null) {
                        final customerRows = await txn.query(
                              'customers',
                              columns: ['id'],
                              where: 'id = ?',
                              whereArgs: [customerId],
                              limit: 1,
                        );

                        if (customerRows.isEmpty) {
                              throw InvalidInventoryException(
                                    'Selected customer does not exist.',
                              );
                        }
                  }

                  // ----------------------------------------------------------
                  // VALIDATE CART LINES
                  // ----------------------------------------------------------

                  for (final line in lines) {
                        if (line.qty <= 0.0) {
                              throw InvalidInventoryException(
                                    'Sale quantity must be greater than zero.',
                              );
                        }

                        if (line.price < 0.0) {
                              throw InvalidInventoryException(
                                    'Sale price cannot be negative.',
                              );
                        }

                        if (line.name.trim().isEmpty) {
                              throw InvalidInventoryException(
                                    'Sale item name cannot be empty.',
                              );
                        }

                        final hasRaw =
                            line.rawMaterialId != null;

                        final hasCombo =
                            line.comboId != null;

                        if (!hasRaw && !hasCombo) {
                              throw InvalidInventoryException(
                                    'Every sale line must contain a raw material or combo.',
                              );
                        }

                        if (hasRaw && hasCombo) {
                              throw InvalidInventoryException(
                                    'A sale line cannot be both raw material and combo.',
                              );
                        }
                  }

                  // ----------------------------------------------------------
                  // TOTAL
                  // ----------------------------------------------------------

                  final double subtotal = lines.fold<double>(
                        0.0,
                            (double sum, line) =>
                        sum + line.amount,
                  );

                  final double total =
                      subtotal + tax - discount;

                  if (total < 0.0) {
                        throw InvalidInventoryException(
                              'Sale total cannot be negative.',
                        );
                  }

                  // ----------------------------------------------------------
                  // EXPAND SALE TO RAW MATERIAL REQUIREMENTS
                  // ----------------------------------------------------------

                  final totalNeeded =
                  await _expandCartToRawMaterialNeeds(
                        txn,
                        lines,
                  );

                  // ----------------------------------------------------------
                  // CREATE SALE
                  // ----------------------------------------------------------

                  final saleId = await txn.insert(
                        'sales',
                        {
                              'customer_id': customerId,
                              'sale_date':
                              DateTime.now().toIso8601String(),
                              'subtotal': subtotal,
                              'tax': tax,
                              'discount': discount,
                              'total': total,
                              'payment_type': paymentType.trim(),
                              'is_voided': 0,
                        },
                  );

                  // ----------------------------------------------------------
                  // SALE LINES
                  // ----------------------------------------------------------

                  for (final line in lines) {
                        await txn.insert(
                              'sale_items',
                              {
                                    'sale_id': saleId,
                                    'raw_material_id':
                                    line.rawMaterialId,
                                    'combo_id': line.comboId,
                                    'item_name': line.name,
                                    'sub_item': line.subItem,
                                    'qty': line.qty,
                                    'price': line.price,
                                    'amount': line.amount,
                              },
                        );
                  }

                  // ----------------------------------------------------------
                  // DEDUCT STOCK
                  // ----------------------------------------------------------

                  for (final entry in totalNeeded.entries) {
                        await _deductFEFO(
                              txn,
                              entry.key,
                              entry.value,
                              refType: 'sale_deduction',
                              refId: saleId,
                              allowNegative: true,
                        );
                  }

                  // ----------------------------------------------------------
                  // CUSTOMER CREDIT
                  // ----------------------------------------------------------

                  if (customerId != null &&
                      paymentType.toLowerCase() == 'credit') {
                        final double balance =
                        await _customerBalance(
                              txn,
                              customerId,
                        );

                        final double newBalance =
                            balance + total;

                        await txn.insert(
                              'customer_ledger',
                              {
                                    'customer_id': customerId,
                                    'entry_date':
                                    DateTime.now().toIso8601String(),
                                    'type': 'sale_credit',
                                    'amount': total,
                                    'balance_after': newBalance,
                                    'ref_sale_id': saleId,
                              },
                        );
                  }

                  return saleId;
            });
      }

      // ============================================================
      // CART -> RAW MATERIAL REQUIREMENTS
      // ============================================================

      Future<Map<int, double>>
      _expandCartToRawMaterialNeeds(
          AppDb txn,
          List<CartLine> lines,
          ) async {
            final totalNeeded = <int, double>{};

            for (final line in lines) {
                  // --------------------------------------------------------
                  // DIRECT RAW MATERIAL
                  // --------------------------------------------------------

                  if (line.rawMaterialId != null) {
                        final rawMaterialId =
                        line.rawMaterialId!;

                        final double existing =
                            totalNeeded[rawMaterialId] ?? 0.0;

                        totalNeeded[rawMaterialId] =
                            existing +
                                (line.qty * await _qtyNeeded(
                                  txn,
                                  rawMaterialId,
                                ));

                        continue;
                  }

                  // --------------------------------------------------------
                  // COMBO
                  // --------------------------------------------------------

                  if (line.comboId != null) {
                        final comboRows = await txn.query(
                              'combos',
                              columns: [
                                    'id',
                                    'name',
                                    'is_active',
                              ],
                              where: 'id = ?',
                              whereArgs: [line.comboId],
                              limit: 1,
                        );

                        if (comboRows.isEmpty) {
                              throw InvalidInventoryException(
                                    'Combo does not exist.',
                              );
                        }

                        final bool isActive =
                            (comboRows.first['is_active'] as num?)
                                ?.toInt() ==
                                1;

                        if (!isActive) {
                              throw InvalidInventoryException(
                                    'Combo "${comboRows.first['name']}" is inactive.',
                              );
                        }

                        final comboItems = await txn.query(
                              'combo_raw_materials',
                              where: 'combo_id = ?',
                              whereArgs: [line.comboId],
                              orderBy: 'id ASC',
                        );

                        if (comboItems.isEmpty) {
                              throw InvalidInventoryException(
                                    'Combo does not contain any raw materials.',
                              );
                        }

                        for (final comboItem in comboItems) {
                              final rawMaterialId =
                              (comboItem['raw_material_id'] as num)
                                  .toInt();

                              final double comboQty =
                              (comboItem['qty'] as num)
                                  .toDouble();

                              if (comboQty <= 0.0) {
                                    throw InvalidInventoryException(
                                          'Combo contains an invalid raw material quantity.',
                                    );
                              }

                              final double requiredQty =
                                  comboQty *
                                      line.qty *
                                      await _qtyNeeded(
                                        txn,
                                        rawMaterialId,
                                      );

                              final double existing =
                                  totalNeeded[rawMaterialId] ?? 0.0;

                              totalNeeded[rawMaterialId] =
                                  existing + requiredQty;
                        }
                  }
            }

            return totalNeeded;
      }

      Future<double> _qtyNeeded(
            AppDb txn,
            int rawMaterialId,
            ) async {
            final rows = await txn.query(
                  'raw_materials',
                  columns: ['qty_needed'],
                  where: 'id = ?',
                  whereArgs: [rawMaterialId],
                  limit: 1,
            );

            if (rows.isEmpty) return 1;

            final value =
                (rows.first['qty_needed'] as num?)?.toDouble() ?? 1;
            return value <= 0 ? 1 : value;
      }

      // ============================================================
      // CUSTOMER BALANCE
      // ============================================================

      Future<double> _customerBalance(
          AppDb executor,
          int customerId,
          ) async {
            final rows = await executor.query(
                  'customer_ledger',
                  where: 'customer_id = ?',
                  whereArgs: [customerId],
                  orderBy: 'id DESC',
                  limit: 1,
            );

            if (rows.isEmpty) {
                  return 0.0;
            }

            final double balance =
            (rows.first['balance_after'] as num)
                .toDouble();

            return balance;
      }

      Future<void> recordCustomerPayment(
          int customerId,
          double amount,
          ) async {
            final db = await _db;

            if (amount <= 0.0) {
                  throw InvalidInventoryException(
                        'Payment amount must be greater than zero.',
                  );
            }

            return db.transaction((txn) async {
                  final customerRows = await txn.query(
                        'customers',
                        columns: ['id'],
                        where: 'id = ?',
                        whereArgs: [customerId],
                        limit: 1,
                  );

                  if (customerRows.isEmpty) {
                        throw InvalidInventoryException(
                              'Customer does not exist.',
                        );
                  }

                  final double previousBalance =
                  await _customerBalance(
                        txn,
                        customerId,
                  );

                  final double newBalance =
                      previousBalance - amount;

                  await txn.insert(
                        'customer_ledger',
                        {
                              'customer_id': customerId,
                              'entry_date':
                              DateTime.now().toIso8601String(),
                              'type': 'payment',
                              'amount': -amount,
                              'balance_after': newBalance,
                        },
                  );
            });
      }

      Future<List<Map<String, dynamic>>>
      customerLedger(
          int customerId,
          ) async {
            final db = await _db;

            return db.query(
                  'customer_ledger',
                  where: 'customer_id = ?',
                  whereArgs: [customerId],
                  orderBy: 'entry_date DESC, id DESC',
            );
      }

      Future<double> customerBalance(
          int customerId,
          ) async {
            final db = await _db;

            return _customerBalance(
                  db,
                  customerId,
            );
      }

      // ============================================================
      // SALE / RECEIPT
      // ============================================================

      Future<Map<String, dynamic>?> saleById(
          int saleId,
          ) async {
            final db = await _db;

            final rows = await db.query(
                  'sales',
                  where: 'id = ?',
                  whereArgs: [saleId],
                  limit: 1,
            );

            return rows.isEmpty ? null : rows.first;
      }

      Future<List<Map<String, dynamic>>>
      saleItems(
          int saleId,
          ) async {
            final db = await _db;

            return db.query(
                  'sale_items',
                  where: 'sale_id = ?',
                  whereArgs: [saleId],
                  orderBy: 'id ASC',
            );
      }

      // ============================================================
      // VOID SALE
      // ============================================================

      Future<void> voidSale(
          int saleId,
          String reason,
          ) async {
            final db = await _db;

            if (reason.trim().isEmpty) {
                  throw InvalidInventoryException(
                        'Void reason is required.',
                  );
            }

            return db.transaction((txn) async {
                  final rows = await txn.query(
                        'sales',
                        where: 'id = ?',
                        whereArgs: [saleId],
                        limit: 1,
                  );

                  if (rows.isEmpty) {
                        throw InvalidInventoryException(
                              'Sale does not exist.',
                        );
                  }

                  final sale = rows.first;

                  final bool isVoided =
                      (sale['is_voided'] as num?)?.toInt() == 1;

                  if (isVoided) {
                        return;
                  }

                  // ----------------------------------------------------------
                  // RESTORE STOCK FROM LEDGER
                  // ----------------------------------------------------------

                  final deductions = await txn.query(
                        'stock_ledger',
                        where: 'ref_type = ? AND ref_id = ?',
                        whereArgs: [
                              'sale_deduction',
                              saleId,
                        ],
                        orderBy: 'id ASC',
                  );

                  for (final deduction in deductions) {
                        final rawMaterialId =
                        deduction['raw_material_id'] as int;

                        final double qty =
                        (deduction['qty_out'] as num)
                            .toDouble();

                        final double? unitCost =
                        (deduction['unit_cost'] as num?)
                            ?.toDouble();

                        if (qty <= 0.0) {
                              continue;
                        }

                        await txn.insert(
                              'stock_batches',
                              {
                                    'raw_material_id': rawMaterialId,
                                    'qty_remaining': qty,
                                    'rate': unitCost,
                                    'expiry_date': null,
                                    'purchase_item_id': null,
                                    'created_at':
                                    DateTime.now().toIso8601String(),
                              },
                        );

                        final double newBalance =
                        await _bumpStock(
                              txn,
                              rawMaterialId,
                              qty,
                        );

                        await _writeLedger(
                              txn: txn,
                              rawMaterialId: rawMaterialId,
                              refType: 'sale_reversal',
                              refId: saleId,
                              qtyIn: qty,
                              unitCost: unitCost,
                              balanceAfter: newBalance,
                        );
                  }

                  // ----------------------------------------------------------
                  // VOID SALE
                  // ----------------------------------------------------------

                  await txn.update(
                        'sales',
                        {
                              'is_voided': 1,
                              'voided_reason': reason.trim(),
                              'voided_at':
                              DateTime.now().toIso8601String(),
                        },
                        where: 'id = ?',
                        whereArgs: [saleId],
                  );

                  // ----------------------------------------------------------
                  // CREDIT REVERSAL
                  // ----------------------------------------------------------

                  if (sale['customer_id'] != null &&
                      (sale['payment_type'] as String)
                          .toLowerCase() ==
                          'credit') {
                        final customerId =
                        sale['customer_id'] as int;

                        final double total =
                        (sale['total'] as num).toDouble();

                        final double previousBalance =
                        await _customerBalance(
                              txn,
                              customerId,
                        );

                        final double newBalance =
                            previousBalance - total;

                        await txn.insert(
                              'customer_ledger',
                              {
                                    'customer_id': customerId,
                                    'entry_date':
                                    DateTime.now().toIso8601String(),
                                    'type': 'sale_void',
                                    'amount': -total,
                                    'balance_after': newBalance,
                                    'ref_sale_id': saleId,
                              },
                        );
                  }
            });
      }

      // ============================================================
      // SALES REPORT
      // ============================================================

      Future<List<Map<String, dynamic>>>
      salesReport({
            DateTime? from,
            DateTime? to,
            bool includeVoided = true,
      }) async {
            final db = await _db;

            final where = <String>[];
            final args = <dynamic>[];

            if (from != null) {
                  where.add(
                        'sale_date >= ?',
                  );

                  args.add(
                        from.toIso8601String(),
                  );
            }

            if (to != null) {
                  where.add(
                        'sale_date <= ?',
                  );

                  args.add(
                        to.toIso8601String(),
                  );
            }

            if (!includeVoided) {
                  where.add(
                        'is_voided = 0',
                  );
            }

            return db.query(
                  'sales',
                  where: where.isEmpty
                      ? null
                      : where.join(' AND '),
                  whereArgs: args.isEmpty ? null : args,
                  orderBy: 'sale_date DESC, id DESC',
            );
      }

      // ============================================================
      // DAY END REPORT
      // ============================================================

      Future<Map<String, dynamic>>
      dayEndReport(
          DateTime date,
          ) async {
            final db = await _db;

            final start = DateTime(
                  date.year,
                  date.month,
                  date.day,
            );

            final end = start.add(
                  const Duration(days: 1),
            );

            final startIso =
            start.toIso8601String();

            final endIso =
            end.toIso8601String();

            final byPayment = await db.rawQuery(
                  '''
      SELECT
        payment_type,
        COUNT(*) AS cnt,
        SUM(total) AS total
      FROM sales
      WHERE sale_date >= ?
        AND sale_date < ?
        AND is_voided = 0
      GROUP BY payment_type
      ORDER BY payment_type
      ''',
                  [
                        startIso,
                        endIso,
                  ],
            );

            final voidedRows = await db.rawQuery(
                  '''
      SELECT
        COUNT(*) AS cnt,
        COALESCE(SUM(total), 0) AS total
      FROM sales
      WHERE sale_date >= ?
        AND sale_date < ?
        AND is_voided = 1
      ''',
                  [
                        startIso,
                        endIso,
                  ],
            );

            final double grandTotal =
            byPayment.fold<double>(
                  0.0,
                      (double sum, row) =>
                  sum +
                      ((row['total'] as num?)?.toDouble() ??
                          0.0),
            );

            return {
                  'by_payment': byPayment,
                  'grand_total': grandTotal,
                  'voided_count':
                  (voidedRows.first['cnt'] as num?)
                      ?.toInt() ??
                      0,
                  'voided_total':
                  (voidedRows.first['total'] as num?)
                      ?.toDouble() ??
                      0.0,
            };
      }

      // ============================================================
      // TOP SELLING ITEMS
      // ============================================================

      Future<List<Map<String, dynamic>>>
      topSellingItems({
            int limit = 10,
      }) async {
            final db = await _db;

            if (limit <= 0) {
                  limit = 10;
            }

            return db.rawQuery(
                  '''
      SELECT
        si.item_name,
        si.sub_item,
        SUM(si.qty) AS total_qty,
        SUM(si.amount) AS total_amount
      FROM sale_items si
      JOIN sales s
        ON s.id = si.sale_id
      WHERE s.is_voided = 0
      GROUP BY si.item_name, si.sub_item
      ORDER BY total_qty DESC
      LIMIT ?
      ''',
                  [limit],
            );
      }

      Future<List<Map<String, dynamic>>> itemSalesReport() async {
            final db = await _db;

            final countRows = await db.rawQuery(
                  'SELECT COUNT(*) AS cnt FROM sales WHERE is_voided = 0',
            );
            final saleCount =
                (countRows.isEmpty
                    ? 0
                    : (countRows.first['cnt'] as num?)?.toInt()) ??
                0;
            if (saleCount == 0) {
                  return const [];
            }

            return db.rawQuery(
                  '''
      WITH component_usage AS (
        SELECT
          crm.raw_material_id AS raw_material_id,
          SUM(
            crm.qty * si.qty * COALESCE(rm.qty_needed, 1)
          ) AS consumed_qty
        FROM sale_items si
        JOIN sales s
          ON s.id = si.sale_id
        JOIN combo_raw_materials crm
          ON crm.combo_id = si.combo_id
        JOIN raw_materials rm
          ON rm.id = crm.raw_material_id
        WHERE s.is_voided = 0
          AND si.combo_id IS NOT NULL
        GROUP BY crm.raw_material_id
      ),
      direct_sales AS (
        SELECT
          si.raw_material_id AS raw_material_id,
          SUM(si.qty) AS sold_qty,
          SUM(si.amount) AS total_amount
        FROM sale_items si
        JOIN sales s
          ON s.id = si.sale_id
        WHERE s.is_voided = 0
          AND si.raw_material_id IS NOT NULL
        GROUP BY si.raw_material_id
      )
      SELECT
        rm.name AS item_name,
        rm.sub_item AS sub_item,
        COALESCE(ds.sold_qty, 0) + COALESCE(cu.consumed_qty, 0) AS sold_qty,
        COALESCE(ds.total_amount, 0) AS total_amount,
        rm.current_stock AS current_stock,
        'item' AS sale_kind
      FROM raw_materials rm
      LEFT JOIN direct_sales ds
        ON ds.raw_material_id = rm.id
      LEFT JOIN component_usage cu
        ON cu.raw_material_id = rm.id
      WHERE COALESCE(ds.sold_qty, 0) + COALESCE(cu.consumed_qty, 0) > 0

      UNION ALL

      SELECT
        si.item_name AS item_name,
        si.sub_item AS sub_item,
        SUM(si.qty) AS sold_qty,
        SUM(si.amount) AS total_amount,
        NULL AS current_stock,
        'combo' AS sale_kind
      FROM sale_items si
      JOIN sales s
        ON s.id = si.sale_id
      WHERE s.is_voided = 0
        AND si.combo_id IS NOT NULL
      GROUP BY
        si.combo_id,
        si.item_name,
        COALESCE(si.sub_item, '')

      ORDER BY
        sale_kind ASC,
        item_name ASC,
        sub_item ASC
      ''',
            );
      }

      // ============================================================
      // PURCHASE REPORT
      // ============================================================

      Future<List<Map<String, dynamic>>>
      purchaseReport() async {
            final db = await _db;

            return db.rawQuery(
                  '''
      SELECT
        pi.*,
        rm.name AS material_name,
        p.purchase_date,
        p.invoice_no,
        s.name AS supplier_name
      FROM purchase_items pi
      JOIN purchases p
        ON p.id = pi.purchase_id
      JOIN raw_materials rm
        ON rm.id = pi.raw_material_id
      LEFT JOIN suppliers s
        ON s.id = p.supplier_id
      ORDER BY
        p.purchase_date DESC,
        pi.id DESC
      ''',
            );
      }

      // ============================================================
      // STOCK SUMMARY
      // ============================================================

      Future<Map<String, dynamic>>
      stockSummary() async {
            final db = await _db;

            final rows = await db.rawQuery(
                  '''
      SELECT
        COUNT(*) AS item_count,
        COALESCE(
          SUM(current_stock),
          0
        ) AS total_stock,
        SUM(
          CASE
            WHEN current_stock <= reorder_level
            THEN 1
            ELSE 0
          END
        ) AS low_stock_count
      FROM raw_materials
      ''',
            );

            final row = rows.first;

            return {
                  'item_count':
                  (row['item_count'] as num?)?.toInt() ?? 0,
                  'total_stock':
                  (row['total_stock'] as num?)?.toDouble() ??
                      0.0,
                  'low_stock_count':
                  (row['low_stock_count'] as num?)?.toInt() ??
                      0,
            };
      }

      // ============================================================
      // LOW STOCK ITEMS
      // ============================================================

      Future<List<Map<String, dynamic>>>
      lowStockItems() async {
            final db = await _db;

            return db.rawQuery(
                  '''
      SELECT
        rm.id,
        rm.name,
        rm.barcode,
        rm.current_stock,
        rm.reorder_level,
        rm.cost_price,
        rm.selling_price,
        rm.image_path,
        u.short_code AS unit,
        c.name AS category
      FROM raw_materials rm
      LEFT JOIN units u
        ON u.id = rm.unit_id
      LEFT JOIN categories c
        ON c.id = rm.category_id
      WHERE rm.current_stock <= rm.reorder_level
      ORDER BY
        rm.current_stock ASC,
        rm.name ASC
      ''',
            );
      }

      // ============================================================
      // DEMO RESET (SETTINGS → RESET)
      // ============================================================

      /// Deletes sales and purchases, clears stock movement history, and
      /// restores each menu item's stock to its opening_stock. Keeps menu
      /// items, categories, units, customers, combos, and suppliers.
      Future<void> resetDemoTransactionData() async {
            final db = await _db;

            await db.transaction((txn) async {
                  await txn.delete('customer_ledger');
                  await txn.delete('sale_items');
                  await txn.delete('sales');
                  await txn.delete('purchase_items');
                  await txn.delete('purchases');
                  await txn.delete('stock_ledger');
                  await txn.delete('stock_adjustments');
                  await txn.delete('stock_batches');
            });

            await resetAllStockToOpening();

            if (!ApiConfig.enabled) {
                  final sqlite = await DBHelper.instance.database;
                  await sqlite.delete(
                        'sqlite_sequence',
                        where: '''
                          name IN (
                            ?, ?, ?, ?, ?, ?, ?, ?
                          )
                        ''',
                        whereArgs: [
                          'sale_items',
                          'sales',
                          'customer_ledger',
                          'stock_ledger',
                          'stock_adjustments',
                          'purchase_items',
                          'purchases',
                          'stock_batches',
                        ],
                  );
            }
      }

      /// Sets every item's stock to its opening_stock and rebuilds batches.
      Future<void> resetAllStockToOpening() async {
            final db = await _db;
            final now = DateTime.now().toIso8601String();

            await db.transaction((txn) async {
                  await txn.delete('stock_ledger');
                  await txn.delete('stock_adjustments');
                  await txn.delete('stock_batches');

                  final materials = await txn.query('raw_materials');
                  for (final row in materials) {
                        final id = (row['id'] as num).toInt();
                        final opening =
                            (row['opening_stock'] as num?)?.toDouble() ?? 0.0;
                        final cost =
                            (row['cost_price'] as num?)?.toDouble();

                        await txn.update(
                              'raw_materials',
                              {'current_stock': opening},
                              where: 'id = ?',
                              whereArgs: [id],
                        );

                        if (opening > 0.0) {
                              await txn.insert(
                                    'stock_batches',
                                    {
                                          'raw_material_id': id,
                                          'qty_remaining': opening,
                                          'rate': cost,
                                          'expiry_date': null,
                                          'purchase_item_id': null,
                                          'created_at': now,
                                    },
                              );

                              await _writeLedger(
                                    txn: txn,
                                    rawMaterialId: id,
                                    refType: 'opening',
                                    qtyIn: opening,
                                    unitCost: cost,
                                    balanceAfter: opening,
                              );
                        }
                  }
            });
      }

      // ============================================================
      // CLOSE DATABASE
      // ============================================================

      Future<void> close() async {
            await DBHelper.instance.close();
      }
}
