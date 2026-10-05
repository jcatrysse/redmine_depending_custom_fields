# Project-level pages (points 7, 8, 9, project side): implementation design, revision 2

> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 9; plus the project side of 7 and 8 (shared editor on the project dependency page, project-mode CSV import and export through the shared editor). Owner area: project (project configuration controller, project services, values page, sort, page-scoped enumeration save, project storage ceiling, project views, `dcf_config.css`, `dcf_values_page.js`, project locale keys). Work packages: WP-27, WP-28, WP-29, WP-30, WP-31 (primary, release 0.3.0); consumed: WP-04 (project characterization specs, 0.0.16), WP-05 (`DependencyRules.parent_of`, `value_options`, `FieldIndex`, 0.0.16), WP-06 (`storage_preview(custom_field, store)`, 0.0.16), WP-11 and WP-12 (`CustomFieldValidationPatch`, `StorageLimits`, service error mapping, `OperationError` kwargs, `translate_error(e)`, `dcf_status_code`, `AuditPayload`, 0.1.0), WP-18 (head hook, `ClientConfig.editor_page?`, 0.2.0), WP-21 to WP-26 (`DependencyPayload`, shared editor partial, presenter, JS, CSV import and export, 0.3.0); WP-32 (release 0.3.0: CHANGELOG, README, docs amendments A5 and A6). Decisions: UD-01, UD-03, UD-15, UD-16, UD-17, UD-18, UD-19, UD-21, UD-22, UD-23, UD-24, UD-28.

**Consolidation.** The final completeness critic (gaps 1, 2, 3, 4, 8, 11, 12 and 14, project parts) and the binding contracts of `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts") and section 3 ("Contract rows added during consolidation") are applied inline below. Where the revision 2 text conflicted with them, they win. Release targets follow the work packages: 0.0.16 = WP-01..WP-07, 0.1.0 = WP-08..WP-14, 0.2.0 = WP-15..WP-20, 0.3.0 = WP-21..WP-32; every project item of this document ships in 0.3.0, except the service error mapping, `translate_error` escaping and `dcf_status_code` (WP-12, 0.1.0). Locale texts live only in `large_lists_i18n_registry.md`; this document names keys, interpolations and owner WPs.

| Topic | Consolidated rule | Sections |
|---|---|---|
| Release and deprecation | Project items ship in 0.3.0 (WP-27 to WP-31). Project nested params on `update_dependencies` are deprecated in 0.3.0 (accepted throughout 0.3.x, deprecation log) and removable no earlier than 0.4.0 (UD-01). | 1, 3.3, 13, 16 |
| Failed-save re-render (gap 1) | Hidden input always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; no `data-dcf-editor-echo`, no `input_value`. Project: `posted: service.parsed_payload` passed to `DependencyEditorConfig.for_project`. | 1, 2.1, 3.2, 3.5, 15 |
| 409 conflict and submit gate | Editor names: `data-dcf-editor-conflict-mapping` (from `conflict:`) with the shared conflict panel (UD-17), and `data-dcf-editor-submit` on the Save button. The project's `data-dcf-editor-pending` and `data-dcf-editor-submit-gate` are withdrawn. | 1, 2.1, 3.2, 3.5, 14, 15 |
| `DependencyRules.parent_of` (gap 2) | WP-05 API: memoized on the record, returns the parent record or nil for blank, dangling, wrong type or family, or self. WP-27 uses it for `text_dcf_parent_missing` and `text_dcf_parent_not_available` and in `DependencyMappingService#perform!`. | 2.6, 3.2, 3.3, 3.4 |
| `value_options` (gap 3) | Returns `[key, label, active]` tuples; consumed as `\|key, label, active\|` in `labels()` (WP-27) and in the `ValuesPage` rows (WP-28). The wire shape is only `DependencyEditorConfig.wire_values` (WP-24). No project hash contract spec. | 2.3, 3.3, 5, 15 |
| Signatures (gap 4) | `translate_error(e)` with the `OperationError` (owner limits, WP-12; one signature `translate_error(error_or_key)`), used by WP-27 to WP-31. `storage_preview(custom_field, store)`, called as `format.storage_preview(record, record.format_store)` (WP-06, consumed through `StorageLimits`). | 2.4, 3.2, 12 |
| Callback registration | The storage validation and the non-persisted `dcf_storage_ceiling` accessor live in the single `Patches::CustomFieldValidationPatch` (WP-11; WP-31 adds the accessor). There is no `CustomFieldStoragePatch`. | 0, 2.4 |
| Locale keys (gap 8) | WP-27 reuses the editor-owned `error_invalid_dependency_payload` and `error_dcf_dependencies_too_large_to_send` (WP-25) and adds none of `text_dcf_editor_pending_conflict`, `button_dcf_editor_pending_*`, `error_dcf_dependency_payload_too_large`, `text_dcf_orphan_entries`, `text_dcf_editor_requires_javascript`. | 2.2, 3.3, 3.5, 11 |
| Values page thresholds (gap 11) | Search box above 25 values (`FILTER_MIN`) or when `q` is present; pagination above 500 values (`UNPAGINATED_MAX`, UD-21). | 1, 5, 13, 16 |
| Tests added (gap 12) | WP-27: unauthorized PATCH `update_dependencies` with a malformed or 1,000,000-digit payload gives 403, an `authorization_failed` audit row, and `DependencyPayload.parse` is not called. WP-31: plugin settings page request spec (`project_storage_ceiling_kib` renders in en and de; a non-numeric POST falls back to 2,048 KiB). | 15 |
| WP lists (gap 14) | WP-31 lists `lib/redmine_depending_custom_fields/dependency_editor_config.rb` with the spec "`for_project` storage limit equals `ProjectStoragePolicy.format_store_limit(field)`" and depends on WP-30 (both edit `update_enumerations_service.rb`). WP-27 depends on WP-26 (project-mode import verified end to end with the WP-26 import panel). | 2.1, 17 |

Revision 2 adopts these shared contracts instead of the project-only variants in revision 1:
- the editor area's shared editor partial and presenter (R4, UX-01);
- one payload schema and parser (R3, QA-02, BC-03, SP-01, SP-02);
- the limits area's storage validation, error mapping and audit cap (R5, R10, SP-09);
- one value-option shape (R7).

It also fixes the project-specific defects the reviewers found:
- R9: state hash computed from a mutated field;
- QA-18: posted mapping lost on 409;
- SP-03: no storage ceiling for non-admin writes;
- SP-06: HTML in flash interpolations;
- SP-12: client-reported audit metadata;
- SP-17: payload parsed twice;
- QA-17: test gaps;
- UX-10: banners without icons;
- UX-12: values toolbar.

## 0. Scope, ownership, evidence

### Owned by this area
- **Controller:** `ProjectCustomFieldConfigurationController`.
- **Services:** `DependencyMappingService`, the new `SortValuesService`, `UpdateEnumerationsService` (page mode), `ReorderValuesService`, and the save path of the Add, Rename, Remove and SetDefault services.
- **New service-layer objects:** `ValuesPage`, `ValueCollation`, `DependencyDelta`, `ProjectStoragePolicy`, `UsageCalculator.page_usage`.
- **Views and helper:** the project views and helper.
- **Assets:** `assets/stylesheets/dcf_config.css`, `assets/javascripts/dcf_values_page.js`.
- **Wiring:** the `sort_values` route and its permission entry; the project locale keys listed in section 11.
- **Tests, docs, CHANGELOG:** the project specs, the docs/specs amendments and the CHANGELOG lines for project items (section 16).

### Consumed, owned elsewhere
Interfaces are pinned in section 2. If a consumed piece is not merged when this work starts, this work package implements it to the pinned contract, never a project variant.

| Piece | Owner |
|---|---|
| Shared editor partial `depending_custom_fields/_dependency_editor`, presenter `DependencyEditorConfig` (with `wire_values`), JS (`dcf_dependency_editor_model.js`, `dcf_dependency_editor.js`), CSS, its `DependencyEditorConfig::I18N` map, `DependencyPayload` parser, the conflict panel | editor area (WP-21 to WP-26) |
| `StorageLimits`, `CustomFieldValidationPatch`, `AuditPayload`, the `BaseService` storage rescue mapping, `OperationError` kwargs, `translate_error(error_or_key)`, the large-list generator, rake tasks | limits area (WP-11 to WP-13) |
| `DependencyRules` (`value_options`, `parent_of`), `FieldIndex`, `storage_preview(custom_field, store)`, head hook, `ClientConfig.editor_page?` | server area (WP-05, WP-06, WP-18) |
| Locale parity and duplicate-key spec, RuboCop ratchet, markup fixture mechanism | quality area (WP-01, WP-02) |

**Scratchpad root:** `$S` = `<planning scratch space, not part of the repository>`.

### Evidence

Revision 1 probes are still valid for the rows below. They ran in rolled-back transactions on 5.1 (Rails 6.1) and 7.0 (Rails 8.1) with identical output (`design/project/probe_project.{5.1,7.0}.out`, `design/project/rack_probe.out`):

| Probe | Result |
|---|---|
| `a_brackets_saved` | `a]`, `[b`, `Foo [x]` round-trip exactly through one JSON field |
| `f_big` | 8,000 links (136,975 B JSON) saved as one param |
| `b_*` | malformed or blank payload gives an audited `validation_failed` row with reason and size |
| `c_unknown` | aggregated offender summary |
| `i_*`, `j_*` | stable accent- and case-insensitive sort; chunked `CASE` update for enumerations, including inactive ones |
| `k_*` | page-scoped enumeration save |
| `l_*` | pagination and page clamp |
| `m_usage_queries` | 2 SQL queries per page for usage |
| rack probe | urlencoded body over 4 MB: PATCH downgraded to POST (404) on rack 2.2.24 and 3.2.7; multipart stays PATCH |

The revision 1 rows `g_*` and `h_*` (project pre-check guard) are withdrawn. The storage path now follows limits evidence V10: `AddValueService` and `DependencyMappingService` map a `RecordInvalid` storage violation to an audited `OperationError`, and the `ValueTooLong` safety net works (`design/limits/probe_services.7.0.out`).

New probes for revision 2 are in `$S/design/project/proto2/`. All files pass `Lint/Syntax` at `TargetRubyVersion 2.7`.

| File | Result |
|---|---|
| `collation.out` | Shared fold table, 20 cases (accents, ß, ł, ø, đ, æ, œ, þ, ı, İ, ligature, roman numeral, whitespace, lone combining mark). 0 mismatches on Ruby 3.1.6, 3.2.6 and 3.3.6, and 0 mismatches against the editor model's `fold()` on Node 22.22.0 (`collation_test.js`). `tokens("́") == []`. The fixture must be read with `encoding: 'UTF-8'`; the default external encoding is US-ASCII in CI shells. |
| `number_guard.out` | Pre-parse long-number guard. A 4 MiB payload holding one 4,194,255-digit integer is rejected in 4.8 to 8.7 ms. A 4.3 MB digit-dense payload of 160,000 small keys is accepted in 181 to 244 ms, the same order as `JSON.parse` of that input (185 ms, `guard_alt.out`). Digits inside strings are not rejected. 20-digit negatives are rejected; 19-digit integers are accepted. |
| `delta_worst.out` | Byte-budgeted delta, worst case: 20,000 added and 20,000 removed links, 100 changed defaults, every label made of characters that ActiveSupport escapes to 6 bytes. `after_value` = 12,028 B, `before_value` = 118 B, on ActiveSupport 6.1.7.10 and 8.1.4. That is under the 16,384 B AuditPayload cap, so AuditPayload never shrinks it. |

### Core facts relied on
- **Flash rendering is unescaped.** `render_flash_messages` renders `v.html_safe` (core-5.1 `app/helpers/application_helper.rb:487`; core-6.0 `:514`; core-6.1 `:521`; core-7.0 `:527`). From 6.0 on it prepends `notice_icon(k)`. `notice_icon(type)` exists in 6.0, 6.1 and 7.0 (`app/helpers/icons_helper.rb:82` and `:94`) but not in 5.1.
- **Core filter pattern:** `form_tag(..., method: :get)` + `<fieldset><legend>label_filter_plural</legend>`, `label`, `text_field_tag`, `submit_tag button_apply class small name nil`, and a `button_clear` link with `icon icon-reload` (with `sprite_icon('reload', ...)` on 7.0). Source: core-5.1 and core-7.0 `app/views/groups/index.html.erb:7-14`.
- **Page size:** `per_page_option` validates against `Setting.per_page_options_array` and stores the choice in the session (core-5.1 `application_controller.rb:667-678`, core-7.0 `:673-684`).
- **Paginator does not clamp** (core-7.0 `lib/redmine/pagination.rb:25-40`).
- **No `CustomFieldEnumeration` update callbacks** in 5.1 to 7.0; only `before_create :set_position`.
- **State hash.** `BaseService.state_hash` hashes the in-memory `value_dependencies`/`default_value_dependencies` (`base_service.rb:31-39`). The preamble does not reload the field. `check_state_hash!` skips a blank `state_hash` (`base_service.rb:83-89`); this existing script-friendly behaviour is kept.
- **Parent requirement.** `FieldRelevance.dependency_capable?` requires a raw parent id (`field_relevance.rb:34-37`), so a dangling parent id reaches `edit_dependencies`.

## 1. Decisions at a glance

