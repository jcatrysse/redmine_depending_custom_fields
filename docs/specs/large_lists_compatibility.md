# Large lists: backward compatibility
> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 to 9. Owner area: compatibility (cross-area). Work packages: all, see per row. Decisions: UD-01, UD-04 to UD-12, UD-14 to UD-19, UD-21 to UD-25, UD-27, UD-34.

## Purpose

Existing users of 0.0.15 must not break. This document lists what is guaranteed, every surface that changes, every change a user can notice (each with its CHANGELOG line), deprecations and removal targets, upgrade notes and rollback per release.

## Contents

1. Guarantees for existing users
2. Compatibility matrix (platform, surfaces, deprecations, reconciled contracts)
3. Contract rows added during consolidation
4. Perceptible changes
5. Area compatibility entries
6. Upgrade notes and rollback

## 1. Guarantees for existing users

- **No data migration of custom field data.** `format_store` keeps the keys `parent_custom_field_id`, `value_dependencies`, `default_value_dependencies` and `hide_when_disabled` with the same types. Stored shapes from 0.0.15, including garbage keys written by the old bracket bug and links to inactive enumerations, still load. The editor reports keys that no longer match a value as orphans and removes them only at the next editor save.
- **JSON API contract unchanged.** Routes, authentication (admin only), request parameters and the response shape stay the same. New HTTP 422 reasons appear for a circular parent and for a mapping or value list too large for the column. `value_dependencies` and `default_value_dependencies` stay safe attributes permanently (UD-15). `jc-redmine_extended_api` writes through `safe_attributes=` and keeps working.
- **Mail handler and CSV import** keep matching values by label on the full list (`value_from_keyword`). Disallowed combinations are rejected by validation, as before.
- **Settings and permissions.** Existing plugin settings and the `manage_project_custom_field_configuration` permission keep their names and meaning. New actions are added to the same permission.
- **Platforms.** `requires_redmine` stays at 5.0 (declared, untested). 5.1, 6.0, 6.1 and 7.0 are tested. Ruby 2.7 or newer is documented as the floor (UD-34).
- **No automatic change to core tables.** Widening MySQL columns is an opt-in rake task with a dry run by default.

## 2. Compatibility matrix

### 2.1 Platform matrix

'tested' = green on the manual GitHub workflow and on the local `.codex/test_matrix.sh` chain for every WP of the release (one SHA).

| Platform | 0.0.15 | 0.0.16 | 0.1.0 | 0.2.0 | 0.3.0 |
|---|---|---|---|---|---|
| Redmine 5.1 (Rails 6.1.7.10, Ruby 3.2, Rack 2.2) | tested (rspec-51) | tested | tested | tested + opt-in system specs | tested + opt-in system specs |
| Redmine 6.0 (Rails 7.2.3, Ruby 3.3, Rack >= 3.1.3) | tested (rspec-60) | tested | tested | tested | tested |
| Redmine 6.1 (Rails 7.2.3, Ruby 3.3) | not in CI | tested (new rspec-61, upstream 6.1-stable) | tested | tested | tested |
| Redmine 7.0 (Rails 8.1.4, Ruby 3.3 local / 3.4 CI) | tested (rspec-70) | tested + lint ratchet | tested | tested + opt-in system specs | tested + opt-in system specs |
| Redmine 5.0 | declared (`requires_redmine 5.0`), untested | declared, untested; Ruby 2.7 / Rails 6.1 syntax gate | same | same | same |
| Ruby floor | implicit | 2.7 documented | 2.7 | 2.7 | 2.7 |
| PostgreSQL 16 | CI | CI | CI | CI | CI |
| MySQL / MariaDB | untested; HTTP 500 or silent truncation above 64 KB | untested | size validation, `:mysql` specs, manual MariaDB 10.11 recipe (+ optional manual workflow, UD-27) | same | same + project ceiling |
| SQLite | untested | untested | no size check (no column limit) | same | project ceiling applies |
| Browser JS language level | unchecked | ES2017 gate (acorn) | same | new runtime ES2017, no CSS.escape | editor ES2017 |
| Node (development only) | none | >= 22.13, jsdom ~29.1.1, jquery 3.7.1, acorn ~8.18.0 | same | same | same |
| CI workflows (all workflow_dispatch only) | 3 | 5 (+6.1, +JS), read-only permissions | 5 (+ optional MariaDB) | same | same |

### 2.2 Surface compatibility

| Surface | 0.0.15 | After | Release | Breaking | Mitigation |
|---|---|---|---|---|---|
| Plugin JSON API `/depending_custom_fields/*.json` | admin-only | payload and params unchanged; new 422 reasons (circular parent, MySQL oversize); name-only PUT byte-identical; `dependencies_json` not permitted | 0.1.0 | no | request specs; README API section |
| CustomField safe attributes `value_dependencies`, `default_value_dependencies` | safe | permanent (UD-15); `dependencies_json` added for the admin form | 0.3.0 | no | jc-redmine_extended_api writes through `safe_attributes=` |
| Stored data (`format_store` keys, Hash storage) | as is | unchanged; editor saves normalize order and default shape; before_save stays sanitize-only | all | no | BC-02 specs |
| Validation of stored (legacy) combinations | rejected whenever values are assigned | per-value tolerance while parent unchanged; copies judged against source; non-editable unchanged children accepted | 0.1.0 | no (fewer rejections) | UD-04..UD-07 |
| Saving a self or cyclic parent | saved silently | refused (422) when the parent id changes; stored cycles do not block other saves | 0.1.0 | yes, invalid configs only | D9 refinement |
| MySQL oversize saves | HTTP 500 (strict) or silent truncation (non-strict) | validation error, audited in services | 0.1.0 | yes on non-strict servers (intended) | upgrade note, report_sizes, widen task |
| Audit before/after values | full JSON | <= 16 KB with payload_* markers; project dependency rows compact v2 (0.3.0) | 0.1.0 / 0.3.0 | no (no view reads them) | CHANGELOG |
| OperationError constructor | key, http_status, audit_status | + summary, interpolations, payload (optional) | 0.1.0 | no | defaults |
| Cache key `depending_custom_fields/mapping` | written, `delete_matched('dcf/*')` | delete_matched removed (0.0.16); key never read or written (0.2.0) | 0.0.16 / 0.2.0 | no | downgrade command in README |
| `window.DependingCustomFieldData`, `window.ContextMenuWizardConfig` | inline script on every page | removed | 0.2.0 | yes | no external users found; README Integration |
| `window.DependingCustomFields.setup/requestSetup` | rescan with global mapping | deprecated aliases of `init(root)` | 0.2.0 | no | see timetable |
| Issue-form markup | no data attributes | `data-dcf-*` per field (managed fields only for parent data), id-less radio sentinel, marked required '(none)' option in bulk; no new ids | 0.2.0 | no | label for= unchanged (spec) |
| Child control state | disabled while parent offers nothing | never disabled; options hidden+disabled; `data-dcf-state` output | 0.2.0 | yes for scripts/themes relying on disabled | README Integration |
| change event | always fired | only on a real value change, plus `dcf:updated` | 0.2.0 | yes for listeners | README Integration |
| Depending fields rendered by third-party `select_tag` | filtered via DOM id/name scan | not filtered in the browser | 0.2.0 | yes | README documents the contract; server validates |
| Bulk edit / wizard semantics | '(no change)' hidden but selected; wizard root preselected with default | per UD-09 / UD-11 | 0.2.0 | yes (documented) | CHANGELOG, README rewrite |
| Context-menu hiding | every globally mapped child and parent | only children relevant to the selection and their parents | 0.2.0 | no | D4 |
| Routes | `options` shadowed (dead); `save` auto-named | `options` removed; `depending_custom_fields_save` named, same path | 0.2.0 | no | routing spec |
| MappingBuilder, ParentMenuBuilder, after_custom_field_save dispatch | public | removed (UD-14) | 0.2.0 | yes for third-party callers (none found) | CHANGELOG |
| QueryCustomFieldColumnPatch | prepended, no effect | removed | 0.0.16 | no | verified no-op |
| CustomFieldVisibility | used, fail open | unused, deprecated | 0.2.0 | no | see timetable |
| Admin form params | nested matrix params, urlencoded | one `custom_field[dependencies_json]`, multipart while the editor is active; nested still accepted | 0.3.0 | no | old tabs and scripts keep working |
| Admin form without JavaScript | matrix usable | mapping unchanged on save | 0.3.0 | yes | API path; UD-16 |
| Project `update_dependencies` params | nested params | `dependencies_json`; nested deprecated | 0.3.0 | no | see timetable |
| Project dependency page without JavaScript | matrix usable | Save disabled, noscript text | 0.3.0 | yes | UD-16 |
| Matrix partials and CSS classes | present | removed | 0.3.0 | yes for theme overrides | CHANGELOG Removed |
| Values page above 500 values | all rows, drag (404 above about 4,090) | paginated, search, sort buttons, page-scoped batch | 0.3.0 | no | lists <= 500 unchanged |
| Permission action list | 10 actions | + `sort_values` (auto granted) | 0.3.0 | no | upgrade note |
| Project-page writes on PostgreSQL/SQLite | unlimited | limited by setting (default 2,048 KiB, never blocks non-growing edits); values <= 255 chars | 0.3.0 | yes (new refusal) | UD-22, configurable |
| Rake tasks | none | report_sizes, widen_core_columns (opt-in) | 0.1.0 | no | never automatic |
| Asset files | 2 JS + CSS + inline script | same file names + meta tag (0.2.0); editor assets on 2 controllers, dcf_config.css, dcf_values_page.js (0.3.0) | 0.2.0 / 0.3.0 | no | restart; assets rake when mirroring disabled |
| Locale keys | 74 per locale | additions at parity in de/en/fr/nl; `label_default_value` use fixed; `text_dependency_matrix_help` removed | all | no | parity spec |

