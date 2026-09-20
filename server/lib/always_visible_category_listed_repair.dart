const alwaysVisibleCategoryListedRepairV1 =
    'always_visible_category_listed_repair_v1';

const postgresAlwaysVisibleCategoryListedRepairSql = '''
UPDATE raw_materials rm
SET listed = 1
FROM categories c
WHERE c.id = rm.category_id
  AND c.type = 'raw_material'
  AND lower(trim(c.name)) IN ('sauces', 'fried items', 'snacks', 'uncategorized')
  AND COALESCE(rm.listed, 1) <> 1
''';

const postgresAlwaysVisibleCategoryListedAuditSql = '''
SELECT c.name AS category_name, COUNT(*)::int AS hidden_count
FROM raw_materials rm
JOIN categories c ON c.id = rm.category_id
WHERE c.type = 'raw_material'
  AND lower(trim(c.name)) IN ('sauces', 'fried items', 'snacks', 'uncategorized')
  AND COALESCE(rm.listed, 1) = 0
GROUP BY c.name
ORDER BY c.name
''';
