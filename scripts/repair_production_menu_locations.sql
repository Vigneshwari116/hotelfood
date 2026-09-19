-- Production menu repairs (run after one pg_dump backup).
-- Order: listed visibility first (unblocks Purchase/POS pickers), then combo FKs.

-- 1) Listed / is_active sync for locations 2+
\i repair_listed_location_clone.sql

-- 2) Combo ingredient location FKs
\i repair_combo_ingredient_locations.sql
