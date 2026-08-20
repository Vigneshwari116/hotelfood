import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/branding/app_brand.dart';
import 'package:foodstock/widgets/brand_logo.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('login branding asset is registered', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrandLogo(height: 80),
        ),
      ),
    );

    expect(find.byType(BrandLogo), findsOneWidget);
    expect(AppBrand.name, 'Shilpa Enterprise');
  });
}