1. **Transport.**
   - `edit_dependencies` posts ONE hidden field, `dependencies_json`, plus `state_hash`, in a multipart PATCH form.
   - The value is decoded inside `DependencyMappingService` with the shared `DependencyPayload.parse!` (schema v1, section 2.2), so every bad input is audited.
   - Key absent: the request uses the legacy nested params (deprecated in 0.3.0; accepted throughout 0.3.x, removable no earlier than 0.4.0; UD-01).
   - Key present but blank or invalid: audited 422.
2. **Initial state.**
   - The editor reads it from `data-dcf-editor-mapping`. The hidden input is ALWAYS rendered blank (GET and every re-render), so a server pre-fill never counts as dirty.
   - Failed-save re-render (gap 1, compat section 3): the controller passes `posted: service.parsed_payload` to `DependencyEditorConfig.for_project`; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`, so the editor starts dirty, which is correct. There is no `input_value` option and no `data-dcf-editor-echo` attribute.
   - The Save button is rendered `disabled` with `data-dcf-editor-submit`. The editor enables it after a successful init, so without working JavaScript nothing can be submitted, and nobody sees a false success or a pointless "reload" message (UD-16).
3. **Validation stays strict:**
   - unknown parent keys, unknown child values and defaults outside the links give 422 `error_invalid_dependency`;
   - lookups use Sets, and offenders are aggregated into the audit summary;
   - inactive enumerations are valid;
   - the JSON path shapes defaults by `multiple?`.
4. **Compact audit delta v2.**
   - Samples are bounded by entry count and by encoded bytes, so `after_value` is at most about 12 KB, below the limits area's 16,384 B AuditPayload cap.
   - Digest key `mapping_sha256`; it never collides with the AuditPayload marker key `payload_sha256`.
5. **Values page.**
   - Server-side search (`q`, token AND match on the shared collation key) and pagination (`page`, `per_page` from `per_page_option`, capped at 500).
   - Search box above 25 values (`FILTER_MIN`) or when `q` is present. Pagination only above 500 values (UD-21). Drag-and-drop only when unfiltered and unpaginated.
   - Core filter fieldset markup and a filtered empty state.
6. **Sort service.**
   - New `sort_values` action (`PATCH .../values/sort`, `direction` = `asc` or `desc`), audit action `sort_values`.
   - Stable, using the shared collation. Inactive enumerations are sorted together with active ones (UD-24).
   - The audit row carries `order_sha256` before and after.
7. **Enumeration page mode.** `batch_scope=page` takes a validated subset; positions are never changed in page mode; duplicates are checked on the merged state. Full mode is unchanged.
8. **`reorder_values` keeps its array contract.** It gains `order_sha256` in the audit.
9. **Storage.**
   - The limits area's model validation and `RecordInvalid` mapping are the single mechanism.
   - Project services add an application ceiling (default 2,048 KiB, plugin setting, UD-22) through `BaseService#save_field!`, which sets the non-persisted `record.dcf_storage_ceiling`.
   - New list values are capped at 255 characters.
10. **Assets.**
    - Editor JS and CSS come only from the head hook (`ClientConfig.editor_page?` includes this controller).
    - Project views include only `dcf_config.css`, plus `dcf_value_reorder.js` when the list is sortable and `dcf_values_page.js` in page mode. Nothing is loaded twice.
11. **409 recovery (UD-17, compat section 2.4 row "Project conflict (409) and submit gate").**
    - A stale save re-renders the fresh DB state and passes the parsed posted payload as `conflict:`, which the presenter emits as `data-dcf-editor-conflict-mapping`.
    - The editor shows the same conflict panel as on the admin stale save (editor design 5.8): "Use my version", "Keep the current version" and "Export my version (CSV)". Nothing is applied automatically.
12. **Parse once per request.**
    - The service exposes `parsed_payload` (the memoized ok `Result` of `DependencyPayload.parse!`), and the controller reuses it on 422.
    - On 409 the service never parsed (the conflict is raised in the preamble), so the controller parses exactly once, after authorization.
13. **Error re-renders reload the field** before computing `state_hash` (R9).
14. **Flash safety.** `translate_error(e)` (limits WP-12; one signature `translate_error(error_or_key)`, Symbol or `OperationError`) HTML-escapes every interpolation value. Flashes never contain payload content.
15. **Banners.**
    - The global/shared banner on `edit_dependencies` is based on the child scope. Shared and global fields get no server-side confirmation panel for dependency saves (replace imports included) or sort; only the scope banner and the sort JS confirm (UD-23).
    - Notices replace the editor when the parent is missing or not relevant, decided with `DependencyRules.parent_of` (gap 2).
    - Flash boxes carry `notice_icon` on 6.0+.

## 2. Consumed contracts (pinned)

### 2.1 Shared editor (owner: editor area)

The project view renders the shared partial inside its own PATCH form:

```erb
<%= render 'depending_custom_fields/dependency_editor',
           editor: RedmineDependingCustomFields::DependencyEditorConfig.for_project(
             field: @field, parent: @parent, view: self,
             posted: @posted_payload, conflict: @conflict_payload) %>
```

Presenter signature (editor area, WP-24): `for_project(field:, parent:, view:, posted: nil, conflict: nil)`. `posted` and `conflict` are ok `DependencyPayload::Result` objects or nil. There is no `input_value:`, `pending:` or `storage_limit:` option: the project storage limit is computed inside the presenter in project mode as `ProjectStoragePolicy.format_store_limit(field)` (WP-31 changes `lib/redmine_depending_custom_fields/dependency_editor_config.rb` for this; until WP-31 the WP-24 column limit applies).

Root element: `fieldset.dcf-dep-editor[data-dcf-editor]`. The only named input is the hidden `dependencies_json` (id `dcf_dependencies_json`, `autocomplete="off"`).

Attributes used in project mode (all in the `data-dcf-editor-*` namespace, so nothing collides with the issue-form contract, BC-03 and UX-01):

| attribute | project value |
|---|---|
| `data-dcf-editor-mode` | `project` |
| `data-dcf-editor-kind` | child family, `list` or `enumeration` |
| `data-dcf-editor-field-id`, `-field-type`, `-field-name` | child |
| `data-dcf-editor-parent-id`, `-parent-name` | parent (always present, because the editor is only rendered when the parent exists and is relevant) |
| `data-dcf-editor-parent-values`, `data-dcf-editor-child-values` | wire values from `DependencyEditorConfig.wire_values(DependencyRules.value_options(cf))` (2.3); enumerations are all values, inactive included, by position then id |
| `data-dcf-editor-mapping` | `{"value_dependencies":{...},"default_value_dependencies":{...}}`, unpruned. GET and 409: the stored mapping from the reloaded record. Failed-save re-render (422 with an ok parse): the posted payload from `posted:` (gap 1). The editor counts orphans client-side with `text_dcf_editor_orphans`, the same copy as on the admin form. |
| `data-dcf-editor-dirty` | `1` on a failed-save re-render that renders `posted:` (gap 1); absent otherwise |
| `data-dcf-editor-multiple`, `-required` | `0`/`1` |
| `data-dcf-editor-always-submit` | `1` (the editor writes JSON on every change and synchronously on submit) |
| `data-dcf-editor-submit` (on the Save button, not the root) | after a successful init the editor sets `disabled = false` on every `[data-dcf-editor-submit]` of the enclosing form (editor design 5.4 step 5). The revision 2 root attribute `data-dcf-editor-submit-gate` is withdrawn (compat section 2.4). |
| `data-dcf-editor-max-payload-bytes` | `4194304` (`DependencyPayload::MAX_BYTES`). Before submit the editor refuses a larger JSON and shows the editor-owned `error_dcf_dependencies_too_large_to_send` (`%{size}`, `%{limit}`; WP-25). |
| `data-dcf-editor-conflict-mapping` | 409 re-render only: the user's refused version from `conflict:`, `{"value_dependencies":...,"default_value_dependencies":...,"source":...,"import":{...}}`. The editor shows the shared conflict panel (editor design 5.8, UD-17): `text_dcf_editor_conflict` with "Use my version", "Keep the current version" and "Export my version (CSV)"; nothing is auto-applied. Replaces the revision 2 `data-dcf-editor-pending` with `text_dcf_editor_pending_conflict` and `button_dcf_editor_pending_*` (withdrawn, gap 8). |
| `data-dcf-editor-storage-limit`, `data-dcf-editor-storage-base`, `data-dcf-editor-storage-warn` | effective `format_store` limit for project writes (`ProjectStoragePolicy.format_store_limit(field)`, computed by the presenter from WP-31 on), base bytes (limits formula) and the warn percent (`StorageLimits::WARN_PERCENT`, 90); omitted when there is no limit. Same attribute names, threshold (90 percent) and client key `text_dcf_storage_estimate` as the admin form (R20). |
| `data-dcf-editor-csv-separator`, `-csv-encoding`, `-max-form-bytes`, `-warn-unsaved`, `-i18n` | as on the admin form (`-i18n` from `DependencyEditorConfig::I18N`) |
| not emitted in project mode | `-base` (the project path relies on `state_hash`), `-values-url`, `-parent-source`, `-values-source`, `-allow-add-values` |

Initial state and failed-save semantics (gap 1, compat section 3):
- **GET:** the hidden input is blank. The state comes from `data-dcf-editor-mapping` (stored mapping); not dirty, no `data-dcf-editor-dirty`.
- **422 re-render with an ok parse** (invalid mapping, storage violation): the hidden input is blank; `posted: service.parsed_payload` renders the posted mapping in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`, so the editor starts dirty and writes the payload again. No `input_value`, no `data-dcf-editor-echo`, no raw echo of the posted string.
- **422 without an ok parse** (malformed, blank, oversize, long number) and the legacy nested path: the hidden input is blank and the stored mapping is rendered, not dirty.
- **409 re-render:** the hidden input is blank; the stored mapping is rendered, not dirty; `conflict:` (parsed once, after authorization) adds `data-dcf-editor-conflict-mapping`. Nothing is auto-applied.

The editor also renders the neutral help text `text_dcf_editor_help` (editor key, owner WP-24, section 11), replacing the project-only matrix wording `text_dependency_matrix_help`. Empty states come from the editor: `text_dcf_editor_no_parent_values` and `text_dcf_editor_no_child_values`.

### 2.2 Payload schema v1 and parser (owner: editor area, consolidated per R3, QA-02, BC-03, SP-01, SP-02)

```json
{"version":1,"source":"import","import":{"mode":"replace","rows":5000},
 "value_dependencies":{"Belgium":["Brussels","Ghent"]},"default_value_dependencies":{"Belgium":"Ghent"}}
```

- **Top-level keys:** `version` (must be 1), `source` (`editor` | `import`, default `editor`), `base` (String; admin only, ignored at project level), `import`, `value_dependencies`, `default_value_dependencies`.
- **`import`:** optional. Exactly `{mode: "merge"|"replace", rows: Integer 0..10_000_000}`, allowed only together with `source: "import"`; otherwise `:invalid_import`.
- **Unknown keys:** any other key gives `:unknown_key`. There is no `meta` wrapper; revision 1's `meta.source` and `meta.import` are withdrawn.
- **Parsing:** `JSON.parse(raw, max_nesting: 3, create_additions: false)`. `MAX_BYTES = 4 MiB` on both paths; the project form stays multipart, which buffers up to 16 MB.
- **Long-number guard before parsing.** The editor's `long_number?` (editor design 2.2, step 5) gives `:number_too_long`: stage 1 `raw.match?(/\d{20}/)`, stage 2 `raw.scan(/"[^"\\]*(?:\\.[^"\\]*)*"|\d{20}/m)` returning true on the first token that is not a string. It is O(n) and ignores digits inside strings. The revision 2 project prototype `raw.match?(/\d{20}/) && raw.gsub(/"(?:[^"\\]|\\.)*"/m, '""').match?(/\d{20}/)` has the same accept and reject behaviour (evidence `number_guard.out`); the editor's implementation is the one that ships.
- **Scalars.** Strings are accepted. An Integer is accepted only when `v.positive? && v.bit_length <= 63`, checked before `to_s`. Floats, booleans, null and nested objects in arrays are rejected (`:invalid_links` / `:invalid_defaults`).
- **API:** `parse(raw)` returns `nil` (absent or blank) or `Result(ok?, error, value_dependencies, default_value_dependencies, source, base, import, bytes)` and never raises. `parse!(raw)` is the project entry point: it raises `DependencyPayload::Invalid` (readers `reason`, `bytes`) with `:blank` when `parse` returns nil and with `result.error` when the result is not ok, and otherwise returns the ok `Result`. Error codes:
  - `:not_a_string`
  - `:too_large`
  - `:number_too_long`
  - `:invalid_json` (also nesting)
  - `:not_an_object`
  - `:unknown_key`
  - `:unsupported_version`
  - `:invalid_source`
  - `:invalid_base`
  - `:invalid_import`
  - `:invalid_links`
  - `:invalid_defaults`
- **Project semantics:** key present plus `nil` result means `:blank`, which is an error (never a clear). A `Result` that is not ok is an error. `too_large` maps to the editor-owned size message `error_dcf_dependencies_too_large_to_send` with `%{size}` and `%{limit}` (WP-25; compat section 2.4 row "Payload-too-large key"); every other error maps to the editor-owned `error_invalid_dependency_payload` (WP-25). The revision 2 project key `error_dcf_dependency_payload_too_large` (`%{max}`) is withdrawn (gap 8).
- **Cross-layer contract.** A node test writes `test/js/fixtures/editor/serialized_import_payload.json` from the real model `serialize()` after applying an import (`DCF_WRITE_JS_FIXTURES=1`). The project request spec T-DEPJ-15 posts it unchanged; the admin request spec (editor area) posts it too.

