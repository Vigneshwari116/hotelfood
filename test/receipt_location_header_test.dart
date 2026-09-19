import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/esc_pos_receipt_builder.dart';
import 'package:foodstock/services/receipt_document.dart';
import 'package:foodstock/services/receipt_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default address when sale location is unknown', () {
    expect(
      ReceiptProfile.addressLineForLocation(null),
      ReceiptProfile.defaultAddress,
    );
    expect(
      ReceiptDocument(
        saleId: 1,
        lines: const [],
        paymentType: 'Cash',
        subtotal: 0,
        tax: 0,
        discount: 0,
        grandTotal: 0,
      ).headerAddressLine,
      ReceiptProfile.defaultAddress,
    );
  });

  test('receipt address line uses sale location name', () {
    const locationName = 'Magadi road';
    final document = ReceiptDocument(
      saleId: 111,
      lines: [
        CartLine(name: 'Combo test', qty: 1, price: 199),
      ],
      paymentType: 'Cash',
      subtotal: 199,
      tax: 0,
      discount: 0,
      grandTotal: 199,
      locationName: locationName,
    );

    expect(
      document.headerAddressLine,
      'MAGADI ROAD, BANGALORE-560040',
    );
    expect(
      ReceiptProfile.addressLineForLocation('Gt world mall'),
      'GT WORLD MALL, BANGALORE-560040',
    );
  });

  test('ESC/POS receipt bytes include location in address line', () async {
    final document = ReceiptDocument(
      saleId: 111,
      lines: [
        CartLine(name: 'Tea', qty: 1, price: 10),
      ],
      paymentType: 'Cash',
      subtotal: 10,
      tax: 0,
      discount: 0,
      grandTotal: 10,
      locationName: 'Magadi road',
    );

    final bytes = await EscPosReceiptBuilder.build(
      profile: ReceiptProfile.defaults(),
      document: document,
    );

    final text = String.fromCharCodes(bytes);
    expect(text, contains('MAGADI ROAD, BANGALORE-560040'));
    expect(text, isNot(contains('SUBBANNA GARDEN')));
  });
}
