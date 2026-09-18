import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/trial_license.dart';

void main() {
  test('applyFromHealth parses warning state', () {
    final license = TrialLicense.instance;
    license.applyFromHealth({
      'license_expires_at': '2026-10-20T23:59:59.000Z',
      'license_expired': false,
      'license_days_remaining': 3,
      'license_warning': true,
    });

    expect(license.expired, isFalse);
    expect(license.daysRemaining, 3);
    expect(license.warning, isTrue);

    license.clear();
  });

  test('warning message uses day count', () {
    final license = TrialLicense.instance;
    license.applyFromHealth({
      'license_expires_at': '2026-10-20T23:59:59.000Z',
      'license_expired': false,
      'license_days_remaining': 5,
      'license_warning': true,
    });

    expect(
      license.warningMessage,
      'Trial ends in 5 days — contact us to continue.',
    );

    license.applyFromHealth({
      'license_expires_at': '2026-10-20T23:59:59.000Z',
      'license_expired': false,
      'license_days_remaining': 1,
      'license_warning': true,
    });
    expect(
      license.warningMessage,
      'Trial ends tomorrow — contact us to continue.',
    );

    license.clear();
  });
}