### 2.3 Value option shape (R7, gap 3, owner: server area, WP-05)

`DependencyRules.value_options(cf)` returns ordered tuples `[[key, label, active], ...]` (compat section 3 row "value_options"). Project code consumes them as `|key, label, active|` block parameters and never as hashes.
- Lists: key = label = value (String), active true, in `possible_values` order.
- Enumerations: key = `id.to_s`, label = name, active = the enumeration's flag; all enumerations, inactive included, by position then id.

Consumers:
- `DependencyMappingService#labels` (WP-27) and `DependencyDelta` labels: `value_options(cf).each_with_object({}) { |(key, label, _active), h| h[key] = label }`.
- `ValuesPage` rows (WP-28): `value_options(field).each_with_index.map { |(key, label, active), i| Row.new(key: key, label: label, active: active, index: i) }`.
- `data-dcf-editor-parent-values` and `-child-values`: only through `DependencyEditorConfig.wire_values` (editor, WP-24), the compact wire shape (`label` omitted when equal to `key`, `active` only when false; compat section 2.4 row "Value option wire shape"). The admin values endpoint uses the same function.

The revision 2 hash contract spec `spec/lib/dcf_value_options_contract_spec.rb` (string-key hashes) is dropped (gap 3). The tuple contract is pinned by the WP-05 `DependencyRules` spec; WP-24 writes `test/js/fixtures/value_options.json` from `DependencyEditorConfig.wire_values` and asserts endpoint == presenter == fixture.

### 2.4 Storage limits, project ceiling, error mapping (owner: limits area, plus the project ceiling)

**Limits area, consumed as designed (WP-11, WP-12, 0.1.0):**
- The single `Patches::CustomFieldValidationPatch` (WP-11, compat section 2.4 row "CustomField callback registration") registers `validate :dcf_validate_storage_limits`. There is no separate `CustomFieldStoragePatch` module.
- Error `activerecord.errors.messages.dcf_storage_too_large`.
- `StorageLimits.violation_in(record)`.
- Measurement of `format_store`: `StorageLimits.preview_value(record, 'format_store')` calls the server-owned `storage_preview(custom_field, store)` (WP-06) as `format.storage_preview(record, record.format_store)` when the format responds to it (compat section 3 row "storage_preview", gap 4). It is sanitize-only, so project-service saves (cascades included) are measured exactly as they are written.
- `translate_error(error_or_key)` (WP-12): project actions call it as `translate_error(e)` with the `OperationError` (gap 4); see 3.2.
- In `BaseService#call`:
  - a `RecordInvalid` storage violation gives `OperationError(:error_dcf_values_too_large | :error_dcf_mapping_too_large, interpolations: {field, size, limit})`, audited `validation_failed` with a machine-readable message;
  - `ActiveRecord::ValueTooLong` gives `OperationError(:error_dcf_value_too_long, audit_status: 'save_failed')`.
- Audit row for `ValueTooLong` (limits design 5.3): `error_message` is `error_dcf_value_too_long`; `changes_summary` is `ActiveRecord::ValueTooLong column=<column> field_id=<id> possible_values_bytes=<n> format_store_bytes=<n>` (falls back to `ActiveRecord::ValueTooLong` if building it raises); never `e.message`, SQL, the DB message or values (SP-09; the project audit view shows `changes_summary` or `error_message` to managers, both through `h()`).

**Additions requested by this area (SP-03, UD-22; implemented in WP-31, 0.3.0), small and additive:**
- `CustomFieldValidationPatch` adds `attr_accessor :dcf_storage_ceiling` (Integer bytes or nil; never persisted, defaults to nil, so admin, API and import saves are unaffected).
- `StorageLimits.effective_limit(record, column)` returns `[limit, source]`:
  - `limit` is the smaller of `column_limit(...)` and the ceiling, `source` is `'column'` or `'ceiling'`;
  - the ceiling counts only when `record.dcf_storage_ceiling` is set;
  - the effective ceiling is `max(dcf_storage_ceiling, persisted_bytes)`; `persisted_bytes` (one serialize of `attribute_in_database`) is computed lazily only when the new bytes exceed the ceiling.
  - So a field that an admin already made larger than the ceiling can still be edited at project level as long as the change does not grow it.
- `violations` uses `effective_limit`. `Violation` gains `source`, and `errors.add` passes `source: v.source` with explicit keys (no hash shorthand).

**Owned here:** `app/services/redmine_depending_custom_fields/project_storage_policy.rb`.

```ruby
module RedmineDependingCustomFields
  module ProjectStoragePolicy
    DEFAULT_CEILING_KIB = 2_048
    MIN_CEILING_KIB = 64
    LIST_VALUE_MAX_CHARS = 255

    module_function

    def ceiling_bytes
      raw = (Setting.plugin_redmine_depending_custom_fields || {})['project_storage_ceiling_kib']
      kib = raw.to_s.strip.match?(/\A\d+\z/) ? raw.to_i : DEFAULT_CEILING_KIB
      [kib, MIN_CEILING_KIB].max * 1024
    rescue StandardError
      DEFAULT_CEILING_KIB * 1024
    end

    # Effective limit for the editor's client estimate (data-dcf-editor-storage-limit).
    def format_store_limit(field)
      field.dcf_storage_ceiling = ceiling_bytes
      StorageLimits.effective_limit(field, 'format_store').first
    ensure
      field.dcf_storage_ceiling = nil
    end
  end
end
```

**Plugin setting (WP-31, UD-22).** `init.rb` settings default gains `'project_storage_ceiling_kib' => '2048'`. `app/views/settings/_dcf_project_config.html.erb` gains a number field with the label `label_dcf_project_storage_ceiling` and the info text `text_dcf_project_storage_ceiling_info`. A stored value that is not a plain non-negative integer (for example `abc` posted from the settings page) makes `ceiling_bytes` fall back to 2,048 KiB; values below 64 KiB are raised to 64 KiB. The settings page request spec of section 15 (gap 12) pins the rendering in en and de and the non-numeric fallback.

**Service error texts** for project pages (owner: limits) use neutral wording that is correct for both the column and the ceiling, and no README reference (UX-04). See section 11, "requested from limits".

### 2.5 Audit cap (owner: limits area, WP-12, 0.1.0)

- `AuditPayload::MAX_BYTES = 16_384` per before/after value.
- The marker uses the limits names (compat section 2.4 row "Audit marker keys"): `{"payload_truncated":true,"payload_bytes":N,"payload_sha256":"..."}`, with top-level scalars kept when a value is shrunk. R10's rename from `sha256` to `payload_sha256` is part of it; none of the marker keys collides with the project delta's own `truncated` and `mapping_sha256`.
- `error_message` is capped at 4,000 characters.
- The project delta (section 4) is sized so the cap never triggers; this is asserted by T-DEP-9. There is no plugin migration 002.

### 2.6 Topology and rules (R18)

- **Topology** comes from `FieldIndex` (server area, WP-05; one class with the server names `load` and `children_ids`, compat section 2.4 row "FieldIndex API"): raw `parent_custom_field_id` extraction, `children_ids(id)`. `UsageCalculator.page_usage` builds one `FieldIndex` per request and loads only the child records it needs. There is no project topology code; `FieldRelevance.children_of` stays only for the per-value impact paths until point 6 replaces it.
- **Rules and parent lookup** come from `DependencyRules` (server area, WP-05): `parent_of`, `value_options`.
  - `DependencyRules.parent_of(cf)` (gap 2; compat section 3 row "DependencyRules.parent_of"): memoized on the record; returns the parent record, or nil when the stored parent id is blank, dangling, of the wrong type or family, or the field itself. WP-27 uses it in `prepare_dependencies` (nil gives `text_dcf_parent_missing`; a parent that is not relevant to the project gives `text_dcf_parent_not_available`) and in `DependencyMappingService#perform!` (nil gives `error_invalid_dependency`). The issue-form client emission uses `effective_parent_id` instead (acyclic and visible, WP-16), which is not used here.
  - `value_options(cf)`: tuples, see 2.3.

### 2.7 Collation table (owned here, mirrored by the editor JS fold)

`ValueCollation` uses the SAME character tables as the editor model's `fold()`:
- `COMBINING = /[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︠-︯]/` (not `\p{Mn}`);
- `SPECIAL = { 'ß' => 'ss', 'æ' => 'ae', 'œ' => 'oe', 'ø' => 'o', 'đ' => 'd', 'ł' => 'l', 'ı' => 'i', 'þ' => 'th' }`;
- the steps: NFKD, strip the COMBINING range, `downcase` (full Unicode, to match JS `toLowerCase`), apply SPECIAL, collapse whitespace, strip.

A shared fixture `test/js/fixtures/shared/collation_cases.json` (20 cases, `proto2/collation_cases.json`) is asserted by `spec/lib/dcf_value_collation_spec.rb`, which reads it with `encoding: 'UTF-8'`, and by `test/js/collation_parity.test.js`, which uses the editor model. Changing either side fails CI.

## 3. edit_dependencies and update_dependencies

### 3.1 Routes and permission
The `GET`/`PATCH custom_field_configuration/fields/:field_id/dependencies` routes are unchanged, as are `find_field`, `require_dependency_capable` and `require_active_project`.

### 3.2 Controller (`app/controllers/project_custom_field_configuration_controller.rb`)

```ruby
def edit_dependencies
  prepare_dependencies
end

def update_dependencies
  service = RedmineDependingCustomFields::DependencyMappingService.new(
    project: @project, field: @field, user: User.current,
    params: dependency_params, request: request
  )
  service.call
  flash[:notice] = l(:notice_dependencies_saved)
  redirect_to custom_field_configuration_field_dependencies_path(@project, @field)
rescue RedmineDependingCustomFields::OperationError => e
  case e.http_status
  when :forbidden then deny_access
  when :not_found then render_404
  else
    flash.now[:error] = translate_error(e)          # gap 4: the OperationError itself
    if e.http_status == :conflict
      prepare_dependencies(conflict: conflict_payload)
    else
      prepare_dependencies(posted: posted_payload(service))
    end
    render :edit_dependencies, status: dcf_status_code(e.http_status)
  end
end

private

def dependency_params
  out = { state_hash: params[:state_hash] }
  if params.key?(:dependencies_json)
    out[:dependencies_json] = params[:dependencies_json]       # raw; the service checks the type
  else
    out[:value_dependencies] = unsafe_hash(params[:value_dependencies])
    out[:default_value_dependencies] = unsafe_hash(params[:default_value_dependencies])
  end
  out
end

# R9: never compute state_hash or render from an instance the failed service mutated.
# Gap 1: the hidden input is always blank. A posted ok Result is rendered by the
# presenter in data-dcf-editor-mapping with data-dcf-editor-dirty="1".
def prepare_dependencies(posted: nil, conflict: nil)
  @field.reload
  @state_hash = RedmineDependingCustomFields::BaseService.state_hash(@field)
  @parent = RedmineDependingCustomFields::DependencyRules.parent_of(@field)   # gap 2 (WP-05)
  @parent_available = @parent.present? &&
                      RedmineDependingCustomFields::FieldRelevance.relevant?(@parent, @project)
  @posted_payload = posted
  @conflict_payload = conflict
end

# The service's memoized ok Result (parse! succeeded, SP-17: no second parse).
# nil after a parser error, on the legacy nested path, or when no service exists.
def posted_payload(service)
  result = service&.parsed_payload
  result&.ok? ? result : nil
end

# The service raised the 409 in its preamble, before parsing, so this is the
# only parse of the request (SP-17) and it runs after authorization.
def conflict_payload
  raw = params[:dependencies_json]
  return nil unless raw.is_a?(String)

  result = RedmineDependingCustomFields::DependencyPayload.parse(raw)
  result&.ok? ? result : nil
end

def dcf_status_code(symbol)
  symbol == :conflict ? 409 : 422          # numeric: no Rack 3.1 deprecation warning (quality Q16)
end

# Owner: limits area (WP-12, limits design 5.4); one signature for the whole
# controller, shown here because every project flash goes through it. SP-06:
# Redmine renders flash with html_safe, so every interpolation is escaped here.
# Interpolations are used for flash only; never put payload content (offenders,
# labels, import rows) into a flash.
def translate_error(error_or_key)
  if error_or_key.is_a?(RedmineDependingCustomFields::OperationError)
    key = error_or_key.key
    values = error_or_key.interpolations || {}
  else
    key = error_or_key
    values = {}
  end
  escaped = values.each_with_object({}) { |(k, v), h| h[k.to_sym] = ERB::Util.html_escape(v.to_s).to_str }
  l(key, escaped.merge(default: key.to_s))
end
```

Other controller changes:
- `perform_value_operation` (WP-12; reused by WP-28 to WP-31 for `sort_values`, page mode and the ceiling) calls `translate_error(e)` and uses `dcf_status_code`.
- `render_field_error` and `require_active_project` keep calling `translate_error(key)` with a Symbol.
- The view needs no `@storage_limit`: the presenter computes the project storage limit itself (2.1, WP-31).
- **Authorization before parsing (SP-20b, gap 12).** `dependency_params` only copies the raw value; nothing parses it in the controller before the service runs. The core `authorize` filter stops a user without the permission with 403 before the action; the service preamble re-checks the permission (defense in depth) and raises `OperationError(:error_forbidden, http_status: :forbidden, audit_status: 'authorization_failed')` before `read_input!`, so an unauthorized PATCH with a malformed or 1,000,000-digit `dependencies_json` gives 403 (`deny_access`), one `authorization_failed` audit row from the preamble, and no call of `DependencyPayload.parse` or `parse!`. The 409 branch is the only controller-side parse, and it runs only after the preamble passed authorization.