### 2.3 Deprecation and removal timetable

| Item | Deprecated in | Kept at least | Removable no earlier than |
|---|---|---|---|
| `DependingCustomFields.setup` / `requestSetup` | 0.2.0 | throughout 0.2.x (D5: one minor) | 0.3.0 (recommended: 0.4.0 together with the project params) |
| `CustomFieldVisibility` | 0.2.0 | throughout 0.2.x | 0.3.0 (recommended: 0.4.0) |
| Project nested params on `update_dependencies` | 0.3.0 | throughout 0.3.x | 0.4.0 |
| Admin nested safe attributes `value_dependencies` / `default_value_dependencies` | never (deviation from D5, UD-15) | permanent | - |
| Admin nested HTML form params | not rendered from 0.3.0 | accepted permanently through the safe attributes | - |

### 2.4 Reconciled cross-area contracts (binding for all WPs)

The revised area designs still disagreed on these shared contracts; one choice is fixed here and every WP implements it.

| Contract | Conflict | Adopted | Reason |
|---|---|---|---|
| Context vocabulary | server/quality `form/bulk`, frontend `edit/bulk` | `form`/`bulk`; client reads missing or unknown as `form` | edit_tag also renders new records; prototype already treats non-bulk as form |
| Emission on stored cycles and self-parents | server: omit; frontend/quality: emit | omit (effective parent: valid, acyclic, not self, visible) | server validation treats cycle members as unconstrained (UD-08), so client and server agree |
| Legacy marker | server: none; frontend: `data-dcf-stored` for persisted records only | `data-dcf-stored` = server D1 baseline (value_was, or copy source) | the client never shows as kept what the server rejects, and copies match UD-06 |
| i18n meta tag | server/quality flat `dcf-i18n` with 4 keys; frontend nested `redmine-depending-custom-fields` with 10 keys | `<meta name='dcf-i18n'>`, flat object, frontend's 10 keys | server emits, frontend owns the key list; no nested config needed (basePath replaced by form action) |
| Rules asset | server/quality separate rules file; frontend one UMD file | one UMD `depending_custom_fields.js` | no 'rules missing' inert mode, no new asset |
| Value option wire shape | server/editor compact; project/quality full triple | compact on the wire; Ruby tuples internally | about 200 KB less at 5,570 values; project code reads the Ruby API |
| CustomField callback registration | server: two modules; editor: transport module; limits/quality: one module | one `CustomFieldValidationPatch` prepended after CustomFieldPatch | single registration point; stand-in specs removed in WP-04 anyway |
| `column_limit` signature | `(column, model)` vs `(model, column)` | `column_limit(column, model = CustomField)` | limits owns StorageLimits |
| Storage threshold and client key | 80 or 90 percent; `text_dcf_storage_estimate(_over)` | 90 percent, `text_dcf_storage_estimate` | limits owns storage UX |
| Audit marker keys | limits `payload_truncated/payload_bytes/payload_sha256`; quality `truncated/original_bytes/payload_sha256` | limits names | no collision with the project delta's `truncated` and `mapping_sha256` |
| Large-list generator | limits rev 2 mulberry32 (0634a624422f2f06); quality rev 2 arithmetic (233acf899217e962) | arithmetic with JS twin | cross-language parity verified (E17), exact YAML targets, tricky values; quality owns it |
| Fixture ids | server placeholders; frontend 91000-91999; editor 1.9e9 base; quality per-kind ranges from 9,100,001 | quality ranges + normalizer + sequence-bump self check + 2 seeds | verified stable while sequences drift (E23) |
| FieldIndex API | server `load`/`children_ids`; limits `build`/`child_ids` | server names, one class | lands first (WP-05) |
| Payload-too-large key | editor `error_dcf_dependencies_too_large_to_send` (%{limit}); project `error_dcf_dependency_payload_too_large` (%{max}) | editor key with %{size}/%{limit} | editor owns the payload |
| Hint keys | server `text_dcf_hint_*_first/value`; frontend 9 keys | frontend keys | frontend owns runtime texts |
| Project conflict (409) and submit gate | project `data-dcf-editor-pending`, `-submit-gate`; editor `-conflict-mapping`, `data-dcf-editor-submit` | editor names and conflict panel | same UX on both pages |
| Service storage error text | limits 'the database allows'; project 'can be stored for this field' | project neutral wording | also correct for the project ceiling |
| Shared rules case table path | server `test/js/fixtures/rules_cases.json`; frontend `spec/fixtures/...` | `test/js/fixtures/shared/rules_cases.json` | `spec/fixtures` is the DB fixture directory |
| Admin form encoding | quality urlencoded + 3.9 MB pre-check; editor multipart switch | multipart switch (UD-16) | 4 MiB payload reachable |
| D2 bulk semantics | literal D2 vs frontend revision | frontend revision (UD-09) | literal D2 clears still-valid values on every selected issue |


## 3. Contract rows added during consolidation

