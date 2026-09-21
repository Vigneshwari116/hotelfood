/// Tags the current inventory write with a human-readable source for audit logs.
class InventoryChangeContext {
  InventoryChangeContext._();

  static String? _source;

  static String? get source => _source;

  static Future<T> run<T>(
    String source,
    Future<T> Function() action,
  ) async {
    final previous = _source;
    _source = source;
    try {
      return await action();
    } finally {
      _source = previous;
    }
  }
}
