import 'package:shared_preferences/shared_preferences.dart';

/// Header/footer printed on 58mm thermal bills (POSiFLOW / ESC-POS).
class ReceiptProfile {
  static const shopNameKey = 'receipt_shop_name';
  static const addressKey = 'receipt_address';
  static const phoneKey = 'receipt_phone';
  static const emailKey = 'receipt_email';

  static const defaultShopName = 'FIVE STAR';
  static const defaultAddress = 'SUBBANNA GARDEN, BANGALORE-560040';
  static const defaultPhone = '9739577651';
  static const defaultEmail = 'shilpaenterprise@gmail.com';
  static const footerBrand = 'SHILPA ENTERPRISE';

  final String shopName;
  final String address;
  final String phone;
  final String email;

  const ReceiptProfile({
    required this.shopName,
    required this.address,
    required this.phone,
    required this.email,
  });

  factory ReceiptProfile.defaults() {
    return const ReceiptProfile(
      shopName: defaultShopName,
      address: defaultAddress,
      phone: defaultPhone,
      email: defaultEmail,
    );
  }

  factory ReceiptProfile.fromPrefs(SharedPreferences prefs) {
    return ReceiptProfile(
      shopName: _orDefault(prefs.getString(shopNameKey), defaultShopName),
      address: _orDefault(prefs.getString(addressKey), defaultAddress),
      phone: _orDefault(prefs.getString(phoneKey), defaultPhone),
      email: _orDefault(prefs.getString(emailKey), defaultEmail),
    );
  }

  static String _orDefault(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    return value.trim();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(shopNameKey, shopName.trim());
    await prefs.setString(addressKey, address.trim());
    await prefs.setString(phoneKey, phone.trim());
    await prefs.setString(emailKey, email.trim());
  }

  static Future<ReceiptProfile> load() async {
    return ReceiptProfile.defaults();
  }
}