| Contract | Rule | Owner | WP |
|---|---|---|---|
| Failed-save re-render (gap 1) | Hidden input always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; no `data-dcf-editor-echo`, no `input_value`. Project: `posted: service.parsed_payload` passed to `DependencyEditorConfig.for_project`. | editor | WP-22, WP-25, WP-27 |
| storage_preview (gap 4) | `storage_preview(custom_field, store)`, called as `format.storage_preview(record, record.format_store)`. | server (limits consumes) | WP-06, WP-11 |
| translate_error (gap 4) | `translate_error(e)` with an `OperationError`; interpolations escaped for flash. | limits | WP-12, WP-27 to WP-31 |
| DependencyRules.parent_of (gap 2) | Memoized raw parent lookup, nil for blank, dangling, wrong type or family, or self. Client emission uses `effective_parent_id`. | server | WP-05, WP-16, WP-27 |
| value_options (gap 3) | Returns `[key, label, active]` tuples; wire format for the editor via `DependencyEditorConfig.wire_values`. | server, editor | WP-05, WP-24, WP-27, WP-28 |
| i18n maps (gap 5) | `ClientConfig::I18N` (meta tag) and `DependencyEditorConfig::I18N` (editor); the parity spec iterates both. | server, editor | WP-02, WP-18, WP-24 |
| MutationObserver (gap 13) | All mutations of one observer callback are coalesced; added roots are initialised synchronously in that callback (no timer debounce), so there is no unfiltered window after an AJAX re-render. | frontend | WP-17 |

## 4. Perceptible changes

Every change a user or integrator can notice, with release and CHANGELOG line. Ids PC-01 to PC-65 come from the delivery slice; PC-66 to PC-68 were added by the completeness critic (gap 11).

