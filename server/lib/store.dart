import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

import 'env.dart';
import 'location_menu_scoping.dart';
import 'postgres_app_db.dart';

class DbStore {
  DbStore(this._pool, this._endpoint);

  final Pool _pool;
  final Endpoint _endpoint;
  final _txs = <String, Connection>{};

  static Future<DbStore> open({Endpoint? testEndpoint}) async {
    final endpoint = testEndpoint ??
        Endpoint(
          host: Env.pgHost,
          port: Env.pgPort,
          database: Env.pgDatabase,
          username: Env.pgUser,
          password: Env.pgPassword,
        );
    if (endpoint.database == 'db_accounting_testing' ||
        endpoint.database == 'db_accounting_live') {
      throw StateError('Refusing to use an accounting database.');
    }
    if (endpoint.password == null || endpoint.password!.isEmpty) {
      throw StateError('PGPASSWORD is not set.');
    }
    final pool = Pool.withEndpoints(
      [endpoint],
      settings: const PoolSettings(
        maxConnectionCount: 16,
        sslMode: SslMode.disable,
        connectTimeout: Duration(seconds: 20),
      ),
    );
    final store = DbStore(pool, endpoint);
    await store._withAutocommit((db) => db.ensureSchema());
    await store._ensureDefaults();
    return store;
  }

  Endpoint get endpoint => _endpoint;

  Future<T> _withAutocommit<T>(Future<T> Function(PostgresAppDb db) fn) {
    return _pool.withConnection((conn) => fn(PostgresAppDb(conn, connection: conn)));
  }

  Future<T> withDb<T>(
    String? txId,
    Future<T> Function(PostgresAppDb db) fn,
  ) async {
    if (txId == null || txId.isEmpty) {
      return _withAutocommit(fn);
    }
    final conn = _txs[txId];
    if (conn == null) {
      throw StateError('Transaction is not active.');
    }
    return fn(PostgresAppDb(conn));
  }

  Future<String> begin() async {
    Connection conn;
    try {
      conn = await Connection.open(
        _endpoint,
        settings: const ConnectionSettings(
          sslMode: SslMode.disable,
          connectTimeout: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      conn = await Connection.open(
        _endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.require),
      );
    }
    await conn.execute('BEGIN');
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    _txs[id] = conn;
    return id;
  }

  Future<void> commit(String txId) async {
    final conn = _txs.remove(txId);
    if (conn == null) throw StateError('Transaction is not active.');
    try {
      await conn.execute('COMMIT');
    } finally {
      await conn.close();
    }
  }

  Future<void> rollback(String txId) async {
    final conn = _txs.remove(txId);
    if (conn == null) return;
    try {
      await conn.execute('ROLLBACK');
    } finally {
      await conn.close();
    }
  }

  Future<void> _ensureDefaults() async {
    await _withAutocommit((db) async {
      final now = DateTime.now().toIso8601String();

      Future<int> ensureLocation(String name) async {
        final rows = await db.query(
          'locations',
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return rows.first['id'] as int;
        }
        return db.insert('locations', {
          'name': name,
          'created_at': now,
        });
      }

      Future<void> ensureUser(
        String username,
        String password,
        String role, {
        int? locationId,
      }) async {
        final rows = await db.query(
          'users',
          where: 'username = ?',
          whereArgs: [username],
          limit: 1,
        );
        final values = {
          'username': username,
          'password_hash': sha256.convert(utf8.encode(password)).toString(),
          'role': role,
          'location_id': locationId,
        };
        if (rows.isEmpty) {
          await db.insert('users', {
            ...values,
            'created_at': now,
          });
          return;
        }
        await db.update(
          'users',
          values,
          where: 'username = ?',
          whereArgs: [username],
        );
      }

      final gtWorldMall = await ensureLocation('Gt world mall');
      final magadiRoad = await ensureLocation('Magadi road');
      final subbannaGarden = await ensureLocation('Subbanna garden');
      const locationPassword = 'Shilpa@0902';

      await ensureUser('admin', 'admin123', 'admin');
      await ensureUser(
        'Gt mall five star',
        locationPassword,
        'location',
        locationId: gtWorldMall,
      );
      await ensureUser(
        'Gt mall staff',
        locationPassword,
        'staff',
        locationId: gtWorldMall,
      );
      await ensureUser(
        'Magadi road five star',
        locationPassword,
        'location',
        locationId: magadiRoad,
      );
      await ensureUser(
        'Magadi road staff',
        locationPassword,
        'staff',
        locationId: magadiRoad,
      );
      await ensureUser(
        'Subbanna garden five star',
        locationPassword,
        'location',
        locationId: subbannaGarden,
      );
      await ensureUser(
        'Subbanna garden staff',
        locationPassword,
        'staff',
        locationId: subbannaGarden,
      );
      await ensureUser('staff', 'staff123', 'staff');
      await migrateMenuCatalogToLocationScope(db);
    });
  }

  Future<void> close() async {
    for (final id in _txs.keys.toList()) {
      await rollback(id);
    }
    await _pool.close();
  }
}
