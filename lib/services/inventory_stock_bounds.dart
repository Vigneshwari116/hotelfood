/// Application-layer stock quantity limits (mirrors production CHECK constraints).
class InventoryStockBounds {
  InventoryStockBounds._();

  static const double minQuantity = -1000;
  static const double maxQuantityExclusive = 100000;

  static void requireFiniteQuantity(
    double? value, {
    required String fieldLabel,
    required String itemLabel,
  }) {
    if (value == null) return;
    if (value.isNaN || value.isInfinite) {
      throw InventoryStockBoundsException(
        '$itemLabel: $fieldLabel must be a valid number.',
      );
    }
    if (value < minQuantity) {
      throw InventoryStockBoundsException(
        '$itemLabel: $fieldLabel cannot be below ${minQuantity.toStringAsFixed(0)}.',
      );
    }
    if (value >= maxQuantityExclusive) {
      throw InventoryStockBoundsException(
        '$itemLabel: $fieldLabel must be below '
        '${maxQuantityExclusive.toStringAsFixed(0)}.',
      );
    }
  }

  static void requirePositiveUnitsPerPacket(
    double? value, {
    required String itemLabel,
  }) {
    if (value == null) return;
    if (value.isNaN || value.isInfinite || value <= 0) {
      throw InventoryStockBoundsException(
        '$itemLabel: units per packet must be a positive number (or left blank).',
      );
    }
  }

  static void requireQuantityAfterDelta({
    required double current,
    required double delta,
    required String itemLabel,
  }) {
    requireFiniteQuantity(
      current + delta,
      fieldLabel: 'current stock',
      itemLabel: itemLabel,
    );
  }
}

class InventoryStockBoundsException implements Exception {
  InventoryStockBoundsException(this.message);

  final String message;

  @override
  String toString() => message;
}
