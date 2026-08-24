import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  static const _userKey = 'auth_username';
  static const _roleKey = 'auth_role';

  final String username;
  final String role;

  const AuthSession({required this.username, required this.role});

  static Future<void> save({
    required String username,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, username);
    await prefs.setString(_roleKey, role);
  }

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_userKey);
    final role = prefs.getString(_roleKey);
    if (username == null || username.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return AuthSession(username: username, role: role);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_roleKey);
  }
}
