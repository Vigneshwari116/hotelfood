// lib/model/models.dart

// ============================================================
// CATEGORY
// ============================================================

class Category {
  final int? id;
  final String name;
  final String type;

  Category({
    this.id,
    required this.name,
    this.type = 'raw_material',
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'raw_material',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
    };
  }
}


// ============================================================
// UNIT
// ============================================================

class UnitM {
  final int? id;
  final String name;
  final String shortCode;

  UnitM({
    this.id,
    required this.name,
    required this.shortCode,
  });

  factory UnitM.fromMap(Map<String, dynamic> map) {
    return UnitM(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      shortCode: map['short_code']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'short_code': shortCode,
    };
  }
}


// ============================================================
// SUPPLIER
// ============================================================

class Supplier {
  final int? id;
  final String name;
  final String? mobile;
  final String? city;
  final DateTime? createdAt;

  Supplier({
    this.id,
    required this.name,
    this.mobile,
    this.city,
    this.createdAt,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      mobile: map['mobile']?.toString(),
      city: map['city']?.toString(),
      createdAt: _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      'city': city,
      'created_at':
      createdAt?.toIso8601String() ??
          DateTime.now().toIso8601String(),
    };
  }
}


// ============================================================
// CUSTOMER
// ============================================================

class Customer {
  final int? id;
  final String name;
  final String? phone;
  final double creditLimit;
  final double openingBalance;
  final DateTime? createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.creditLimit = 0,
    this.openingBalance = 0,
    this.createdAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      creditLimit:
      (map['credit_limit'] as num?)?.toDouble() ?? 0,
      openingBalance:
      (map['opening_balance'] as num?)?.toDouble() ?? 0,
      createdAt: _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'credit_limit': creditLimit,
      'opening_balance': openingBalance,
      'created_at':
      createdAt?.toIso8601String() ??
          DateTime.now().toIso8601String(),
    };
  }
}


// ============================================================
// RAW MATERIAL
// ============================================================

class RawMaterial {
  final int? id;

  final String? barcode;
  final String name;
  final String? subItem;

  final int? categoryId;
  final int? unitId;

  final double openingStock;
  final double currentStock;
  final double reorderLevel;

  final int? shelfLifeDays;
  final double? unitsPerPacket;

  final String? entryPasswordHash;

  final double? costPrice;
  final double? sellingPrice;

  final String? imagePath;

  final DateTime? createdAt;

  RawMaterial({
    this.id,
    this.barcode,
    required this.name,
    this.subItem,
    this.categoryId,
    this.unitId,
    this.openingStock = 0,
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.shelfLifeDays,
    this.unitsPerPacket,
    this.entryPasswordHash,
    this.costPrice,
    this.sellingPrice,
    this.imagePath,
    this.createdAt,
  });

  factory RawMaterial.fromMap(Map<String, dynamic> map) {
    return RawMaterial(
      id: map['id'] as int?,
      barcode: map['barcode']?.toString(),
      name: map['name']?.toString() ?? '',
      subItem: map['sub_item']?.toString(),
      categoryId: map['category_id'] as int?,
      unitId: map['unit_id'] as int?,
      openingStock:
      (map['opening_stock'] as num?)?.toDouble() ?? 0,
      currentStock:
      (map['current_stock'] as num?)?.toDouble() ?? 0,
      reorderLevel:
      (map['reorder_level'] as num?)?.toDouble() ?? 0,
      shelfLifeDays:
      (map['shelf_life_days'] as num?)?.toInt(),
      unitsPerPacket:
      (map['units_per_packet'] as num?)?.toDouble(),
      entryPasswordHash:
      map['entry_password_hash']?.toString(),
      costPrice:
      (map['cost_price'] as num?)?.toDouble(),
      sellingPrice:
      (map['selling_price'] as num?)?.toDouble(),
      imagePath:
      map['image_path']?.toString(),
      createdAt:
      _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'sub_item': subItem,
      'category_id': categoryId,
      'unit_id': unitId,
      'opening_stock': openingStock,
      'current_stock': currentStock,
      'reorder_level': reorderLevel,
      'shelf_life_days': shelfLifeDays,
      'units_per_packet': unitsPerPacket,
      'entry_password_hash': entryPasswordHash,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'image_path': imagePath,
      'created_at':
      createdAt?.toIso8601String() ??
          DateTime.now().toIso8601String(),
    };
  }

  bool get isLowStock {
    return currentStock <= reorderLevel;
  }