### 3.3 Service (`app/services/redmine_depending_custom_fields/dependency_mapping_service.rb`)

```ruby
attr_reader :parsed_payload          # public: ok Result reused by the controller on 422 (SP-17)

def perform!
  parent = DependencyRules.parent_of(field)          # gap 2: nil for blank, dangling, wrong type or family, self
  raise OperationError.new(:error_invalid_dependency) unless parent
  raise OperationError.new(:error_field_not_found, http_status: :not_found) unless FieldRelevance.relevant?(parent, project)

  input = read_input!
  parent_labels = labels(parent)                     # ordered {key => label}, all enumerations
  child_labels  = labels(field)
  vd = Sanitizer.sanitize_dependencies(input[:value_dependencies])
  dd = Sanitizer.sanitize_default_dependencies(input[:default_value_dependencies])
  dd = shape_defaults!(dd) if input[:json]
  validate_mapping!(vd, dd, parent_labels, child_labels)

  delta = DependencyDelta.new(old_vd: field.value_dependencies || {}, old_dd: field.default_value_dependencies || {},
                              new_vd: vd, new_dd: dd, parent_labels: parent_labels, child_labels: child_labels,
                              source: input[:source], import: input[:import])
  field.value_dependencies = vd
  field.default_value_dependencies = dd
  save_field!(field)                                 # sets the project ceiling, then save! (section 9)
  Outcome.new(before: delta.before, after: delta.after, summary: delta.summary,
              affected_projects_count: affected_projects_count)
end

def read_input!
  return legacy_input unless @params.key?(:dependencies_json)

  begin
    # The only parse of this request (SP-17); it runs after the preamble authorized the user.
    @parsed_payload = DependencyPayload.parse!(@params[:dependencies_json])
  rescue DependencyPayload::Invalid => e
    reject_payload!(e.reason, e.bytes.to_i)
  end
  { json: true, value_dependencies: @parsed_payload.value_dependencies,
    default_value_dependencies: @parsed_payload.default_value_dependencies,
    source: @parsed_payload.source, import: @parsed_payload.import }
end

# Both keys are owned by the editor (WP-25, gap 8); interpolations are integers only.
def reject_payload!(reason, bytes)
  key = reason == :too_large ? :error_dcf_dependencies_too_large_to_send : :error_invalid_dependency_payload
  raise OperationError.new(key,
                           summary: "dependencies_json rejected: #{reason} (#{bytes} bytes)",
                           interpolations: { size: StorageLimits.delimited(bytes),
                                             limit: StorageLimits.delimited(DependencyPayload::MAX_BYTES) })
end

def legacy_input
  Rails.logger.warn('[redmine_depending_custom_fields] update_dependencies received legacy nested params; ' \
                    'send dependencies_json (deprecated in 0.3.0, removable no earlier than 0.4.0)')
  { json: false, value_dependencies: @params[:value_dependencies],
    default_value_dependencies: @params[:default_value_dependencies], source: 'form', import: nil }
end

# Gap 3: value_options returns [key, label, active] tuples, never hashes.
def labels(cf)
  DependencyRules.value_options(cf).each_with_object({}) { |(key, label, _active), h| h[key] = label }
end
```

- **Labels.** `labels(cf)` returns an ordered `{key => label}` Hash built from the `[key, label, active]` tuples of `DependencyRules.value_options(cf)` (gap 3), all enumerations, inactive included. The same Hashes feed `DependencyDelta`.
- **Parser errors.** `parse!` raises `DependencyPayload::Invalid` for `:blank` and for every parser error code; `parsed_payload` then stays nil, so the controller renders the stored mapping (2.1). `too_large` gives `error_dcf_dependencies_too_large_to_send` (`%{size}`, `%{limit}`), every other reason `error_invalid_dependency_payload`.
- **`shape_defaults!`, JSON path only:**
  - multiple field: every default becomes an Array;
  - single field: `[x]` becomes `"x"` and `[]` drops the key;
  - more than one value is collected as an offender ("defaults with several values on a single-value field").
- **`validate_mapping!`:**
  - `Hash#key?` lookups on the label hashes;
  - it collects all offenders: unknown parent keys, unknown child values, defaults not linked, several defaults on a single field;
  - it raises `OperationError(:error_invalid_dependency, summary: "unknown parent keys: N [first 5]; unknown child values: N [first 5]; defaults not linked: N [first 5]; several defaults on a single-value field: N [first 5]")`;
  - offender labels are cut at 40 characters, and the summary at 1,000;
  - the flash is the generic key; offenders go only to the audit summary, which a manager can read in the project audit view;
  - the labels belong to this field and its parent, both relevant to the project.
- **Full replacement is preserved.** A missing parent key means no links, and `{"value_dependencies":{}}` clears.
- **Legacy path.** A post without any mapping param still clears, as today (T-DEPJ-9). Legacy defaults are stored as submitted (characterized). When both JSON and nested params are posted, JSON wins.
- **`OperationError`** gains the additive kwargs (limits plus project, one signature, owner limits WP-12, 0.1.0): `OperationError.new(key, http_status: :unprocessable_entity, audit_status: 'validation_failed', summary: nil, interpolations: nil, payload: nil)`.
- **`BaseService#record_failure(status, message, summary = nil)`** passes `summary` to `AuditRecorder#record_failure!(summary:)`, which already accepts it (`audit_recorder.rb:31`).

### 3.4 View (`app/views/project_custom_field_configuration/edit_dependencies.html.erb`, rewritten)

```erb
<% content_for :header_tags do %>
  <%= stylesheet_link_tag 'dcf_config', plugin: 'redmine_depending_custom_fields' %>
<% end %>
<div class="contextual"><%= link_to dcf_icon('cancel', l(:button_back)), custom_field_configuration_field_path(@project, @field), class: 'icon icon-cancel' %></div>
<h2><%= @field.name %> <em class="info">(<%= l(:label_custom_field_dependencies) %>)</em></h2>
<% scope = dcf_field_scope(@field, @project) %>
<% unless scope == :project %>
  <%= dcf_flash_box(:warning, scope == :global ? l(:text_global_field_warning) : l(:text_shared_field_warning)) %>
<% end %>
<%= dcf_storage_usage_hint(@field) %>
<% if @parent.nil? %>
  <p class="nodata"><%= l(:text_dcf_parent_missing) %></p>
<% elsif !@parent_available %>
  <p class="warning"><%= l(:text_dcf_parent_not_available, name: @parent.name) %></p>
<% else %>
  <p class="info"><%= l(:field_parent_custom_field_id) %>: <strong><%= @parent.name %></strong></p>
  <%= form_tag(custom_field_configuration_update_dependencies_path(@project, @field),
               method: :patch, multipart: true, id: 'dcf-dependencies-form', class: 'dcf-dependencies-form') do %>
    <%= hidden_field_tag :state_hash, @state_hash, id: nil %>
    <%= render 'depending_custom_fields/dependency_editor',
               editor: RedmineDependingCustomFields::DependencyEditorConfig.for_project(
                 field: @field, parent: @parent, view: self,
                 posted: @posted_payload, conflict: @conflict_payload) %>
    <p class="buttons">
      <%= submit_tag l(:button_save), name: nil, disabled: true, data: { dcf_editor_submit: 1 } %>
      <%= link_to l(:button_cancel), custom_field_configuration_field_path(@project, @field) %>
    </p>
  <% end %>
<% end %>
```

- **Parent notices (gap 2).** `@parent` comes from `DependencyRules.parent_of(@field)`: nil (blank, dangling, wrong type or family, or self) renders `text_dcf_parent_missing`; a parent that is not relevant to the project renders `text_dcf_parent_not_available`. Both keys are owned by WP-27.
- **Escaping.** ERB escapes `l(...)` output, including the interpolated parent name. Rails JSON-encodes and escapes `data:` values.
- **`dcf_flash_box(type, text)`** (new helper): `content_tag(:div, (respond_to?(:notice_icon) ? notice_icon(type.to_s) : ''.html_safe) + text, class: "flash #{type}")`.
  - On 6.0+ the SVG fills the 30px padding that core reserves.
  - On 5.1 the classic background icon applies (UX-10).
  - It is also used by `show.html.erb` (scope banner) and `_confirm_panel.html.erb`.
- **`dcf_storage_usage_hint`** (limits helper, WP-11, UD-28) renders nothing below the shared 90 percent threshold.

### 3.5 Behaviour matrix of the dependency page

| Situation | Response | Editor state | Hidden input | Audit |
|---|---|---|---|---|
| GET | 200 | DB mapping, clean | blank | none |
| JS disabled | 200; noscript text `text_dcf_editor_noscript`; Save disabled | n/a | blank | none (nothing can be posted) |
| Valid JSON save | 302 + `notice_dependencies_saved` | n/a | n/a | `success`, delta v2 |
| Invalid mapping (unknown key) | 422 `error_invalid_dependency` | posted state from `posted: service.parsed_payload` in `data-dcf-editor-mapping`, `data-dcf-editor-dirty="1"` | blank (gap 1) | `validation_failed` with offender summary |
| Malformed, blank, unknown top-level key, long number | 422 `error_invalid_dependency_payload` (editor key, WP-25) | DB state, clean | blank | `validation_failed`, reason and bytes |
| Payload over 4 MiB (crafted; the editor pre-checks) | 422 `error_dcf_dependencies_too_large_to_send` (editor key, WP-25) with `size` and `limit` | DB state, clean | blank | `validation_failed`, `too_large` |
| Storage over the column limit or the ceiling | 422 `error_dcf_mapping_too_large` (field, size, limit) | posted state in `data-dcf-editor-mapping`, `data-dcf-editor-dirty="1"`, with a fresh `state_hash` (R9) | blank (gap 1) | `validation_failed`, machine message |
| Stale `state_hash` | 409 `error_stale_edit` | DB state, clean, plus the shared conflict panel from `data-dcf-editor-conflict-mapping` (UD-17) | blank | `validation_failed` (existing) |
| Unauthorized PATCH (any payload, including malformed or 1,000,000 digits) | 403 (`deny_access`) | n/a | n/a | `authorization_failed` from the service preamble when the request reaches the service; `DependencyPayload.parse` never called (SP-20b, gap 12) |
| Closed project | 403 | n/a | n/a | none (`require_active_project`, as today) |
| Parent missing or not relevant (`DependencyRules.parent_of`, gap 2) | 200 notice, no form; a direct PATCH gives 422 `error_invalid_dependency` or 404 (unchanged) | n/a | n/a | failure row for the PATCH |

## 4. Compact audit delta v2 (`update_dependencies`)

New class `app/services/redmine_depending_custom_fields/dependency_delta.rb` (prototype `proto2/dependency_delta.rb`).

**`before_value`** (was NULL): `{"v":2,"links":120,"defaults":3,"mapping_sha256":"<64 hex>"}`.

**`after_value`:**

```json
{"v":2,"source":"editor|import|form","links":150,"defaults":4,"mapping_sha256":"<64 hex>",
 "added":40,"removed":10,"orphans_removed":2,"defaults_changed":2,"parents_changed":23,
 "sample":{"added":[["Belgium","Ghent"]],"removed":[["France","Lyon"]],"defaults":[["Belgium",["Ghent"]]]},
 "truncated":true,"import":{"mode":"replace","rows":5000}}
```

- `import` is present only when `source` is `import`.
- Pairs compare as Set entries `[pk, ck]`.
- `orphans_removed` counts removed pairs whose parent key or child key is not in the current labels.
- `defaults_changed` counts parent keys whose sorted default list differs.
- `parents_changed` is the union of the parent keys touched.

**Bounds** (a deterministic guarantee, not a hope):
- at most 20 entries per sample list;
- at most 4,000 encoded bytes per sample list, measured with `ActiveSupport::JSON.encode`, the audit encoder;
- labels cut to 80 JSON-encoded bytes (`LABEL_MAX_BYTES = 80`, limits design 6.3): a label is shortened until its `ActiveSupport::JSON.encode` form fits 80 bytes, then `...` is appended inside the budget;
- 3 child labels per defaults entry;
- `truncated` is true when any list was cut.

Measured worst case 12,028 B (`proto2/delta_worst.out`). AuditPayload's 16,384 B cap is a backstop that this delta never reaches.

**Digest.** `mapping_sha256` = SHA-256 of `JSON.generate([vd.keys.sort.map { |k| [k, vd[k].sort] }, dd.keys.sort.map { |k| [k, Array(dd[k]).sort] }])`. The `before_value` chain lets an auditor detect mapping changes made outside the audited project path (admin form, API, D6).

**Summary** (English, as every existing summary, at most 1,000 characters): `Updated dependency mapping (import, replace, 5000 rows): +40/-10 links, 2 orphaned removed, 2 default(s) changed, 23 parent value(s)`. The source part is `(editor)`, `(form)` or `(import, <mode>, <rows> rows)`. A no-op save is still audited.

**Client-reported metadata (SP-12).**
- `source` and `import` come from the browser.
- They are informational only, never used for authorization or compliance.
- The server-computed counts, samples and `mapping_sha256` are authoritative.
- This goes into the Audit Spec §3 and the README.

