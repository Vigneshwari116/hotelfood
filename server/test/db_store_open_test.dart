import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shilpa_api/postgres_app_db.dart';
import 'package:shilpa_api/store.dart';
import 'package:test/test.dart';

import 'support/postgres_legacy_fixture.dart';

/// Full [DbStore.open] regression on pg_dump-shaped data: catalog row counts
/// must not shrink during startup (clone migration may multiply rows per shop).
///
/// Uses a disposable database (drops `public` each run). Set [POSTGRES_TEST_URL].
void main() {
  final url = Platform.environment['POSTGRES_TEST_URL'];
  if (url == null || url.isEmpty) {
    test(
      'DbStore.open preserves catalog row counts on legacy pg_dump data',
      () {},
      skip: 'Set POSTGRES_TEST_URL to run',
    );
    return;
  }

  group('DbStore.open on populated legacy database', () {
    late Endpoint endpoint;

    setUpAll(() {
      endpoint = postgresEndpointFromUrl(url);
    });

    test('ensureSchema alone does not delete catalog rows', () async {
      final conn = await openLegacyPostgresConnection(endpoint);
      addTearDown(conn.close);

      await resetPublicSchema(conn);
      await applyLegacyPgDumpFixture(conn);
      await seedLegacyLocations(conn);
      const materialCount = 48;
      const comboCount = 18;
      await seedCatalogRows(
        conn,
        materialCount: materialCount,
        comboCount: comboCount,
      );

      final before = await queryCatalogCounts(conn);
      expect(before.materials, materialCount);
      expect(before.combos, comboCount);

      final db = PostgresAppDb(conn, connection: conn);
      await db.ensureSchema();

      final after = await queryCatalogCounts(conn);
      expect(after.materials, before.materials);
      expect(after.combos, before.combos);
    });

    test('DbStore.open end-to-end does not shrink catalog rows', () async {
      final conn = await openLegacyPostgresConnection(endpoint);
      addTearDown(conn.close);

      await resetPublicSchema(conn);
      await applyLegacyPgDumpFixture(conn);
      await seedLegacyLocations(conn);
      const materialCount = 48;
      const comboCount = 18;
      await seedCatalogRows(
        conn,
        materialCount: materialCount,
        comboCount: comboCount,
      );
      final before = await queryCatalogCounts(conn);
      await conn.close();

      final store = await DbStore.open(testEndpoint: endpoint);
      addTearDown(store.close);

      final after = await queryCatalogCountsOnEndpoint(endpoint);

      expect(
        after.materials >= before.materials,
        isTrue,
        reason: 'startup must never delete raw_materials rows',
      );
      expect(
        after.combos >= before.combos,
        isTrue,
        reason: 'startup must never delete combos rows',
      );

      final locationCount = await locationCountOnEndpoint(endpoint);
      final migrationApplied = await menuMigrationAppliedOnEndpoint(endpoint);
      if (migrationApplied && locationCount >= 2) {
        expect(
          after.materials,
          before.materials * locationCount,
          reason: 'location clone migration multiplies rows per shop',
        );
        expect(
          after.combos,
          before.combos * locationCount,
          reason: 'location clone migration multiplies rows per shop',
        );
      }
    });
  });
}

class CatalogCounts {
  const CatalogCounts(this.materials, this.combos);

  final int materials;
  final int combos;
}

Future<CatalogCounts> queryCatalogCounts(Connection conn) async {
  final materials = await conn.execute('SELECT COUNT(*)::int FROM raw_materials');
  final combos = await conn.execute('SELECT COUNT(*)::int FROM combos');
  return CatalogCounts(
    materials.first.first as int,
    combos.first.first as int,
  );
}

Future<CatalogCounts> queryCatalogCountsOnEndpoint(Endpoint endpoint) async {
  final conn = await openLegacyPostgresConnection(endpoint);
  try {
    return await queryCatalogCounts(conn);
  } finally {
    await conn.close();
  }
}

Future<int> locationCountOnEndpoint(Endpoint endpoint) async {
  final conn = await openLegacyPostgresConnection(endpoint);
  try {
    final result = await conn.execute('SELECT COUNT(*)::int FROM locations');
    return result.first.first as int;
  } finally {
    await conn.close();
  }
}

Future<bool> menuMigrationAppliedOnEndpoint(Endpoint endpoint) async {
  final conn = await openLegacyPostgresConnection(endpoint);
  try {
    final result = await conn.execute(
      Sql(
        "SELECT COUNT(*)::int FROM schema_migrations "
        "WHERE name = 'location_menu_catalog_scope_v1'",
      ),
    );
    return (result.first.first as int) > 0;
  } finally {
    await conn.close();
  }
}
