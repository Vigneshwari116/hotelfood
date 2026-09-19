import 'app_db.dart';

/// Tracks one-time repair of combo ingredient FKs after per-location menu clone.
const comboIngredientLocationRepairV1 = 'combo_ingredient_location_repair_v1';

/// PostgreSQL repair statement (also in [scripts/repair_combo_ingredient_locations.sql]).
const postgresComboIngredientLocationRepairSql = '''
WITH mismatched AS (
  SELECT
    crm.id AS link_id,
    (
      SELECT rm_target.id
      FROM raw_materials rm_target
      WHERE rm_target.location_id = c.location_id
        AND lower(trim(rm_target.name)) = lower(trim(rm_wrong.name))
        AND lower(trim(coalesce(nullif(trim(rm_target.sub_item), ''), rm_target.name)))
          = lower(trim(coalesce(nullif(trim(rm_wrong.sub_item), ''), rm_wrong.name)))
        AND (
          rm_wrong.barcode IS NULL
          OR trim(rm_wrong.barcode::text) = ''
          OR rm_target.barcode IS NOT DISTINCT FROM rm_wrong.barcode
        )
        AND (
          rm_wrong.category_id IS NULL
          OR rm_target.category_id = rm_wrong.category_id
        )
      ORDER BY rm_target.id ASC
      LIMIT 1
    ) AS correct_material_id
  FROM combo_raw_materials crm
  JOIN combos c ON c.id = crm.combo_id
  JOIN raw_materials rm_wrong ON rm_wrong.id = crm.raw_material_id
  WHERE c.location_id IS NOT NULL
    AND rm_wrong.location_id IS NOT NULL
    AND c.location_id != rm_wrong.location_id
)
UPDATE combo_raw_materials crm
SET raw_material_id = mismatched.correct_material_id
FROM mismatched
WHERE crm.id = mismatched.link_id
  AND mismatched.correct_material_id IS NOT NULL
''';

const postgresCrossLocationComboIngredientCountSql = '''
SELECT COUNT(*)::int AS c
FROM combo_raw_materials crm
JOIN combos c ON c.id = crm.combo_id
JOIN raw_materials rm ON rm.id = crm.raw_material_id
WHERE c.location_id IS NOT NULL
  AND rm.location_id IS NOT NULL
  AND c.location_id != rm.location_id
''';

Future<int> countCrossLocationComboIngredientLinks(AppDb db) async {
  final rows = await db.rawQuery(postgresCrossLocationComboIngredientCountSql);
  final value = rows.first['c'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