**Old rows** keep their full-mapping JSON (`before_value` NULL). Both audit views show only `changes_summary` and `error_message`. The `audit` action (and `DcfConfigAuditController#index`) selects only the listed columns (`id project_id custom_field_id custom_field_name acting_user_id acting_user_name action status changes_summary error_message created_at`), and the count stays on the unselected scope.

## 5. Values page: search and pagination

**Query object** `app/services/redmine_depending_custom_fields/values_page.rb` (WP-28, UD-21): read-only, not a `BaseService`. Thresholds (gap 11, PC-59): the search box appears above 25 values (`FILTER_MIN`) or whenever `q` is present; pagination appears above 500 values (`UNPAGINATED_MAX`).

```ruby
class ValuesPage
  UNPAGINATED_MAX = 500   # at or below: one page, drag allowed when unfiltered
  MAX_PER_PAGE    = 500   # cap on per_page_option (Rack budget, section 8)
  FILTER_MIN      = 25    # search box shown above this many values, or when q is present
  Row = Struct.new(:key, :label, :active, :index, keyword_init: true)
  attr_reader :total, :filtered_count, :query, :tokens, :paginator, :rows
  def initialize(field, q: nil, page: nil, per_page: 25) ... end
  def filtered?;   !tokens.empty?; end            # QA-17: a q whose key is empty is unfiltered
  def paginated?;  total > UNPAGINATED_MAX; end
  def sortable?;   !filtered? && !paginated? && total > 1; end
  def batch_scope; filtered? || paginated? ? 'page' : nil; end
  def show_filter?; total > FILTER_MIN || query.present?; end
  def empty_match?; filtered? && filtered_count.zero?; end
  def default_options; ...; end                   # unchanged semantics (enumerations: active only)
  def self.page_for_index(index, total, per_page) ...; end
end
```

**Rows.**
- Built from the `[key, label, active]` tuples of `DependencyRules.value_options(field)` (gap 3), which costs one pluck for enumerations: `value_options(field).each_with_index.map { |(key, label, active), i| Row.new(key: key, label: label, active: active, index: i) }`. No hash access (`o['key']`) anywhere.
- Search: `tokens = ValueCollation.tokens(q)` (q stripped and cut to 255 characters). A row matches when `ValueCollation.match?(ValueCollation.key(label), tokens)`, a token AND substring match, the same rule as the editor.
- Keys are computed only when filtered: about 0.3 s at 25,000 values.

**Pagination.**
- `per = [[per_page, 1].max, MAX_PER_PAGE].min`.
- The page is clamped to `1..last_page`.
- Rows are `matching[offset, per]`.

**Controller `prepare_show`:**
- `@field.reload` (unchanged);
- `@values_page = ValuesPage.new(@field, q: params[:q], page: params[:page], per_page: per_page_option)`;
- `@rows = @values_page.rows`;
- `@usage = UsageCalculator.page_usage(@field, @rows.map(&:key), @project)` when `@show_usage` is set on a list-family field;
- `@default_options = @values_page.default_options`.
`@enumerations` and `@list_values` are removed.

**State preservation.**
- `_list_state_fields.html.erb` emits hidden `q` (only when filtered) and `page` (only when greater than 1), with `id: nil`.
- They go into: the rename forms, the delete `button_to` params, the enumeration form, the `delete_link` query, the sort buttons (`q` only) and the confirm panel.
- Small unfiltered lists keep their exact current markup.
- Redirects go to `custom_field_configuration_field_path(@project, @field, redirect_state(action))`:
  - `sort_values` drops `page`;
  - `add_value` clears `q` and jumps to the page of the new value (list: index in the reloaded values; enumeration: last).
- Re-renders read the posted `q` and `page`.

**Show usage.** `UsageCalculator.page_usage(field, keys, project, index: FieldIndex.load)` (server API name, compat section 2.4 row "FieldIndex API"):
- 2 grouped `CustomValue` queries per page, plus one load of the child records found by `FieldIndex` (no YAML parse of unrelated depending fields);
- counts are exact (no per-value cap);
- the per-value methods stay for the rename and remove impact paths;
- enumeration fields still offer no usage.

**View (`show.html.erb`).**
- Toolbar `_values_toolbar.html.erb` in core filter markup (UX-12):

```erb
<% if @values_page.show_filter? %>
<%= form_tag(custom_field_configuration_field_path(@project, @field), method: :get, class: 'dcf-values-filter') do %>
<fieldset><legend><%= l(:label_filter_plural) %></legend>
  <label for="dcf_values_q"><%= l(:label_search) %>:</label>
  <%= text_field_tag 'q', params[:q], size: 30, id: 'dcf_values_q', maxlength: 255 %>
  <%= hidden_field_tag 'show_usage', '1', id: nil if @show_usage %>
  <%= submit_tag l(:button_apply), class: 'small', name: nil %>
  <%= link_to dcf_icon('reload', l(:button_clear)),
              custom_field_configuration_field_path(@project, @field, (@show_usage ? { show_usage: 1 } : {})),
              class: 'icon icon-reload' %>
</fieldset>
<% end %>
<% end %>
```

- **Sort buttons:** `button_to` for `label_dcf_sort_az` and `label_dcf_sort_za` when `total > 1`, posting `direction`, `state_hash` and `q`, with `data-confirm` = `text_dcf_sort_confirm` (count = total).
- **Info lines:**
  - `text_dcf_values_filtered` when filtered;
  - `text_dcf_drag_reorder_large` (`max: 500`) when paginated;
  - `text_dcf_drag_reorder_filtered` when filtered.
- **Empty states:**
  - no values: `text_no_values` (unchanged);
  - filtered with no match: `<p class="nodata">text_dcf_no_matches <a>button_clear</a></p>` (`text_dcf_no_matches` shared with the editor: WP-28 owns it unless WP-25 already landed it, then WP-28 reuses it; gap 8).
- **Drag affordances:** handles, `_reorder_form` and the `dcf_value_reorder.js` include appear only when `sortable?`.
- **Rows** drop duplicate DOM ids. The text field gets `aria-label` = `label_dcf_value`.
- **Pagination:** `pagination_links_full @values_page.paginator, @values_page.filtered_count, per_page_links: true` when paginated. Core links merge `request.query_parameters`, so `q` and `show_usage` survive.
- **Page-mode dirty guard (UX-12).**
  - The page-mode enumeration form carries `data-dcf-page-scope="1"`, plus `data-dcf-warn-unsaved="<l(:text_warn_on_leaving_unsaved)>"` unless `User.current.pref.warn_on_leaving_unsaved == '0'`.
  - `dcf_values_page.js` (ES2017, no globals, included only in page mode) watches `input` and `change` inside that form.
  - While the form is dirty it registers `beforeunload` and asks `confirm(text)` on clicks on `.pagination a`, on submits of `form.dcf-values-filter` and on the sort buttons.
  - It clears the guard on form submit.
- **Default-value select:** unchanged; it lists all values.

## 6. Sort A-Z / Z-A

Implemented by WP-29 (0.3.0). Decisions: UD-23 (shared and global fields: JS confirm only, no server confirmation panel) and UD-24 (inactive enumerations sorted together with active ones). Errors reach the flash through `translate_error(e)` (gap 4).

**Route:**

```ruby
patch 'custom_field_configuration/fields/:field_id/values/sort',
      to: 'project_custom_field_configuration#sort_values',
      as: 'custom_field_configuration_sort_values'
```

**Permission and filters.**
- `init.rb` adds `sort_values` to `manage_project_custom_field_configuration`, next to `reorder_values`. It is granted automatically to role holders; CHANGELOG upgrade note.
- `sort_values` is added to the `find_field` and `require_active_project` lists.
- `value_params` permits `:direction` and `:batch_scope`.

**Service** `sort_values_service.rb` (`BaseService`, `audit_action` `'sort_values'`):
- **Direction:** anything other than `asc` or `desc` raises `OperationError(:error_reorder_mismatch)` (422, audited).
- **List family:** `ValueCollation.sort` over `possible_values`; when any index moved, assign and call `save_field!`.
- **Enumeration family:**
  - pluck `id`, `name`, `position`, inactive included, and assign positions 1..N in sorted order;
  - update only the changed rows, in chunks of 500, with `CustomFieldEnumeration.where(custom_field_id: field.id, id: ids).update_all(sanitize_sql_array(["position = CASE id WHEN ? THEN ? ... END", *pairs]))`.
- **Outcome:**
  - `before: {"count":N,"order_sha256":"<sha of ordered keys>"}`;
  - `after: {"direction":"asc","count":N,"moved":M,"order_sha256":"..."}`;
  - summary `Sorted N value(s) A-Z (M moved)`.
  - When M is 0 nothing is written, but the operation is still audited.
- **Order digest:** `order_sha256` = SHA-256 of `JSON.generate(ordered_keys)`, where the keys are list values or enumeration ids as strings in position order, inactive included.
- No `CustomValue` rewrite and no cascade.

**`ReorderValuesService`:**
- `index_by` replaces the O(N^2) `enums.find`;
- `field.save!` becomes `save_field!`;
- the audit gains `before.order_sha256` and `after.order_sha256` (additive);
- the `ordered_values[]` contract is unchanged.

## 7. Enumeration page-scoped batch (`UpdateEnumerationsService`)

Implemented by WP-30 (0.3.0, depends on WP-28). Errors reach the flash through `translate_error(e)` (gap 4). WP-31 later changes the same service (`clear_dangling_default!` through `save_field!`) and therefore depends on WP-30 (gap 14).

- **`batch_scope`:**
  - absent or blank: full mode, unchanged (T-ACT-21);
  - `'page'`: page mode;
  - anything else: `error_reorder_mismatch`.
- **Page mode:**
  1. The submitted ids must be a non-empty subset of the field's ids (an `index_by` lookup).
  2. `name` and `active` are normalized as in full mode; a missing `active` means unticked.
  3. `position` is ignored.
  4. `validate_names!` runs.
  5. The duplicate-active check runs on submitted rows plus unsubmitted DB rows.
  6. `apply!(rows, positions: false)` uses `enum.update!` (validations run, so a name over 60 characters rolls everything back).
  7. `clear_dangling_default!` (now via `save_field!`) and `deactivated_usage` work as in full mode.
  8. The audit `after` gains `"scope":"page","rows":n`, and the summary reads `Saved n of N enumeration value(s) (page): ...`.
- **`state_hash`** is checked as in full mode (409, T-ENP-9).
- **View in page mode:** hidden `batch_scope=page`, no `dcf-position` inputs, no handles, the `text_dcf_page_scope_save` note, and the dirty-guard attributes from section 5.

## 8. Rack parameter budget (limits: 4,096 params, urlencoded 4 MiB, multipart non-file 16 MB)

| Form | Params | Body |
|---|---|---|
| `update_dependencies` | 4: `_method`, `authenticity_token`, `state_hash`, `dependencies_json`; plus `utf8` on 5.1. Save has `name: nil`. | multipart; JSON at most 4 MiB (editor pre-check, server `too_large`) |
| `reorder_values` (drag) | at most 500 + 4 | rendered only for 500 values or fewer |
| `update_enumerations` full mode | at most 4 x 500 + 4 | only when unpaginated and unfiltered |
| `update_enumerations` page mode | at most 3 x 500 + 7 = 1,507 | `per_page` capped at 500 |
| sort, add, rename, remove, set default, confirm panel | at most 8 | tiny |
| search (GET) | at most 4 | query string |

## 9. Storage, ceiling, per-value cap, failure auditing

The storage validation, the `RecordInvalid` and `ValueTooLong` mapping and the audit cap ship with the limits area in 0.1.0 (WP-11, WP-12). The project ceiling, `save_field!`, the per-value cap and the editor's project storage limit ship in WP-31 (0.3.0, UD-22; depends on WP-11, WP-12, WP-27, WP-29 and WP-30). Errors reach the flash through `translate_error(e)` (gap 4).

**`BaseService` additions (project-owned parts, WP-31):**

```ruby
def save_field!(record)
  record.dcf_storage_ceiling = ProjectStoragePolicy.ceiling_bytes   # SP-03, project surface only
  record.save!
ensure
  record.dcf_storage_ceiling = nil
end
```

**Every custom field write in project services goes through `save_field!`:**
- `AddValueService` (list)
- `RenameValueService` (list)
- `RemoveValueService`
- `ReorderValuesService` (list)
- `SetDefaultValueService`
- `UpdateEnumerationsService#clear_dangling_default!`
- `DependencyMappingService`
- `SortValuesService`
- `BaseService#cascade_parent_key!` (`child.save!`)

A violation surfaces as the limits area's `RecordInvalid` storage mapping:
- `error_dcf_values_too_large` / `error_dcf_mapping_too_large` with escaped `field`, delimited `size` and `limit`;
- audited `validation_failed`;
- a cascade names the child field (`e.record`).

**Ceiling semantics:**
- The effective ceiling is `max(ceiling, persisted bytes)`. A write that does not grow an already-large column (admin made) passes, and growth beyond the ceiling is refused.
- MySQL TEXT stays bound by 65,535, the smaller limit.
- The admin form, API and import are unaffected (the ceiling attribute is nil there).

**Per-value cap.** `AddValueService` and `RenameValueService` (list family) reject a normalized value longer than `ProjectStoragePolicy::LIST_VALUE_MAX_CHARS` (255) with `OperationError(:error_dcf_value_length, interpolations: { max: 255 })`, audited `validation_failed`. Existing longer values are untouched. Enumeration names keep core's 60-character model limit.

