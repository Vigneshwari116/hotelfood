import 'dart:io';

import 'package:postgres/postgres.dart';

Endpoint postgresEndpointFromUrl(String url) {
  final uri = Uri.parse(url);
  return Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.isEmpty ? 'postgres' : uri.pathSegments.last,
    username: uri.userInfo.split(':').first,
    password: uri.userInfo.contains(':')
        ? uri.userInfo.split(':').skip(1).join(':')
        : '',
  );
}

Future<Connection> openLegacyPostgresConnection(Endpoint endpoint) {
  return Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
}

Future<void> resetPublicSchema(Connection conn) async {
  await conn.execute('DROP SCHEMA IF EXISTS public CASCADE');
  await conn.execute('CREATE SCHEMA public');
}

Future<void> applyLegacyPgDumpFixture(Connection conn) async {
  final fixture = File('test/fixtures/legacy_pg_dump_menu_schema.sql');
  final sql = await fixture.readAsString();
  for (final statement in splitSqlStatements(sql)) {
    await conn.execute(statement);
  }
}

Future<void> seedLegacyLocations(Connection conn) async {
  final now = DateTime.now().toIso8601String();
  for (final name in [
    'Gt world mall',
    'Magadi road',
    'Subbanna garden',
  ]) {
    await conn.execute(
      Sql('INSERT INTO locations (name, created_at) VALUES (\$1, \$2)'),
      parameters: [name, now],
    );
  }
}

Future<void> seedCatalogRows(
  Connection conn, {
  required int materialCount,
  required int comboCount,
}) async {
  final now = DateTime.now().toIso8601String();
  for (var i = 1; i <= materialCount; i++) {
    await conn.execute(
      Sql(
        'INSERT INTO raw_materials (barcode, name, sub_item, created_at) '
        'VALUES (\$1, \$2, \$2, \$3)',
      ),
      parameters: ['RM-${i.toString().padLeft(4, '0')}', 'Material $i', now],
    );
  }
  for (var i = 1; i <= comboCount; i++) {
    await conn.execute(
      Sql(
        'INSERT INTO combos (name, price, selling_price, created_at) '
        'VALUES (\$1, 99, 99, \$2)',
      ),
      parameters: ['Combo $i', now],
    );
  }
}

Iterable<String> splitSqlStatements(String sql) sync* {
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
