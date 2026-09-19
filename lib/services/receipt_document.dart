import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_profile.dart';

/// Shared receipt payload for PDF preview and Bluetooth ESC/POS printing.
class ReceiptDocument {
  final int saleId;
  final List<CartLine> lines;
  final String paymentType;
  final double subtotal;
  final double tax;
  final double discount;
  final double grandTotal;
  final String? customerName;
  final String? customerPhone;
  final String? locationName;
  final DateTime billedAt;

  ReceiptDocument({
    required this.saleId,
    required this.lines,
    required this.paymentType,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.grandTotal,
    this.customerName,
    this.customerPhone,
    this.locationName,
    DateTime? billedAt,
  }) : billedAt = billedAt ?? DateTime.now();

  String get headerAddressLine =>
      ReceiptProfile.addressLineForLocation(locationName);

  bool get hasCustomer =>
      (customerName?.trim().isNotEmpty ?? false) ||
      (customerPhone?.trim().isNotEmpty ?? false);

  String? get trimmedCustomerName {
    final value = customerName?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? get trimmedCustomerPhone {
    final value = customerPhone?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