**Before-save sanitation (BC-02).** `before_custom_field_save` must stay sanitize-only; D6 pruning happens only in the admin JSON transport. The project spec T-CASC-1 pins that a rename cascade `child.save!` keeps unrelated keys of the child byte-identical, including orphan and bracket-corrupted keys.

**`ValueTooLong` backstop** (limits): audited `save_failed`, `error_message` `error_dcf_value_too_long`, summary per limits design 5.3 (class, column, field id, byte counts), no SQL and no value.

## 10. Assets and CSS

| View | `content_for :header_tags` |
|---|---|
| `show.html.erb` | `dcf_config` css; `dcf_value_reorder` js when `sortable?`; `dcf_values_page` js when `batch_scope == 'page'` |
| `edit_dependencies.html.erb` | `dcf_config` css only. The editor JS and CSS come from the head hook, never from here (R2, R4, BC-13). |
| `_settings_tab.html.erb` | `dcf_config` css (core `_tabs` renders tab partials inline) |
| `audit.html.erb`, `app/views/dcf_config_audit/index.html.erb` | `dcf_config` css |

All of them use `plugin: 'redmine_depending_custom_fields'`. The head hook never includes `dcf_config.css`, `dcf_value_reorder.js` or `dcf_values_page.js`, so no asset is loaded twice.

**CSS move.** The rules at lines 114-133 of `depending_custom_fields.css` move unchanged into the new `dcf_config.css`: scope badges, confirm panel, status colours, inline forms, sort handle. `.dcf-dependencies-matrix td.center` is deleted. New rules:
- `.dcf-values-filter fieldset{margin-bottom:.5em}`
- `.dcf-values-toolbar{display:flex;flex-wrap:wrap;gap:.5em 1.5em;align-items:center;margin-bottom:.5em}`
- `.dcf-values-toolbar form{display:inline}`
- `.dcf-page-scope-note{color:#555}`

The global CSS keeps only the runtime and wizard rules (frontend area).

## 11. i18n registry for this area (de/en/fr/nl at parity; one owner per key)

**Single source of truth for texts:** `large_lists_i18n_registry.md` holds the en, de, fr and nl text of every key (with the UX-16 corrections and the de „…“ / fr « … » quotes). This section keeps only key names, owner WPs, interpolations and where each key is used. The revision 2 translation cells of this section are superseded by the registry.

**Reused core keys:** `label_filter_plural`, `label_search`, `button_apply`, `button_clear`, `button_save`, `button_cancel`, `text_warn_on_leaving_unsaved`.
**Reused plugin keys:** `label_dcf_value`, `label_dcf_default`, `text_no_values`, `text_global_field_warning`, `text_shared_field_warning`, `error_stale_edit`, `error_reorder_mismatch`, `error_invalid_dependency`, `notice_dependencies_saved`.
**Reused from the editor registry (gap 8):** `text_dcf_editor_help`, `text_dcf_editor_noscript` (owner WP-24), `error_invalid_dependency_payload`, `error_dcf_dependencies_too_large_to_send` (owner WP-25; WP-27 reuses them and does not redefine them), `text_dcf_editor_orphans`, `text_dcf_editor_no_parent_values`, `text_dcf_editor_no_child_values`, the conflict panel keys `text_dcf_editor_conflict`, `button_dcf_use_my_version`, `button_dcf_keep_current_version`, `button_dcf_export_my_version`, `text_dcf_editor_conflict_mine_loaded` (editor area; owner WP in the registry), and `text_dcf_no_matches` (owner WP-28 unless WP-25 already landed it, then WP-28 reuses it).
**Withdrawn from revision 1:** `error_value_too_large`, `text_dcf_size_detail`, `text_dcf_orphan_entries`, `text_dcf_editor_requires_javascript`.
**Withdrawn from revision 2 (gap 8; never added by WP-27):** `text_dcf_editor_pending_conflict`, `button_dcf_editor_pending_download`, `button_dcf_editor_pending_load` (replaced by the editor conflict panel keys), `error_dcf_dependency_payload_too_large` (replaced by `error_dcf_dependencies_too_large_to_send`), and this area's copy of `error_invalid_dependency_payload` (now owned by WP-25).
**Removed by WP-27:** `text_dependency_matrix_help` (its only user is the deleted matrix; `label_dcf_default` stays because `show.html.erb:157` uses it).

### Owned by this area

| key | owner WP | interpolations | used by | texts |
|---|---|---|---|---|
| notice_values_sorted | WP-29 | none | `sort_values` success flash | see large_lists_i18n_registry.md |
| label_dcf_sort_az | WP-29 | none | sort button | see large_lists_i18n_registry.md |
| label_dcf_sort_za | WP-29 | none | sort button | see large_lists_i18n_registry.md |
| text_dcf_sort_confirm | WP-29 | `%{count}` | sort button `data-confirm` (UD-23) | see large_lists_i18n_registry.md |
| text_dcf_values_filtered | WP-28 | `%{count}`, `%{total}` | values page info line when filtered | see large_lists_i18n_registry.md |
| text_dcf_drag_reorder_large | WP-28 | `%{max}` | values page info line when paginated | see large_lists_i18n_registry.md |
| text_dcf_drag_reorder_filtered | WP-28 | none | values page info line when filtered | see large_lists_i18n_registry.md |
| text_dcf_page_scope_save | WP-30 | none | page-mode enumeration form note | see large_lists_i18n_registry.md |
| error_dcf_value_length | WP-31 | `%{max}` | 255-character cap on add and rename | see large_lists_i18n_registry.md |
| text_dcf_parent_not_available | WP-27 | `%{name}` | dependency page notice (`parent_of` resolves, parent not relevant) | see large_lists_i18n_registry.md |
| text_dcf_parent_missing | WP-27 | none | dependency page notice (`parent_of` returns nil) | see large_lists_i18n_registry.md |
| label_dcf_project_storage_ceiling | WP-31 | none | plugin settings field label | see large_lists_i18n_registry.md |
| text_dcf_project_storage_ceiling_info | WP-31 | `%{default}` | plugin settings info text | see large_lists_i18n_registry.md |

### Requested from the limits registry (owner: limits, WP-12, 0.1.0)

Neutral limit wording, correct for both the column limit and the project ceiling ("at most %{limit} bytes can be stored for this field", compat section 2.4 row "Service storage error text"). No README reference on project-facing copy (UX-04).

| key | owner WP | interpolations | texts |
|---|---|---|---|
| error_dcf_values_too_large | WP-12 | `%{field}`, `%{size}`, `%{limit}` | see large_lists_i18n_registry.md |
| error_dcf_mapping_too_large | WP-12 | `%{field}`, `%{size}`, `%{limit}` | see large_lists_i18n_registry.md |
| error_dcf_value_too_long | WP-12 | none | see large_lists_i18n_registry.md |

The terms follow the existing files and the UX-03 glossary: de "Abhängigkeitszuordnung, übergeordnet, benutzerdefiniertes Feld"; fr "mappage des dépendances, parent, champ personnalisé"; nl "afhankelijkheidskoppeling, bovenliggend, aangepast veld". YAML values containing `%{` or `: ` are double-quoted, and inner ASCII quotes are escaped. Any value identical to its English text must be listed in the WP-02 parity allowlist; revision 2 found none for the keys of this area. This area adds no I18N constant map: every key is referenced with a literal `l(:key)` and is found by the used-keys scan. Keys sent to the editor JS go only through the editor's `DependencyEditorConfig::I18N`; the meta-tag map is `ClientConfig::I18N`, and the parity spec iterates both (gap 5).

## 12. File-by-file change list

The WP in brackets is the canonical work package of `large_lists_work_packages.md` that changes the file for that item.

### Configuration
- `config/routes.rb`: the `sort_values` route [WP-29].
- `init.rb`: `sort_values` in the permission list [WP-29]; settings default `project_storage_ceiling_kib` [WP-31].

### Controller
`app/controllers/project_custom_field_configuration_controller.rb`:
- `before_action` lists [WP-29];
- `sort_values` [WP-29];
- `update_dependencies` with service reuse and re-render [WP-27];
- `dependency_params`, `prepare_dependencies(posted: nil, conflict: nil)` with reload, `posted_payload(service)`, `conflict_payload` [WP-27];
- `dcf_status_code`, `translate_error(error_or_key)` with escaping, called as `translate_error(e)` [WP-12; call sites in WP-27 to WP-31];
- `prepare_show` with `ValuesPage` and `page_usage` [WP-28];
- `list_state`, `redirect_state`, `add_value_state` [WP-28];
- the `audit` column select [WP-28];
- `value_params` permits `:direction` [WP-29] and `:batch_scope` [WP-30].

### Services
- `base_service.rb`: `save_field!` (ceiling) and `cascade_parent_key!` via `save_field!` [WP-31]; `record_failure` with summary [WP-12]; `DELTA_CAP`/`capped` moved from `UpdateEnumerationsService` [WP-31, the WP that lists both files]. The storage and `ValueTooLong` rescue mapping is the limits area's [WP-12].
- `operation_error.rb`: `summary:`, `interpolations:` and `payload:` kwargs [WP-12].
- `dependency_mapping_service.rb`: `parsed_payload`, `read_input!` with `DependencyPayload.parse!`, `labels` from `value_options` tuples, `shape_defaults!`, Set validation, `DependencyDelta` [WP-27]; `save_field!` [WP-31].
- New: `dependency_delta.rb` [WP-27], `value_collation.rb` and `values_page.rb` [WP-28], `sort_values_service.rb` [WP-29], `project_storage_policy.rb` [WP-31].
- `update_enumerations_service.rb`: page mode, `apply!(rows, positions:)` [WP-30]; `clear_dangling_default!` via `save_field!` [WP-31, after WP-30].
- `reorder_values_service.rb`: `index_by`, `order_sha256` [WP-29]; `save_field!` [WP-31].
- `add_value_service.rb`, `rename_value_service.rb`: `save_field!` plus the 255-character cap [WP-31].
- `remove_value_service.rb`, `set_default_value_service.rb`: `save_field!` [WP-31].
- `usage_calculator.rb`: `page_usage(field, keys, project, index:)` [WP-28].

### Presenter and patches (owned elsewhere, changed for this area)
- `lib/redmine_depending_custom_fields/dependency_editor_config.rb`: project-mode storage limit = `ProjectStoragePolicy.format_store_limit(field)` [WP-31, gap 14; presenter created by WP-24].
- `lib/redmine_depending_custom_fields/storage_limits.rb` (`effective_limit`, `Violation#source`) and `lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb` (`dcf_storage_ceiling` accessor) [WP-31; files created by WP-11].

### Views and helper
In `app/views/project_custom_field_configuration/`:
- `show.html.erb` [WP-28, WP-29 buttons, WP-30 page mode] and `edit_dependencies.html.erb` [WP-27]: rewritten parts;
- `_values_toolbar.html.erb` and `_list_state_fields.html.erb`: new [WP-28; sort buttons WP-29];
- `_confirm_panel.html.erb`: list state [WP-28] and `dcf_flash_box` [WP-27];
- `_settings_tab.html.erb` and `audit.html.erb`: CSS include [WP-28].

Elsewhere:
- `app/views/dcf_config_audit/index.html.erb`: CSS include [WP-28].
- `app/views/settings/_dcf_project_config.html.erb`: ceiling field [WP-31].
- `app/helpers/project_custom_field_configuration_helper.rb`: `dcf_flash_box` [WP-27], `dcf_list_state` [WP-28].

### Assets, locales, docs, specs
- `assets/stylesheets/dcf_config.css` (new) and `assets/stylesheets/depending_custom_fields.css` (project rules removed) [WP-28]; `assets/javascripts/dcf_values_page.js` (new) [WP-30].
- `config/locales/{en,de,fr,nl}.yml`: the owned keys of section 11, each in its owner WP; `text_dependency_matrix_help` removed [WP-27]. Texts from `large_lists_i18n_registry.md`.
- `CHANGELOG.md` (each WP adds its lines; WP-32 finalizes 0.3.0), `README.md` [WP-31 performance notes; WP-32], `docs/specs/*` [A5 in WP-27, A6 in WP-29, finalized in WP-32] (section 15).
- Specs and JS tests (section 15).

## 13. Behaviour table (before and after)

