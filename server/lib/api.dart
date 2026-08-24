import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'env.dart';
import 'store.dart';

Response _json(Object body, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

bool _authorized(Request request) {
  final key = request.headers['x-api-key'] ?? '';
  return key.isNotEmpty && key == Env.apiKey;
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry('$key', value));
  }
  throw const FormatException('JSON object required');
}

List<Object?>? _list(dynamic value) {
  if (value == null) return null;
  if (value is List) return [for (final item in value) item];
  return null;
}

Map<String, Object?> _map(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  }
  return {};
}

Handler buildApi(DbStore store) {
  final router = Router();

  router.get('/health', (Request request) {
    return _json({'ok': true, 'database': Env.pgDatabase});
  });

  Future<Response> guarded(
    Request request,
    Future<Response> Function() action,
  ) async {
    if (!_authorized(request)) {
      return _json({'ok': false, 'error': 'Unauthorized'}, status: 401);
    }
    try {
      return await action();
    } catch (error) {
      return _json({'ok': false, 'error': '$error'}, status: 400);
    }
  }

  router.post('/v1/tx/begin', (Request request) {
    return guarded(request, () async {
      final id = await store.begin();
      return _json({'ok': true, 'tx': id});
    });
  });

  router.post('/v1/tx/commit', (Request request) {
    return guarded(request, () async {
      final body = await _readJson(request);
      await store.commit('${body['tx'] ?? ''}');
      return _json({'ok': true});
    });
  });

  router.post('/v1/tx/rollback', (Request request) {
    return guarded(request, () async {
      final body = await _readJson(request);
      await store.rollback('${body['tx'] ?? ''}');
      return _json({'ok': true});
    });
  });

  router.post('/v1/db', (Request request) {
    return guarded(request, () async {
      final body = await _readJson(request);
      final tx = body['tx']?.toString();
      final method = '${body['method'] ?? ''}';
      final result = await store.withDb(tx, (db) async {
        switch (method) {
          case 'insert':
            final id = await db.insert(
              '${body['table']}',
              _map(body['values']),
            );
            return {'ok': true, 'id': id};
          case 'query':
            final rows = await db.query(
              '${body['table']}',
              distinct: body['distinct'] as bool?,
              columns: _list(body['columns'])?.map((e) => '$e').toList(),
              where: body['where'] as String?,
              whereArgs: _list(body['whereArgs']),
              groupBy: body['groupBy'] as String?,
              having: body['having'] as String?,
              orderBy: body['orderBy'] as String?,
              limit: (body['limit'] as num?)?.toInt(),
              offset: (body['offset'] as num?)?.toInt(),
            );
            return {'ok': true, 'rows': rows};
          case 'update':
            final count = await db.update(
              '${body['table']}',
              _map(body['values']),
              where: body['where'] as String?,
              whereArgs: _list(body['whereArgs']),
            );
            return {'ok': true, 'count': count};
          case 'delete':
            final count = await db.delete(
              '${body['table']}',
              where: body['where'] as String?,
              whereArgs: _list(body['whereArgs']),
            );
            return {'ok': true, 'count': count};
          case 'rawQuery':
            final rows = await db.rawQuery(
              '${body['sql']}',
              _list(body['arguments']),
            );
            return {'ok': true, 'rows': rows};
          default:
            throw StateError('Unknown method $method');
        }
      });
      return _json(result);
    });
  });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
}

Future<void> serve(DbStore store) async {
  final server = await io.serve(buildApi(store), InternetAddress.anyIPv4, Env.port);
  stdout.writeln(
    'Shilpa API listening on ${server.address.host}:${server.port} '
    '(database ${Env.pgDatabase})',
  );
}