- PC-01 [0.0.16, Fixed] Depending field saves no longer crash on MemCacheStore. CHANGELOG: 'Fixed: Saving a depending field no longer fails with an internal error on MemCacheStore or other cache stores without delete_matched.'
- PC-02 [0.0.16, Fixed] Bulk edit stops wiping untouched multi-value children (data loss). CHANGELOG: 'Fixed: Bulk edit of issues and time entries no longer clears untouched multi-value dependent fields.'
- PC-03 [0.0.16, Fixed] Admin form header shows 'Default value'. CHANGELOG: 'Fixed: The admin custom field form shows Default value instead of a missing translation.'
- PC-04 [0.0.16, Removed] QueryCustomFieldColumnPatch removed. CHANGELOG: 'Removed: QueryCustomFieldColumnPatch (it had no effect on any supported Redmine version).'
- PC-05 [0.0.16, Upgrade notes] Ruby floor documented. CHANGELOG: 'Upgrade notes: Ruby 2.7 or newer is required. Redmine 5.0 remains declared but is not tested.'
- PC-06 [0.1.0, Changed] Legacy values accepted per value while the parent is unchanged. CHANGELOG: 'Changed: Stored values that no longer fit the parent are accepted on save until the parent changes; other values of a multi-value field can still be added or removed.' Note (gap 11): in 0.1.0 the leniency applies to the REST API, email, bulk edit, the wizard and copies; the issue form keeps such values from 0.2.0 on, because the legacy JS of 0.1.0 still drops them at load.
- PC-07 [0.1.0, Changed] Untouched child accepted when its parent is not available for the tracker. CHANGELOG: 'Changed: An untouched value is accepted when its parent field is not available for the issue's tracker.' Note (gap 11): in 0.1.0 the leniency applies to the REST API, email, bulk edit, the wizard and copies; the issue form keeps such values from 0.2.0 on, because the legacy JS of 0.1.0 still drops them at load.
- PC-08 [0.1.0, Changed/Fixed] Copies keep legacy combinations. CHANGELOG: 'Changed: Issue copies (single copy, bulk copy, project copy) keep such values when copied unchanged; project copy no longer skips those issues.'
- PC-09 [0.1.0, Changed] Non-editable child does not block a parent change. CHANGELOG: 'Changed: A dependent field you cannot edit no longer blocks saving a change of its parent.'
- PC-10 [0.1.0, Added] Circular parent refused. CHANGELOG: 'Added: Choosing the field itself or one of its dependent fields as Depends on is refused (form error, HTTP 422 in the APIs).'
- PC-11 [0.1.0, Added/Changed] Cycle warning, cycle members independent. CHANGELOG: 'Added: The admin form warns about fields that are part of an existing circular dependency; such fields are treated as independent until the cycle is fixed.'
- PC-12 [0.1.0, Changed] Parent select excludes descendants. CHANGELOG: 'Changed: The Depends on select no longer offers the field's own dependent fields.'
- PC-13 [0.1.0, Fixed] Enumeration single error, no duplicate option. CHANGELOG: 'Fixed: Key/Value list (depending): a disallowed new value gives one error instead of two, and the edit form no longer shows the stored value twice.'
- PC-14 [0.1.0, Added/Fixed] MySQL size validation. CHANGELOG: 'Fixed: On MySQL/MariaDB, a value list or dependency mapping that is too large gives a clear validation error (HTTP 422 in the APIs, audited error in project settings) instead of an internal error or silent truncation.'
- PC-15 [0.1.0, Upgrade notes] Non-strict MySQL now refuses; core List/Key-Value checked. CHANGELOG: 'Upgrade notes: On MySQL servers running without strict mode, saves that used to be truncated silently are now refused. Core List and Key/Value list fields are checked too.'
- PC-16 [0.1.0, Added] Rake tasks. CHANGELOG: 'Added: Rake tasks redmine:depending_custom_fields:report_sizes and redmine:depending_custom_fields:widen_core_columns (opt-in, dry run by default, CONFIRM=1 to apply).'
- PC-17 [0.1.0, Added] Storage usage line at 90 percent. CHANGELOG: 'Added: A database storage usage line on the custom field form and project pages at 90 percent of the column limit.'
- PC-18 [0.1.0, Changed] Audit values capped. CHANGELOG: 'Changed: Audit before/after values above 16 KB are stored shrunk with payload_truncated, payload_bytes and payload_sha256 of the full value.'
- PC-19 [0.1.0, Fixed] Audit overflow rollback. CHANGELOG: 'Fixed: A large mapping save on widened MySQL columns no longer rolls back because its audit row overflowed.'
- PC-20 [0.1.0, Fixed] Escaped flash interpolations. CHANGELOG: 'Fixed: Error messages in project settings no longer interpret HTML in field names.'
- PC-21 [0.1.0, API] New 422 reasons. CHANGELOG: 'API: The response shape is unchanged. New HTTP 422 reasons: circular parent and MySQL oversize.'
- PC-22 [0.2.0, Changed] Child never disabled, hint names the parent. CHANGELOG: 'Changed: Dependent fields are never disabled. Disallowed options are hidden and disabled, and a hint under the field names the parent field.'
- PC-23 [0.2.0, Fixed] Legacy values kept in the browser and restored on return. CHANGELOG: 'Fixed: Stored values that do not match an unchanged parent stay selected, marked and saved instead of being removed silently on the next save; switching the parent back restores them.'
- PC-24 [0.2.0, Changed] Defaults on load only for new records (UD-12). CHANGELOG: 'Changed: Per-parent defaults are filled in on new records and when the parent changes; they are no longer filled into empty fields of existing records when the form opens.'
- PC-25 [0.2.0, Changed] Read-only or unavailable parent filters by stored value. CHANGELOG: 'Changed: Dependent fields whose parent is read-only on the form or not available for the tracker are filtered by the stored parent value and may be hidden when Hide when no valid options is set.'
- PC-26 [0.2.0, Changed] Invisible parent: child unfiltered, no mapping leak. CHANGELOG: 'Changed: Dependent fields whose parent you cannot see are no longer filtered in the browser and the page no longer contains that parent's mapping; the server still validates them.'
- PC-27 [0.2.0, Changed] hide_when_disabled meaning (D3). CHANGELOG: 'Changed: Hide when no valid options hides the field with its label while the parent offers no options, only on single-record forms, never while a stored non-matching value is shown and never in bulk edit.'
- PC-28 [0.2.0, Changed] Bulk/wizard keep '(No change)' (UD-09). CHANGELOG: 'Changed: In bulk edit and the context-menu wizard, choosing a parent value keeps (No change) available on dependent fields; a per-parent default is preselected with a visible hint; a dependent field is cleared automatically only when the parent is (none) or its value allows nothing. Setting the parent back to (No change) restores the previous choice.'
- PC-29 [0.2.0, Changed] Wizard opens on '(No change)' (UD-11). CHANGELOG: 'Changed: The context-menu wizard opens every field on (No change); saving without choosing changes nothing (it used to write the root field's default).'
- PC-30 [0.2.0, Fixed] Wizard errors shown. CHANGELOG: 'Fixed: The wizard reports server errors and stays open.'
- PC-31 [0.2.0, Changed] Context menu hides per selection (D4). CHANGELOG: 'Changed: The context menu hides only dependent fields available for the selected issues and their parents; parents of unavailable fields come back with their full list; fields whose parent was deleted show as plain lists.' Fields in a circular configuration also show as plain lists (gap 11).
- PC-32 [0.2.0, Changed] Larger context-menu responses. CHANGELOG: 'Changed: Context-menu responses include dependency data for the wizard fields and can be larger for very big mappings.'
- PC-33 [0.2.0, Changed] change event only on value change, dcf:updated added. CHANGELOG: 'Changed: The change event fires only when a value really changes; listen to the new dcf:updated event for option changes (see README Integration).'
- PC-34 [0.2.0, Changed] Custom-rendered fields not filtered. CHANGELOG: 'Changed: Fields rendered without Redmine's custom field helpers are no longer filtered in the browser (see README Integration); the server still validates them.'
- PC-35 [0.2.0, Changed] No-JS enumeration lists show all active values. CHANGELOG: 'Changed: Without JavaScript, Key/Value list (depending) fields show all active values; the server still rejects invalid combinations.'
- PC-36 [0.2.0, Fixed] No browser recursion on cycles. CHANGELOG: 'Fixed: No more browser errors with circular configurations.'
- PC-37 [0.2.0, Fixed] No global mapping on every page. CHANGELOG: 'Fixed: The dependency mapping is no longer embedded in every page, including the login page.'
- PC-38 [0.2.0, Fixed] Required radio child clearable. CHANGELOG: 'Fixed: Required radio-style dependent fields can be cleared.'
- PC-39 [0.2.0, Added] Required '(none)' in bulk/wizard (UD-10). CHANGELOG: 'Added: In bulk edit and the wizard, required dependent fields offer (none) while the parent selection allows no value.'
- PC-40 [0.2.0, Added] Screen reader hints. CHANGELOG: 'Added: Hints are announced to screen readers.'
- PC-41 [0.2.0, Deprecated] JS shims and CustomFieldVisibility. CHANGELOG: 'Deprecated: DependingCustomFields.setup and requestSetup (aliases of DependingCustomFields.init) and CustomFieldVisibility; kept at least throughout 0.2.x, removable no earlier than 0.3.0.'
- PC-42 [0.2.0, Removed] Globals and internals. CHANGELOG: 'Removed: window.DependingCustomFieldData, window.ContextMenuWizardConfig, MappingBuilder, ParentMenuBuilder, ContextMenuWizardController#options, the after_custom_field_save dispatch, data-depending-* attributes, depending_cf_N ids, the hidden mirror inputs and the data-field-id attribute.'
- PC-43 [0.2.0, Upgrade notes] Restart, assets, reload tabs, cache key, downgrade. CHANGELOG: 'Upgrade notes: Restart Redmine; run the plugin asset task when automatic mirroring or detect_update is disabled; reload open browser tabs; the cache key depending_custom_fields/mapping is no longer used, delete it once before downgrading on a persistent cache store.'
- PC-44 [0.2.0 at the latest, Security, separately tracked SD-01] Wizard writes only editable fields. CHANGELOG: 'Security: The context-menu wizard writes only fields the user may edit.'
- PC-45 [0.3.0, Added/Changed] Admin and project dependency editor replaces the matrix. CHANGELOG: 'Added: A dependency editor replaces the checkbox matrix on the admin custom field form and on the project dependency page: collapsible sections per parent value, search, check or uncheck all shown, filters for values without links, counters, per-parent defaults inside each section and inactive values shown and kept.'
- PC-46 [0.3.0, Changed] Single JSON field, multipart admin form. CHANGELOG: 'Changed: The admin form sends the dependency mapping as one field (custom_field[dependencies_json]) and is submitted as multipart/form-data while the editor is active.'
- PC-47 [0.3.0, Fixed] Untick-all, brackets, more than about 4,000 links. CHANGELOG: 'Fixed: Unticking every link clears the mapping; parent values containing [ or ] and mappings with more than about 4,000 links can be saved (admin form and project settings).'
- PC-48 [0.3.0, Changed] Untouched admin save leaves the mapping alone. CHANGELOG: 'Changed: Saving the admin form without touching the dependencies leaves the stored mapping unchanged.'
- PC-49 [0.3.0, Fixed] Inactive enumeration links kept. CHANGELOG: 'Fixed: Links to inactive Key/Value list entries are kept on admin saves.'
- PC-50 [0.3.0, Changed] Parent change prunes links. CHANGELOG: 'Changed: Changing the parent field in the admin form removes links that do not match the new parent's values.'
- PC-51 [0.3.0, Changed] Orphans reported and removed. CHANGELOG: 'Changed: Links to values that no longer exist are reported by the editor and removed at the next editor save; project audit rows count them.'
- PC-52 [0.3.0, Added] Lost-update guard with conflict panel (UD-17). CHANGELOG: 'Added: A save is refused when someone else changed the dependency mapping after the page was opened; the editor then shows the current version and your version (use, keep or export yours).'
- PC-53 [0.3.0, Changed] Default value field visible until a parent is chosen. CHANGELOG: 'Changed: The default value field stays visible until a parent field is chosen.'
- PC-54 [0.3.0, Changed] Editor normalizes stored mapping. CHANGELOG: 'Changed: Editor saves store defaults as one value for single-value fields and as a list for multi-value fields and normalize the order; API GET output can change after an editor save. The JSON API itself is unchanged.'
- PC-55 [0.3.0, Changed] Editors need JavaScript (UD-16). CHANGELOG: 'Changed: The dependency editors need JavaScript. Without it the admin form keeps the mapping unchanged and the project page disables Save.'
- PC-56 [0.3.0, Added] CSV import/export and add missing child values (UD-18, UD-19). CHANGELOG: 'Added: CSV import of links (paste or file, preview with per-line errors, merge or replace, undo) and CSV export from the editor, with optional spreadsheet formula protection; Add missing child values for List (depending) fields on the admin form.'
- PC-57 [0.3.0, Changed] Compact project audit delta. CHANGELOG: 'Changed: Project dependency audit rows store a compact summary (counts, samples, SHA-256 of the mapping); sort and reorder audit rows store the SHA-256 of the order. The source and import details are reported by the browser and are informational.'
- PC-58 [0.3.0, Fixed] Corrected resubmit no longer 409. CHANGELOG: 'Fixed: Correcting a failed dependency save in project settings and saving again no longer reports a conflict.'
- PC-59 [0.3.0, Added/Changed] Values page search, pagination, drag threshold (UD-21). CHANGELOG: 'Added: Search on the project values page for fields with more than 25 values, and pagination for fields with more than 500 values.' and 'Changed: Drag-and-drop ordering is offered only for unfiltered lists with at most 500 values; redirects keep the search and the page; Show usage reports exact counts.'
- PC-60 [0.3.0, Added] Sort A-Z/Z-A (UD-23, UD-24). CHANGELOG: 'Added: Sort A-Z / Sort Z-A buttons on the project values page; members with Manage project custom field configuration get the new action automatically.'
- PC-61 [0.3.0, Added] Page-scoped enumeration save. CHANGELOG: 'Added: Page-scoped save of Key/Value list values on paginated or filtered pages, with a warning before leaving unsaved changes.'
- PC-62 [0.3.0, Added/Changed] Project storage ceiling and 255-character cap (UD-22). CHANGELOG: 'Added: Plugin setting for the maximum stored size of changes made in project settings (default 2,048 KiB).' and 'Changed: Values added or renamed in project settings are limited to 255 characters, and project-settings changes cannot grow a field beyond the new storage setting.'
- PC-63 [0.3.0, Deprecated] Project nested params. CHANGELOG: 'Deprecated: Posting value_dependencies / default_value_dependencies as nested params to the project dependency page; send dependencies_json (removed no earlier than 0.4.0). The admin safe attributes remain permanently.'
- PC-64 [0.3.0, Removed] Matrix partials, CSS classes, locale key. CHANGELOG: 'Removed: Partials custom_fields/formats/_dependencies_matrix and _default_dependencies, CSS classes .dependencies-matrix*, .dependencies-defaults* and .dcf-dependencies-matrix, locale key text_dependency_matrix_help.'
- PC-65 [0.3.0, Upgrade notes] Orphans from earlier versions, copies, proxies, restart. CHANGELOG: 'Upgrade notes: Links dropped by earlier versions cannot be restored; links under parent values containing [ or ] must be re-linked once; copied Key/Value list (depending) fields keep the source entries (no remap) and show them as orphans; raise reverse proxy body limits for very large mappings; restart Redmine.'
- PC-66 [0.2.0, Added] Per-parent memory survives form refreshes. CHANGELOG: 'Added: The value you last picked for each parent value comes back when you switch the parent back, also after the form refreshes.' (gap 11, WP-17)
- PC-67 [0.3.0, Changed] Project dependency page scope warning and parent notices. CHANGELOG: 'Changed: The project dependency page shows the global/shared field warning, and a notice instead of the editor when the parent field is not available in the project or no longer exists.' (gap 11, WP-27)
- PC-68 [0.3.0, Changed] Admin form confirmations and editor placement. CHANGELOG: 'Changed: The admin form asks for confirmation before a format change that would discard unsaved dependency edits, warns before leaving with unsaved edits, and now places the dependency editor after Hide when no valid options and the edit style.' (gap 11, WP-25)