| Surface | Before | After |
|---|---|---|
| edit_dependencies markup | NxM checkbox matrix with nested names (50x5,000 is about 58 MB) | shared editor partial, data attributes, one hidden JSON input |
| Transport | nested params | `dependencies_json` (multipart); nested still accepted (deprecated in 0.3.0, accepted throughout 0.3.x, removable no earlier than 0.4.0) |
| Parent values with `[` or `]` | corrupted or moved (Rack 2.2) | exact |
| More than about 4,090 links | PATCH becomes POST, 404, not audited | saved, up to 4 MiB of JSON |
| No JavaScript | matrix usable | noscript text, Save disabled; nothing can be posted |
| Invalid mapping | 422, ticks lost, audit key only | 422, posted state re-rendered through `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"` (hidden input blank, gap 1), offender summary audited |
| Corrected resubmit after a 422 | (no 422 storage case existed) | 302; the `state_hash` comes from the reloaded field (R9) |
| Stale save (409) | DB state, user changes lost | DB state plus the shared conflict panel (use my version, keep the current version, export my version as CSV; UD-17) |
| Malformed, huge-number or oversize payload | n/a | audited 422; size message for `too_large`; guard rejects bignums in under 10 ms |
| Stored orphans | silently dropped by the next save | counted by the editor on load (same copy as admin), dropped on save, `orphans_removed` in the audit |
| update_dependencies audit | `before` NULL, `after` = full mapping (overflows MySQL TEXT, 500) | v2 delta, at most about 12 KB, `mapping_sha256` |
| Global or shared banner on the dependency page | missing | shown (child scope), with an icon on 6.0+ |
| Parent missing or not relevant | "No values yet." or a matrix whose save fails | specific notice, no form |
| Values page, 500 values or fewer | all rows, drag | same, plus sort buttons and the search box (above 25 values, `FILTER_MIN`) |
| Values page, more than 500 values | all rows, drag over the Rack limit 404s | search box, paginated (above 500 values, UD-21), sort buttons, no drag, page-scoped enumeration save with a leave warning |
| Search with no match | n/a | `text_dcf_no_matches` plus a Clear link |
| Show usage | about 4 capped queries per row | 2 queries per page plus one child load; exact counts |
| Writes on PostgreSQL/SQLite via project pages | unbounded | refused above max(2,048 KiB setting, current size) with an audited 422 |
| New list values via project pages | any length | at most 255 characters |
| MySQL oversize | 500 or silent truncation | audited 422 (limits mapping, from 0.1.0), neutral message |
| Flash with a field name containing HTML | rendered as HTML (`html_safe`) | escaped (`translate_error`, from 0.1.0) |
| Assets | global CSS from the head hook | editor assets from the head hook only; project views include `dcf_config.css` and page-specific JS |

## 14. Edge cases

**Dependency page.**
1. **Dangling parent id:** `DependencyRules.parent_of` returns nil (also for a blank id, a parent of the wrong type or family, or a self-parent; gap 2), so `text_dcf_parent_missing`, no form. A PATCH gives `error_invalid_dependency` (unchanged).
2. **Parent not relevant:** notice, no form. A PATCH gives 404 (unchanged service check).
3. **Inactive enumerations** are listed, mappable and kept.
4. **Payload type and precedence.**
   - A non-String `dependencies_json` gives `:not_a_string`, which is 422 and audited.
   - When JSON and nested params are posted together, JSON wins.
   - A `base` key is ignored at project level.
   - Authorization precedes every payload check (SP-20b, gap 12): an unauthorized PATCH gives 403 before any parse, whatever the payload (malformed, 1,000,000 digits, over 4 MiB), and the service preamble writes the `authorization_failed` row (3.2).
5. **`source`/`import` mismatch.** `source: "editor"` together with `import` gives `:invalid_import` (422).
6. **409 detail.**
   - Raised in the preamble, so the service never parses; the controller parses once (`conflict_payload`).
   - A posted payload that fails to parse is not offered: no `data-dcf-editor-conflict-mapping`, so no conflict panel; the stored mapping is shown.
   - The flash stays `error_stale_edit`, and the shared conflict panel (`text_dcf_editor_conflict`, UD-17) explains the recovery.
7. **No `state_hash` posted** (scripts): no 409 check, as today.
8. **Bodies over 16 MB:** Rack refuses them before the controller and nothing is audited. The editor pre-check (4 MiB) prevents this. Proxies (nginx default 1 MB) can cut earlier; the README documents this.
9. **Saving with no changes when orphans exist:** the orphans are removed and audited.

**Values page.**
10. **Search input:** a `q` of whitespace or only combining marks is unfiltered, so drag stays available. `q` is cut at 255 characters. Regex metacharacters are inert.
11. **Page clamp:** 0, negative and beyond the last page are clamped. Removing the last value on the last page redirects to a clamped page.

**Sort.**
12. Already sorted: nothing is written; the operation is audited with `moved` 0.

**Enumeration page mode.**
13. **Ids:** ids from different pages are accepted when all belong to the field.
14. **Default:** deactivating the default clears it.

**Storage.**
15. **Admin-made large field:** a field already above the ceiling still accepts shrinking or same-size project edits; growth is refused.
16. **Cascade growth:** a cascade that grows a child beyond the ceiling rolls back the whole rename, and the message names the child.

**Project states.**
17. **Closed project:** every write returns 403, including the JSON path, page mode and `sort_values`.
18. **Archived project:** core denies (403).
19. **Missing audit table:** fails closed.

## 15. Specs and docs

### Characterization first (WP-04, 0.0.16, committed alone, green on the base matrix; revision 2 WP-P0)
- A legacy `update_dependencies` with no mapping params clears the mapping and writes one audit row (T-DEPJ-9).
- The current `update_dependencies` audit shape (flipped in WP-27).
- The current re-render after a validation failure (flipped in WP-27).
- Enumeration reorder with 3 or more rows before the `index_by` refactor.

### `spec/requests/dcf_project_custom_field_configuration_spec.rb`

**Amended:**
- T-UI-7 (x2): editor root `data-dcf-editor` with `data-dcf-editor-mode="project"`, `data-dcf-editor-multiple` 1/0, `name="dependencies_json"`, `enctype="multipart/form-data"`, no `default_value_dependencies[` in the body, no `data-dcf-parent-values` attribute.
- T-UI-4: editor root present; `dcf_config.css` included; the editor JS comes from the head hook, so it appears exactly once.
- The legacy save examples are kept and renamed "(legacy nested params, deprecated)".

**New:**
- T-DEPJ-1 JSON save, redirect, one success row with `source` editor and `mapping_sha256`.
- T-DEPJ-2 bracket values round-trip.
- T-DEPJ-3 `{}` clears.
- T-DEPJ-4 4,200 links in one request.
- T-DEPJ-5 malformed JSON gives 422 `error_invalid_dependency_payload`, DB state, blank hidden input, audited reason.
- T-DEPJ-6 unknown key gives 422, offenders in the summary; failed-save re-render (gap 1): `data-dcf-editor-mapping` holds the posted mapping, `data-dcf-editor-dirty="1"`, the hidden input is blank, and there is no `data-dcf-editor-echo` attribute.
- T-DEPJ-7 JSON wins over nested params.
- T-DEPJ-8 409 re-renders the DB state (no `data-dcf-editor-dirty`).
- T-DEPJ-9 legacy clear-all.
- T-DEPJ-10 GET: blank hidden input, `data-dcf-editor-mapping` holds the stored mapping, XSS value escaped.
- T-DEPJ-11 global/shared banner rendered through `dcf_flash_box` (an `svg` inside it when `notice_icon` exists, none on 5.1).
- T-DEPJ-12 parent not relevant gives the notice and no form; dangling parent gives `text_dcf_parent_missing`.
- T-DEPJ-13 an import payload records `source` import, mode and rows.
- T-DEPJ-14 (R9): a stubbed storage limit gives 422 with the posted mapping in `data-dcf-editor-mapping`, `data-dcf-editor-dirty="1"` and a blank hidden input (gap 1); the corrected resubmit with the re-rendered `state_hash` gives 302, not 409.
- T-DEPJ-15 (QA-02): the committed fixture `test/js/fixtures/editor/serialized_import_payload.json` from the real model posts successfully and the audit `after.source` is `import`.
- T-DEPJ-16 (QA-18, UD-17): 409 response has `data-dcf-editor-conflict-mapping` with the posted links (and `source`/`import` when posted), a blank hidden input and an unchanged DB; no `data-dcf-editor-pending` attribute.
- T-DEPJ-17 closed project gives 403 on the JSON path.
- T-DEPJ-18 (SP-17): `DependencyPayload.parse` is called exactly once on the 422 path and once on the 409 path (spy).
- T-DEPJ-19 no-JS: Save rendered `disabled` with `data-dcf-editor-submit`, plus noscript text.
- T-DEPJ-20 (SP-01): a 1,000,000-digit integer and a 20-digit negative give an audited 422 `number_too_long`; elapsed under 1 s as a regression bound.
- T-DEPJ-21 a crafted payload over 4 MiB gives `error_dcf_dependencies_too_large_to_send` (editor key, WP-25) with delimited `size` and `limit`, not the "could not be read" text.
- T-DEPJ-22 (SP-06): a field named `<img src=x onerror=alert(1)>` that triggers the size error renders the escaped name in the 422 flash.
- T-DEPJ-23 `source: "editor"` together with `import` gives 422 `invalid_import`.
- T-DEPJ-24 (SP-20b, gap 12): an unauthorized PATCH `update_dependencies` with a malformed payload and with a 1,000,000-digit payload each gives 403, one `authorization_failed` audit row, and `DependencyPayload.parse` (spy, `parse!` included) is not called. The request reaches the service preamble, the layer that writes the row: the example stubs the controller-level check (`allowed_to?` with a `{ controller: ..., action: ... }` Hash returns true) while `User#allowed_to?(:manage_project_custom_field_configuration, project)` returns false.
- T-DEPJ-25 (gap 2): `DependencyRules.parent_of` decides the notices: a blank, dangling, wrong-family or self parent id renders `text_dcf_parent_missing`; a parent not enabled for the project renders `text_dcf_parent_not_available`; neither renders the editor root.

**Values page:**
- T-PAG-1 500 values or fewer keep the drag markup, with no `q`/`page` hidden fields.
- T-PAG-2 520 values: 25 rows, pagination, no handles or reorder form, sort buttons, drag notice.
- T-PAG-3 page 2 rows; the page 999 clamp.
- T-PAG-4 `per_page` honoured and capped at 500.
- T-PAG-5 case- and accent-insensitive token search disables drag.
- T-PAG-6 rename on page 3 with `q` redirects back.
- T-PAG-7 the confirm panel carries `q` and `page`.
- T-PAG-8 paginated enumeration form: `batch_scope=page`, no positions, `data-dcf-page-scope`, `data-dcf-warn-unsaved`, `dcf_values_page.js` included.
- T-PAG-9 show-usage query count is the same for `per_page` 25 and 100 (invariance, R16).
- T-PAG-10 a `q` made only of a combining mark is unfiltered.
- T-PAG-11 filtered with no match shows `text_dcf_no_matches` and a Clear link.
- T-PAG-12 the filter uses core markup (`fieldset legend` = `label_filter_plural`).
- T-PAG-13 (gap 11): no search box at 25 values, a search box at 26 values and whenever `q` is present (`FILTER_MIN`); no pagination at 500 values, pagination at 501 (`UNPAGINATED_MAX`).

**Sort, enumeration page mode, storage, assets, params, performance:**
- T-SORT-1..6: list asc; enumeration desc; 409; closed project 403 and no permission 403; invalid direction 422; archived project 403.
- T-ENP-R1 page-mode save redirects keeping `page`; T-ENP-R2 closed project 403 in page mode.
- T-SIZE-R1 stubbed column limit on `add_value` gives 422 with field, size and limit.
- T-SIZE-R2 (SP-03) on PostgreSQL with a stubbed small ceiling: `add_value` over it gives 422 and an audit row; `remove_value` on a field already above the ceiling succeeds.
- T-LEN-1: `add_value` and `rename_value` with 256 characters give 422 `error_dcf_value_length`, audited.
- T-ASSET-1..4: `dcf_config.css` on show, edit_dependencies, the settings tab and audit; `dcf_value_reorder.js` only when sortable; `dcf_values_page.js` only in page mode.
- T-PARAM-1: the dependencies form has at most 5 named inputs; the page-mode form at `per_page` 500 has fewer than 4,096.
- T-PERF-1: edit_dependencies query count is the same for 10 and 1,000 parent values.

### `spec/services/dcf_value_services_spec.rb` (additions only)
- **Sort:** T-SORT-10..17 (stable, accent-insensitive, positions 1..N including inactive, no `CustomValue` rewrite, no-op audited, invalid direction, 409, chunked with `CHUNK` stubbed to 2, no permission). T-SORT-18: `before.order_sha256` and `after.order_sha256`.
- **Reorder:** T-ORD-A: the reorder audit carries `order_sha256`.
- **Enumeration page mode:** T-ENP-1..8 (subset applied, positions ignored, foreign id or empty subset rejected, duplicate against an unsubmitted row, unknown scope, audit scope and rows, dangling default cleared, full mode still strict). T-ENP-9: stale `state_hash` in page mode gives 409, nothing applied.
- **Storage:**
  - T-SIZE-1: add over the stubbed limit maps to `error_dcf_values_too_large` and a `validation_failed` row.
  - T-SIZE-2: rename cascade over the limit rolls back and names the child.
  - T-SIZE-3: no limit is a no-op.
  - T-SIZE-4: `ValueTooLong` gives a `save_failed` row whose `error_message` has no SQL and no value.
  - T-SIZE-5: an enumeration add never checks `possible_values`.
  - T-SIZE-6: the ceiling uses max(ceiling, persisted bytes).
  - T-SIZE-7: `save_field!` resets `dcf_storage_ceiling` to nil after the save.
- **Cascade:** T-CASC-1 (BC-02): a rename cascade keeps the child's unrelated, orphan and bracket keys byte-identical.
- **Audit:**
  - T-AUD-9: failure rows carry the `OperationError` summary.
  - T-AUD-10: aligned with limits; a value over 16,384 B is stored as the marker with `payload_sha256`.
  - T-AUD-11: `error_message` capped at 4,000 characters.

