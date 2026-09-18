import 'package:test/test.dart';

import 'package:shilpa_api/license.dart';

void main() {
  group('License raw SQL classification', () {
    test('SELECT and WITH queries are read-only', () {
      expect(License.isWriteRawQuery('SELECT * FROM sales'), isFalse);
      expect(
        License.isWriteRawQuery('WITH x AS (SELECT 1) SELECT * FROM x'),
        isFalse,
      );
      expect(License.isWriteRawQuery('EXPLAIN SELECT 1'), isFalse);
    });

    test('mutating SQL is treated as a write', () {
      expect(License.isWriteRawQuery('INSERT INTO sales VALUES (1)'), isTrue);
      expect(License.isWriteRawQuery('UPDATE users SET role = ?'), isTrue);
      expect(License.isWriteRawQuery('DELETE FROM sales'), isTrue);
    });
  });
}
