# Changelog

## 0.3.1 (2026-11-22)

### Dependencies

- Accepts PgRest 0.2 and 0.3 (`{:pgrest, "~> 0.2 or ~> 0.3"}`). Tested against PgRest 0.3.0; no code changes.

## 0.3.0 (2026-11-18)

### Dependencies

- Requires PgRest 0.2 (`{:pgrest, "~> 0.2.0"}`). PgRest 0.2
  removed `PgRest.Parser`, `PgRest.Filter` and `PgRest.TypeCaster`; LiveFilter now parses
  operator values with `PgRest.Grammar.Filter.parse_condition/2` and applies filters with
  `PgRest.Ecto.Filter.where/3`.
- Updated for PgRest 0.2's `ecto_sql ~> 3.14` requirement: ecto 3.14.3, ecto_sql 3.14.0,
  postgrex 0.22.4, db_connection 2.10.2, decimal 3.2.0, doctor 0.23.0, plug 1.20.4,
  plug_crypto 2.2.1, telemetry 1.4.3.

### Changed

- `LiveFilter.QueryBuilder.apply/3` skips a filter it cannot apply: with `schema:`, a value
  the field type cannot cast (`22P02`, e.g. `?qty=gt.lots`) or a field that is not a schema
  field (`42703`). The other filters still apply, so a hand-edited URL no longer crashes the
  LiveView; 0.1 passed an uncastable value through and the query raised in the repo.
- Added `apply_with_errors/3`, which also returns the skipped filters as
  `{filter, %PgRest.Error{}}`, and `apply!/3` / `apply_raw!/3`, which raise the first
  `PgRest.Error` instead.
- `LiveFilter.QueryBuilder.apply_raw/3` casts values with the query's schema even without
  `schema:`, skips a param with an unknown field or an uncastable value, and needs
  `allowed_fields:` on a schemaless source (`"tasks"`); it raises `ArgumentError` without
  it. Field names are no longer converted to atoms.
- `apply_raw/3` applies negated filters (`not.eq.x`, `not.in.(a,b)`, `not.is.null`) and
  quoted list values (`in.("a,b",c)`); 0.1 skipped negations.
- URL parsing (`LiveFilter.Params.Parser`) maps `not.in.(...)` to `:not_in`, `not.eq` to
  `:neq`, `not.neq` to `:eq` and `not.is.null` / `not.is.not_null` to `:is_null`. Other
  negations and `any`/`all` modifiers still fall back to the config's default operator.
  `in` lists honour quoted values.
- A URL value with an operator prefix that the PostgREST grammar rejects (`?enabled=is.maybe`,
  `?status=in.abc`) is skipped instead of falling back to the default operator with the raw
  string. `Parser.from_params_with_errors/2` and `QueryBuilder.apply_with_errors/3` (with a
  param map) report it with its `PGRST100`.
- `fts` filters bind the query text and no longer default to the `english` config: without
  an explicit config (`fts(english).cats`) Postgres uses `default_text_search_config`. An
  explicit config is kept as `{config, query}` in the filter value.
- `:not_in` filters are applied through `PgRest.Ecto.Filter` as a negated `in`, so
  `schema:` casts their values too. The SQL is unchanged (`NOT (col = ANY($1))`).
- `LiveFilter.Pagination.start_item/1` and `end_item/1` return 0 when the total count is
  known and the page holds no rows; `start_item/1` returned 1 for an empty result and
  `offset + 1` past the end, so `?offset=999` over 3 rows read "Showing 1000 to 3 of 3".
- Added `LiveFilter.Pagination.past_end?/1`. When the offset is past the last row,
  `LiveFilter.Paginator` shows "No results on this page" with a "Go to first page" button
  instead of a range. An empty result still shows "No results".
- `LiveFilter.Paginator`'s per-page form and select take their ids from the component id
  (`<id>-limit-form`, `<id>-limit`), so LiveView can recover the form after a reconnect and
  two paginators on one page no longer share `id="limit-select"`.
- `LiveFilter.Bar`'s command-mode number/text value forms and inline editor form have ids
  (`filter-value-form-<filter id>`, `filter-editor-<filter id>`), matching the existing
  `always-on-<filter id>` form, so LiveView can recover them.
