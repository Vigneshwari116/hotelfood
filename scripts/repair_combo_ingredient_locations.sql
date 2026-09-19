-- One-time repair: remap combo_raw_materials at locations 2+ that still point at
-- location-1 (or other wrong) raw_material_id rows after menu clone (PR #88).
--
-- BEFORE RUNNING ON PRODUCTION:
--   pg_dump -Fc -h HOST -U USER -d DATABASE -f pre_combo_repair_$(date +%Y%m%d_%H%M).dump
--
-- Run inside a transaction; verify counts before COMMIT.

BEGIN;

-- 1) Baseline (expect ~68 on your production audit)
SELECT COUNT(*) AS mismatched_links_before
FROM combo_raw_materials crm
JOIN combos c ON c.id = crm.combo_id
JOIN raw_materials rm ON rm.id = crm.raw_material_id
WHERE c.location_id IS NOT NULL
  AND rm.location_id IS NOT NULL
  AND c.location_id != rm.location_id;

-- 2) Optional: list unresolved combos if any remain after UPDATE
-- (run again after step 3 if count > 0)

-- 3) Repair (idempotent — re-run yields 0 updates once clean)
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
  AND mismatched.correct_material_id IS NOT NULL;

-- 4) Must be 0 before COMMIT
SELECT COUNT(*) AS mismatched_links_after
FROM combo_raw_materials crm
JOIN combos c ON c.id = crm.combo_id
JOIN raw_materials rm ON rm.id = crm.raw_material_id
WHERE c.location_id IS NOT NULL
  AND rm.location_id IS NOT NULL
  AND c.location_id != rm.location_id;

-- If mismatched_links_after > 0, ROLLBACK and inspect remaining rows:
-- SELECT c.id, c.name, c.location_id, crm.raw_material_id, rm.name, rm.location_id
-- FROM combo_raw_materials crm
-- JOIN combos c ON c.id = crm.combo_id
-- JOIN raw_materials rm ON rm.id = crm.raw_material_id
-- WHERE c.location_id IS NOT NULL AND rm.location_id IS NOT NULL
--   AND c.location_id != rm.location_id;

COMMIT;

-- Record one-time migration if deploying via app (optional; server ensureSchema also inserts this):
-- INSERT INTO schema_migrations (name, applied_at)
-- VALUES ('combo_ingredient_location_repair_v1', NOW() AT TIME ZONE 'utc')
-- ON CONFLICT (name) DO NOTHING;
