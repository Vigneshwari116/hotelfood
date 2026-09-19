import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shilpa_api/location_menu_scoping.dart';
import 'package:shilpa_api/postgres_app_db.dart';
import 'package:test/test.dart';

/// VPS / pg_dump regression: restored databases may lack [stock_source_id] and
/// per-location menu columns until migrations run. Tests mirror [DbStore.open]
/// (ensureSchema → migrate) and the direct migration entry point.
///
/// Run against a **disposable** database (this test drops `public` each run):
/// POSTGRES_TEST_URL=postgres://user:pass@127.0.0.1:5432/dbname dart test test/location_menu_startup_test.dart
void main() {
  final url = Platform.environment['POSTGRES_TEST_URL'];
  if (url == null || url.isEmpty) {
    test(
      'Postgres menu migration on legacy pg_dump-shaped schema',
      () {},
      skip: 'Set POSTGRES_TEST_URL to run',
    );
    return;
  }

  group('legacy pg_dump-shaped database', () {
    late Endpoint endpoint;
    late Connection conn;

    setUp(() async {
      final uri = Uri.parse(url);
      endpoint = Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.isEmpty ? 'postgres' : uri.pathSegments.last,
        username: uri.userInfo.split(':').first,
        password: uri.userInfo.contains(':')
            ? uri.userInfo.split(':').skip(1).join(':')
            : '',
      );

      conn = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      await conn.execute('DROP SCHEMA IF EXISTS public CASCADE');
      await conn.execute('CREATE SCHEMA public');
      await _applyLegacyPgDumpFixture(conn);
      await _seedLegacySharedMenu(conn);
    });

    tearDown(() async {
      await conn.close();
    });

    test('DbStore.open path: ensureSchema then migrate completes', () async {
      final db = PostgresAppDb(conn, connection: conn);
      await db.ensureSchema();
      await migrateMenuCatalogToLocationScope(db);

      await _expectMigrationSucceeded(conn);
    });

    test('migrate alone on pg_dump snapshot without stock_source_id', () async {
      final hasStockSource = await conn.execute('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'raw_materials'
          AND column_name = 'stock_source_id'
      ''');
      expect(hasStockSource.first.first, 0);

      final db = PostgresAppDb(conn, connection: conn);
      await migrateMenuCatalogToLocationScope(db);

      await _expectMigrationSucceeded(conn);
    });
  });
}

Future<void> _applyLegacyPgDumpFixture(Connection conn) async {
  final fixture = File('test/fixtures/legacy_pg_dump_menu_schema.sql');
  final sql = await fixture.readAsString();
  for (final statement in _splitSqlStatements(sql)) {
    await conn.execute(statement);
  }
}

Iterable<String> _splitSqlStatements(String sql) sync* {
  final buffer = StringBuffer();
  for (final line in sql.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('--')) {
      continue;
    }
    buffer.writeln(line);
    if (trimmed.endsWith(';')) {
      final statement = buffer.toString().trim();
      buffer.clear();
      if (statement.isNotEmpty) {
        yield statement.substring(0, statement.length - 1);
      }
    }
  }
}

Future<void> _seedLegacySharedMenu(Connection conn) async {
  final now = DateTime.now().toIso8601String();
  await conn.execute(
    Sql('INSERT INTO locations (name, created_at) VALUES (\$1, \$2)'),
    parameters: ['Gt world mall', now],
  );
  await conn.execute(
    Sql('INSERT INTO locations (name, created_at) VALUES (\$1, \$2)'),
    parameters: ['Magadi road', now],
  );
  await conn.execute(
    Sql('INSERT INTO locations (name, created_at) VALUES (\$1, \$2)'),
    parameters: ['Subbanna garden', now],
  );
  await conn.execute(
    Sql(
      'INSERT INTO raw_materials (barcode, name, sub_item, created_at) '
      'VALUES (\$1, \$2, \$2, \$3)',
    ),
    parameters: ['TEA-001', 'Tea', now],
  );
  await conn.execute(
    Sql(
      'INSERT INTO location_stock '
      '(location_id, raw_material_id, current_stock, opening_stock) '
      'VALUES (1, 1, 10, 10), (2, 1, 20, 20), (3, 1, 5, 5)',
    ),
  );
  await conn.execute(
    Sql(
      'INSERT INTO combos (name, price, selling_price, created_at) '
      'VALUES (\$1, 99, 99, \$2)',
    ),
    parameters: ['Big juicy burger', now],
  );
}

Future<void> _expectMigrationSucceeded(Connection conn) async {
  final combos = await conn.execute('SELECT COUNT(*)::int FROM combos');
  expect(combos.first.first, 3);

  final materials = await conn.execute('SELECT COUNT(*)::int FROM raw_materials');
  expect(materials.first.first, 3);

  final applied = await conn.execute(
    Sql(
      "SELECT COUNT(*)::int FROM schema_migrations "
      "WHERE name = 'location_menu_catalog_scope_v1'",
    ),
  );
  expect(applied.first.first, 1);

  final duplicateNames = await conn.execute('''
    SELECT COUNT(*)::int
    FROM (
      SELECT location_id, lower(name) AS n
      FROM combos
      GROUP BY location_id, lower(name)
      HAVING COUNT(*) > 1
    ) dup
  ''');
  expect(duplicateNames.first.first, 0);
}
