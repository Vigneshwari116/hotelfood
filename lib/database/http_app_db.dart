import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foodstock/database/api_config.dart';
import 'package:foodstock/database/app_db.dart';

class HttpAppDb implements AppDb {
  HttpAppDb({this.txId});

  final String? txId;
  final _client = http.Client();

  Uri _uri(String path) => Uri.parse('${ApiConfig.url}$path');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-api-key': ApiConfig.apiKey,
      };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError(
        'Shop server returned an invalid response (${response.statusCode}).',
      );
    }
    if (response.statusCode >= 400 || decoded['ok'] != true) {
      throw StateError(
        decoded['error']?.toString() ??
            'Shop server error (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _db(Map<String, Object?> body) {
    return _post('/v1/db', {
      if (txId != null) 'tx': txId,
      ...body,
    });
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values) async {
    final result = await _db({
      'method': 'insert',
      'table': table,
      'values': values,
    });
    return (result['id'] as num?)?.toInt() ?? 0;
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
  }) async {
    final result = await _db({
      'method': 'query',
      'table': table,
      'distinct': distinct,
      'columns': columns,
      'where': where,
      'whereArgs': whereArgs,
      'groupBy': groupBy,
      'having': having,
      'orderBy': orderBy,
      'limit': limit,
      'offset': offset,
    });
    return _rows(result);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final result = await _db({
      'method': 'update',
      'table': table,
      'values': values,
      'where': where,
      'whereArgs': whereArgs,
    });
    return (result['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final result = await _db({
      'method': 'delete',
      'table': table,
      'where': where,
      'whereArgs': whereArgs,
    });
    return (result['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final result = await _db({
      'method': 'rawQuery',
      'sql': sql,
      'arguments': arguments,
    });
    return _rows(result);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDb txn) action) async {
    final begun = await _post('/v1/tx/begin', {});
    final id = begun['tx']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Shop server did not start a transaction.');
    }
    try {
      final value = await action(HttpAppDb(txId: id));
      await _post('/v1/tx/commit', {'tx': id});
      return value;
    } catch (error) {
      try {
        await _post('/v1/tx/rollback', {'tx': id});
      } catch (_) {}
      rethrow;
    }
  }

  List<Map<String, Object?>> _rows(Map<String, dynamic> result) {
    final rows = result['rows'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          {
            for (final entry in row.entries) '${entry.key}': entry.value,
          },
    ];
  }
}