### `spec/services/dcf_dependency_mapping_service_spec.rb`
- T-DEP-1..6 kept (legacy hash path).
- T-DEP-7: JSON path.
- T-DEP-8: each parser error (`not_a_string`, `blank`, `too_large`, `number_too_long`, `invalid_json`, `not_an_object`, `unknown_key`, `unsupported_version`, `invalid_source`, `invalid_import`, `invalid_links`, `invalid_defaults`) gives 422 (`too_large`: `error_dcf_dependencies_too_large_to_send` with `size` and `limit`; every other code: `error_invalid_dependency_payload`), an audited summary `dependencies_json rejected: <code> (<bytes> bytes)`, and `parsed_payload` nil (the controller then renders the stored mapping); a valid payload leaves the ok `Result` in `parsed_payload`.
- T-DEP-9: delta v2 keys, the byte budget (worst case at most 12,100 B and never shrunk by AuditPayload), 20-entry and 4,000-byte list caps, 80-encoded-byte label cut (`LABEL_MAX_BYTES`), 3 labels per default, `mapping_sha256`.
- T-DEP-10: aggregated offenders.
- T-DEP-11: inactive enumerations accepted.
- T-DEP-12: storage mapping.
- T-DEP-13: `shape_defaults!` (single `[x]` becomes `"x"`, several values are an offender, multiple becomes an Array).

### New spec files
- `spec/services/dcf_values_page_spec.rb`: threshold, clamp, tokens, empty token set, `batch_scope`, `sortable?`, `default_options`, `page_for_index`.
- `spec/lib/dcf_value_collation_spec.rb`: shared fixture (UTF-8 read), stable ties, scrub.
- `spec/services/dcf_dependency_delta_spec.rb`.
- `spec/services/dcf_project_storage_policy_spec.rb`: setting parse, minimum, default, rescue (WP-31).
- WP-31 presenter example (gap 14, in the editor presenter spec): `DependencyEditorConfig.for_project(...)` renders `data-dcf-editor-storage-limit` equal to `ProjectStoragePolicy.format_store_limit(field)`.
- WP-31 plugin settings page request spec (gap 12): the `project_storage_ceiling_kib` field with `label_dcf_project_storage_ceiling` and `text_dcf_project_storage_ceiling_info` renders in en and in de; a non-numeric POST (for example `abc`) is stored as posted and `ProjectStoragePolicy.ceiling_bytes` falls back to 2,048 KiB (2,097,152 bytes).
- No `spec/lib/dcf_value_options_contract_spec.rb`: the revision 2 hash contract is dropped (gap 3); `labels()` and `ValuesPage` specs use `[key, label, active]` tuples from the real `DependencyRules.value_options`.
- `spec/services/dcf_usage_calculator_spec.rb`: T-USE-7, `page_usage` equals the per-value methods.

### JS
- `test/js/collation_parity.test.js`: the editor model `fold()` against the shared fixture.
- `test/js/values_page.test.js` (jsdom): dirty guard, pagination confirm, cleared on submit, no attribute means no guard.
- The editor's jsdom tests (editor area, `test/js/dcf_dependency_editor.test.js`, listed in WP-27) get project cases: the editor enables every `[data-dcf-editor-submit]` after init; the conflict panel from `data-dcf-editor-conflict-mapping` (use my version, keep the current version, export my version); a project root with `data-dcf-editor-dirty="1"` starts dirty; `always-submit` writes JSON on submit; `meta` is never written.
- System (opt-in, 5.1 and 7.0, WP-27 acceptance; gap 14): project-mode import end to end with the WP-26 import panel on the project page; the saved audit row records `source` import with mode and rows.

### Fixture normalization (R13)
The project scenario of the editor fixture spec replaces:
- project ids and identifiers in URLs with `{{PROJECT}}`;
- `state_hash` with `{{STATE_HASH}}`;
- custom field ids with `{{P}}`/`{{C}}`;
- enumeration ids with `{{E1}}..` by position order;
- and strips `authenticity_token`.
The WP evidence runs it under seeds 1 and 4242.

### Docs amendments (`docs/specs`; A5 written in WP-27, A6 in WP-29, both finalized in WP-32)
- **Review log:** Amendments A5 (editor, transport, delta, import/export, orphans, 409 recovery) and A6 (search, pagination, sort, page mode, storage ceiling, per-value cap, parameter budget).
- **Operations spec:**
  - §0: `save_field!`, ceiling;
  - §D: drag at most 500 values, unfiltered;
  - §J: sort;
  - §E: `batch_scope`;
  - §F and §G: payload schema v1, legacy fallback and removal target (deprecated in 0.3.0, removable no earlier than 0.4.0), aggregated validation, delta, 409 conflict panel (`data-dcf-editor-conflict-mapping`);
  - error table: `error_invalid_dependency_payload` and `error_dcf_dependencies_too_large_to_send` (editor keys, WP-25), `error_dcf_value_length`, the limits keys.
- **Audit spec:**
  - §3: v2 delta, client-reported `source`/`import`, AuditPayload marker;
  - §4: `sort_values`;
  - §5: examples;
  - §10: storage rows.
- **UI spec:**
  - §4: toolbar, core filter, empty states, page-mode warning;
  - §5: shared editor, banners, notices, Save gate (`data-dcf-editor-submit`), failed-save re-render (gap 1), conflict panel (UD-17);
  - §8: keys;
  - §9: JS requirement.
- **Integration spec:** §3 route; §5 filters; §11 asset ownership (head hook vs per view).
- **Security model:**
  - §15: strong params `dependencies_json` (String, at most 4 MiB, schema v1, long-number guard), `direction`, `batch_scope`, `q`/`page`/`per_page`;
  - §18: audit samples hold only labels of this field and its parent; flash interpolations are escaped.
- **Permissions spec:** `sort_values` (granted automatically).
- **Functional spec** §14 and §24: orphans are reported by the editor and removed on save.
- **Test plan:**
  - the new IDs;
  - system specs are opt-in;
  - T-CMP-4 smoke checks for the editor, sort and pagination.
- **HTML-only rule:** no amendment needed. The JSON is a field of an HTML form, and the CSV is a browser Blob.

## 16. CHANGELOG lines for project items (BC-14), version targets

**Version targets.** The project items ship in 0.3.0 (WP-27 to WP-31; the 0.3.0 CHANGELOG is finalized by WP-32). Two lines below belong to 0.1.0 because their WP ships there (WP-11 and WP-12: MySQL oversize mapping, escaped flash interpolations). The legacy nested project params are deprecated in 0.3.0, accepted throughout 0.3.x and removable no earlier than 0.4.0 (UD-01, compat section 2.3). The admin safe attributes are the editor area's decision (UD-15: kept permanently). Each line carries its release, WP and compat PC id; the PC wording in `large_lists_compatibility.md` section 4 is canonical where it differs.

**Added:**
- [0.3.0, WP-27, PC-45] Project settings: a scalable dependency editor replaces the checkbox matrix (search, sections per parent value, check or uncheck all shown, unlinked filters, per parent defaults, CSV import with preview, CSV export).
- [0.3.0, WP-28, PC-59] Search on the values page for fields with more than 25 values, and pagination for fields with more than 500 values (gap 11).
- [0.3.0, WP-29, PC-60] Sort A-Z / Sort Z-A buttons. Members with "Manage project custom field configuration" get the new sort action automatically.
- [0.3.0, WP-30, PC-61] Page-scoped save of key/value list values on paginated or filtered pages, with a warning before leaving unsaved changes.
- [0.3.0, WP-31, PC-62] New plugin setting: maximum stored size for changes made in project settings (default 2,048 KiB).
- [0.3.0, WP-27, PC-52] A stale save on the project dependency page shows the current version and your version, with use, keep and export actions (same conflict panel as the admin form, UD-17).

**Changed:**
- [0.3.0, WP-27, PC-47] The dependency page sends the mapping as one JSON field, so parent values containing [ or ] are stored exactly.
- [0.3.0, WP-27, PC-67] The project dependency page shows the global/shared field warning, and a notice instead of the editor when the parent field is not available in the project or no longer exists.
- [0.3.0, WP-27, PC-51] Links to values that no longer exist are reported by the editor and removed when the mapping is saved; the audit counts them.
- [0.3.0, WP-27 and WP-29, PC-57] Dependency audit rows store a compact summary (counts, samples, SHA-256 of the mapping); sort and reorder rows store the SHA-256 of the order. The source and import details are reported by the browser and are informational.
- [0.3.0, WP-28, PC-59] Drag-and-drop ordering is offered only for unfiltered lists with at most 500 values.
- [0.3.0, WP-28, PC-59] "Show usage" reports exact counts.
- [0.3.0, WP-28, PC-59] Redirects keep the search and the page.
- [0.3.0, WP-31, PC-62] Values added or renamed in project settings are limited to 255 characters, and project-settings changes cannot grow a field beyond the new storage setting.
- [0.3.0, WP-27, PC-55] The dependency editors need JavaScript; without it the project page disables Save (UD-16).

**Fixed:**
- [0.3.0, WP-27, PC-47] Saving large dependency mappings (more than about 4,000 links) in project settings no longer ends on "page not found".
- [0.1.0, WP-11 and WP-12, PC-14] On MySQL/MariaDB, a too large value list or mapping gives a clear, audited error instead of an internal error or silent truncation.
- [0.3.0, WP-27, PC-58] Correcting a failed dependency save and saving again no longer reports a conflict.
- [0.1.0, WP-12, PC-20] Error messages no longer interpret HTML in field names.

**Deprecated:**
- [0.3.0, WP-27, PC-63] Posting `value_dependencies` / `default_value_dependencies` as nested params to the project dependency page. Send `dependencies_json` (removed no earlier than 0.4.0).

**Removed:**
- [0.3.0, WP-27, PC-64] The matrix markup of the project dependency page.
- [0.3.0, WP-27, PC-64] The locale key `text_dependency_matrix_help`.

**Upgrade notes:**
- [0.3.0, WP-27, PC-55] Managers need JavaScript to change dependency mappings in project settings.
- [0.3.0, WP-31, PC-62] On PostgreSQL and SQLite, changes from project settings are limited by the new storage setting; the administration and the API are not.
- [0.3.0, WP-28 and WP-30, PC-65] Restart Redmine after upgrading (new assets `dcf_config.css`, `dcf_values_page.js`).

## 17. Work packages and order

The canonical work packages are those of `large_lists_work_packages.md` (WP-27 to WP-31 for this area, all 0.3.0). The revision 2 project-local ids WP-P0 to WP-P7 are kept only as a mapping; every reference to them elsewhere in this document means the canonical WP named here.

| Revision 2 id | Canonical WP (release) | Content | Depends on (canonical) |
|---|---|---|---|
| WP-P0 | WP-04 (0.0.16) | Characterization specs (`spec/characterization/project_dependencies_spec.rb`: legacy clear-all, audit shape, re-render, enumeration reorder with 3 or more rows); flips listed in WP-27 | WP-02, WP-03 |
| WP-P1 | WP-12 (0.1.0), WP-31 (0.3.0), WP-27 (0.3.0) | WP-12: `OperationError` kwargs, `record_failure` summary, `translate_error(error_or_key)` escaping, `dcf_status_code`. WP-31: `save_field!` with ceiling, `ProjectStoragePolicy` + setting, per-value cap, every `save!` replaced, editor project storage limit in `dependency_editor_config.rb`, settings page request spec. WP-27: `dcf_flash_box` | WP-12: WP-11. WP-31: WP-11, WP-12, WP-27, WP-29, WP-30 (gap 14: WP-30 because both change `update_enumerations_service.rb`) |
| WP-P2 | WP-27 (0.3.0) | `DependencyMappingService` JSON path (`parsed_payload` from `parse!`, `labels` from `value_options` tuples, `shape_defaults!`, Set validation), `DependencyDelta`, controller update path (reload, `posted:`, `conflict:`), request specs | WP-12, WP-21, WP-25, WP-26 (gap 14: WP-26 for the project-mode import end to end); transitively WP-05 (`parent_of`, `value_options`) and WP-18 (point 1 cache removal, head hook) |
| WP-P3 | WP-27 (0.3.0), WP-28 (0.3.0) | WP-27: edit_dependencies view, fixture scenario. WP-28: `dcf_config.css` split, per-view asset includes | WP-27: editor partial, presenter and JS (WP-24, WP-25: `data-dcf-editor-submit`, conflict panel, max payload) |
| WP-P4 | WP-28 (0.3.0) | `ValueCollation` + shared fixture, `ValuesPage` (rows from `value_options` tuples, `FILTER_MIN` 25, `UNPAGINATED_MAX` 500), `page_usage` with `FieldIndex`, show view, toolbar, empty state, state preservation | WP-05 (`FieldIndex`, `value_options`), WP-12, WP-23 |
| WP-P5 | WP-29 (0.3.0) | `SortValuesService`, route, `init.rb`, buttons, `order_sha256` in reorder | WP-28 |
| WP-P6 | WP-30 (0.3.0) | Enumeration page mode, `dcf_values_page.js` + jsdom test | WP-28 |
| WP-P7 | WP-27 to WP-31, WP-32 (0.3.0) | Locales (each owner WP adds its keys; texts from `large_lists_i18n_registry.md`), docs amendments (A5 in WP-27, A6 in WP-29), CHANGELOG lines per WP; WP-32 finalizes CHANGELOG 0.3.0, README and docs | WP-32: WP-21 to WP-31 |

## 18. Out of scope (tracked separately)
- Move to position N on paginated lists.
- Autocomplete for the default-value select on very large lists.
- Counting the issues that become legacy combinations after links are removed.
- Adding missing child values during an import at project level (admin form only, point 8).
- Wizard save hardening: a SECURITY defect (SP-07, SD-01), tracked separately with a CHANGELOG Security entry, scheduled no later than the point 1 release (0.2.0; owner decision UD-03, WP-07 or WP-20).
- The time-entry context menu.
