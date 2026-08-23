import 'package:flutter/material.dart';

class BrandAssets {
  static const logo = 'assets/branding/shilpa_logo.png';
  static const icon = 'assets/branding/shilpa_icon.png';
  static const chicken = 'assets/branding/five_star_chicken.png';
  static const thankYou = 'assets/branding/thank_you_hands.png';
}

class BrandLogo extends StatelessWidget {
  final double height;
  final BoxFit fit;

  const BrandLogo({
    super.key,
    this.height = 140,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.logo,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
    );
  }
}
