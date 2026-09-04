import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sales_export_service.dart';
import 'package:foodstock/services/spreadsheet_export.dart';

void main() {
  test('import filename must match location name exactly', () {
    final service = ItemImportService();
    expect(
      () => service.validateImportFilename(
        '/tmp/Gt world mall.xlsx',
        'Gt world mall',
      ),
      returnsNormally,
    );
    expect(
      () => service.validateImportFilename(
        '/tmp/Magadi road.xlsx',
        'Gt world mall',
      ),
      throwsA(
        isA<InvalidInventoryException>().having(
          (e) => e.message,
          'message',
          'This file is for a different location',
        ),
      ),
    );
  });

  test('sales export includes customer columns', () {
    final csv = SalesExportService.buildCsv([
      {
        'id': 1,
        'sale_date': '2026-09-04T10:00:00.000',
        'location_name': 'Gt world mall',
        'customer_name': 'Ravi',
        'customer_phone': '9876543210',
        'subtotal': 100,
        'tax': 0,
        'discount': 0,
        'total': 100,
        'payment_type': 'cash',
        'is_voided': 0,
      },
    ]);

    expect(csv, contains('customer_name'));
    expect(csv, contains('mobile'));
    expect(csv, contains('Ravi'));
    expect(csv, contains('9876543210'));
  });

  test('spreadsheet export builds non-empty xlsx bytes', () {
    final bytes = SpreadsheetExport.buildXlsx(
      const ['a', 'b'],
      const [
        ['1', 'two'],
      ],
    );
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(2)), 'PK');
  });
}