  String? get trimmedSubItem {
    final value = subItem?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}


// ============================================================
// COMBO
// ============================================================

class Combo {
  final int? id;

  final String name;
  final String? barcode;

  final int? categoryId;

  final double price;

  final String? imagePath;

  final bool isActive;

  /// Read/display-only list.
  ///
  /// This is populated by the repository/UI after loading the combo.
  /// It is NOT stored in the `combos` table.
  final List<ComboItem> items;

  final DateTime? createdAt;

  Combo({
    this.id,
    required this.name,
    this.barcode,
    this.categoryId,
    this.price = 0,
    this.imagePath,
    this.isActive = true,
    this.items = const [],
    this.createdAt,
  });

  factory Combo.fromMap(Map<String, dynamic> map) {
    return Combo(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      categoryId: map['category_id'] as int?,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      imagePath: map['image_path']?.toString(),
      isActive: (map['is_active'] as num?)?.toInt() == 1,
      items: const [],
      createdAt: _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'category_id': categoryId,
      'price': price,
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
      'created_at':
      createdAt?.toIso8601String() ??
          DateTime.now().toIso8601String(),
    };
  }
}

// ============================================================
// COMBO RAW MATERIAL
// ============================================================
//
// Database relationship:
//
// combos
//    ↓
// combo_raw_materials
//    ↓
// raw_materials
//
// ============================================================

class ComboRawMaterial {
  final int? id;

  final int comboId;
  final int rawMaterialId;

  final double qty;

  ComboRawMaterial({
    this.id,
    required this.comboId,
    required this.rawMaterialId,
    required this.qty,
  });

  factory ComboRawMaterial.fromMap(
      Map<String, dynamic> map,
      ) {
    return ComboRawMaterial(
      id: map['id'] as int?,
      comboId: map['combo_id'] as int,
      rawMaterialId:
      map['raw_material_id'] as int,
      qty:
      (map['qty'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'combo_id': comboId,
      'raw_material_id': rawMaterialId,
      'qty': qty,
    };
  }
}


// ============================================================
// COMBO ITEM
// ============================================================
//
// UI/read model.
//
// This is intentionally separate from ComboRawMaterial because
// comboItems() also returns material name, stock and unit.
//
// ============================================================

class ComboItem {
  final int? id;
  final int comboId;
  final int rawMaterialId;

  final double qty;

  final String? materialName;
  final double? currentStock;
  final String? unit;

  ComboItem({
    this.id,
    required this.comboId,
    required this.rawMaterialId,
    required this.qty,
    this.materialName,
    this.currentStock,
    this.unit,
  });

  factory ComboItem.fromMap(
      Map<String, dynamic> map,
      ) {
    return ComboItem(
      id: map['id'] as int?,
      comboId:
      (map['combo_id'] as num?)?.toInt() ?? 0,
      rawMaterialId:
      (map['raw_material_id'] as num?)?.toInt() ?? 0,
      qty:
      (map['qty'] as num?)?.toDouble() ?? 0,
      materialName:
      map['material_name']?.toString(),
      currentStock:
      (map['current_stock'] as num?)?.toDouble(),
      unit:
      map['unit']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'combo_id': comboId,
      'raw_material_id': rawMaterialId,
      'qty': qty,
      'material_name': materialName,
      'current_stock': currentStock,
      'unit': unit,
    };
  }

  ComboRawMaterial toComboRawMaterial() {
    return ComboRawMaterial(
      id: id,
      comboId: comboId,
      rawMaterialId: rawMaterialId,
      qty: qty,
    );
  }
}


// ============================================================
// CART LINE
// ============================================================

class CartLine {
  final int? rawMaterialId;
  final int? comboId;

  final String name;
  final String? subItem;

  final double qty;
  final double price;

  CartLine({
    this.rawMaterialId,
    this.comboId,
    required this.name,
    this.subItem,
    required this.qty,
    required this.price,
  });

  double get amount {
    return qty * price;
  }

  bool get isRawMaterial {
    return rawMaterialId != null &&
        comboId == null;
  }

  bool get isCombo {
    return comboId != null &&
        rawMaterialId == null;
  }

  Map<String, dynamic> toMap() {
    return {
      'raw_material_id': rawMaterialId,
      'combo_id': comboId,
      'item_name': name,
      'sub_item': subItem,
      'qty': qty,
      'price': price,
      'amount': amount,
    };
  }
}


// ============================================================
// DATE HELPER
// ============================================================

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value;
  }

  final text = value.toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text);
}
