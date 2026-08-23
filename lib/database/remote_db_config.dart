import 'package:shared_preferences/shared_preferences.dart';

class RemoteDbConfig {
  static const enabledKey = 'vps_pg_enabled';
  static const hostKey = 'vps_pg_host';
  static const portKey = 'vps_pg_port';
  static const databaseKey = 'vps_pg_database';
  static const userKey = 'vps_pg_user';
  static const passwordKey = 'vps_pg_password';

  static const defaultHost = '187.127.180.135';
  static const defaultPort = 5434;
  static const defaultDatabase = 'shilpa_enterprise';
  static const defaultUser = 'postgres';

  final bool enabled;
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  const RemoteDbConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  static Future<RemoteDbConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return RemoteDbConfig(
      enabled: prefs.getBool(enabledKey) ?? false,
      host: prefs.getString(hostKey) ?? defaultHost,
      port: prefs.getInt(portKey) ?? defaultPort,
      database: prefs.getString(databaseKey) ?? defaultDatabase,
      username: prefs.getString(userKey) ?? defaultUser,
      password: prefs.getString(passwordKey) ?? '',
    );
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, enabled);
    await prefs.setString(hostKey, host.trim());
    await prefs.setInt(portKey, port);
    await prefs.setString(databaseKey, database.trim());
    await prefs.setString(userKey, username.trim());
    await prefs.setString(passwordKey, password);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, false);
  }
}
