import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_layout.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/widgets/brand_logo.dart';

class EscPosReceiptBuilder {
  static Future<List<int>> build({
    required ReceiptProfile profile,
    required int saleId,
    required List<CartLine> lines,
    required double subtotal,
    required double tax,
    required double discount,
    required double grandTotal,
    DateTime? billedAt,
    bool testBanner = false,
  }) async {
    final generator = Generator(
      PaperSize.mm58,
      await CapabilityProfile.load(),
    );

    var bytes = <int>[];
    bytes += generator.reset();

    bytes += await _logo(generator, BrandAssets.icon, 168);

    bytes += generator.text(
      profile.shopName.toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    if (profile.address.isNotEmpty) {
      bytes += generator.text(
        profile.address,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (profile.phone.isNotEmpty) {
      bytes += generator.text(
        'Mob No.-${profile.phone}.',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (profile.email.isNotEmpty) {
      bytes += generator.text(
        'Email:${profile.email}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    if (testBanner) {
      bytes += generator.feed(1);
      bytes += generator.text(
        'PRINTER TEST RECEIPT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        ),
      );
    }

    bytes += generator.text(ReceiptLayout.dash());
    bytes += generator.text(
      ReceiptLayout.pair(
        'Bill #$saleId',
        ReceiptLayout.billWhen(billedAt ?? DateTime.now()),
      ),
    );
    bytes += generator.text(ReceiptLayout.dash());
    bytes += generator.text(
      ReceiptLayout.pair('Item x Qty', 'Rate'),
      styles: const PosStyles(bold: true),
    );

    for (final line in lines) {
      final printed = ReceiptLayout.itemLines(
        name: line.name,
        qty: ReceiptLayout.qtyText(line.qty),
        rate: ReceiptLayout.money(line.amount),
      );
      for (final row in printed) {
        bytes += generator.text(row);
      }
      if (line.subItem != null && line.subItem!.trim().isNotEmpty) {
        bytes += generator.text('  ${line.subItem!.trim()}');
      }
    }

    bytes += generator.text(ReceiptLayout.dash());
    bytes += generator.text(
      ReceiptLayout.pair(
        'SubTotal',
        ReceiptLayout.money(subtotal, forceDecimals: true),
      ),
    );
    if (tax > 0) {
      bytes += generator.text(
        ReceiptLayout.pair(
          ReceiptLayout.taxLabel(tax, subtotal),
          ReceiptLayout.money(tax, forceDecimals: true),
        ),
      );
    }
    if (discount > 0) {
      bytes += generator.text(
        ReceiptLayout.pair(
          'Discount',
          ReceiptLayout.money(discount, forceDecimals: true),
        ),
      );
    }
    bytes += generator.text(
      ReceiptLayout.pair(
        'Grand Total',
        ReceiptLayout.money(grandTotal, forceDecimals: true),
      ),
      styles: const PosStyles(bold: true),
    );

    bytes += generator.feed(1);
    bytes += await _logo(generator, BrandAssets.logo, 200);
    bytes += generator.text(
      ReceiptProfile.footerBrand,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );
    bytes += generator.text(
      'Thank You',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );
    bytes += generator.feed(3);
    bytes += generator.cut();
    return bytes;
  }

  static Future<List<int>> _logo(
    Generator generator,
    String asset, [
    int width = 180,
  ]) async {
    try {
      final data = await rootBundle.load(asset);
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded == null) return <int>[];
      final resized = img.copyResize(
        decoded,
        width: width,
        interpolation: img.Interpolation.linear,
      );
      return generator.image(resized);
    } catch (_) {
      return <int>[];
    }
  }
}
