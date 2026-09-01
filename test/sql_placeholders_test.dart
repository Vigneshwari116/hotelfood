import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sql_placeholders.dart';

void main() {
  test('converts sqlite placeholders to postgres dollars', () {
    final converted = sqliteToPostgres(
      'SELECT * FROM sales WHERE sale_date >= ? AND sale_date < ?',
      ['a', 'b'],
    );
    expect(
      converted.$1,
      'SELECT * FROM sales WHERE sale_date >= \$1 AND sale_date < \$2',
    );
    expect(converted.$2, ['a', 'b']);
  });

  test('rewrites IFNULL to COALESCE', () {
    final converted = sqliteToPostgres(
      "GROUP BY IFNULL(si.sub_item, '')",
    );
    expect(converted.$1, contains('COALESCE('));
  });
}
