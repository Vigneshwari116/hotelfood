import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/spreadsheet_export.dart';

void main() {
  test('xlsx shared strings are valid utf-8 and readable by Excel', () {
    final bytes = SpreadsheetExport.buildXlsx(
      const ['category', 'item_name', 'barcode'],
      const [
        ['Snacks', 'Chicken 65', 'SNACKS'],
      ],
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedEntry = archive.files.firstWhere(
      (file) => file.name == 'xl/sharedStrings.xml',
    );
    final sharedXml = utf8.decode(sharedEntry.content as List<int>);

    expect(sharedXml, contains('<si><t>category</t></si>'));
    expect(sharedXml, contains('<si><t>Snacks</t></si>'));
    expect(sharedXml, contains('<si><t>Chicken 65</t></si>'));
    expect(sharedXml, contains('<si><t>SNACKS</t></si>'));

    final workbookRels = utf8.decode(
      archive.files
          .firstWhere((file) => file.name == 'xl/_rels/workbook.xml.rels')
          .content as List<int>,
    );
    expect(workbookRels, contains('sharedStrings.xml'));
  });
}
