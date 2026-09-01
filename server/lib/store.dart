import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

import 'env.dart';
import 'postgres_app_db.dart';

class DbStore {
  DbStore(this._pool, this._endpoint);

  final Pool _pool;
  final Endpoint _endpoint;
  final _txs = <String, Connection>{};

  static Future<DbStore> open() async {
    if (Env.pgDatabase == 'db_accounting_testing' ||
        Env.pgDatabase == 'db_accounting_live') {
      throw StateError('Refusing to use an accounting database.');
    }
    if (Env.pgPassword.isEmpty) {
      throw StateError('PGPASSWORD is not set.');
    }
    final endpoint = Endpoint(
      host: Env.pgHost,
      port: Env.pgPort,
      database: Env.pgDatabase,
      username: Env.pgUser,
      password: Env.pgPassword,
    );
    final pool = Pool(
      endpoint,
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
      Future<void> user(String username, String password, String role) async {
        final rows = await db.query(
          'users',
          where: 'username = ?',
          whereArgs: [username],
          limit: 1,
        );
        if (rows.isNotEmpty) return;
        await db.insert('users', {
          'username': username,
          'password_hash': sha256.convert(utf8.encode(password)).toString(),
          'role': role,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Must match Flutter hashPin (utf8.encode then sha256).
      await user('admin', 'admin123', 'admin');
      await user('staff', 'staff123', 'staff');
    });
  }

  Future<void> close() async {
    for (final id in _txs.keys.toList()) {
      await rollback(id);
    }
    await _pool.close();
  }
}
