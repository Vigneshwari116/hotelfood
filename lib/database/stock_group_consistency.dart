import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// One inconsistent field between siblings in a shared stock group.
class StockGroupMismatch {
  const StockGroupMismatch({
    required this.stockKey,
    required this.field,
    required this.itemId,
    required this.itemName,
    required this.detail,
  });

  final String stockKey;
  final String field;
  final int itemId;
  final String itemName;
  final String detail;
}

Future<List<RawMaterial>> _stockGroupFamily(
  AppDb db, {
  required RawMaterial probe,
  int? catalogLocationId,
}) async {
  final stockKey = SubItemStock.stockKey(probe);
  if (stockKey == null || stockKey.isEmpty) return const [];

  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'unit_id',
      'units_per_packet',
      'location_id',
      'variant_group',
      'stock_source_id',
    ],
  );

  final family = <RawMaterial>[];
  for (final row in rows) {
    final item = RawMaterial(
      id: row['id'] as int?,
      name: row['name']?.toString() ?? '',
      subItem: row['sub_item']?.toString(),
      unitId: (row['unit_id'] as num?)?.toInt(),
      unitsPerPacket: (row['units_per_packet'] as num?)?.toDouble(),
      locationId: (row['location_id'] as num?)?.toInt(),
      variantGroup: row['variant_group']?.toString(),
      stockSourceId: (row['stock_source_id'] as num?)?.toInt(),
    );
    if (catalogLocationId != null &&
        item.locationId != null &&
        item.locationId != catalogLocationId) {
      continue;
    }
    if (SubItemStock.stockKey(item) == stockKey) {
      family.add(item);
    }
  }
  return family;
}

/// Read-only scan for mismatched [unit_id] or partial [units_per_packet] in a group.
Future<List<StockGroupMismatch>> auditStockGroupMismatches(
  AppDb db, {
  int? locationId,
}) async {
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'unit_id',
      'units_per_packet',
      'location_id',
    ],
  );

  final byKey = <String, List<RawMaterial>>{};
  for (final row in rows) {
    final item = RawMaterial(
      id: row['id'] as int?,
      name: row['name']?.toString() ?? '',
      subItem: row['sub_item']?.toString(),
      unitId: (row['unit_id'] as num?)?.toInt(),
      unitsPerPacket: (row['units_per_packet'] as num?)?.toDouble(),
      locationId: (row['location_id'] as num?)?.toInt(),
    );
    if (locationId != null &&
        item.locationId != null &&
        item.locationId != locationId) {
      continue;
    }
    final key =
        '${item.locationId ?? 0}|${SubItemStock.stockKey(item) ?? ''}';
    if (key.endsWith('|')) continue;
    byKey.putIfAbsent(key, () => []).add(item);
  }

  final mismatches = <StockGroupMismatch>[];
  for (final entry in byKey.entries) {
    final family = entry.value;
    if (family.length < 2) continue;
    final stockKey = SubItemStock.stockKey(family.first) ?? entry.key;

    final unitIds = family.map((i) => i.unitId).toSet();
    unitIds.remove(null);
    if (unitIds.length > 1) {
      for (final item in family) {
        if (item.id == null) continue;
        mismatches.add(
          StockGroupMismatch(
            stockKey: stockKey,
            field: 'unit_id',
            itemId: item.id!,
            itemName: item.name,
            detail:
                'Group uses multiple units (${unitIds.join(', ')}); '
                'every sibling must share the same unit.',
          ),
        );
      }
    }

    final packetValues = family
        .map((i) => i.unitsPerPacket)
        .where((v) => v != null && v! > 0)
        .toSet();
    final anyPacket = packetValues.isNotEmpty;
    final allPacket = family.every(
      (i) => i.unitsPerPacket != null && i.unitsPerPacket! > 0,
    );
    if (anyPacket && !allPacket) {
      for (final item in family) {
        if (item.id == null) continue;
        final missing = item.unitsPerPacket == null || item.unitsPerPacket! <= 0;
        if (!missing) continue;
        mismatches.add(
          StockGroupMismatch(
            stockKey: stockKey,
            field: 'units_per_packet',
            itemId: item.id!,
            itemName: item.name,
            detail:
                'Another item in this stock group has units per packet set — '
                'enter the same value for "${item.name}".',
          ),
        );
      }
    }
  }
  return mismatches;
}

/// Rejects saves that would leave a stock group with inconsistent units or packets.
Future<void> assertStockGroupConsistency(
  AppDb db, {
  required RawMaterial material,
  int? catalogLocationId,
}) async {
  final family = await _stockGroupFamily(
    db,
    probe: material,
    catalogLocationId: catalogLocationId,
  );
  if (family.length < 2) return;

  final label = material.salesLabel;
  final unitIds = {
    for (final item in family)
      if (item.unitId != null) item.unitId!,
  };
  if (material.unitId != null) {
    unitIds.add(material.unitId!);
  }
  if (unitIds.length > 1) {
    throw StockGroupConsistencyException(
      '$label: this stock group must use one unit for every size — '
      'matched unit ids: ${unitIds.join(', ')}.',
    );
  }

  final siblingsWithPackets = family
      .where((i) => i.unitsPerPacket != null && i.unitsPerPacket! > 0)
      .toList();
  final probePackets = material.unitsPerPacket;
  final anyPackets = siblingsWithPackets.isNotEmpty ||
      (probePackets != null && probePackets > 0);
  if (!anyPackets) return;

  if (probePackets == null || probePackets <= 0) {
    final example = siblingsWithPackets.isNotEmpty
        ? siblingsWithPackets.first.name
        : 'another size';
    throw StockGroupConsistencyException(
      '$label: "$example" in this stock group has units per packet set — '
      'enter units per packet for every item in the group.',
    );
  }

  for (final sibling in siblingsWithPackets) {
    final theirs = sibling.unitsPerPacket;
    if (theirs == null || theirs <= 0) continue;
    if ((theirs - probePackets).abs() > 0.000001) {
      throw StockGroupConsistencyException(
        '$label: units per packet must match "${sibling.name}" '
        '(${theirs.toStringAsFixed(0)}) in this stock group.',
      );
    }
  }
}

class StockGroupConsistencyException implements Exception {
  StockGroupConsistencyException(this.message);

  final String message;

  @override
  String toString() => message;
}
