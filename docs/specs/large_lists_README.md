# Large lists, frontend runtime and dependency editor: specification set

> Status: plan (spec only, no production code). Spec set: large_lists.
> Points: 1 to 9. Owner area: delivery (spec set index). Work packages: WP-01 to WP-32. Decisions: UD-01 to UD-34.

## Purpose

This spec set plans nine improvements to `redmine_depending_custom_fields`. Three goals drive them:

- make the plugin lighter, faster and simpler;
- make it able to manage very large dependent lists, for example 27 parents × 5,570 children;
- break nothing for existing users.

Some ideas come from a comparison with the competing plugin `redmine_cascading_custom_fields` (per-field data attributes, a scalable dependency editor, cycle detection). Wherever this plugin is already stronger, it keeps its broader feature set: Key/Value lists, per-parent defaults, the context-menu wizard, the JSON API, the project-level configuration and the audit log.

> These documents are implementation-ready, but nothing is implemented yet. Each work package is one small, reversible pull request. A pull request may only be merged when the repo-specific quality protocol passes ([`large_lists_quality_protocol.md`](large_lists_quality_protocol.md)).

## The nine points

| # | Point | Work packages | Release | Main document |
|---|-------|---------------|---------|---------------|
| 1 | Per-field data attributes instead of the global inline script; remove the Rails.cache mapping and its invalidation; context menu without cache | WP-15, WP-16, WP-18 | 0.2.0 | [server](large_lists_server_design.md), [frontend](large_lists_frontend_design.md) |
| 2 | Never disable the child control: hide and disable options, show a hint, remove the hidden-input mirror | WP-03 (hotfix), WP-09, WP-17, WP-19 | 0.0.16 to 0.2.0 | [frontend](large_lists_frontend_design.md) |
| 3 | One delegated change listener and a filtered MutationObserver | WP-17 | 0.2.0 | [frontend](large_lists_frontend_design.md) |
| 4 | Only touch the depending fields that are present in the DOM | WP-16, WP-17 | 0.2.0 | [frontend](large_lists_frontend_design.md) |
| 5 | Fire `change` only on a real change; server-side cycle validation | WP-10, WP-17 | 0.1.0, 0.2.0 | [server](large_lists_server_design.md), [frontend](large_lists_frontend_design.md) |
| 6 | Central rules module and a shared module for both depending formats | WP-05, WP-06, WP-08, WP-09 | 0.0.16, 0.1.0 | [server](large_lists_server_design.md) |
| 7 | Admin dependency editor with a single JSON transport | WP-21 to WP-25 | 0.3.0 | [editor](large_lists_editor_design.md) |
| 8 | CSV import and export of the mapping, "add missing child values" | WP-26 | 0.3.0 | [editor](large_lists_editor_design.md) |
| 9 | Project pages: shared editor, compact audit delta, search and pagination, sort, page-scoped Key/Value batch save | WP-27 to WP-31 | 0.3.0 | [project](large_lists_project_design.md) |
| x | MySQL/MariaDB TEXT 64 KB storage safety (cross-cutting) | WP-11 to WP-13, WP-31 | 0.1.0, 0.3.0 | [limits](large_lists_limits_design.md) |

## Baseline (measured before any change)

| Check | Result | How |
|-------|--------|-----|
| Plugin specs, Redmine 5.1 (Ruby 3.2.6) | 259 examples, 0 failures | Local replica of `.github/workflows/rspec-*.yml` (PostgreSQL 16, `libpq-dev` needed for `pg` on 5.1/6.x) |
| Plugin specs, Redmine 6.0 (Ruby 3.3.6) | 259 examples, 0 failures | same |
| Plugin specs, Redmine 6.1 (Ruby 3.3.6) | 259 examples, 0 failures | same (there is no CI workflow for 6.1 yet; WP-01 adds a manual one) |
| Plugin specs, Redmine 7.0 (Ruby 3.3.6) | 259 examples, 0 failures | same |
| RuboCop (core 7.0 config, `plugins/**` un-excluded) | 107 offenses in 38 files | Starting point for the "no new offenses" ratchet |
| JavaScript tests | none exist | WP-01/WP-04 add `node --test` + jsdom |

## Releases

| Release | Contents | Work packages |
|---------|----------|---------------|
| 0.0.16 | Foundation and hotfixes: tooling (`.codex` scripts, RuboCop ratchet, JS tests, manual 6.1 and JS workflows), test hygiene, the MemCacheStore save crash fix and the bulk-edit data-loss fix, characterization specs, `DependencyRules` + `FieldIndex`, shared `DependingFormatMethods` | WP-01 to WP-07 |
| 0.1.0 | Server rules and storage safety: Key/Value list options fix, per-value leniency for stored combinations (D1), cycle validation, MySQL size validation, service error mapping and audit cap, opt-in rake tasks | WP-08 to WP-14 |
| 0.2.0 | Issue-form runtime without inline script (points 1 to 5): context menu without cache, per-field data contract, new runtime, switch-over, required "(none)" and radio sentinel | WP-15 to WP-20 |
| 0.3.0 | Dependency editor, CSV import and export, project pages (points 7 to 9) | WP-21 to WP-32 |

