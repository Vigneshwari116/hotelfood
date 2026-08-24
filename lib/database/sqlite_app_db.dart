import 'package:sqflite/sqflite.dart';

import 'package:foodstock/database/app_db.dart';

class SqliteAppDb implements AppDb {
  SqliteAppDb(this._db);

  final DatabaseExecutor _db;

  @override
  Future<int> insert(String table, Map<String, Object?> values) {
    return _db.insert(table, values);
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
    return _db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _db.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawQuery(sql, arguments);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDb txn) action) {
    final db = _db;
    if (db is Database) {
      return db.transaction((txn) => action(SqliteAppDb(txn)));
    }
    return action(this);
  }
}
