/// Converts SQLite `?` placeholders to PostgreSQL `$1, $2, ...`.
(String sql, List<Object?> args) sqliteToPostgres(
  String sql, [
  List<Object?>? arguments,
]) {
  var converted = sql.replaceAll('IFNULL(', 'COALESCE(');
  final args = arguments ?? const <Object?>[];
  if (args.isEmpty) {
    return (converted, args);
  }
  var index = 0;
  converted = converted.replaceAllMapped(RegExp(r'\?'), (_) {
    index += 1;
    return '\$$index';
  });
  return (converted, args);
}

Object? normalizePgValue(Object? value) {
  if (value == null) return null;
  if (value is BigInt) return value.toInt();
  if (value is DateTime) return value.toIso8601String();
  return value;
}

Map<String, Object?> normalizePgRow(Map<String, Object?> row) {
  return {
    for (final entry in row.entries) entry.key: normalizePgValue(entry.value),
  };
}