[`large_lists_work_packages.md`](large_lists_work_packages.md) has the full CHANGELOG lines per release. [`large_lists_compatibility.md`](large_lists_compatibility.md) has every change a user can notice.

## Reading order

| # | Document | Purpose |
|---|----------|---------|
| 1 | this README | Scope, baseline, releases, reading order |
| 2 | [`large_lists_decisions.md`](large_lists_decisions.md) | Owner decisions UD-01 to UD-34 with recommendations, deviations from the default decisions |
| 3 | [`large_lists_compatibility.md`](large_lists_compatibility.md) | Guarantees for existing users, compatibility matrix, perceptible changes, deprecations, upgrade notes, rollback |
| 4 | [`large_lists_server_design.md`](large_lists_server_design.md) | Rules module, shared format module, canonical issue-form client contract, context menu without cache, cycle validation, D1 leniency |
| 5 | [`large_lists_frontend_design.md`](large_lists_frontend_design.md) | New issue-form runtime (points 1 to 5, client side) |
| 6 | [`large_lists_editor_design.md`](large_lists_editor_design.md) | Admin dependency editor, JSON payload v1 and parser, values endpoint, CSV import and export |
| 7 | [`large_lists_project_design.md`](large_lists_project_design.md) | Project dependency page, compact audit delta, values page search and pagination, sort, page-scoped Key/Value batch |
| 8 | [`large_lists_limits_design.md`](large_lists_limits_design.md) | MySQL TEXT safety, audit cap, rake tasks, payload sizes, CPU and memoization |
| 9 | [`large_lists_i18n_registry.md`](large_lists_i18n_registry.md) | Every new locale key with its owner WP and en/de/fr/nl text |
| 10 | [`large_lists_quality_protocol.md`](large_lists_quality_protocol.md) | Repo-specific quality protocol: roles, gates G1 to G12, commands, `.codex` scripts, test strategy, definition of done |
| 11 | [`large_lists_work_packages.md`](large_lists_work_packages.md) | WP-01 to WP-32: scope, files, tests, acceptance, rollback, dependency graph |
| 12 | [`large_lists_defects.md`](large_lists_defects.md) | Defects found during research: SD-01 to SD-12 tracked separately (SD-01 is a security issue), plus the defects fixed inside the plan |
| 13 | [`large_lists_review_log.md`](large_lists_review_log.md) | Review lenses, issues and resolutions, critic gaps, remaining risks |

## Hard rules carried over

The existing spec set ([`README.md`](README.md)) sets these rules, and they still apply:

- the project settings tab is added with `alias_method`, never `prepend`;
- no `Rails.configuration.to_prepare` in `init.rb`;
- the admin JSON API stays admin-only and keeps its contract;
- every project-level write is audited in the same transaction and fails closed.

This spec set adds:

- CI stays manual-only (`workflow_dispatch`). Claude may dispatch a workflow deliberately, and reports every dispatch (UD-32, resolved).
- Code stays Ruby 2.7 / Rails 6.1 compatible, and `requires_redmine` stays at 5.0 (UD-34).
- The locales de, en, fr and nl stay at key parity, with proper translations.
- No core table is ever altered automatically.
- PASS is declared only from observed command output.

## Highlights for the owner

- **Found during research and fixed early (0.0.16):**
  - every save of a depending field fails on MemCacheStore, because `Rails.cache.delete_matched` raises inside `after_save`;
  - bulk edit clears untouched multi-value dependent fields, because the JS checks the selector `#bulk-edit-form` while core uses `#bulk_edit_form`.
- **Security (SD-01):** the context-menu wizard save writes every posted custom field, including fields that are read-only by workflow or hidden for the user's role, and creates no journal entry. The recommendation is a separate PR before 0.0.16 is tagged (UD-03).
- **Large lists on MySQL/MariaDB:** `custom_fields.possible_values` and `custom_fields.format_store` are 64 KB TEXT columns in every Redmine version. A list of 27 × 5,570 values does not fit (about 86 KB of values, 98 KB of mapping), with or without this plugin. The plan adds a clear validation error instead of HTTP 500 or silent truncation, plus an opt-in rake task that widens the columns. PostgreSQL and SQLite have no such limit.
- **Decisions to confirm:** the work starts with 0.0.16, which needs UD-01, UD-02, UD-03, UD-29, UD-30, UD-31, UD-33 and UD-34. The other decisions are only needed for later releases; see section 4 of [`large_lists_decisions.md`](large_lists_decisions.md).
