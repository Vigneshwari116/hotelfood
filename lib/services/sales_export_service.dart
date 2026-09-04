import 'dart:typed_data';

import 'package:foodstock/services/spreadsheet_export.dart';

class SalesExportService {
  static const headers = [
    'sale_id',
    'sale_date',
    'location',
    'customer_name',
    'mobile',
    'subtotal',
    'tax',
    'discount',
    'total',
    'payment_type',
    'voided',
  ];

  static String buildCsv(List<Map<String, dynamic>> rows) {
    return SpreadsheetExport.buildCsv(headers, _toRows(rows));
  }

  static Uint8List buildXlsx(List<Map<String, dynamic>> rows) {
    return SpreadsheetExport.buildXlsx(headers, _toRows(rows));
  }

  static List<List<String>> _toRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      return [
        row['id']?.toString() ?? '',
        row['sale_date']?.toString() ?? '',
        row['location_name']?.toString() ?? '',
        row['customer_name']?.toString() ?? '',
        row['customer_phone']?.toString() ?? '',
        _formatNumber(row['subtotal']),
        _formatNumber(row['tax']),
        _formatNumber(row['discount']),
        _formatNumber(row['total']),
        row['payment_type']?.toString() ?? '',
        ((row['is_voided'] as num?)?.toInt() ?? 0) == 1 ? 'yes' : 'no',
      ];
    }).toList();
  }

  static String _formatNumber(Object? value) {
    if (value == null) return '';
    final number = (value as num).toDouble();
    if (number % 1 == 0) return number.toStringAsFixed(0);
    return number.toStringAsFixed(2);
  }
}