## 5. Area compatibility entries

| Area | Surface | Before | After | Breaking | Mitigation |
|---|---|---|---|---|---|
| server | window.DependingCustomFieldData and window.ContextMenuWizardConfig | Inline head script on every base-layout page, anonymous included | Removed. Per-field data-dcf-* attributes plus meta dcf-i18n | yes | D5, no external users found. Server and JS ship in one PR and release. CHANGELOG Removed entry. README Integration documents the contract. |
| server | Rails.cache key depending_custom_fields/mapping | Written without TTL; invalidated with delete_matched in after_save | Never read or written | no | Fixes MemCacheStore and namespaced-store saves. A documented downgrade step deletes the stale key (BC-07). |
| server | MappingBuilder.build, ParentMenuBuilder.build | Public, cache-backed | Removed | yes | Nothing in the plugin needs them (D5). CHANGELOG points to DependencyRules, FieldIndex and SelectionGraph. A shim is available as a user decision. |
| server | ParentDetector.for_issues(issues) | Roots from the global cached mapping; fail-open visibility | Same signature plus optional graph:/user:. Roots from the selection graph; fail-closed visibility | no | Same output for normal configurations. A visibility error now hides the field (safe direction). |
| server | after_custom_field_save format hook dispatch | Called by CustomFieldPatch after_save | Removed | no | Only the plugin's formats implemented it. CHANGELOG note. |
| server | Routes depending_custom_fields/options and depending_custom_fields_save | options shadowed by :id; save auto-named | options removed (still reaches API#show as today); save explicitly named with the same name and path | no | Identical responses. Routing spec. |
| server | Wizard form markup | No action; regex-injected data-field-id; posts to basePath | action from the named route, method post, data-dcf-wizard-field wrappers, depending children carry data-dcf-* with context bulk | no | The new context_menu_wizard.js reads form.action. Fixture-tested. |
| server | Issue context menu | Hides every globally mapped child and parent | Hides children with an effective parent relevant to the selection, and their parents. Dangling-parent and cycle children are shown as plain lists | no | D4 intended. CHANGELOG and README. |
| server | Issue and other edit forms (markup) | No data attributes; JS used the global mapping | data-dcf-field/context on depending fields; parent attributes on managed fields; radio sentinel; no new ids | no | label-for unchanged (spec). Fail-open ClientData. Contract documented. |
| server | Bulk edit and wizard of required managed depending children | No (none) option | (none) option marked data-dcf-required-none, usable only while no value is allowed | no | Without JS, choosing it while options exist fails per issue with 'cannot be blank' (nothing silently cleared). CHANGELOG Added. |
| server | Validation of legacy combinations (form, bulk, REST, mail, wizard) | Rejected whenever values are assigned | Per-value tolerance while the parent is unchanged; issue copies judged against the source; non-editable unchanged children never rejected | no | Fewer rejected saves only. Never introduces a new invalid value. Matrix specs. |
| server | Validation of stored cycle members | Validated per mapping (JS crashed) | Unconstrained on server and client; admin warning | no | Only affects configurations that can no longer be created. Warning on the admin form. |
| server | CustomField saves setting a self or cyclic parent (admin, API, extended API, services) | Saved silently | Error on parent_custom_field_id (422 in the API) when the parent id changes | yes | Only invalid configurations are refused. Unresolvable parents keep the silent nil (D9). Stored cycles do not block unrelated saves. |
| server | DependingEnumerationFormat edit options and errors | Hidden 3-tuples, duplicate stored option, 2 errors | Active list plus stored ids, 1 error | no | Characterization flip plus CHANGELOG. Strictness for new values unchanged. |
| server | possible_values_options(cf, object) public contract | 3-tuples per carrying object; all-hidden 3-tuples for non-carrying objects (Project for Issue fields) | Unchanged for carrying objects; base list for non-carrying objects | no | Core menus destructure 2 elements (F5). Characterized flip with CHANGELOG line. |
| server | value_from_keyword (CSV import, mail) | Linear label scan on the filtered list | Hash lookup on the full list | no | Identical results (characterized). Faster. |
| server | CustomField safe attributes value_dependencies and default_value_dependencies | Safe attributes | Permanent safe attributes; only the nested HTML form params are deprecated | no | BC-04 spec: safe_attribute_names include both; a Hash persists unchanged. |
| server | Plugin JSON API | Admin-only contract | Unchanged payload and params; new 422 reasons for cycles and MySQL oversize; name-only PUT round-trips the mapping byte-identically; admin-editor saves may normalize stored mappings | no | Request specs. CHANGELOG and README API section. |
| server | QueryCustomFieldColumnPatch | Prepended, no effect | Removed | no | Verified no-op on all target versions. |
| server | CustomFieldVisibility | Used by the wizard and ParentDetector, fail open | Unused; deprecated in 0.2.0 (WP-15), kept throughout 0.2.x, removable no earlier than 0.3.0 (recommended 0.4.0) | no | Kept unchanged with its spec. |
| server | Ruby floor | Implicit (requires_redmine 5.0) | Documented Ruby >= 2.7 | no | README Compatibility and CHANGELOG Upgrade notes (BC-11). Quality syntax gate at 2.7. |
| frontend | window.DependingCustomFieldData (inline mapping global) | Emitted on every base-layout page including /login | Removed; per-field data-dcf-* attributes on visible active children only | yes | No external users found; CHANGELOG Removed |
| frontend | window.ContextMenuWizardConfig | {basePath}, read unguarded by context_menu_wizard.js | Removed; the wizard form carries the named-route action and passes a same-origin check | yes | Ship JS and markup in one release; asset ids (5.1) and digests (6.x/7.0) bust caches after a restart; CHANGELOG Upgrade note to reload tabs |
| frontend | window.DependingCustomFields.setup/requestSetup | Rescan with the global mapping | Deprecated wrappers of init(root); window.DependingCustomFields.rules added | no | Deprecated in 0.2.0, kept throughout 0.2.x, removable no earlier than 0.3.0 (recommended 0.4.0) |
| frontend | Asset list | depending_custom_fields.js, context_menu_wizard.js, CSS, inline script | Same files (rules folded into depending_custom_fields.js), meta tag instead of the inline script | no | Restart Redmine; run plugin asset tasks when auto mirroring or precompile is disabled |
| frontend | Child control disabled state | Child select or all group inputs disabled while the parent offers nothing | Never disabled; disallowed options or inputs hidden and disabled; data-dcf-state output | yes | README Integration: use [data-dcf-state]; same submitted values in regular forms |
| frontend | Hidden mirror inputs and removal of core's hidden '' input | JS rebuilt hidden inputs and removed core's multi-select hidden input | Removed; native submission; server sentinel for single radios | no | Entry-list and serialize parity tests; the bulk untouched multi child now posts nothing (data-loss fix) |
| frontend | Bulk edit / wizard with a concrete parent value | '(no change)' hidden but still selected; default applied when present (A, A') | '(no change)' visible and selectable; default applied with a hint; parent '(none)' or a value without links forces '(none)' | yes | README promise withdrawn and documented as an Upgrade note; no valid values are cleared silently; the server reports invalid kept values per issue |
| frontend | Wizard root preselection | Root opened on cf.default_value, and Save wrote it to all selected issues | All wizard fields open on '(no change)'; Save without a choice writes nothing | yes | CHANGELOG Upgrade note; request spec |
| frontend | Required depending children in bulk edit and the wizard | No '(none)' option | '(none)' offered for active children (FD-22) | no | With a parent that maps to options, core reports 'cannot be blank' per issue |
| frontend | Stored values not allowed under the stored parent (legacy) | Silently removed at load and cleared on the next save | Persisted records and issue copies (data-dcf-stored = value_was or the copy-source baseline, UD-06) keep, mark and post them while the parent is unchanged; per value for multi fields; plain new records without data-dcf-stored drop them as before | no | Requires server D1 per value and the copy baseline (WP-09, already shipped in 0.1.0) |
| frontend | Per-parent defaults on page load | Filled into empty children of existing records and saved on the next save | Only for new records and on parent changes | yes | CHANGELOG Upgrade note; owner confirmation |
| frontend | Dependent fields with a read-only or tracker-unavailable parent | Unfiltered on the client | Filtered by data-dcf-parent-values; may be hidden by hide_when_disabled | yes | Matches server validation; CHANGELOG Upgrade note |
| frontend | Depending fields rendered without core custom field helpers | Filtered by the DOM id or name scan | Not filtered in the browser | yes | README Integration documents C1 so integrators can emit it; server validation remains |
| frontend | data-depending-*, data-value-map, depending_cf_N ids, data-field-id | Internal bookkeeping attributes | Not written or read; data-dcf-state, dcf-legacy-option, dcf-auto-applied and dcf-hidden are the outputs | yes | Internal only; CHANGELOG Removed |
| frontend | change event dispatch | Always fired at setup and on every parent change | Only on a value change; dcf:updated for every evaluation | yes | README Integration: listen to dcf:updated |
| frontend | hide_when_disabled | Also hid fields in bulk; forced p.hidden=false otherwise | Single-record forms only, never while a legacy value is shown, only un-hides what it hid | yes | Stored key and API name unchanged (D3); CHANGELOG |
| frontend | Radio-style single child markup | span.check_box_group only | An id-less hidden input name=<field> value='' data-dcf-blank=1 precedes the span | no | Last-wins verified on all Rack versions; label for unchanged |
| frontend | Context menu response size | No per-field mapping (global inline mapping instead) | Wizard templates carry data-dcf-map per wizard field | no | CHANGELOG note; integer enumeration ids; recommend depending_enumeration for very large lists |
| frontend | CSS | Unused wizard spinner rules | Removed; new hint, hidden-choice, legacy and auto-applied rules; .depending-child unchanged | no | Rules were unused |
| frontend | Wizard submit and errors | POST to basePath + path; non-JSON errors silent | POST to the same path through the form action with an origin check; localized alert on any error | no | Route path and controller contract unchanged |
| editor | Admin custom field form params | Nested custom_field[value_dependencies][P][] checkboxes and custom_field[default_value_dependencies][P](/[]) selects, urlencoded | One hidden custom_field[dependencies_json], submitted multipart/form-data once the editor has initialized. Nested params remain accepted as safe attributes permanently; when both are posted, the JSON wins | no | Old tabs, scripted posts and jc-redmine_extended_api keep working. CHANGELOG entry. |
| editor | Admin save semantics | Full matrix re-posted on every save; untick-all ignored; inactive enumeration links dropped; old keys stored under a newly chosen parent | Mapping untouched unless the editor is dirty; '{}' clears; inactive links kept; a parent change prunes to the new parent's values | no | CHANGELOG Fixed/Changed entries; README transport section. |
| editor | Admin form without JavaScript | Matrix usable | noscript message; saving keeps the mapping unchanged | yes | Documented. The JSON API and jc-redmine_extended_api remain JS-free paths, and core admin pages already need JS for format switching. |
| editor | Project dependency page without JavaScript | Matrix usable | noscript message; Save disabled (no misleading no-op success) | yes | Documented. Nested params remain accepted from scripts throughout 0.3.x (deprecated in 0.3.0, removable no earlier than 0.4.0). |
| editor | Partials _dependencies_matrix and _default_dependencies; CSS .dependencies-matrix*, .dependencies-defaults*, .dcf-dependencies-matrix | Present | Deleted; replaced by depending_custom_fields/_dependency_editor and .dcf-dep-* classes | yes | Affects only themes or plugins that override these internals; listed in the CHANGELOG Removed section. |
| editor | Default value dependencies shape | Stored as submitted (String or Array regardless of multiple) | Editor saves normalize: String for single fields, Array for multiple fields; the API path is unchanged | no | The runtime and services already accept both shapes. The CHANGELOG notes that API GET output can change after an editor save. |
| editor | Concurrent edits | Admin save silently overwrote concurrent changes; project 409 discarded the user's state | Refused with dcf_stale_dependencies (admin) or 409 (project); the editor shows both versions with use, keep and export actions | no | Triggers only in the lost-update case; the user's version is never lost. |
| editor | Validation errors on the admin form | No payload errors | Errors on :value_dependencies (label 'Dependency mapping'): dcf_invalid_dependencies_payload, dcf_stale_dependencies, dcf_dependencies_too_large_to_send | no | Only reachable with tampered, stale or oversize input; i18n in all four locales. |
| editor | New route GET /dcf_dependency_editor/values | n/a | Admin-only, session-authenticated JSON with the canonical value wire format | no | Additive; no API key access. |
| editor | Plugin JSON API /depending_custom_fields/*.json | Hash value_dependencies/default_value_dependencies in and out | Unchanged; dependencies_json is not permitted, and editor pruning never runs on API saves | no | Existing request specs stay green; new specs pin that dependencies_json is ignored and that name-only updates keep the mapping byte-identical. |
| editor | Project dependency page params | Nested value_dependencies[P][] and selects; nothing ticked meant clear | dependencies_json, always posted by the editor; a present-but-blank value is an audited error. The legacy nested fallback keeps 'absent means clear' throughout 0.3.x | no | Point 9 implements contract section 7; CHANGELOG Deprecated entry with version targets. |
| editor | Copy of a depending_enumeration | Stale source enumeration ids copied unseen | Still copied (no remap, D6), shown as orphans, removed at the first editor save of the copy | no | README and CHANGELOG upgrade note. |
| editor | Page assets | Plugin CSS/JS on every page | Editor JS/CSS only on the custom field admin and project configuration pages, through the head hook | no | None needed; restart after upgrade for the new files. |
| project | PATCH update_dependencies params | nested value_dependencies[pk][] and default_value_dependencies[pk](/[]) | dependencies_json (schema v1) preferred; nested still accepted when dependencies_json is absent (warning logged) | no | Deprecated in 0.3.0, accepted throughout 0.3.x, removable no earlier than 0.4.0; CHANGELOG Deprecated entry; legacy request specs stay green. |
| project | edit_dependencies HTML markup | NxM checkbox matrix with nested input names | Shared editor partial (fieldset[data-dcf-editor], data-dcf-editor-* attributes), one hidden dependencies_json, multipart form, Save disabled until the editor initialises | yes | Only form scrapers are affected; none are known. CHANGELOG Removed entry; T-UI-7 amended. |
| project | No-JavaScript editing of mappings at project level | plain checkbox form worked without JS | noscript text; Save disabled | yes | Documented in the Upgrade notes. Scripts can post dependencies_json, or the nested params throughout 0.3.x (deprecated in 0.3.0, removable no earlier than 0.4.0). |
| project | Audit before_value/after_value of update_dependencies | before NULL; after = full mapping JSON | compact v2 objects with 'v':2 and mapping_sha256; summary is descriptive | yes | No UI or spec reads these columns. Old rows stay valid. Documented in the Audit Spec and the CHANGELOG. |
| project | Audit rows of reorder_values | after {order (first 20), truncated} | additionally before.order_sha256 and after.order_sha256 | no | Additive keys. |
| project | update_enumerations contract | exact full id set | same by default; opt-in batch_scope=page subset, positions ignored | no | Additive; unknown scopes rejected; T-ACT-21 unchanged. |
| project | Values page for fields with more than 500 values | all rows with drag (above about 4,090 values the drag submit 404s) | paginated with search and sort, no drag, page-scoped enumeration save with a leave warning | no | Lists of 500 values or fewer are unchanged; an info line explains why drag is unavailable. |
| project | Permission action list | 10 actions | plus sort_values | no | Granted automatically to holders; listed in the CHANGELOG; closed projects blocked by require_active_project. |
| project | Project-level writes on PostgreSQL/SQLite | no size limit | refused above max(project_storage_ceiling_kib setting, current stored size), default 2,048 KiB, audited 422 | no | Existing fields larger than the ceiling can still be edited as long as they do not grow. The admin form, API and import are not limited. Configurable setting; Upgrade note. |
| project | New list values added or renamed at project level | any length | at most 255 characters (error_dcf_value_length) | no | Existing longer values are untouched. CHANGELOG Changed entry. User decision listed. |
| project | MySQL/MariaDB oversize writes via project pages | strict: HTTP 500 with no audit; non-strict: silent truncation | audited 422 with error_dcf_values_too_large or error_dcf_mapping_too_large (limits mapping); ValueTooLong backstop audited save_failed without the DB message | no | README and CHANGELOG; opt-in rake tasks from the limits area. |
| project | Flash messages with interpolated names | interpolations rendered as HTML (core flash html_safe) | interpolations escaped | no | A security fix; no visible change for normal names. |
| project | Re-render after a failed dependency save | state_hash from the in-memory field (would be stale after a mutation) | field reloaded; a corrected resubmit succeeds | no | Bug fix (T-DEPJ-14). |
| project | 409 on the dependency page | DB state shown, user changes lost | DB state shown plus the shared conflict panel (data-dcf-editor-conflict-mapping; use my version, keep the current version, export my version as CSV; UD-17) | no | Additive; never auto-applied. |
| project | OperationError / AuditRecorder failure rows | failure rows carry only error_message (the key) | plus changes_summary with sanitized details (reason, byte counts, offender labels of this field and its parent) | no | Additive keyword arguments with defaults. |
| project | CSS and JS files | project rules in depending_custom_fields.css (loaded globally); dcf_value_reorder.js always on show | project rules in dcf_config.css included per view; dcf_value_reorder.js only when sortable; new dcf_values_page.js in page mode; editor assets via the head hook only | no | Selectors unchanged, so theme overrides still match. Restart noted in the Upgrade notes. |
| project | Redirects after value operations | always to the unfiltered field page | keep q and page; add_value jumps to the page of the new value; sort resets the page | no | Unchanged for unfiltered, unpaginated pages. |
| project | Orphan entries in stored mappings | silently dropped by the next save | reported by the editor on load (same copy as the admin form), dropped on save, orphans_removed in the audit | no | Matches Functional Spec §24; shown before saving. |
| project | Locale key text_dependency_matrix_help | used by the project matrix | removed; replaced by the editor's neutral text_dcf_editor_help on both pages | no | CHANGELOG Removed entry; parity maintained. |
| limits | Admin custom field form on MySQL strict, saving values or a mapping above the column limit | HTTP 500 ActiveRecord::ValueTooLong, transaction rolled back | Form re-rendered with a translated validation error naming the bytes and the limit | no | CHANGELOG Fixed entry; README MySQL section. |
| limits | Plugin JSON API, core /custom_fields API and jc-redmine_extended_api with oversized possible_values or value_dependencies (MySQL) | HTTP 500 | HTTP 422 {"errors":["... is too large to store (N bytes, the database allows at most 65,535 bytes)"]}, the same shape as any validation error | no | API contract (keys, statuses) unchanged; README documents the message. |
| limits | Write semantics of the JSON API, the extended API and project cascades (format_store) | before_custom_field_save sanitizes only | Unchanged: sanitize-only. D6 pruning happens only on the admin dependencies_json path. | no | No-prune specs (rename-only PUT byte-identical, safe_attributes save, cascade). |
| limits | Project-level services (add, rename including child cascade, mapping save, import, sort) on MySQL | HTTP 500, no audit row | 422 page with an escaped flash naming field and sizes; exactly one validation_failed audit row | no | Audit actions unchanged. |
| limits | MySQL servers in non-strict mode | Oversized saves silently truncated (data loss, possibly unreadable fields) | Save refused with a validation error | yes | Intended (never silent truncation); Upgrade note; report_sizes finds affected fields; widen_core_columns raises the limit. |
| limits | Core list and enumeration fields on MySQL | 500 or truncation above 64 KB | Validation error | no | Upgrade note; GUARDED_FORMATS constant; user decision. |
| limits | Audit before_value/after_value columns | Full JSON of any size (on MySQL an overflow rolled the whole change back) | Byte-identical JSON up to 16,384 bytes (every compact project delta); above that, a shrunk JSON with top-level scalars kept and payload_truncated/payload_bytes/payload_sha256 | no | No view renders these columns; CHANGELOG Changed entry; the marker names do not collide with delta keys. |
| limits | Audit error_message, changes_summary and affected_child_field_ids | Unbounded; a RecordInvalid message was stored raw | error_message cut at 4,000 chars; ValueTooLong rows store only class, column identifier, field id and byte counts; ids limited to the first 1,000 (still a JSON array) | no | ConfigAuditEvent#affected_child_field_ids_list unaffected. |
| limits | RedmineDependingCustomFields::OperationError constructor | key, http_status:, audit_status: | Adds optional summary:, interpolations: and payload: keywords and readers | no | Defaults keep every existing call valid. |
| limits | ProjectCustomFieldConfigurationController#translate_error (private) | translate_error(key) | translate_error(error_or_key), accepting a Symbol or an OperationError and escaping interpolations | no | Symbol callers keep working. |
| limits | CustomField validations seen by other plugins calling valid?/save | No size validation | A new dcf_storage_too_large error, only on MySQL, only for guarded formats, only when a changed column exceeds the limit | no | Symbol callback deduplicated; separate prepended module. |
| limits | Rake tasks | None | redmine:depending_custom_fields:report_sizes and :widen_core_columns (opt-in, dry run by default) | no | Never run automatically; documented. |
| limits | Issue-form data-dcf-map for depending_enumeration | Global inline mapping with string ids | Per-field attribute (server canonical table) with JSON integer ids, not pruned | no | The client coerces with String(); the server owns the contract. |
| limits | PostgreSQL and SQLite installations | No limit | Unchanged (no check); only the audit cap applies | no | None needed. |
| limits | Widened core columns (after running the task) | TEXT 65,535 bytes | MEDIUMTEXT (or LONGTEXT); the validation limit follows after a restart | no | REVERT=1 path; uninstall leaves the harmless wider type; re-run report_sizes before Redmine upgrades. |
| quality | Developer test command `RAILS_ENV=test bundle exec rspec plugins/redmine_depending_custom_fields/spec` | Defined order; no system, :mysql or :perf specs | Same command; random order with the seed printed; system specs excluded unless DCF_SYSTEM_SPECS=1; :mysql specs excluded unless the DB is MySQL; :perf specs excluded unless DCF_PERF_SPECS=1 | no | Verified green on 3 seeds (7.0) and on all four versions with the prototype; a failing seed is reproduced with --seed. |
| quality | spec/rails_helper.rb second init.rb load | init.rb executed twice | Executed once | no | Suite green on 5.1, 6.0, 6.1 and 7.0 without the line (E12). |
| quality | test/spec/** and test/test_helper.rb | Present, never run, broken | Deleted | no | Not referenced by CI, README or Redmine rake tasks; CHANGELOG note. |
| quality | Repository dev files (.codex/, .rubocop.yml, package.json, package-lock.json, .gitignore, test/js/ including generated fixtures) | Absent | Present; dev-only | no | Redmine does not load them (Zeitwerk covers app/lib; assets come from assets/); rsync excludes node_modules; core RuboCop ignores plugins/** (E5). |
| quality | Plugin Gemfile | rspec-rails in the test group | Unchanged | no | System specs use core's capybara and selenium; no gems leak into Redmine bundles. |
| quality | GitHub workflows rspec-51/60/70.yml | workflow_dispatch, no inputs, apt nodejs, mkdir tmp/test-results | workflow_dispatch with system_specs input (default false); rspec-70 also lint (default true) and base_ref inputs with fetch-depth 0; permissions: contents: read; node_modules excluded; unused steps removed | no | Still manual only, guarded by spec/quality/ci_workflows_spec.rb; default inputs keep today's spec run. |
| quality | New workflows rspec-61.yml and js-tests.yml | Absent | workflow_dispatch only | no | Dispatchable once on the default branch; documented in the CI policy. |
| quality | Admin custom field form header (_default_dependencies.html.erb) | l(:label_default_value), undefined, renders as missing translation | l(:field_default_value), core key in de/en/fr/nl | no | Display-only fix; parity stays at 74 keys. |
| quality | spec/patches/custom_field_required_validation_spec.rb | 7 endless defs and stand-in classes that only define after_save | Normal defs (WP-01), then DB-backed with real fields (WP-04) | no | Spec-only; same behaviour asserted; new callbacks live in a separate module either way. |
| quality | Contributor workflow (lint) | No lint gate | Ratchet: no new offenses in changed files, Ruby 2.7 syntax, compat grep including javascript_tag and en/em dashes on added lines | no | Existing offenses grandfathered by the dynamic base; '# dcf-compat-ok' marker for justified exceptions. |
| quality | README.md and CHANGELOG.md punctuation | 14 and 3 en/em dashes | Commas, colons or plain hyphens; no-dash spec keeps it so | no | Text-only change, meaning unchanged. |
| quality | Admin nested params value_dependencies / default_value_dependencies (CustomField safe attributes) | Accepted | Accepted permanently (D5 suggested one minor version); the JSON field wins when both are posted | no | jc-redmine_extended_api writes through safe_attributes= (E28); no pruning on that path (S7). |
| quality | Project nested params on update_dependencies | Accepted | Accepted and logged as deprecated. Deprecated in 0.3.0, accepted throughout 0.3.x, removable no earlier than 0.4.0 | no | Version target stated in the CHANGELOG (UN-42). |

## 6. Upgrade notes and rollback

| Release | Upgrade notes | Rollback |
|---|---|---|
| 0.0.16 | Restart Redmine. No migration. Ruby 2.7 or newer. | Install 0.0.15 again; nothing stored changes. |
| 0.1.0 | Restart Redmine. On MySQL servers without strict mode, saves that used to be truncated silently are now refused with a clear error; run `rake redmine:depending_custom_fields:report_sizes` first. Core List and Key/Value list fields are checked too (UD-25). | Install 0.0.16 again; data written by 0.1.0 is valid for 0.0.16. Audit rows with `payload_truncated` stay readable. |
| 0.2.0 | Restart Redmine. Run `rake redmine:plugins:assets` when automatic asset mirroring is disabled or assets are baked into an image. Integrations that read `window.DependingCustomFieldData` must use the per-field `data-dcf-*` attributes (README Integration). | Install 0.1.0 again and restart; the old global script comes back. No stored data changes. |
| 0.3.0 | Restart Redmine. The admin and project dependency editors need JavaScript. Integrations posting nested `value_dependencies` to the project page should switch to `dependencies_json` (accepted throughout 0.3.x). | Install 0.2.0 again; mappings saved by the editor are plain Hashes and load in 0.2.0. Compact audit rows (v2) stay readable as text. |
