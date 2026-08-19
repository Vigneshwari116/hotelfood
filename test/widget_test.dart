import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/repository.dart';

void main() {
  test('PIN hashing is deterministic', () {
    final first = hashPin('admin123');
    final second = hashPin('admin123');

    expect(first, second);
    expect(first.length, 64);
    expect(first, isNot(equals(hashPin('other-pin'))));
  });
}
