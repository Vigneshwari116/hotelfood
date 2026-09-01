import 'package:postgres/postgres.dart';

import 'app_db.dart';
import 'postgres_schema.dart';
import 'sql_placeholders.dart';

class PostgresAppDb implements AppDb {
  PostgresAppDb(this._session, {Connection? connection})
      : _connection = connection;

  final Session _session;
  final Connection? _connection;

  Future<void> ensureSchema() async {
    for (final statement in postgresSchemaStatements) {
      await _session.execute(statement);
    }
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values) async {
    final columns = values.keys.toList();
    final parameters = [for (final key in columns) values[key]];
    final placeholders = [
      for (var i = 0; i < columns.length; i++) '\$${i + 1}',
    ];
    final sql =
        'INSERT INTO $table (${columns.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id';
    final result = await _session.execute(sql, parameters: parameters);
    final id = normalizePgValue(result.first.first);
    if (id is int) return id;
    if (id is num) return id.toInt();
    return 0;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    final select = (columns == null || columns.isEmpty)
        ? '*'
        : columns.join(', ');
    final sql = StringBuffer(
      'SELECT ${distinct == true ? 'DISTINCT ' : ''}$select FROM $table',
    );
    if (where != null && where.isNotEmpty) {
      sql.write(' WHERE $where');
    }
    if (groupBy != null && groupBy.isNotEmpty) {
      sql.write(' GROUP BY $groupBy');
    }
    if (having != null && having.isNotEmpty) {
      sql.write(' HAVING $having');
    }
    if (orderBy != null && orderBy.isNotEmpty) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }
    if (offset != null) {
      sql.write(' OFFSET $offset');
    }
    return rawQuery(sql.toString(), whereArgs);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (values.isEmpty) return 0;
    final columns = values.keys.toList();
    final setParts = [
      for (var i = 0; i < columns.length; i++) '${columns[i]} = \$${i + 1}',
    ];
    var sql = 'UPDATE $table SET ${setParts.join(', ')}';
    final parameters = [for (final key in columns) values[key]];
    if (where != null && where.isNotEmpty) {
      final converted = sqliteToPostgres(where, whereArgs);
      var rewritten = converted.$1;
      if (columns.isNotEmpty) {
        rewritten = rewritten.replaceAllMapped(RegExp(r'\$(\d+)'), (match) {
          final n = int.parse(match.group(1)!);
          return '\$${n + columns.length}';
        });
      }
      sql = '$sql WHERE $rewritten';
      parameters.addAll(converted.$2);
    }
    final result = await _session.execute(sql, parameters: parameters);
    return result.affectedRows;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    var sql = 'DELETE FROM $table';
    List<Object?> parameters = const [];
    if (where != null && where.isNotEmpty) {
      final converted = sqliteToPostgres(where, whereArgs);
      sql = '$sql WHERE ${converted.$1}';
      parameters = converted.$2;
    }
    final result = await _session.execute(sql, parameters: parameters);
    return result.affectedRows;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final converted = sqliteToPostgres(sql, arguments);
    final result = await _session.execute(
      converted.$1,
      parameters: converted.$2,
    );
    return [
      for (final row in result) normalizePgRow(row.toColumnMap()),
    ];
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDb txn) action) {
    final conn = _connection;
    if (conn != null) {
      return conn.runTx((session) => action(PostgresAppDb(session)));
    }
    return action(this);
  }
}
