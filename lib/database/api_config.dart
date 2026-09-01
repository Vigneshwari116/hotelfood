class ApiConfig {
  static const url = String.fromEnvironment(
    'SHILPA_API_URL',
    defaultValue: 'http://187.127.180.135:8080',
  );

  static const apiKey = String.fromEnvironment(
    'SHILPA_API_KEY',
    defaultValue: 'shilpa-enterprise-api',
  );

  static const useLocalDb = bool.fromEnvironment(
    'SHILPA_LOCAL_DB',
    defaultValue: false,
  );

  static bool get enabled => !useLocalDb && url.isNotEmpty;
}
