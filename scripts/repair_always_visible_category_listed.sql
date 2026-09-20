-- Force listed = 1 for Sauces, Fried Items, Snacks, Uncategorized (all locations).
-- Run after pg_dump backup. Safe to re-run (idempotent).

BEGIN;

UPDATE raw_materials rm
SET listed = 1
FROM categories c
WHERE c.id = rm.category_id
  AND c.type = 'raw_material'
  AND lower(trim(c.name)) IN ('sauces', 'fried items', 'snacks', 'uncategorized')
  AND COALESCE(rm.listed, 1) <> 1;

-- Expect zero rows:
SELECT c.name AS category_name, COUNT(*) AS still_hidden
FROM raw_materials rm
JOIN categories c ON c.id = rm.category_id
WHERE c.type = 'raw_material'
  AND lower(trim(c.name)) IN ('sauces', 'fried items', 'snacks', 'uncategorized')
  AND COALESCE(rm.listed, 1) = 0
GROUP BY c.name
ORDER BY c.name;

INSERT INTO schema_migrations (name, applied_at)
VALUES ('always_visible_category_listed_repair_v1', NOW() AT TIME ZONE 'utc')
ON CONFLICT (name) DO NOTHING;

COMMIT;
