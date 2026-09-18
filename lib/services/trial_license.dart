import 'package:flutter/foundation.dart';
import 'package:foodstock/database/api_config.dart';

/// Trial/license status fetched from the VPS /health endpoint.
class TrialLicense extends ChangeNotifier {
  TrialLicense._();

  static final TrialLicense instance = TrialLicense._();

  static const warningDays = 5;
  static const expiredMessage =
      'Trial period has ended. Contact us to continue.';

  DateTime? expiresAt;
  bool expired = false;
  int? daysRemaining;
  bool warning = false;

  bool get isActiveOnServer => ApiConfig.enabled;

  bool get showWarning =>
      isActiveOnServer && !expired && warning && daysRemaining != null;

  String get warningMessage {
    final days = daysRemaining ?? 0;
    if (days == 1) {
      return 'Trial ends tomorrow — contact us to continue.';
    }
    return 'Trial ends in $days days — contact us to continue.';
  }

  void applyFromHealth(Map<String, dynamic> body) {
    final rawExpiry = body['license_expires_at'];
    expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    expired = body['license_expired'] == true;
    final rawDays = body['license_days_remaining'];
    daysRemaining = rawDays is num ? rawDays.toInt() : null;
    warning = body['license_warning'] == true;
    notifyListeners();
  }

  void clear() {
    expiresAt = null;
    expired = false;
    daysRemaining = null;
    warning = false;
    notifyListeners();
  }
}
