import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/variant_helpers.dart';

/// Mirrors POS variant-card add rules: only variant selector taps add to cart.
class PosCartSimulator {
  PosCartSimulator(this.regular, this.large);

  final RawMaterial regular;
  final RawMaterial large;
  final List<CartLine> cart = [];
  int? selectedId;

  String _label(RawMaterial material) =>
      VariantHelpers.variantSelectorLabel(material);

  int _indexFor(RawMaterial material) {
    if (material.id == null) return -1;
    final label = _label(material);
    return cart.indexWhere(
      (line) =>
          line.rawMaterialId == material.id &&
          (line.variantLabel ?? '') == label,
    );
  }

  void onVariantTapped(RawMaterial variant) {
    final id = variant.id;
    if (id == null) return;

    selectedId = id;
    addRawMaterial(variant);
  }

  /// Variant card image/price areas are display-only (no independent add).
  void onVariantCardTapped(RawMaterial selected) {}

  void addRawMaterial(
    RawMaterial material, {
    double qty = 1,
  }) {
    if (material.id == null) return;
    final variantLabel = _label(material);
    final index = _indexFor(material);

    if (index == -1) {
      cart.add(
        CartLine(
          rawMaterialId: material.id,
          name: material.name,
          variantLabel: variantLabel,
          qty: qty,
          price: material.sellingPrice ?? 0,
        ),
      );
      return;
    }

    final old = cart[index];
    cart[index] = CartLine(
      rawMaterialId: old.rawMaterialId,
      name: old.name,
      variantLabel: old.variantLabel,
      qty: old.qty + qty,
      price: old.price,
    );
  }
}

void main() {
  group('POS cart variant flow (14c staging scenario)', () {
    late RawMaterial regular;
    late RawMaterial large;
    late PosCartSimulator sim;

    setUp(() {
      regular = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn',
        variantLabel: 'Regular',
        sellingPrice: 75,
      );
      large = RawMaterial(
        id: 2,
        name: 'Chicken popcorn large',
        subItem: 'Chicken Popcorn',
        variantLabel: 'popcorn large',
        sellingPrice: 129,
      );
      sim = PosCartSimulator(regular, large);
      sim.selectedId = regular.id;
    });

    test('Regular x2 → Large x1 → Regular x3 with two cart lines total', () {
      sim.onVariantTapped(regular);
      sim.onVariantTapped(regular);
      expect(sim.cart.length, 1);
      expect(sim.cart.first.qty, 2);

      sim.onVariantTapped(large);
      expect(sim.cart.length, 2);
      expect(sim.cart.firstWhere((l) => l.rawMaterialId == 1).qty, 2);
      expect(sim.cart.firstWhere((l) => l.rawMaterialId == 2).qty, 1);

      sim.onVariantTapped(regular);
      expect(sim.cart.length, 2);
      expect(sim.cart.firstWhere((l) => l.rawMaterialId == 1).qty, 3);
      expect(sim.cart.firstWhere((l) => l.rawMaterialId == 2).qty, 1);
    });

    test('repeat tap on same variant increments without extra lines', () {
      sim.onVariantTapped(large);
      sim.onVariantTapped(large);
      sim.onVariantTapped(large);

      expect(sim.cart.length, 1);
      expect(sim.cart.single.rawMaterialId, 2);
      expect(sim.cart.single.qty, 3);
    });

    test('chip tap then card tap adds only once', () {
      sim.onVariantTapped(regular);
      sim.onVariantCardTapped(regular);

      expect(sim.cart.length, 1);
      expect(sim.cart.single.qty, 1);
    });
  });
}
