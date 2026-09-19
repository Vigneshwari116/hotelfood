import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/screens/menu_items_grid_screen.dart';

void main() {
  testWidgets('stock source grid select cell builds RawAutocomplete without assertion',
      (tester) async {
    final controller = TextEditingController(text: 'Chicken 65');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: buildMenuGridSelectCellForTesting(
              controller: controller,
              options: const ['Chicken 65', 'Tea', 'Krusty Bites'],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Chicken 65'), findsOneWidget);
  });
}
