import 'package:flutter/material.dart';

/// Shared Shilpa Enterprise mark used on login and the console chrome.
class BrandLogo extends StatelessWidget {
  final double height;
  final BoxFit fit;

  const BrandLogo({
    super.key,
    this.height = 140,
    this.fit = BoxFit.contain,
  });

  static const assetPath =
      'assets/branding/shilpa_enterprise_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Shilpa Enterprise',
    );
  }
}
