/// Login roles for Shilpa Enterprise.
class UserRoles {
  UserRoles._();

  static const admin = 'admin';
  static const location = 'location';
  static const staff = 'staff';

  static String normalize(String role) => role.trim().toLowerCase();

  static bool isAdmin(String? role) => normalize(role ?? '') == admin;

  static bool isLocationManager(String? role) =>
      normalize(role ?? '') == location;

  static bool isStaff(String? role) => normalize(role ?? '') == staff;

  /// Location manager — menu, masters, settings, etc.
  static bool hasFullAppAccess(String? role, {int? locationId}) {
    if (isAdmin(role)) return true;
    return isLocationManager(role) && locationId != null;
  }

  /// Counter staff — sales, purchase, reports, dashboard only.
  static bool isLocationStaff(String? role, {int? locationId}) {
    return isStaff(role) && locationId != null;
  }
}
