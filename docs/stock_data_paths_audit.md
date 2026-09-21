# Part A — Stock & menu data paths (audit)

This document maps every application code path that reads or writes `raw_materials`,
`location_stock`, and closely related stock tables. Use it with production
`stock_audit_log` when tracing unexpected changes.

## Central write API (`lib/services/repository.dart`)

| Operation | Function | Transaction | `location_id` filter | Validation | Trigger |
|-----------|----------|-------------|----------------------|------------|---------|
| Save menu / stock item | `saveRawMaterial` | Yes | Updates `location_stock` for `_stockLocationId` only; sets `raw_materials.location_id` on save | Bounds, stock group units/packets, stock source, variant labels | User save, import, variant sync |
| Hide from sales | `hideRawMaterial` | No | `id` only | — | User hide, import dedupe |
| Toggle listed | `setRawMaterialListed` | No | `id` only | Always-visible categories forced listed | User toggle |
| Delete item | `deleteRawMaterial` | Yes | Scoped cleanup | — | User delete |
| Purchase | `recordPurchase` | Yes | `_stockLocationId` on batches/ledger/location_stock | Qty/rate, stock group unit | User purchase |
| Sale / POS | `recordSale` | Yes | Sale `location_id`; stock via `_stockLocationId` | Cart normalization; deduct via `_stockMaterialIdForSale` (no double pool debit) | User checkout |
| Stock adjustment | `recordStockAdjustment` | Yes | Location fields on ledger | — | User adjustment |
| Opening / manual stock in editor | `saveRawMaterial` (`fromGridSave`) | Yes | Per-location row | Bounds | Grid save |
| Aggregate sync | `_syncRawMaterialAggregateStock` | Inside parent txn | Sums `location_stock` for material id | — | After stock movement |
| Bump stock | `_bumpStock` | Inside parent txn | `location_id` + `raw_material_id` | Bounds on result | Sales, purchases, adjustments |
| Variant link refresh | `refreshVariantLinks` | Partial | Location-scoped stock_source (PR #94) | — | After save (not grid/import) |
| Expired write-off | `writeOffExpiredStock` | Yes | Location on ledger | — | Deferred startup |

## Menu import (`lib/services/item_import_service.dart`)

| Step | Transaction | Stock preserved? | `listed` side effects |
|------|-------------|------------------|------------------------|
| Per-row `saveRawMaterial(..., fromMenuImport: true)` | Per save (txn inside) | Yes — catalog fields only; stock columns stripped on update | Import row value; post-pass dedupe may call `hideRawMaterial` |
| `_runCatalogMaintenance(aggressiveDedup: true)` | Per statement | Merges can zero duplicate rows | **Can set `listed = 0`** on merged duplicates only during import |
| `_dedupeDuplicateVariantLabels` | Per hide | — | **Explicit `hideRawMaterial`** for duplicate variant labels |
| `_applyVariantAutoLinking` | Per save | — | No direct listed change |

## Catalog maintenance (`lib/database/category_cleanup.dart`)

| Function | Runs on login? | Can change `listed`? |
|----------|----------------|----------------------|
| `runCatalogMaintenance(aggressiveDedup: false)` | Yes (`maintainCatalog`) | No |
| `mergeGlobalStockDuplicateRows` | Import / DB migration only | Yes (duplicates) |
| `dedupeDuplicateRowsInCategory` | Import / migration | Yes |
| `dedupeDuplicateItemNamesInCategory` | Import / migration | Yes |
| `hideSnacksPopcornLargeDuplicates` | Import / migration | Yes |

## Startup / migrations

| Entry | File | Notes |
|-------|------|-------|
| `AppBootstrap.runDeferredInit` | `lib/services/app_bootstrap.dart` | Safe catalog pass; **no** aggressive dedup |
| SQLite upgrades | `lib/database/database_helper.dart` | One-time aggressive dedup only in old version steps |
| Postgres one-time data migrations | `server/lib/postgres_data_migrations.dart` | Historical `listed = 0` dedup (v1) — **not** re-run; repairs in later migrations |
| Location menu clone | `lib/database/location_menu_scoping.dart` | Clones rows per location |
| Listed clone repair | `lib/database/listed_location_clone_repair.dart` | Restores `listed` on clones |
| Orphan FK repair | `lib/database/raw_material_integrity.dart` | Clears bad `stock_source_id` only |

## Server PostgreSQL (`server/lib/postgres_app_db.dart`, `store.dart`)

All Flutter clients talk to the VPS through HTTP `/v1/db` and `/v1/tx/*`; the server
executes the same `Repository` SQL against PostgreSQL with `location_stock` and
`raw_materials` constraints/triggers from `server/lib/postgres_stock_integrity.dart`.

## Incident mapping (hypothesis)

| Symptom | Likely paths to investigate |
|---------|------------------------------|
| `opening_stock` changed without user save | Grid `fromGridSave` baseline sync; Krusty `stock_source` zeroing; import mistaken for stock reset; check `stock_audit_log.change_source` |
| Saved fields reverted | Partial txn (mitigated by single txn); UI without `rawMaterialById` refresh (grid fixed); import overwriting catalog |
| Silent unlist | Import dedupe / `hideRawMaterial`; **not** login `maintainCatalog` after PR #94 |
| Shared group unit error | `_assertStockGroupUnitMatches` / `assertStockGroupConsistency` |
| 100k+ stock | Double import + opening stock apply; mitigated by bounds + idempotent import |
