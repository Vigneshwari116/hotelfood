import 'combo_ingredient_location_repair.dart';

/// One-time data fixes for restored production databases. These must never run
/// on every server boot — only once, tracked in [schema_migrations].
class PostgresDataMigration {
  const PostgresDataMigration(this.name, this.statements);

  final String name;
  final List<String> statements;
}

const postgresOneTimeDataMigrations = <PostgresDataMigration>[
  PostgresDataMigration('postgres_listed_material_dedup_v1', [
    '''
    WITH ranked AS (
      SELECT id,
        ROW_NUMBER() OVER (
          PARTITION BY category_id,
            lower(trim(name)),
            lower(trim(coalesce(nullif(trim(sub_item), ''), name)))
          ORDER BY
            listed DESC,
            abs(current_stock) DESC,
            CASE WHEN units_per_packet IS NOT NULL THEN 0 ELSE 1 END,
            id ASC
        ) AS rn
      FROM raw_materials
      WHERE listed = 1
    )
    UPDATE raw_materials SET listed = 0
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    ''',
  ]),
  PostgresDataMigration('postgres_listed_variant_dedup_v1', [
    '''
    WITH ranked AS (
      SELECT id,
        ROW_NUMBER() OVER (
          PARTITION BY category_id, lower(trim(name))
          ORDER BY
            CASE
              WHEN variant_group IS NOT NULL AND trim(variant_group) <> '' THEN 0
              ELSE 1
            END,
            CASE WHEN lower(coalesce(variant_label, '')) = 'regular' THEN 0 ELSE 1 END,
            id ASC
        ) AS rn
      FROM raw_materials
      WHERE listed = 1
    )
    UPDATE raw_materials SET listed = 0
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    ''',
  ]),
  PostgresDataMigration('postgres_popcorn_snack_listed_fix_v1', [
    '''
    UPDATE raw_materials snacks
    SET listed = 0
    WHERE snacks.listed = 1
      AND lower(snacks.name) LIKE '%popcorn%'
      AND lower(snacks.name) LIKE '%large%'
      AND EXISTS (
        SELECT 1
        FROM raw_materials fried
        JOIN categories fried_cat ON fried_cat.id = fried.category_id
        WHERE fried.listed = 1
          AND lower(fried.name) LIKE '%popcorn%'
          AND lower(fried.name) LIKE '%large%'
          AND lower(fried_cat.name) LIKE '%fried%'
      )
      AND EXISTS (
        SELECT 1 FROM categories snack_cat
        WHERE snack_cat.id = snacks.category_id
          AND lower(snack_cat.name) LIKE '%snack%'
      )
    ''',
  ]),
  PostgresDataMigration('postgres_fried_category_backfill_v1', [
    '''
    UPDATE raw_materials rm
    SET category_id = fried_cat.id
    FROM categories fried_cat
    WHERE fried_cat.type = 'raw_material'
      AND lower(fried_cat.name) LIKE '%fried%'
      AND rm.category_id IS NULL
      AND lower(trim(rm.name)) IN ('paratha', 'bun', 'burger bun with sesame')
    ''',
  ]),
  PostgresDataMigration('postgres_combo_items_backfill_v1', [
    '''
    INSERT INTO combo_raw_materials (combo_id, raw_material_id, qty)
    SELECT ci.combo_id, ci.raw_material_id, ci.qty
    FROM combo_items ci
    WHERE NOT EXISTS (
      SELECT 1
      FROM combo_raw_materials crm
      WHERE crm.combo_id = ci.combo_id
        AND crm.raw_material_id = ci.raw_material_id
    )
    ''',
  ]),
  PostgresDataMigration(
    comboIngredientLocationRepairV1,
    [postgresComboIngredientLocationRepairSql],
  ),
];
