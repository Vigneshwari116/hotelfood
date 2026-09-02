import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  static const _userKey = 'auth_username';
  static const _roleKey = 'auth_role';
  static const _locationIdKey = 'auth_location_id';
  static const _locationNameKey = 'auth_location_name';

  final String username;
  final String role;
  final int? locationId;
  final String? locationName;

  const AuthSession({
    required this.username,
    required this.role,
    this.locationId,
    this.locationName,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  static Future<void> save({
    required String username,
    required String role,
    int? locationId,
    String? locationName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, username);
    await prefs.setString(_roleKey, role);
    if (locationId == null) {
      await prefs.remove(_locationIdKey);
      await prefs.remove(_locationNameKey);
    } else {
      await prefs.setInt(_locationIdKey, locationId);
      await prefs.setString(_locationNameKey, locationName ?? '');
    }
  }

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_userKey);
    final role = prefs.getString(_roleKey);
    if (username == null || username.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    final locationId = prefs.containsKey(_locationIdKey)
        ? prefs.getInt(_locationIdKey)
        : null;
    final locationName = prefs.getString(_locationNameKey);
    return AuthSession(
      username: username,
      role: role,
      locationId: locationId,
      locationName: locationName?.isEmpty == true ? null : locationName,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_locationIdKey);
    await prefs.remove(_locationNameKey);
  }
}
