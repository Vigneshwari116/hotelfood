import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/user_roles.dart';

void main() {
  group('UserRoles', () {
    test('location manager has full app access', () {
      expect(
        UserRoles.hasFullAppAccess(UserRoles.location, locationId: 1),
        isTrue,
      );
      expect(
        UserRoles.hasFullAppAccess(UserRoles.staff, locationId: 1),
        isFalse,
      );
    });

    test('location staff is limited role', () {
      expect(
        UserRoles.isLocationStaff(UserRoles.staff, locationId: 2),
        isTrue,
      );
      expect(
        UserRoles.isLocationStaff(UserRoles.location, locationId: 2),
        isFalse,
      );
      expect(
        UserRoles.isLocationStaff(UserRoles.staff, locationId: null),
        isFalse,
      );
    });

    test('admin has full app access without location', () {
      expect(UserRoles.hasFullAppAccess(UserRoles.admin), isTrue);
      expect(UserRoles.isAdmin(UserRoles.admin), isTrue);
    });
  });
}
