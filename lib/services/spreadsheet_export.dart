import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class SpreadsheetExport {
  static String buildCsv(
    List<String> headers,
    List<List<String>> rows,
  ) {
    String cell(String value) {
      if (value.contains(',') ||
          value.contains('"') ||
          value.contains('\n')) {
        return '"${value.replaceAll('"', '""')}"';
      }
      return value;
    }

    final buffer = StringBuffer();
    buffer.writeln(headers.map(cell).join(','));
    for (final row in rows) {
      final padded = [
        for (var i = 0; i < headers.length; i++)
          i < row.length ? row[i] : '',
      ];
      buffer.writeln(padded.map(cell).join(','));
    }
    return buffer.toString();
  }

  static Uint8List buildXlsx(
    List<String> headers,
    List<List<String>> rows,
  ) {
    final allRows = [headers, ...rows];
    final sharedStrings = <String>[];
    final sharedIndex = <String, int>{};

    int sharedStringIndex(String value) {
      final existing = sharedIndex[value];
      if (existing != null) return existing;
      final index = sharedStrings.length;
      sharedStrings.add(value);
      sharedIndex[value] = index;
      return index;
    }

    final sheetData = StringBuffer();
    for (var rowIndex = 0; rowIndex < allRows.length; rowIndex++) {
      final row = allRows[rowIndex];
      final rowNumber = rowIndex + 1;
      sheetData.write('<row r="$rowNumber">');
      for (var colIndex = 0; colIndex < row.length; colIndex++) {
        final cellRef = '${_columnLetter(colIndex)}$rowNumber';
        final value = row[colIndex];
        final numeric = double.tryParse(value.replaceAll(',', ''));
        if (numeric != null &&
            value.trim().isNotEmpty &&
            RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value.trim())) {
          sheetData.write('<c r="$cellRef"><v>$value</v></c>');
        } else {
          final index = sharedStringIndex(value);
          sheetData.write('<c r="$cellRef" t="s"><v>$index</v></c>');
        }
      }
      sheetData.write('</row>');
    }

    final sharedXml = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'count="${sharedStrings.length}" uniqueCount="${sharedStrings.length}">',
    );
    for (final value in sharedStrings) {
      sharedXml.write('<si><t>${_escapeXml(value)}</t></si>');
    }
    sharedXml.write('</sst>');

    final sheetXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>$sheetData</sheetData>'
        '</worksheet>';

    final workbookXml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>';

    final workbookRels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet1.xml"/>'
        '</Relationships>';

    final rootRels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '</Relationships>';

    final contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '</Types>';

    final archive = Archive()
      ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)))
      ..addFile(ArchiveFile('xl/workbook.xml', workbookXml.length, utf8.encode(workbookXml)))
      ..addFile(ArchiveFile('xl/_rels/workbook.xml.rels', workbookRels.length, utf8.encode(workbookRels)))
      ..addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheetXml.length, utf8.encode(sheetXml)))
      ..addFile(ArchiveFile('xl/sharedStrings.xml', sharedXml.length, sharedXml.toString().codeUnits));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static String _columnLetter(int index) {
    var n = index + 1;
    final buffer = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buffer.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
