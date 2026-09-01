import 'package:flutter_test/flutter_test.dart';

import 'package:foodstock/main.dart';

void main() {
  testWidgets('RestoPosApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const RestoPosApp());
    await tester.pump();
  });
}
