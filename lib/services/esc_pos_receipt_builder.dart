import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:foodstock/services/receipt_document.dart';
import 'package:foodstock/services/receipt_layout.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/widgets/brand_logo.dart';

class EscPosReceiptBuilder {
  static const topLogoWidth = 104;
  static const footerLogoWidth = 118;

  static Future<List<int>> build({
    required ReceiptProfile profile,
    required ReceiptDocument document,
    bool testBanner = false,
  }) async {
    final generator = Generator(
      PaperSize.mm58,
      await CapabilityProfile.load(),
    );

    var bytes = <int>[];
    bytes += generator.reset();

    bytes += await _logo(generator, BrandAssets.chicken, topLogoWidth);

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
        'Bill #${document.saleId}',
        ReceiptLayout.billWhen(document.billedAt),
      ),
    );
    bytes += generator.text(ReceiptLayout.dash());

    final customerName = document.trimmedCustomerName;
    if (customerName != null) {
      bytes += generator.text('Customer: $customerName');
    }
    final customerPhone = document.trimmedCustomerPhone;
    if (customerPhone != null) {
      bytes += generator.text('Mobile: $customerPhone');
    }
    if (customerName != null || customerPhone != null) {
      bytes += generator.text(ReceiptLayout.dash());
    }

    bytes += generator.text(
      ReceiptLayout.pair('Item x Qty', 'Rate'),
      styles: const PosStyles(bold: true),
    );

    for (final line in document.lines) {
      final printed = ReceiptLayout.itemLines(
        name: line.name,
        qty: ReceiptLayout.qtyText(line.qty),
        rate: ReceiptLayout.money(line.amount),
      );
      for (final row in printed) {
        bytes += generator.text(row);
      }
      if (ReceiptLayout.extraDetail(line.name, line.subItem)) {
        bytes += generator.text('  ${line.subItem!.trim()}');
      }
    }

    bytes += generator.text(ReceiptLayout.dash());
    bytes += generator.text(
      ReceiptLayout.pair(
        'SubTotal',
        ReceiptLayout.money(document.subtotal, forceDecimals: true),
      ),
    );
    if (document.tax > 0) {
      bytes += generator.text(
        ReceiptLayout.pair(
          ReceiptLayout.taxLabel(document.tax, document.subtotal),
          ReceiptLayout.money(document.tax, forceDecimals: true),
        ),
      );
    }
    if (document.discount > 0) {
      bytes += generator.text(
        ReceiptLayout.pair(
          'Discount',
          ReceiptLayout.money(document.discount, forceDecimals: true),
        ),
      );
    }
    bytes += generator.text(
      ReceiptLayout.pair(
        'Grand Total',
        ReceiptLayout.money(document.grandTotal, forceDecimals: true),
      ),
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
      ),
    );

    bytes += await _logo(generator, BrandAssets.logo, footerLogoWidth);
    bytes += generator.text(
      'Thank You',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  static Future<List<int>> _logo(
    Generator generator,
    String asset, [
    int width = 104,
  ]) async {
    try {
      final data = await rootBundle.load(asset);
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded == null) return <int>[];
      final resized = img.copyResize(
        decoded,
        width: width,
        interpolation: img.Interpolation.average,
      );
      return generator.image(img.grayscale(resized));
    } catch (_) {
      return <int>[];
    }
  }
}
