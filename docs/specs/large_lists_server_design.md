# Server core design, revision 2: point 1 (server), point 5 (server), point 6, canonical client contract

> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 (server side), 5 (server side), 6; plus the server side of 2 and 4 (radio blank sentinel, required '(none)', the `[data-dcf-parent]` discovery contract). Owner area: server. Work packages: WP-03 (cache hotfix part), WP-04 (server characterization), WP-05, WP-06, WP-08, WP-09, WP-10, WP-15, WP-16, WP-18 (server part: head hook, ClientConfig, cache removal), WP-19; interfaces consumed by WP-11 (`storage_preview`), WP-24 (`value_options`) and WP-27 (`parent_of`). Decisions: UD-01, UD-02, UD-03, UD-04, UD-05, UD-06, UD-07, UD-08, UD-10, UD-11, UD-12, UD-13, UD-14, UD-15, UD-16, UD-28, UD-34.

This is the complete revised design. It replaces revision 1.

**Consolidation.** The final completeness critic (gaps 2, 3, 4, 5, 6 and 15) and the binding contracts of `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts") and section 3 ("Contract rows added during consolidation") are applied inline below. Where the revision 2 text conflicted with them, they win. Release targets follow the work packages: 0.0.16 = WP-01..WP-07, 0.1.0 = WP-08..WP-14, 0.2.0 = WP-15..WP-20, 0.3.0 = WP-21..WP-32. Locale texts live only in `large_lists_i18n_registry.md`; this document names keys and owners.

**Scope (Ruby side only):**
- the shared depending-format module and the central rules module;
- the topology helper (FieldIndex);
- the canonical client contract. The server area owns it: frontend, limits and quality consume it and must not redefine it;
- the head hook;
- the context menu without cache;
- cycle validation;
- D1 leniency;
- the hooks the storage guard (owned by limits) and the admin JSON transport (owned by editor) need.

**Language level.** Every new file is Ruby 2.7 and Rails 6.1 compatible:
- no endless defs, no hash shorthand, no `Array#intersect?`, no anonymous or numbered block parameters;
- explicit `require 'set'`;
- `# frozen_string_literal: true`.

The README documents a Ruby >= 2.7 floor (BC-11, UD-34; documented in 0.0.16 by WP-07): `filter_map` and others are used on render paths.

## 0. Evidence

All probes ran against the baseline Redmine test stacks in rolled-back transactions. The plugin repo was not modified. Scripts and outputs are in `scratchpad/design/server_core/` (revision 1) and `scratchpad/design/server_core/rev/` (revision 2).

| Probe | Versions | What it shows |
|---|---|---|
| `probe_char.rb`, `probe_char2.rb` | 7.0 | Current behaviour of possible_values_options, query_filter_values, value_from_keyword and validation. The enum gives a double error and a duplicate option. Unchanged legacy combinations are rejected once custom_field_values are assigned. |
| `probe_render.rb` | 5.1, 7.0 | edit_tag/bulk_edit_tag overrides with data-* keep `label for=`. A named route resolves inside the context-menu view. GET `/depending_custom_fields/options` routes to API#show. |
| `prototype/*.rb` + `probe_proto*.rb` | 5.1, 6.0, 7.0 | Rules, shared module, enum options fix, cycle validation and selection graph. |
| `probe_graph.rb` | 5.1, 7.0 | After core's `editable_custom_fields`, `available_custom_fields` costs 0 queries and CF instances are shared across issues of a project. |
| `rev/probe_rev.rb` | 5.1, 7.0 | See below. |
| `rev/rules_rev.rb` + `rev/probe_d1.rb` | 5.1, 7.0 (identical) | See below. |

`rev/probe_rev.rb` shows:
- `read_attribute_before_type_cast('format_store')` is the raw YAML String, and reading it leaves the attribute undeserialized (`has_been_read?` nil).
- The anchored regex extracts `parent_custom_field_id`.
- A parent lookup through `customized.custom_field_values` costs 0 queries.
- An unchanged legacy combination is rejected today.
- `Issue#copy` sets `@copied_from`. The copy's child `value_was` is nil and the copy is rejected today ("is invalid").
- `IssueCustomField.customized_class` is `Issue`, and a Project is not an instance of it.

`rev/rules_rev.rb` + `rev/probe_d1.rb`, revised rules on a multi child holding legacy [b1, b2]:
- unchanged, reordered, one legacy value removed, or an allowed value added: valid;
- a new disallowed value: invalid;
- parent changed: strict;
- non-editable child unchanged while the parent changed: valid;
- `Issue#copy` unchanged: valid; copy with a new bad value: invalid; copy with the parent changed: strict;
- stored cycle X<->Y: both unconstrained, `effective_parent_id` nil;
- `parent_state` for 5 children sharing one parent: 0 queries.

Core facts used:
- **F1.** Store dirty helpers (`parent_custom_field_id_was`, `_changed?`) are unreliable for format_store. The cycle check compares normalized ids with `attribute_in_database('format_store')`.
- **F2.** The enum double error and duplicate option come from RecordList using `options.map(&:last)` on 3-tuples (core-7.0 `lib/redmine/field_format.rb:789-806`).
- **F3.** QueryCustomFieldColumn ignores `options[:sortable]` in 5.1..7.0, so QueryCustomFieldColumnPatch is a no-op.
- **F4.** `human_attribute_name(:parent_custom_field_id)` looks up `field_parent_custom_field` (core-7.0 `app/models/application_record.rb:23-32`; 5.1 `config/initializers/10-patches.rb:6-18`).
- **F5.** Core context menus destructure options as `|text, value|` (core-7.0 `app/views/context_menus/issues.html.erb:127`). A 2-tuple and a 3-tuple render the same there.
- **F6.** Core `List#bulk_edit_tag` has the same body in 5.1..7.0 (core-5.1 `field_format.rb:600-610`, core-7.0 `:612-622`) and omits `__none__` for required fields (`:615`).
- **F7.** Core ListFormat tolerates `value_was` per value (core-7.0 `field_format.rb:718-720`). RecordList appends missing `value_was` ids (`:789-796`).
- **F8.** `Issue#copy_from` assigns values to a new record and sets `@copied_from` (core-5.1 `app/models/issue.rb:304-323`, core-7.0 `:339`). There is no reader; `copy?` is public. Project#copy_issues uses copy_from (core-7.0 `app/models/project.rb:1185`) and logs and skips issues that fail validation (`:1227`).
- **F9.** `editable_custom_field_values(user)` exists on Issue, TimeEntry, Project and Version (5.1 and 7.0).
- **F10.** `visible_by?(project, user)` is overridden on Issue/Project/TimeEntry/Version custom fields. The base is `visible? || user.admin?` (core-5.1 `app/models/custom_field.rb:75-77`).

## 1. Revision summary

| Issue(s) | Change in this revision |
|---|---|
| R1, R2, QA-01, UX-02, BC-01, SP-04, SP-05 | One canonical contract owned here (section 2): context `form/bulk`; `data-dcf-parent-values` gated by parent visibility; parent attributes only on managed fields (effective parent: valid, acyclic, visible); unpruned map; meta `dcf-i18n` (flat object with the frontend's 10 runtime keys); one UMD runtime file, no separate rules script (compat section 2.4 "Rules asset"). |
| R6, FD-22 | Radio blank sentinel added. `__none__` with `data-dcf-required-none` for required managed children in bulk (UD-10). |
| R13 | One fixture mechanism (generated markup) with fixed per-kind id ranges, a normalizer and a sequence-bump self check, checked under two seeds (compat section 2.4 "Fixture ids"). The JSON contract fixture is deleted. |
| R14, QA-06, BC-06 | D1 is per value. |
| QA-07 | Issue copies are judged against the source issue. |
| QA-08 | A non-editable unchanged child is never rejected because the parent changed. |
| R16, SP-08 | Parents are resolved from loaded objects. FieldIndex reads raw YAML. Query invariance style throughout. Byte budget for the context menu. |
| R18 | FieldIndex is the single topology helper. `DependencyRules::Graph` is dropped. |
| R5, BC-02, UX-04 | Storage is owned by limits. The server keeps a sanitize-only `normalized_store_pairs` and `storage_preview(custom_field, store)`, called as `format.storage_preview(record, record.format_store)` (gap 4). CustomFieldPatch registers no callbacks. |
| R7 | `value_options` returns Ruby `[key, label, active]` tuples; one compact wire shape, produced only by `DependencyEditorConfig.wire_values` (gap 3). |
| R19, UX-15, UX-03, R11 | Server-owned keys registered with an owner WP; the texts live in `large_lists_i18n_registry.md`. |
| UX-10 | sprite_icon guard on the warning. |
| BC-04 | The two safe attributes are permanent (UD-15). |
| BC-07 | Code change rejected; a rollback note is documented. |
| BC-10 | API normalization documented and specified. |
| BC-12 | ClientData fails open. |
| SP-07 | Wizard save registered as a separately tracked security defect (SD-01, UD-03). |
| SP-10 | Fail-closed visibility. |
| SP-16 | No state on format singletons, enforced by a spec. |
| SP-18 | Hash-based keyword lookup. |
| QA-14, QA-19, QA-21, QA-22, QA-23 | New specs. |
| Consolidation, critic gap 2 | `DependencyRules.parent_of(cf)` added to the API (3.1): memoized raw parent lookup. Client emission keeps using `effective_parent_id`. |
| Consolidation, critic gap 3 | `value_options` returns tuples (3.2); `test/js/fixtures/value_options.json` is written from `DependencyEditorConfig.wire_values`. |
| Consolidation, critic gap 4 | `storage_preview(custom_field, store)` call form fixed (sections 5 and 10); flash errors go through `translate_error(e)` (section 20). |
| Consolidation, critic gap 5 | The i18n constants are `ClientConfig::I18N` and `DependencyEditorConfig::I18N`; the name `I18N_KEYS` is not used (2.4, 15). |
| Consolidation, critic gap 6 | The server emits `data-dcf-stored` with the D1 baseline, including the copy source baseline for issue copies (2.2, 6). |
| Consolidation, critic gap 15 | The head hook writes `tag.meta(name: META_NAME, content: payload.to_json)` (Ruby 2.7, no hash shorthand) (2.4). |

## 2. Canonical client contract

Owner: the server area. It is binding for frontend, limits and quality, and it is documented in the README section "Integration".

### 2.1 Definitions

- **depending field**: `field_format` is `depending_list` or `depending_enumeration`.
- **raw parent** of a depending field (gap 2): `DependencyRules.parent_of(cf)` is non-nil, that is, the stored parent id is present, is not the field's own id, and names an existing field of the same `type` whose format is in the child's family. `parent_of` does no cycle walk and no visibility check. It is the lookup `effective_parent_id` builds on and the one the project pages use to tell "parent missing" from "parent not available" (WP-27). Client emission never uses it directly: it uses `effective_parent_id` (WP-16).
- **effective parent** of a depending field: `DependencyRules.effective_parent_id(cf, lookup)` is non-nil. That means all of the following hold:
  - the parent id is present and is not the field's own id;
  - the parent exists and has the same `type`;
  - its format is in the child's family (list, depending_list / enumeration, depending_enumeration);
  - the ancestor chain, walked through FieldIndex with a visited set, contains no cycle. A chain that reaches a cycle anywhere counts as cyclic.
  - Server validation (section 8) and the client use the same definition. Fields without an effective parent are unconstrained on both sides.
- **managed field**: a depending field with an effective parent that is visible to the current user.
  - Form context: `parent.visible_by?(scope_project(customized), user)`.
  - Bulk context: true for every distinct `scope_project(object)` of the selected objects.
  - `scope_project(x)` is `x.respond_to?(:project) ? x.project : nil` (Project#project exists in 5.1 and 7.0). User, Group and other non-project types give nil, so the base rule `visible? || user.admin?` applies.
  - Any exception in the visibility check counts as not visible (fail closed).

### 2.2 Attributes

Attributes go on the element core passes `options` to. That is the `<select>` (drop-down style, and always in bulk) or the `span.check_box_group` (check_box style). The behaviour is the same in 5.1..7.0 (core-7.0 `field_format.rb:612-691`).

| Attribute | Value | Emitted when |
|---|---|---|
| `data-dcf-field` | child CF id (integer) | every depending field |
| `data-dcf-context` | `form` (from `edit_tag`) or `bulk` (from `bulk_edit_tag`: issue and time-entry bulk edit, and the context-menu wizard) | every depending field. The client treats a missing or unknown value as `form`. |
| `data-dcf-kind` | `list` or `enumeration` (`DependencyRules.kind(cf)`) | every depending field (WP-16). Informational for CSS and integrators; the runtime does not read it. |
| `data-dcf-multiple` | `1` | every depending field with `multiple?` true (WP-16). Informational; the runtime reads `select.multiple` or the input types. |
| `data-dcf-parent` | effective parent id (integer) | managed fields only. The point-4 discovery selector is `[data-dcf-parent]`. |
| `data-dcf-parent-name` | `<prefix>[custom_field_values][<parent id>]`, derived from the child's own `tag_name` | managed fields only, when `tag_name` matches `/\A(.+)\[custom_field_values\]\[\d+\](\[\])?\z/`. Without it the client derives the name from the child's own name; an unparseable name means the field is ignored. |
| `data-dcf-map` | JSON object `{"<parent key>": [<child key>, ...]}`. Keys are always strings. List child values are strings. Enumeration child ids matching `/\A[1-9]\d*\z/` are JSON integers; anything else stays a string. | managed only; `{}` when empty |
| `data-dcf-defaults` | JSON object; each value is one child key or an array, with the same encoding | managed only, and only when non-empty |
| `data-dcf-hide` | `1` | managed and `hide_when_disabled` true. The client ignores it in `bulk` (D3). |
| `data-dcf-parent-values` | JSON array of strings: the parent's current value(s) on the record; `[]` when blank or when the parent is not available on the record (for example not enabled for the tracker) | managed, `form` context, and the customized object carries `custom_field_values` |
| `data-dcf-parent-label` | `parent.name` (plain text) | same condition as `data-dcf-parent-values`. Used by the client only for hints when the parent control is absent from the scope. |
| `data-dcf-stored` | JSON object `{"child": [<child baseline keys>], "parent": [<parent baseline keys>]}`, all strings. It is the server D1 baseline (section 8): `child` is `DependencyRules.child_baseline(custom_value)` and `parent` is `ParentState#baseline`. For a persisted record both come from `value_was`; for an issue copy (new record with `copy?` true and a baseline source) both come from the copy source's stored values (gap 6, UD-06). `parent` is `[]` when blank or unavailable; `child` is `[]` when empty. | managed, `form` context, a parent state exists, and the record is persisted or `DependencyRules.baseline_source(customized)` is non-nil. Absent for every other new record. |

Option-level and sibling markup:

| Markup | Emitted when | Purpose |
|---|---|---|
| `<input type="hidden" name="<tag_name>" value="" data-dcf-blank="1">` (no id), immediately before `span.check_box_group` | managed, `form` context, single-value child, `edit_tag_style == 'check_box'` | Lets a required radio child post `''` when no radio is checked. Last-wins param parsing is verified on Rack 2.2.24, AP 7.2.4 and AP 8.1.4 (frontend finding 4). A checked radio comes later in the form and wins. |
| `<option value="__none__" data-dcf-required-none="1">(none)</option>`, placed right after "(no change)" | managed, `bulk` context, **required** child (core omits `__none__` for required, F6) | D2 for required descendants. **Client rule:** this option is enabled and selectable only while the parent selection yields no allowed values (bulk kind `none`, or the allowed set is empty). Otherwise it stays hidden and disabled and is never chosen as a fallback. **Server:** posting it for a required child while the parent offers options fails per issue with "cannot be blank" (core plus the CustomFieldPatch bypass), so nothing is cleared silently. |

Semantics:
- **Map encoding.** The map is `Sanitizer.sanitize_dependencies(cf.value_dependencies)`. It is **not pruned**: server validation uses the stored mapping, and client and server must agree for parent values that still exist on issues. Orphan entries are rare and are removed by the admin editor's D6 save. Defaults likewise come from `sanitize_default_dependencies`.
- **Parent not in scope.** When the parent input is absent from the client's scope (workflow read-only parent, parent not available for the tracker), the client computes `allowed = union(map[pv] for pv in parent-values)`.
  - Unmanaged fields (role-invisible parent, no or invalid or cyclic parent) carry no parent attributes and are left unfiltered. The server validates them with section 8.
  - No parent-derived data (map keys, defaults, parent values, parent name or label, stored parent baseline) is emitted for a parent the user cannot see (SP-05).
- **Stored baseline (gap 6, UD-06; compat section 2.4 "Legacy marker").** `data-dcf-stored` carries exactly the baseline server validation uses, so the client never shows as kept what the server rejects:
  - persisted record: `value_was` of the child and of the parent;
  - issue copy (single copy, bulk copy, the issue part of project copy): the copy source's stored child and parent values, read through `baseline_source` (`@copied_from`, F8). A copied legacy value is then kept, enabled, marked and posted by the client, and the server accepts it while it stays unchanged (section 8, rule 2). The frontend's revision 2 "persisted records only" wording is superseded;
  - every other new record: no `data-dcf-stored`, so the client drops a disallowed value at load (frontend row F6b, split into these two cases in WP-17).
  - Consequence for the runtime (frontend area, WP-17): the runtime uses the absence of `data-dcf-stored` as its new-record flag, so a copy carrying it gets no per-parent defaults at page load (UD-12); defaults still apply on parent changes.
- **Comparison.** The client compares every value as `String(x)`.

Guarantees, asserted by specs:
1. The server adds no element with an id. `custom_field_tag_with_label` (core-7.0 `app/helpers/custom_fields_helper.rb:122-130`) keeps `for=` on single selects. Multi selects and check groups have no `for`, as before.
2. Elements the client creates (hints) may carry JS-generated unique ids and `aria-describedby` on the control (UX-06). They are never part of the server-rendered tag, so the label-for scan is unaffected. `replaceIssueFormWith` copies only input/select/textarea values (core-7.0 `application-legacy.js:727-737`).
3. Rendering adds 0 queries per field when the parent is available on the object, and at most one query per distinct parent that is not available on the object (section 3.3). For a copy, `data-dcf-stored` reads the source issue's `custom_field_values`, which core already loaded in `copy_from` (F8). Exceptions in ClientData are caught: the field then renders without data-dcf-* (fail open, BC-12). Server validation is unaffected.

### 2.3 Wizard markup

```erb
<form class="cf-wizard-form" action="<%= depending_custom_fields_save_path %>" method="post"> ...hidden ids[], issue_ids, authenticity_token unchanged...
  <div class="cf-wizard-field" data-dcf-wizard-field="<%= cf.id %>"> <%= bulk tag (context bulk) %> </div>
```

The client scope is `closest('form')`. The regex-injected `data-field-id` is removed (0.2.0, WP-18).

### 2.4 Head hook output

The head hook has no DB access and no Rails.cache. It ships in 0.2.0 (WP-18). It renders, in this order, after core's jQuery:

```erb
<meta name="dcf-i18n" content='{"selectParent":"..","noOptions":"..", ... ,"liveMessage":"..","saveFailed":".."}'>
<script src=".../depending_custom_fields.js"></script>
<script src=".../context_menu_wizard.js"></script>
<link rel="stylesheet" href=".../depending_custom_fields.css">
[editor assets: dcf_dependency_editor_model.js, dcf_dependency_editor.js, dcf_dependency_editor.css]
```

Consolidated with compat section 2.4: there is no separate `depending_custom_fields_rules.js`. The rules live in the one UMD runtime `depending_custom_fields.js` ("Rules asset"). The meta tag is `<meta name="dcf-i18n">` with a flat object of the frontend's 10 runtime keys ("i18n meta tag"; the frontend owns the key list, the server emits it).

- The editor assets are added (0.3.0, WP-25) only when `context[:controller].class.name` is one of `CustomFieldsController` or `ProjectCustomFieldConfigurationController`. Class names are compared as strings, so no constant is loaded. The hook adds them through `ClientConfig.editor_asset_tags(view)`, in the order model JS, editor JS, CSS (editor design 5.1, AD-15).
- The editor assets are included **only** by this hook. Project views must not include them again through `content_for`. Page-specific files such as `dcf_config.css` and `dcf_value_reorder.js` stay under project-area `content_for` (P-D11).

```ruby
module RedmineDependingCustomFields
  module ClientConfig
    META_NAME = 'dcf-i18n'
    # The single i18n map of the meta tag (gap 5). JS keys and locale keys come from the frontend design.
    I18N = { 'selectParent' => :text_dcf_hint_select_parent,
             'noOptions' => :text_dcf_hint_no_options,
             'noOptionsGeneric' => :text_dcf_hint_no_options_generic,
             'legacy' => :text_dcf_hint_legacy,
             'legacyLocked' => :text_dcf_hint_legacy_locked,
             'legacyGeneric' => :text_dcf_hint_legacy_generic,
             'bulkDefault' => :text_dcf_hint_bulk_default,
             'bulkCleared' => :text_dcf_hint_bulk_cleared,
             'liveMessage' => :text_dcf_live_message,
             'saveFailed' => :error_save_failed }.freeze
    EDITOR_CONTROLLERS = %w[CustomFieldsController ProjectCustomFieldConfigurationController].freeze
    module_function
    def payload
      I18N.transform_values { |key| ::I18n.t(key) }
    end
    def editor_page?(controller)
      EDITOR_CONTROLLERS.include?(controller.class.name)
    end
    # added by WP-25 (0.3.0)
    def editor_asset_tags(view)
      plugin = 'redmine_depending_custom_fields'
      view.safe_join([view.javascript_include_tag('dcf_dependency_editor_model', plugin: plugin),
                      view.javascript_include_tag('dcf_dependency_editor', plugin: plugin),
                      view.stylesheet_link_tag('dcf_dependency_editor', plugin: plugin)])
    end
  end
end
```

The meta payload is a flat object, built per request in the current locale. The hook writes `tag.meta(name: META_NAME, content: payload.to_json)`, which escapes it correctly (probe_meta). The explicit `name: META_NAME` is required: Ruby 3.1 hash shorthand (`name:` without a value) fails the WP-01 Ruby 2.7 syntax gate (gap 15).

i18n constant names (gap 5): the meta map is `RedmineDependingCustomFields::ClientConfig::I18N` and the editor map is `DependencyEditorConfig::I18N` (editor area, WP-24). The name `I18N_KEYS` (for example `ViewLayoutsBaseHtmlHeadHook::I18N_KEYS`) is not used anywhere. The WP-02 locale parity spec iterates both constants when they are defined, and WP-18 adds an example proving `ClientConfig::I18N` is checked (WP-24 does the same for its map).

### 2.5 One fixture mechanism

- **Fixture spec.** `spec/frontend/markup_fixtures_spec.rb` (WP-16, 0.2.0; regenerated by WP-18 and WP-19) is the only contract fixture. It renders scenarios through the real helpers with the plugin overrides:
  - `custom_field_tag_with_label`;
  - `custom_field_tag_for_bulk_edit`;
  - the wizard partial;
  - the head hook.
  It writes the results to `test/js/fixtures/markup/<scenario>.html` (`DCF_WRITE_JS_FIXTURES=1` rewrites them) and compares in all four rspec workflows. The jsdom suites load the same files.
- **Deleted.** The revision-1 `spec/fixtures/dcf_client_contract.json` is deleted, and its comparison is removed from `client_data_spec.rb`. That spec keeps unit assertions only.
- **Normalization (consolidated, compat section 2.4 "Fixture ids").** The adopted mechanism is the quality area's: fixture records get explicit ids in fixed per-kind ranges (from 9,100,001; `dcf_fixture_record` from WP-02), so ids stay stable while sequences drift (quality E23). `spec/support/dcf_js_fixtures.rb` (WP-16) adds:
  - a normalizer that scrubs authenticity tokens, state hashes, asset digests and timestamps (`?\d+`, `-[0-9a-f]{64}`);
  - a guard that fails on any id-bearing number outside the fixed ranges (a leaked sequence id);
  - a sequence-bump self check (render, create throwaway records, render again, compare);
  - write or compare with `DCF_WRITE_JS_FIXTURES=1`.
  - Fixture labels contain no digits.
  - The quality step runs the spec under seeds 1 and 4242 and requires byte-identical output.
  - Superseded revision 2 proposal, kept for reference only: a replacement table mapping created records to `{{CF1}}`, `{{E1}}`, `{{P1}}`, `{{I1}}` placeholders, applied longest-first with token-boundary regexes `(?<![\w.-])<id>(?![\w])`. It is not implemented.
- **Required scenarios** ("every-field attributes" below means `data-dcf-field`, `data-dcf-context`, `data-dcf-kind` and, for multi fields, `data-dcf-multiple`):
  - list single;
  - list single required with radio and sentinel;
  - radio (not required);
  - multi select;
  - multi checkbox;
  - enumeration (integer ids, stored inactive id, default on an inactive id, inactive ids in the map without an option);
  - a stored inactive parent value (QA-21, gap 12);
  - chain of three;
  - workflow read-only parent (parent-values and parent-label present);
  - parent not enabled for the tracker (`[]`);
  - role-invisible parent for a non-admin member (only the every-field attributes);
  - stored cycle (only the every-field attributes);
  - self parent (only the every-field attributes);
  - dangling parent (only the every-field attributes);
  - legacy value on a persisted issue (`data-dcf-stored` from `value_was`);
  - issue copy holding a legacy combination (`data-dcf-stored` from the copy source, gap 6);
  - new issue (no `data-dcf-stored`);
  - issue + time_entry prefixes;
  - project custom field form;
  - user-custom-field form with a role-restricted parent (QA-23);
  - bulk single;
  - bulk multi;
  - bulk required (required-none option);
  - bulk chain;
  - time-entry bulk edit;
  - wizard template;
  - tricky values (`[ ] < & "` in keys and values);
  - head hook in en and de.
- **Rules cases.** `test/js/fixtures/shared/rules_cases.json` (allowed and default cases; D1 rows added in WP-09) is read by both `spec/lib/dependency_rules_spec.rb` and the JS rules tests. The path follows compat section 2.4 ("Shared rules case table path"). Nothing new goes under `spec/fixtures` (rails_helper loads `spec/fixtures/*.yml` as DB fixtures).

## 3. DependencyRules: the central rules module

File: `lib/redmine_depending_custom_fields/dependency_rules.rb` (WP-05, 0.0.16; D1 in WP-09 and the effective parent and cycle rules in WP-10, both 0.1.0).
- It requires `set`, `sanitizer` and `field_index`.
- Format names are literals, because it loads through the formats before the `FIELD_FORMAT_*` constants exist.
- All functions are `module_function`.
- Memoization lives only on CustomField records, through `CustomFieldPatch#dcf_memo(name, key) { ... }`, which stores a Hash in `@dcf_memo` on the record. It never lives on format singletons (core-7.0 `field_format.rb:24-25,64`, SP-16).

```ruby
DEPENDING_FORMATS = %w[depending_list depending_enumeration].freeze
LIST_FAMILY = %w[list depending_list].freeze
ENUM_FAMILY = %w[enumeration depending_enumeration].freeze
ALL_PARENT_FORMATS = (LIST_FAMILY + ENUM_FAMILY).freeze
PARENT_FORMATS = { 'depending_list' => LIST_FAMILY, 'depending_enumeration' => ENUM_FAMILY }.freeze
CANONICAL_ID = /\A[1-9]\d*\z/.freeze

# values/baseline: Arrays of Strings. baseline = value_was, or the copy source's stored value (section 8, rule 2).
ParentState = Struct.new(:parent, :available, :values, :baseline) do
  def changed?
    available && values.sort != baseline.sort
  end
end
Problem = Struct.new(:type, :parent_key, :child_key, keyword_init: true)
```

### 3.1 API

| Method | Contract |
|---|---|
| `depending?(cf)`, `kind(cf)`, `parent_formats_for(cf)` | as before |
| `normalize_id(raw)` | Mirrors `.to_i`: a positive Integer or nil |
| `normalize_values(raw)` | `Array(raw).map(&:to_s).reject(&:blank?)` |
| `parent_id(cf)` | `normalize_id(cf.parent_custom_field_id)` for depending fields, else nil. Reads the in-memory value (authoritative for the record itself). |
| `resolve_parent_for_save(cf)` | Exactly today's before_save lookup: `CustomField.find_by(id: raw.to_i, type: cf.type, field_format: parent_formats_for(cf))`, nil when blank. Memoized on the record with `dcf_memo(:resolve, raw.to_s)`, so validation, preview and before_save do one query. |
| `find_parent(id)` | `CustomField.find_by(id: id)`: the single stub point for specs |
| `parent_of(cf)` | **Raw parent lookup (gap 2).** Returns the parent CustomField record, or nil when the stored parent id is blank, dangling (no such field), names a field of another STI `type`, names a field outside the child's family (`parent_formats_for(cf)`), or names the field itself. Nil for non-depending fields. Memoized on the record with `dcf_memo(:parent_of, pid)`; nil results are memoized too, so a second call does not query. Goes through `find_parent`. No cycle walk and no visibility check. Consumers: `effective_parent_id` builds on the same rule; the project controller `prepare_dependencies` and `DependencyMappingService#perform!` (WP-27) use it to choose between `text_dcf_parent_missing` (nil) and `text_dcf_parent_not_available` (record present but not available in the project). Client emission (WP-16) uses `effective_parent_id`, never `parent_of` directly. Specified and spec-covered in WP-05. |
| `carries?(cf, customized)` | `klass = cf.class.customized_class; klass && customized.is_a?(klass)`, rescue gives false. False for a Project passed for an Issue field (context menus, query filters). |
| `lookup_records(source)` | Hash `id => CustomField` built from what is loaded: `source.custom_field_values` (single record) or the union of `available_custom_fields` of an Array of objects. 0 queries (probe_rev, probe_graph). |
| `effective_parent_id(cf, lookup = {})` | Definition in 2.1. `dcf_memo(:effective_parent, [cf.id, pid])`. Hops go through a lazy `FieldIndex.new(records: lookup)`: rows come from loaded records first (raw YAML, no deserialization), and missing ids are fetched in one batched raw query. Cycle-safe (visited set, cap 1,000). |
| `parent_state(cf, customized)` | nil unless `customized.respond_to?(:custom_field_values)`, `carries?`, and an effective parent exists. Otherwise `ParentState(parent_cf_or_nil, available, values, baseline)`, read from the parent's CustomFieldValue on `customized` (0 queries). `available == false` with `[]` when the parent is not available on the object. |
| `baseline_source(customized)` | For a new record with `copy?` true: `customized.instance_variable_get(:@copied_from)` (core has no reader, F8; covered by a spec on all 4 versions). Otherwise nil. |
| `child_baseline(custom_value)` | `normalize_values(source.custom_field_value(cf))` when there is a baseline source, else `normalize_values(custom_value.value_was)` |
| `allowed_set(map, parent_values)` / `allowed_values` / `default_values(map, defaults, parent_values, multiple:)` | Pure. Set-based union; first-seen order for `allowed_values`; defaults filtered by allowed; single gives the first. Shared cases in `rules_cases.json`. |
| `allowed_for(cf, state)` | `allowed_set(cf.value_dependencies \|\| {}, state.values)` |
| `dependency_check(custom_value, state, user = User.current)` | Returns `[allowed_empty, errors]`; section 8 |
| `editable_by?(cf, customized, user)` | `customized.editable_custom_field_values(user).any? { \|v\| v.custom_field_id == cf.id }` when the method exists (F9). True when it does not exist. Rescue gives true (editable means strict, so an error never relaxes validation). Only evaluated on the failure path. |
| `no_options?(cf, customized)` | A parent state exists and `allowed_for` is empty. Used by the required bypass. |
| `hide_when_disabled?(cf)`, `mapping(cf)`, `defaults(cf)` | as before |
| `value_keys(cf, include_inactive: true)` | List family: `possible_values` strings, deduplicated keeping the first occurrence. Enum family: ids as strings, by `[position, id]`, inactive included unless `include_inactive: false`. Uses in-memory values, so the textarea of the same request counts. |
| `value_options(cf)` | **The single value-option source (R7)**: ordered Ruby tuples `[key, label, active]`, see 3.2. The wire shape is produced from it only by `DependencyEditorConfig.wire_values` (gap 3). |
| `mapping_problems(vd, dd, parent_keys:, child_keys:)` | Set-based Problem list (`:unknown_parent_key`, `:unknown_child_value`, `:unknown_default`, `:default_not_linked`). Used by the project service (strict). |
| `prune_mapping(vd, dd, parent_keys:, child_keys:, multiple:)` | Used **only** by the admin JSON transport (editor, D6). Never by before_save, storage_preview, the API or the services (BC-02). |
| `parent_changed?(cf)`, `parent_errors(cf)`, `in_cycle?(cf)`, `cycle_member_ids(cf)`, `parent_candidates(cf)`, `descendant_ids(cf)` | section 7; they use `FieldIndex.load` |
| `children_of(field, index: nil)` | `ids = (index \|\| FieldIndex.load).children_ids(field.id)`, then `CustomField.where(id: ids).sorted.to_a` (loads only the children). `FieldRelevance.children_of` delegates here. The project area passes one index per page. |

`parent_of` sketch (Ruby 2.7; `dcf_memo` checks `key?`, so a nil result is memoized as well):

```ruby
def parent_of(cf)
  pid = parent_id(cf)                       # nil for non-depending fields and blank ids
  return nil if pid.nil? || pid == cf.id
  cf.dcf_memo(:parent_of, pid) do
    record = find_parent(pid)
    record if record && record.type == cf.type && parent_formats_for(cf).include?(record.field_format)
  end
end
```

Spec (WP-05, `spec/lib/dependency_rules_spec.rb`): nil for blank, dangling, wrong STI type, wrong family and self; the record otherwise; a second call does not query.

### 3.2 Value options

Consolidated (gap 3, compat section 3 "value_options"; AD-21). `value_options(cf)` returns an Array of Ruby tuples `[key, label, active]`:
- `key` (String) is always present: the list value, or the enumeration id as a String;
- `label` (String): equals `key` for list fields; the enumeration name for enumerations;
- `active` (true or false): always true for list fields; false for inactive enumerations.

Order: list `possible_values` order, or enumeration `[position, id]` with inactive included.

Example: `[["Belgium", "Belgium", true], ["11", "Red", true], ["12", "Old", false]]`.

Ruby consumers destructure the tuples as `|key, label, active|`:
- the project presenter and `labels()`, and the `ValuesPage` rows (WP-27, WP-28);
- the project delta labels;
- `DependencyEditorConfig` (admin and project), through `wire_values`.
There is no Hash contract (no `o['key']` / `o['label']` reads) and no `spec/lib/dcf_value_options_contract_spec.rb`.

**Wire shape.** Only `DependencyEditorConfig.wire_values(options)` (editor area, WP-24) turns the tuples into the compact wire shape: an Array of Hashes with String keys, where
- `'key'` (String) is always present;
- `'label'` is present only when it differs from the key (enumerations);
- `'active' => false` is present only for inactive enumerations.

Wire example: `[{"key":"Belgium"},{"key":"11","label":"Red"},{"key":"12","label":"Old","active":false}]`.

The wire shape is the one shape for:
- the admin values endpoint;
- the `data-dcf-editor-*` attributes rendered by `DependencyEditorConfig` (admin and project);
- the editor JS, which reads `Object.prototype.hasOwnProperty.call(o, 'label') ? String(o.label) : String(o.key)` and `o.active !== false` (editor design 4.1).

**Fixture.** `test/js/fixtures/value_options.json`, which the node tests read, is written from `DependencyEditorConfig.wire_values(DependencyRules.value_options(cf))`, not straight from `value_options`. WP-24 asserts endpoint output == presenter attribute == fixture.

### 3.3 Parent resolution cost (R16)

The issue form, edit and validation paths resolve parent CF instances and values from `customized.custom_field_values`, which core memoizes (0 queries, probe_rev and probe_d1). Hops in the cycle walk read the stored parent id of loaded records from raw YAML. Queries happen only for ids that are not loaded, in one batched raw select per chain level.

The bound is therefore O(distinct parents not available on the object). For the G6 fixtures, where parents are available, the counts are invariant. Role-restricted parents cost one `roles` load per parent instance in `visible_by?`. Instances are shared across issues of a project.

## 4. FieldIndex: the single topology helper (R18)

File: `lib/redmine_depending_custom_fields/field_index.rb` (WP-05, 0.0.16). The server area owns it. It adopts the limits area's raw-regex extraction (limits 6.2, V14: 0.041 ms vs a 16.6 ms YAML parse per S1 row). It replaces the revision-1 `DependencyRules::Graph`, the limits area's separate FieldIndex proposal, and the per-hop `find_by` walk.

```ruby
class FieldIndex
  PARENT_RE = /^parent_custom_field_id: *(?:'(\d*)'|"(\d*)"|(\d*)) *$/.freeze
  Row = Struct.new(:id, :type, :field_format, :parent_id)
  def self.load(scope = CustomField.where(field_format: DependencyRules::DEPENDING_FORMATS)) # 1 raw select_all, no deserialization
  def initialize(records: {}, rows: {})   # lazy: rows from loaded read-only records materialize on first access
  def ensure(ids)                         # one raw select for ids not yet known (id, type, field_format, format_store)
  def row(id); def parent_id(id); def exists?(id)
  def ancestor_ids(id)                    # visited Set, cap 1,000, stops at non-depending or unknown rows
  def descendant_ids(id); def children_ids(id)  # meaningful on an index built by .load (all depending fields)
  def effective_parent_id_for(child_id, child_type, child_format, pid)  # 2.1 definition
  def cycle_from(id)                      # member ids when id is on or reaches a cycle, else []
  def self.parent_id_from_raw(raw)        # regex; deserialization fallback only when the regex misses but the key is present
end
```

Rules:
- `records:` must contain persisted records loaded from the DB and not modified in memory. This holds for issue forms, the context menu and validation of custom values.
- Admin saves use `FieldIndex.load` for fresh topology and the accessor for the record being saved.
- Raw reads use `connection.select_all(scope.select(:id, :type, :field_format, :format_store).to_sql)` (no type casting).

Consumers:
- `DependencyRules.effective_parent_id`;
- `parent_errors`, `in_cycle?`, `cycle_member_ids`, `parent_candidates`, `descendant_ids`, `children_of`;
- `FieldRelevance.children_of`;
- `UsageCalculator.page_usage` (project area, one index per page);
- SelectionGraph.

No other topology code may be added.

## 5. Shared format module and class bodies

File: `lib/redmine_depending_custom_fields/depending_format_methods.rb` (WP-06, 0.0.16; behaviour changes land in WP-08, WP-09 and WP-10 in 0.1.0, and the edit_tag/bulk_edit_tag overrides in WP-16 and WP-19 in 0.2.0). It is included (not prepended), so `super` reaches ListFormat/EnumerationFormat. It declares `field_attributes` in `included`. It assigns no instance variables (spec in section 19).

```ruby
module DependingFormatMethods
  def self.included(base)
    base.field_attributes :parent_custom_field_id, :value_dependencies, :default_value_dependencies, :hide_when_disabled
  end

  # ONE normalizer shared by before_save and the storage preview (limits L2). Sanitize only, never D6 pruning (BC-02).
  def normalized_store_pairs(custom_field)
    pairs = []
    if custom_field.parent_custom_field_id.present?
      parent = DependencyRules.resolve_parent_for_save(custom_field)
      pairs << ['parent_custom_field_id', parent && parent.id]
    end
    pairs << ['value_dependencies', Sanitizer.sanitize_dependencies(custom_field.value_dependencies)]
    pairs << ['default_value_dependencies', Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)]
    pairs
  end

  # Called by StorageLimits.preview_value (limits) as format.storage_preview(record, record.format_store) (gap 4).
  # Same key order as before_save, so the YAML is byte-identical (limits V4).
  def storage_preview(custom_field, store)
    preview = store.respond_to?(:to_hash) ? store.to_hash : {}
    normalized_store_pairs(custom_field).each { |key, value| preview[key] = value }
    preview
  end

  def before_custom_field_save(custom_field)
    super
    parent_given = custom_field.parent_custom_field_id.present?
    normalized_store_pairs(custom_field).each { |key, value| custom_field.public_send("#{key}=", value) }
    custom_field.default_value = nil if parent_given && custom_field.parent_custom_field_id.present?
  end

  # Public contract kept for single objects; nil and Array give the full core list.
  def possible_values_options(custom_field, object = nil)
    single = object.is_a?(Array) ? object.first : object
    base = super(custom_field, single)
    return base if object.nil? || object.is_a?(Array)

    state = DependencyRules.parent_state(custom_field, object)   # nil for non-carrying objects (Project for Issue fields)
    return base unless state

    allowed = DependencyRules.allowed_for(custom_field, state)
    base.map do |opt|
      label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
      value.blank? || allowed.include?(value.to_s) ? [label, value] : [label, value, { hidden: true, style: 'display:none;' }]
    end
  end

  def validate_custom_value(custom_value)
    cf = custom_value.custom_field
    sanitized = DependencyRules.normalize_values(custom_value.value)
    custom_value.value = cf.multiple? ? sanitized : sanitized.first   # kept mutation
    state = DependencyRules.parent_state(cf, custom_value.customized)
    return super unless state

    allowed_empty, dep_errors = DependencyRules.dependency_check(custom_value, state)
    return dep_errors if allowed_empty            # today's early return, without the core inclusion check
    errors = super
    errors + (dep_errors - errors)
  end

  def validate_custom_field(custom_field)
    super + DependencyRules.parent_errors(custom_field)
  end

  # Matches the FULL list (import and mail call this before the parent is set). One Hash per call (SP-18).
  def value_from_keyword(custom_field, keyword, _customized = nil, **_options)
    return if keyword.blank?
    index = {}
    possible_values_options(custom_field).each do |opt|
      label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
      index[label.to_s.strip.downcase(:fold)] ||= value      # first match wins, same as today's find
    end
    keywords = custom_field.multiple? ? keyword.split(/[;,]/).map(&:strip).reject(&:blank?) : [keyword.strip]
    matched = keywords.filter_map { |kw| index[kw.downcase(:fold)] }
    custom_field.multiple? ? matched.presence : matched.first
  end

  def edit_tag(view, tag_id, tag_name, custom_value, options = {})
    cf = custom_value.custom_field
    data = ClientData.attributes_for(cf, context: :form, customized: custom_value.customized,
                                         custom_value: custom_value, tag_name: tag_name)   # never raises
    html = super(view, tag_id, tag_name, custom_value, ClientData.merge_options(options, data))
    return html unless ClientData.sentinel?(cf, data)
    view.hidden_field_tag(tag_name, '', id: nil, data: { dcf_blank: 1 }) + html
  end

  def bulk_edit_tag(view, tag_id, tag_name, custom_field, objects, value, options = {})
    data = ClientData.attributes_for(custom_field, context: :bulk, objects: objects, tag_name: tag_name)
    merged = ClientData.merge_options(options, data)
    return super(view, tag_id, tag_name, custom_field, objects, value, merged) unless custom_field.is_required? && data.key?(:dcf_parent)

    # Required managed child: core omits __none__ (F6). Same body as core plus the marked option.
    opts = []
    opts << [l(:label_no_change_option), ''] unless custom_field.multiple?
    opts << [l(:label_none), '__none__', { 'data-dcf-required-none' => '1' }]
    opts += possible_values_options(custom_field, objects)
    view.select_tag(tag_name, view.options_for_select(opts, value), merged.merge(multiple: custom_field.multiple?))
  end
end
```

Notes on `value_from_keyword`:
- `downcase(:fold)` reproduces `casecmp?` semantics (Unicode case folding).
- The results are identical to today, which is characterized: duplicates are kept, a value containing a comma cannot be imported into a multi field, enumerations return id strings and match active names only.
- 100,000 keywords against 5,570 options is O(n + m).

Class bodies:
- `DependingListFormat`:
  - `include DependingFormatMethods`;
  - `add 'depending_list'` (a private class method, so it stays in the class body);
  - `form_partial`, `label`;
  - `query_filter_values(cf, _query = nil)`: every non-blank value as `[v, v]` (characterized).
- `DependingEnumerationFormat`:
  - the same, plus `query_filter_values(cf, query = nil)`. It restricts to the allowed set of `parent_state(cf, query&.project)` when that is non-empty, and otherwise returns all. A nil query now returns all (today it raises; core never passes nil).
  - `possible_custom_value_options(custom_value)` (F2 fix): the unfiltered active list plus the stored `value_was` ids (inactive included) as 2-tuples. Copies keep core parity: only `value_was`. A crafted inactive id that is not stored is rejected (QA-21).
- `customized_class_names` is inherited and untouched.
- `query_filter_values` stays public.

## 6. ClientData

File: `lib/redmine_depending_custom_fields/client_data.rb`.

```ruby
module ClientData
  module_function
  PARENT_NAME_RE = /\A(.+)\[custom_field_values\]\[\d+\](\[\])?\z/.freeze   # source of data-dcf-parent-name

  # Returns a Hash with symbol keys (Rails dasherizes; non-String values are JSON-encoded and HTML-escaped).
  def attributes_for(cf, context:, customized: nil, objects: nil, custom_value: nil, tag_name: nil, user: User.current)
    return {} unless DependencyRules.depending?(cf)
    data = { dcf_field: cf.id, dcf_context: context.to_s, dcf_kind: DependencyRules.kind(cf) }
    data[:dcf_multiple] = 1 if cf.multiple?
    source = context == :bulk ? Array(objects) : customized
    lookup = DependencyRules.lookup_records(source)
    pid = DependencyRules.effective_parent_id(cf, lookup)   # client emission uses the effective parent (gap 2)
    return data unless pid
    parent = lookup[pid] || DependencyRules.find_parent(pid)
    return data unless parent_visible?(parent, context, customized, objects, user)

    data[:dcf_parent] = pid
    name_match = PARENT_NAME_RE.match(tag_name.to_s)
    data[:dcf_parent_name] = "#{name_match[1]}[custom_field_values][#{pid}]" if name_match
    data[:dcf_map] = encode(cf, DependencyRules.mapping(cf))
    defaults = encode(cf, DependencyRules.defaults(cf))
    data[:dcf_defaults] = defaults unless defaults.empty?
    data[:dcf_hide] = 1 if DependencyRules.hide_when_disabled?(cf)
    if context == :form
      state = DependencyRules.parent_state(cf, customized)
      if state
        data[:dcf_parent_values] = state.values
        data[:dcf_parent_label] = parent.name
        stored = stored_baseline(custom_value, customized, state)
        data[:dcf_stored] = stored if stored
      end
    end
    data
  rescue StandardError => e
    Rails.logger.warn("[DCF] client data skipped for custom field ##{cf.id}: #{e.class}: #{e.message}")
    {}
  end

  # data-dcf-stored (gap 6): the server D1 baseline. Persisted records: value_was. Issue copies: the copy
  # source's stored values (baseline_source, UD-06). Any other new record: nil, so the attribute is absent.
  def stored_baseline(custom_value, customized, state)
    return nil unless custom_value
    return nil unless customized.persisted? || DependencyRules.baseline_source(customized)
    { 'child' => DependencyRules.child_baseline(custom_value), 'parent' => state.baseline }
  end

  def sentinel?(cf, data)
    data.key?(:dcf_parent) && data[:dcf_context] == 'form' && !cf.multiple? && cf.edit_tag_style == 'check_box'
  end

  def merge_options(options, data)        # never mutates the caller's hash; tolerates core's data: nil
    return options if data.empty?
    base = options[:data].is_a?(Hash) ? options[:data] : {}
    options.merge(data: base.merge(data))
  end
end
```

Details:
- `parent_visible?` applies the 2.1 rule and rescues StandardError, giving false.
- `encode` turns canonical enumeration ids into Integers (`kind(cf) == 'enumeration'` and `CANONICAL_ID`), recursively for arrays.
- `data-dcf-stored` stays all-String (no `encode`): the client compares as `String(x)`, and the values are exactly what `dependency_check` compares against.
- ClientData and the overrides ship in 0.2.0: the every-field and managed attributes, `data-dcf-stored` and the fixtures in WP-16 (additive, the legacy JS ignores them); the sentinel and the required-none option in WP-19.
- Unit spec `spec/lib/client_data_spec.rb` (WP-16): unmanaged fields (no parent, dangling, cycle, self, invisible parent) carry only the every-field attributes; managed form context carries parent-values, parent-label and stored; a copy carries stored from the copy source and a plain new record carries none (gap 6); bulk is gated per project; `visible_by?` raising counts as not visible; a corrupt mapping renders without data-dcf-* (fail open).

## 7. Point 1: cache removal and the context menu without cache (D4)

### 7.1 Removed

- the inline `<script>` with `window.DependingCustomFieldData` and `window.ContextMenuWizardConfig` (D5; 0.2.0, WP-18);
- every `Rails.cache` use: the head hook, ContextMenuHook, ContextMenusControllerPatch, ParentDetector, ParentMenuBuilder and ContextMenuWizardController#options (0.2.0: the context-menu paths in WP-15, the head hook and every remaining use in WP-18);
- both formats' `after_custom_field_save`, including `delete_matched('dcf/*')`, which raises NotImplementedError on MemCacheStore and rolls back every depending save. The `delete_matched` call is removed first, as a hotfix in the legacy code (0.0.16, WP-03, UD-02); the plain `Rails.cache.delete('depending_custom_fields/mapping')` and the callbacks go in 0.2.0 (WP-18);
- the CustomFieldPatch `after_save` dispatch (0.2.0, WP-18; deleted outright, UD-14).

The stale key `depending_custom_fields/mapping` is left alone. Nothing reads it. It is not deleted at boot.

Rollback note (BC-07): no code keeps writing or deleting the key. Point 1 explicitly requires removing the invalidation. The CHANGELOG (0.2.0 upgrade notes) and README "Downgrade" note say: after downgrading from 0.2.0 or later to an earlier version (0.1.x and older still read the key) on a persistent cache store, run `bin/rails runner -e production "Rails.cache.delete('depending_custom_fields/mapping')"` once.

### 7.2 SelectionGraph

File: `app/models/redmine_depending_custom_fields/selection_graph.rb` (0.2.0, WP-15; sections 7.2 to 7.6 are WP-15 unless noted).

```ruby
class SelectionGraph
  def initialize(issues)
    @issues = Array(issues).compact
  end

  def candidate_fields     # union of available_custom_fields: 0 queries after core's editable_custom_fields (probe_graph)
    @candidate_fields ||= @issues.flat_map(&:available_custom_fields).uniq(&:id)
  end

  def index                # raw YAML of the loaded candidates, no deserialization; missing parents in one batched query
    @index ||= FieldIndex.new(records: candidate_fields.index_by(&:id))
  end

  def children             # depending candidates with an effective parent (exists, same type, family, acyclic)
    @children ||= begin
      deps = candidate_fields.select { |cf| DependencyRules.depending?(cf) }
      index.ensure(deps.map { |cf| index.parent_id(cf.id) }.compact)
      deps.select { |cf| index.effective_parent_id_for(cf.id, cf.type, cf.field_format, index.parent_id(cf.id)) }
    end
  end

  def child_ids
    @child_ids ||= Set.new(children.map(&:id))
  end

  def parent_ids
    @parent_ids ||= Set.new(children.map { |cf| index.parent_id(cf.id) })
  end

  def hidden_field_ids
    child_ids | parent_ids
  end

  def root_parent_ids
    parent_ids - child_ids
  end

  def children_of(parent_id)
    children.select { |cf| index.parent_id(cf.id) == parent_id }.sort_by { |cf| [cf.position || 0, cf.id] }
  end

  def field(id)
    (@by_id ||= candidate_fields.index_by(&:id))[id]
  end
end
```

Cycle members, and fields whose chain reaches a cycle, have no effective parent. They are shown in the core menu as plain lists, consistent with unconstrained validation.

### 7.3 ContextMenusControllerPatch

- `render`, `issue_context_menu_request?` and `remove_illegal_user_values` are unchanged.
- `dcf_selection_graph` returns `@dcf_selection_graph ||= SelectionGraph.new(Array(@issues))`.
- `filter_depending_custom_fields`:
  - returns early when `@options_by_custom_field.blank?` (users without `@can[:edit]`) or when it does not respond to `reject!`;
  - otherwise runs `reject! { |field, _| hidden.include?(field.id) }`.
- The dead `@custom_fields` branch is dropped.
- The rescue stays `rescue StandardError` with the warning.

Per-child cost (R16): core calls `field.possible_values_options(@projects)`, which reaches the format once per Project (core-5.1 `custom_field.rb:169-173`). `carries?` is false for an Issue field with a Project, so the format returns the core base list without any parent lookup or format_store parse. Characterized flip: today these are all-hidden 3-tuples. That is invisible, because core destructures 2 elements (F5) and the intersection across projects works on either shape.

### 7.4 ContextMenuHook

- The gate is unchanged: `:edit_issues` on every selected issue. So a closed project gets no wizard.
- It reuses the controller graph through `respond_to?(:dcf_selection_graph, true)`, or builds its own.
- `parents = ParentDetector.for_issues(issues, graph: graph)`. It returns nil when empty, so no view_context is built.
- It renders the partial collection with locals `issues` and `graph`.

### 7.5 ParentDetector

The signature is kept, with optional keywords. It fails closed (SP-10) and memoizes per project and tracker (SP-08).

```ruby
PARENT_FORMATS = DependencyRules::ALL_PARENT_FORMATS

def self.for_issues(issues, graph: nil, user: User.current)
  issues = Array(issues).compact
  return [] if issues.empty?
  graph ||= SelectionGraph.new(issues)
  memo = {}
  graph.root_parent_ids.filter_map { |id| graph.field(id) }
       .select { |cf| PARENT_FORMATS.include?(cf.field_format) && usable_on_all?(cf, issues, user, memo) }
       .sort_by { |cf| [cf.position || 0, cf.id] }
end

def self.wizard_levels(root, issues, graph:, user: User.current)   # visited Set: terminates on any stored data
  levels = []
  visited = Set.new
  memo = {}
  current = [root]
  until current.empty?
    level = current.select { |cf| visited.add?(cf.id) && usable_on_all?(cf, issues, user, memo) }
    break if level.empty?
    levels << level
    current = level.flat_map { |cf| graph.children_of(cf.id) }
  end
  levels
end

def self.usable_on_all?(cf, issues, user, memo = {})
  issues.all? do |issue|
    key = [cf.id, issue.project_id, issue.tracker_id]
    memo.key?(key) ? memo[key] : (memo[key] = usable_on?(cf, issue, user))
  end
end

def self.usable_on?(cf, issue, user)
  issue.available_custom_fields.include?(cf) && cf.visible_by?(issue.project, user)
rescue StandardError => e
  Rails.logger.warn("[DCF] wizard visibility check failed for custom field ##{cf.id}: #{e.class}")
  false
end
```

`CustomFieldVisibility` (fail-open `rescue NoMethodError => true`) loses its last callers: the wizard partial, ParentDetector and the deleted controller actions. It is kept unchanged, marked deprecated in 0.2.0 (WP-15, CHANGELOG in WP-20), kept at least throughout 0.2.x, and removable no earlier than 0.3.0 (recommended 0.4.0). Its spec stays until removal.

### 7.6 Wizard partial, route, controller, helper

- **Partial.** Locals `parent_field`, `issues`, `graph`. `levels = ParentDetector.wizard_levels(...)`. Form markup as in 2.3 (form action and method from the named route in WP-15; the `data-dcf-wizard-field` wrappers and the removal of `data-field-id` in WP-18).
- **Route.** `match 'depending_custom_fields/save', to: 'context_menu_wizard#save', via: :post, as: 'depending_custom_fields_save'`. The name equals today's auto name. The `options` line is deleted. GET `/depending_custom_fields/options` keeps reaching API#show (404 JSON for admins, 403 otherwise), as today. API routes are untouched.
- **ContextMenuWizardController.** Delete `include ContextMenuWizardHelper`, `options`, `parent_options` and `child_options`. Keep `before_action :find_issues, only: :save`. `save` is otherwise unchanged; see SP-07 in section 20 (SD-01, UD-03).
- **ContextMenuWizardHelper.** Delete `intersect_allowed_values` (WP-15). `render_custom_field(cf, issues)` returns `custom_field_tag_for_bulk_edit('issue', cf, issues, nil)` without regex injection (0.2.0, WP-18). The value is nil, not `cf.default_value` as in revision 2, so every wizard field, including the root, opens on '(no change)' and a save without a choice changes nothing (UD-11).

### 7.7 Cost and size per right-click

- **Queries:** 0 for the graph when parents are in the selection; one batched raw select for parents outside it.
- **YAML parses:** 0 for hidden children. One per rendered wizard field (its `data-dcf-map`, inherent).
- **Response size (SP-08, QA-22):** the wizard template already renders full bulk selects today. The added bytes are the per-field `data-dcf-map`, about 140 KB for an S1 list child and about 40 KB for an S1 enumeration child.
  - Declared budget, asserted by spec with S1 data (root of 27 values, one child of 5,570): the whole `/issues/context_menu` response is at most 512 KB, and the plugin-added part is at most `sum(rendered select markup + data-dcf-map) + 16 KB`.
  - A lazily loaded wizard body is a user decision (UD-13, recommended: keep the template inline with this budget; the budget spec ships in WP-18), not part of the default plan (D4).

## 8. Validation algorithm (points 5 and 6, D1)

`DependencyRules.dependency_check(custom_value, state, user)` (D1, copies and non-editable children: 0.1.0, WP-09; effective parent and cycles: 0.1.0, WP-10):

```ruby
cf = custom_value.custom_field
current = normalize_values(custom_value.value)
allowed = allowed_for(cf, state)
return [allowed.empty?, []] if current.empty?
baseline = child_baseline(custom_value)
tolerated = state.changed? ? Set.new : Set.new(baseline)          # D1 per value (R14): keep what was there
bad = current.reject { |v| allowed.include?(v) || tolerated.include?(v) }
return [allowed.empty?, []] if bad.empty?
return [allowed.empty?, []] if current.sort == baseline.sort && !editable_by?(cf, custom_value.customized, user)  # QA-08
[allowed.empty?, [::I18n.t('activerecord.errors.messages.invalid')]]
```

Rules:
1. **D1 per value.** While the parent is unchanged, every value already in the baseline is tolerated, and only newly added values must be allowed. This matches core's own idiom (F7). When the parent changed, everything is strict again. A parent that is not available on the object counts as unchanged (no value before or after; UD-05). The one-line switch to strict is a user decision (UD-04).
   - Release effect: in 0.1.0 the leniency applies to the REST API, email, bulk edit, the wizard and copies. The issue form keeps such values only from 0.2.0 on, because the legacy JS still drops a disallowed stored value at load in 0.1.0; the new runtime (WP-17) keeps it using `data-dcf-stored` (2.2).
2. **Copies (QA-07).** For a new record that `copy?` (issue copy, bulk copy, the issue part of project copy), the baseline is the source issue's stored child and parent value instead of `value_was` (F8). Combinations copied unchanged are accepted (UD-06). A changed child or a changed parent is validated as above.
   - The same baseline is emitted to the client as `data-dcf-stored` (2.2, gap 6), so the copy form keeps, marks and posts a copied legacy value instead of dropping it.
   - Today, copies holding a legacy combination fail, and project copy silently skips them (core-7.0 `project.rb:1227`). This revision fixes that.
   - Other new records (including Project copies of project custom fields) stay strict.
   - Core's own inclusion check is untouched. A copied value outside `possible_values`, or a copied inactive enumeration id, is still rejected by core, as for plain list and enumeration fields.
3. **Non-editable child (QA-08).** The dependency rule never rejects an unchanged child that the current user cannot edit (`editable_custom_field_values`, F9), even when the parent changed. Such a child cannot be fixed by that user: core filters its assignment (core-7.0 `app/models/issue.rb:647-648`) but still validates it. A user decision confirms this default (UD-07).
4. **Cycle members and fields whose chain reaches a cycle:** no effective parent, so core validation only (UD-08). The client is unfiltered too (2.1).
5. **No parent, dangling parent, nil customized, or a non-carrying object:** core validation only, as today.
6. **Otherwise:** today's behaviour. When nothing is allowed, a non-blank untolerated value gives "is invalid" with no core check. Otherwise core errors are returned, plus one "is invalid".

When this runs: core validates custom values only on `new_record? || custom_field_values_changed?` (acts_as_customizable 127-131). Form, bulk, REST, mail and the wizard all assign values.

Required bypass (`CustomFieldPatch#validate_custom_value`): the semantics are unchanged; the lookup moves to `DependencyRules.no_options?(self, custom_value.customized)`. Leniency only concerns non-blank values, so the required rule is untouched. Workflow-required depending children with no options still fail through `Issue#validate_required_fields` (pre-existing, tracked separately).

## 9. Point 5: cycle validation and the parent select

All of section 9 ships in 0.1.0 (WP-10; UD-08 for the D9 refinement).

```ruby
def parent_changed?(cf)
  return true if cf.new_record?
  return false unless cf.will_save_change_to_attribute?('format_store')
  old = cf.attribute_in_database('format_store')
  normalize_id(old.respond_to?(:[]) ? old['parent_custom_field_id'] : nil) != normalize_id(cf.parent_custom_field_id)
end

def parent_errors(cf)
  return [] unless depending?(cf) && !cf.new_record? && parent_changed?(cf)
  candidate = resolve_parent_for_save(cf)          # same (memoized) lookup as before_save
  return [] unless candidate                        # D9: unresolvable keeps the silent nil
  if candidate.id == cf.id || FieldIndex.load.ancestor_ids(candidate.id).include?(cf.id)
    return [[:parent_custom_field_id, :dcf_circular_dependency]]
  end
  []
end
```

**D9 refinement (explicit).** The check runs only for persisted fields whose normalized parent id changed. It does not run for every save while a parent is present, because that would block every save of a field already in a stored cycle:
- the admin reorder;
- project-service cascades (`child.save!`);
- unrelated API updates.

**Concurrent creation.** Two admins saving A.parent=B and B.parent=A at the same moment both pass, because each reads the other's old state. This race is accepted (QA-19); WP-10 adds a README note saying so and listing the guards (gap 14). The guards are:
- the effective-parent rule, which makes the members unconstrained everywhere;
- the admin warning;
- visited sets on the server and the client;
- the stored-cycle fixture covering every surface.

**Error path.** Errors reach the admin form, the plugin API (`422 {errors: full_messages}`), project services (RecordInvalid) and jc-redmine_extended_api.

**Parent select.** `_depending_list.html.erb` and `_depending_enumeration.html.erb` use `DependencyRules.parent_candidates(@custom_field).map { |cf| [cf.name, cf.id.to_s] }`:
- same type and family;
- minus self and `FieldIndex.load.descendant_ids(cf.id)`;
- always keeps the current parent, so a stored-cycle member does not silently lose its parent;
- all candidates for a new record.

A dangling parent id is not offered. A save then posts a blank parent, `''` is stored and the mapping becomes inert, as today (QA-23 spec).

**Warning (UX-10).** When `in_cycle?`:

```erb
<p class="icon icon-warning"><%= respond_to?(:sprite_icon) ? sprite_icon('warning', w) : w %></p>
```

where `w = l(:warning_dcf_parent_cycle, fields: names.join(', '))`. Names come from `CustomField.where(id: cycle_member_ids).pluck(:id, :name)`, ordered along the cycle. This is core 7.0's own pattern (core-7.0 `app/views/issues/index.html.erb:65-67`). The editor area keeps these lines when it replaces the matrix.

## 10. Storage limits interplay (owner: limits area)

- The limits area owns (0.1.0, WP-11 to WP-13):
  - `StorageLimits`;
  - registration through the single `Patches::CustomFieldValidationPatch`, prepended in init.rb right after CustomFieldPatch (compat section 2.4 "CustomField callback registration"; revision 2 proposed a separate `Patches::CustomFieldStoragePatch`);
  - the error key `activerecord.errors.messages.dcf_storage_too_large` with `%{size}/%{limit}`;
  - `column_limit(column, model = CustomField)` (compat section 2.4 "`column_limit` signature"), `violation_in(record)`, `report`, the rake tasks and the service mapping.
- Revision-1 server items are withdrawn: the server `StorageLimits`, `dcf_too_large`, `too_large?` and `report`.
- The server provides `normalized_store_pairs`, `storage_preview(custom_field, store)` and the sanitize-only before_save (section 5; 0.0.16, WP-06). Limits calls it as `format.storage_preview(record, record.format_store)` (gap 4, compat section 3 "storage_preview"); there is no one-argument form. The preview includes parent-id normalization (string id to Integer, invalid to nil), so preview bytes equal stored bytes (limits V4).
- The admin JSON transport (editor, 0.3.0, WP-22) assigns the decoded and D6-pruned hashes in `before_validation`, registered in the same `CustomFieldValidationPatch` (the transport callbacks join it in WP-22). Both the size guard and the cycle check then see final values.

## 11. Callback registration rule (R5)

- After point 1, `CustomFieldPatch.prepended` registers **no callbacks** (the `after_save` dispatch is removed). It keeps `validate_custom_value` (required bypass) and `dcf_memo`.
- Every new CustomField callback lives in one prepended module, `Patches::CustomFieldValidationPatch`, prepended in init.rb right after CustomFieldPatch (compat section 2.4: one registration point instead of the two modules revision 2 proposed):
  - limits: `validate :dcf_validate_storage_limits` (0.1.0, WP-11);
  - editor: the `dependencies_json` transport callbacks, `before_validation` and `validate` (0.3.0, WP-22).
- Symbol callbacks are deduplicated if init.rb runs twice (limits V12).
- `spec/patches/custom_field_required_validation_spec.rb` and `spec/lib/value_validation_spec.rb` are rewritten **DB-backed** in WP-04 (0.0.16), before any refactor, with identical assertions; `value_validation_spec.rb` moves to `spec/models/dependency_validation_spec.rb`. Revision 2 placed the rewrite in the commit that switches validation to DependencyRules; moving it earlier means no later WP depends on stand-in classes. `DependencyRules.parent_state` needs a real `custom_field_values` and `customized_class`, so the stand-in classes and `double('Issue')` cannot express it. The 7 endless defs disappear with the rewrite.

## 12. Model API and JSON API (BC-04, BC-10)

- `CustomField.safe_attributes` entries `value_dependencies` and `default_value_dependencies` (`init.rb:43-52`) are a **permanent model API**. jc-redmine_extended_api writes through `safe_attributes=` (its `custom_fields_controller_patch.rb:105-110`, `attribute_policy.rb:223-279`).
  - They stay permanently (UD-15; WP-22 asserts that `CustomField.safe_attribute_names` includes `value_dependencies`, `default_value_dependencies` and `dependencies_json`, gap 12).
  - Only the nested HTML form params are deprecated: the admin form stops rendering them (0.3.0, WP-25) and the server keeps accepting them.
  - The project-level nested params remain a controller contract: deprecated in 0.3.0 (WP-27), accepted throughout 0.3.x, removable no earlier than 0.4.0.
- **API normalization.** The JSON API path (`update` and safe-attribute saves) runs only `before_custom_field_save` (sanitize plus parent normalization). There is no D6 pruning and no reordering, so a PUT that changes only the name leaves `value_dependencies` byte-identical, orphan and bracket-corrupted keys included.
- Saves from the admin editor (0.3.0, WP-22 and WP-25) normalize the stored mapping (order, default shape, removed orphans). GET output can change after such a save; the CHANGELOG and README API section say so.
- New 422 reasons, both in 0.1.0: circular parent (D9, WP-10), and oversize on MySQL (limits, WP-11). The payload shape and permitted params are unchanged.

## 13. Dead code removal

- the `options` route and actions, and `intersect_allowed_values` (0.2.0, WP-15);
- `MappingBuilder` (0.2.0, WP-18) and `ParentMenuBuilder` (0.2.0, WP-15), deleted outright without shims (D5, UD-14, CHANGELOG);
- `QueryCustomFieldColumnPatch`, plus `init.rb:2,55-60` and its spec (F3; 0.0.16, WP-06);
- the formats' `after_custom_field_save` and the dispatch (`delete_matched` in 0.0.16, WP-03; the rest in 0.2.0, WP-18);
- `DependencyRules::Graph` (never shipped; replaced by FieldIndex in WP-05).

Kept: `Sanitizer.*`, `RedmineDependingCustomFields.register_formats` and `CustomFieldVisibility` (deprecated in 0.2.0, removable no earlier than 0.3.0, see 7.5).

## 14. Import and mail handler

- IssueImport and MailHandler call `value_from_keyword` before `safe_attributes=` (core-7.0 `app/models/issue_import.rb:220-234`, `mail_handler.rb:523-529`). The full-list Hash lookup returns the same results as today.
- Disallowed combinations are rejected afterwards: new records have no baseline unless they are copies.
- `IssueImportPatch` is untouched.

## 15. Locales

Server-owned keys, at parity in en/de/fr/nl. The texts in all four locales are defined only in `large_lists_i18n_registry.md` (single source of truth, one owner WP per key); this section keeps key names and owners.

| Key | Owner | en / de / fr / nl texts |
|---|---|---|
| `field_parent_custom_field` (error label, F4; same text as the form label `field_parent_custom_field_id`, R19) | server, WP-10 (0.1.0) | see large_lists_i18n_registry.md |
| `warning_dcf_parent_cycle` (interpolation `%{fields}`) | server, WP-10 (0.1.0) | see large_lists_i18n_registry.md |
| `activerecord.errors.messages.dcf_circular_dependency` (nested; reads after the label, UX-15) | server, WP-10 (0.1.0) | see large_lists_i18n_registry.md |

Full message example (en, illustrative; the canonical texts are in the registry): "Depends on refers to this field or to one of its dependent fields, which would create a circular dependency".

Keys rendered by the server head hook (`ClientConfig::I18N`, 2.4) but owned by the frontend area, added in 0.2.0 by WP-18 (texts in the registry). They follow compat section 2.4 ("Hint keys": frontend keys); the revision 2 server names `text_dcf_hint_select_parent_first` and `text_dcf_hint_legacy_value` are not created:
- `text_dcf_hint_select_parent`;
- `text_dcf_hint_no_options`;
- `text_dcf_hint_no_options_generic`;
- `text_dcf_hint_legacy`;
- `text_dcf_hint_legacy_locked`;
- `text_dcf_hint_legacy_generic`;
- `text_dcf_hint_bulk_default`;
- `text_dcf_hint_bulk_cleared`;
- `text_dcf_live_message`;
- the existing `error_save_failed` (reused, not redefined).

Revision-1 keys are withdrawn:
- `label_dcf_hint_*`;
- `dcf_too_large` (replaced by limits' `dcf_storage_too_large`);
- the server definition of `field_value_dependencies`. Its owner is limits (WP-11, 0.1.0; UX-03); text: see large_lists_i18n_registry.md.

Requirements on the parity spec (quality area):
- flatten nested keys;
- fail on duplicate mapping keys inside one file, using a duplicate-detecting Psych parse;
- resolve every value of every I18N constant map (`RedmineDependingCustomFields::ClientConfig::I18N`, `DependencyEditorConfig::I18N`) in all 4 locales without "translation missing". The WP-02 spec iterates each constant when it is defined; the name `I18N_KEYS` is not used (gap 5). WP-18 and WP-24 each add an example proving their map is checked;
- honour the parity allowlist of keys intentionally identical to en, kept in the registry (it includes de and nl `text_dcf_live_message`, gap 10).

## 16. Behaviour before and after

| Behaviour | Before | After | Release |
|---|---|---|---|
| Mapping delivery | inline global on every page, anonymous included | per-field data-* on managed fields only; nothing for role-invisible parents | 0.2.0 (WP-16, WP-18) |
| Cache | `Rails.cache` without TTL, `delete_matched` in after_save | none | 0.2.0 (WP-15, WP-18); `delete_matched` already in 0.0.16 (WP-03) |
| MemCacheStore and namespaced stores | every depending save fails (500) | works | 0.0.16 (WP-03) |
| Wizard POST URL | basePath plus a literal path | form action from the named route | 0.2.0 (WP-15, WP-18) |
| Core menu hiding | every globally mapped child and parent | children with an effective parent relevant to the selection, and their parents; dangling-parent and cycle children are shown | 0.2.0 (WP-15) |
| Wizard hierarchy | BFS without a visited set | `wizard_levels` with a visited set; fail-closed visibility | 0.2.0 (WP-15) |
| Enum edit options | hidden 3-tuples plus a visible duplicate | full active list plus stored ids | 0.1.0 (WP-08) |
| Enum disallowed new value | 2 errors | 1 error | 0.1.0 (WP-08) |
| Legacy combination, untouched | rejected | accepted | 0.1.0 server (WP-09); issue form from 0.2.0 (WP-17) |
| Multi child with legacy values: add an allowed value, remove one, reorder | rejected | accepted (per value) | 0.1.0 (WP-09) |
| Issue copy, bulk copy or project copy with a legacy combination | rejected; project copy skips the issue | accepted when copied unchanged | 0.1.0 (WP-09) |
| Issue copy form with a legacy combination (browser) | the legacy JS drops the value at load | kept, enabled, marked and posted (`data-dcf-stored` from the copy source, gap 6) | 0.2.0 (WP-16, WP-17) |
| Parent changed while the child is read-only for the user and unchanged | rejected, cannot be fixed | accepted | 0.1.0 (WP-09) |
| Stored cycle members | validated per mapping; JS RangeError | unconstrained on server and client; admin warning | 0.1.0 server and warning (WP-10); client 0.2.0 (WP-16 to WP-18) |
| Self or cyclic parent set | saved silently | 422 or form error when the parent changes | 0.1.0 (WP-10) |
| Parent select | excludes self only | excludes self and descendants; keeps the current parent | 0.1.0 (WP-10) |
| Required radio child | cannot be cleared | sentinel posts `''` | 0.2.0 (WP-19) |
| Required child in bulk or wizard | no "(none)" | "(none)" marked, usable only while no options are allowed | 0.2.0 (WP-19) |
| possible_values_options(project) for an Issue field | all-hidden 3-tuples | base list (no lookup; invisible in core menus) | 0.2.0 (WP-15) |
| value_from_keyword | linear scans per keyword | one Hash per call, same results | 0.0.16 (WP-06) |
| JSON API | | unchanged; new 422 reasons only; byte-identical round trip of name-only PUTs | 0.1.0 (WP-10, WP-11) |

## 17. Edge cases

- **Dangling parent:** unmanaged, core-only validation, shown in the core menu, `''` after the next admin save.
- **Role-invisible parent:** only the every-field attributes (`data-dcf-field`, `data-dcf-context`, `data-dcf-kind` and, for multi fields, `data-dcf-multiple`). The client is unfiltered and the server validates (D1).
- **Read-only parent:** parent-values and parent-label present, so the client filters.
- **Parent not enabled for the tracker:** parent-values `[]`. The client keeps the stored child as legacy; the server accepts it untouched and rejects new values.
- **Multi-valued parent:** union; order-insensitive comparison.
- **Keys with `[ ] < & "`:** JSON in attributes is escaped. The client looks parents up by exact name.
- **Enum ids:** compacted only when canonical.
- **Issue show page** (edit form plus wizard): the client scope is `closest('form')`.
- **time_entry fields inside the issue form:** distinct prefix.
- **Non-Issue customized types:** `scope_project` is nil (User, Group) or the object (Project), and the base visibility rule applies.
- **Issue copy:** `data-dcf-stored` carries the copy source's child and parent values, so a copied legacy combination is kept on the form and accepted by the server while unchanged (gap 6, UD-06). A plain new issue has no `data-dcf-stored`.
- **New record with a parent:** no cycle check.
- **CustomField copy_from:** a new record; the enum remap is out of scope.
- **`parent_custom_field_id = ''`** stays `''`.
- **Corrupt stored mapping:** ClientData fails open, and validation behaves as before.
- **Very large maps on PostgreSQL:** documented scale limit (limits section 5).
- **Memo staleness:** if a chain member is changed in the same request after a child memoized its effective parent, the memo is stale for that request only. Admin saves never use it.

## 18. Implementation order (characterization first)

The work-package split in `large_lists_work_packages.md` is canonical; the WP and release of each step are given in brackets.

1. **Characterization specs, DB-backed** (`spec/characterization/depending_formats_spec.rb`, `spec/requests/context_menu_spec.rb` baseline), green on the base commit across the matrix. Also the DB-backed rewrites of the two validation specs (section 11). [WP-04, 0.0.16; the `delete_matched` hotfix lands just before in WP-03, 0.0.16]
2. **Refactor to the new structure:** DependencyRules, FieldIndex and DependingFormatMethods, with no behaviour change except listed flips. FieldRelevance and the project controller delegate. [WP-05 and WP-06, 0.0.16; `QueryCustomFieldColumnPatch` is removed in WP-06]
3. **Deliberate changes, each flipping listed expectations, with a CHANGELOG line:**
   - (a) the enum options fix [WP-08, 0.1.0];
   - (b) D1 per value plus copies plus non-editable [WP-09, 0.1.0];
   - (c) effective parent (cycle members unconstrained) [WP-10, 0.1.0];
   - (d) cycle validation, locales, parent select and warning [WP-10, 0.1.0];
   - (e) `normalized_store_pairs` and `storage_preview` for limits [defined in WP-06, 0.0.16, without behaviour change; consumed by WP-11, 0.1.0].
4. **Point 1 switch, same release as the frontend runtime (0.2.0), split over four PRs:**
   - SelectionGraph, the patch, the hook, ParentDetector, the partial's form action and the route; controller and helper cleanup; removal of ParentMenuBuilder [WP-15];
   - ClientData and the overrides (including `data-dcf-stored`); the markup fixture spec [WP-16];
   - the head hook and ClientConfig; the wizard partial wrappers; removal of the cache, the dispatch and MappingBuilder [WP-18];
   - the sentinel and the required-none option [WP-19].
5. **Docs:**
   - README Integration (contract 2.2, events) [WP-18], Compatibility (Ruby >= 2.7) [WP-07], Downgrade note [WP-18], API normalization [WP-14 for the new 422 reasons; WP-32 for editor normalization];
   - CHANGELOG (section 19) [per WP; finalized in WP-07, WP-14 and WP-20];
   - removal of the cache statements in docs/specs [WP-18].

## 19. CHANGELOG lines owned by this area (BC-14)

The release-by-release wording in `large_lists_work_packages.md` section 3 is canonical. The lines below are this area's input; each carries the release and WP that ships it.

Added:
- Circular parent selections are refused (form error, 422 in the API). [0.1.0, WP-10]
- The admin form warns about stored cycles. [0.1.0, WP-10]
- Required radio-style depending fields can be cleared. [0.2.0, WP-19; listed under Fixed in the canonical 0.2.0 section]
- In bulk edit and the context-menu wizard, required dependent fields offer "(none)" while the parent selection allows no value. [0.2.0, WP-19; UD-10]

Changed:
- **Stored values.**
  - Stored values that no longer fit the parent are accepted on save until the parent changes. This holds per value: you can add or remove other values. [0.1.0, WP-09; UD-04. In 0.1.0 this applies to the REST API, email, bulk edit, the wizard and copies; the issue form keeps such values from 0.2.0 on]
  - Issue copies, including bulk copy and project copy, keep such values when copied unchanged. [0.1.0, WP-09; UD-06. The copy form keeps them from 0.2.0 on through `data-dcf-stored`, WP-16 and WP-17]
  - A dependent field you cannot edit no longer blocks saving a parent change. [0.1.0, WP-09; UD-07]
  - An untouched value is accepted when the parent field is not available for the issue's tracker. [0.1.0, WP-09; UD-05]
- **Filtering.**
  - Dependent fields whose parent is read-only or hidden by the workflow are filtered by the stored parent value, and may be hidden when "Hide when no valid options" is set. [0.2.0, WP-16 to WP-18]
  - Dependent fields whose parent you cannot see are no longer filtered in the browser. The server still validates them. [0.2.0, WP-16 to WP-18]
  - Fields in a circular configuration are treated as independent until the cycle is fixed. [server 0.1.0, WP-10; browser 0.2.0, WP-16 to WP-18; UD-08]
  - Without JavaScript, Key/Value list (depending) fields show all active values; the server still rejects invalid combinations. [0.2.0, WP-18]
  - Fields rendered without Redmine's custom field helpers are no longer filtered in the browser (see README Integration). [0.2.0, WP-18]
- **Context menu.**
  - Only dependent fields available in the selection, and their parents, are hidden from the core menu. Parents of unavailable children come back with their full list. Children of deleted parents, and fields in a circular configuration, show as plain lists (7.2). [0.2.0, WP-15]
  - Responses include dependency data for the wizard fields and can be larger for very big mappings. [0.2.0, WP-18; UD-13]
  - The wizard opens every field, including the root, on '(no change)'. [0.2.0, WP-18; UD-11]
- **Enumeration fields.** A disallowed new value gives one error instead of two, and the edit form no longer shows a duplicate of the stored value. [0.1.0, WP-08; listed under Fixed in the canonical 0.1.0 section]
- **API.** The response shape is unchanged. New 422 reasons: circular parents, and MySQL oversize (limits). [0.1.0, WP-10 and WP-11] Saves from the admin editor may normalize the stored mapping and change GET output. [0.3.0, WP-22 and WP-25]

Fixed:
- Saving any depending field no longer fails on MemCacheStore or namespaced cache stores. [0.0.16, WP-03; UD-02]
- No more global mapping on anonymous pages. [0.2.0, WP-18]

Deprecated:
- `window.DependingCustomFields.setup` and `requestSetup`: deprecated in 0.2.0 (WP-18), kept throughout 0.2.x, removable no earlier than 0.3.0 (recommended 0.4.0).
- `CustomFieldVisibility`: deprecated in 0.2.0 (WP-15), kept throughout 0.2.x, removable no earlier than 0.3.0 (recommended 0.4.0).

Removed:
- `window.DependingCustomFieldData` and `window.ContextMenuWizardConfig` [0.2.0, WP-18];
- `MappingBuilder` [0.2.0, WP-18] and `ParentMenuBuilder` [0.2.0, WP-15] (UD-14);
- `QueryCustomFieldColumnPatch` (it had no effect) [0.0.16, WP-06];
- `ContextMenuWizardController#options` [0.2.0, WP-15];
- the `after_custom_field_save` dispatch [0.2.0, WP-18];
- the regex-injected `data-field-id` [0.2.0, WP-18].

Upgrade notes:
- Ruby >= 2.7 is required. [0.0.16, WP-07; UD-34]
- Restart Redmine. If automatic plugin asset mirroring (5.1) or redmine_detect_update (6.x/7.0) is disabled or assets are baked into an image, run `rake redmine:plugins:assets` (5.1) or `rake assets:precompile` (6.x/7.0). There is no new `depending_custom_fields_rules.js`: the rules live in the one UMD runtime (compat section 2.4). [0.2.0, WP-18]
- The cache key `depending_custom_fields/mapping` is no longer used. [0.2.0, WP-18]
- Before downgrading to an earlier version on a persistent cache store, delete it (command in 7.1). [0.2.0, WP-18]
- The safe attributes `value_dependencies` and `default_value_dependencies` stay permanently. Scripts and jc-redmine_extended_api are unaffected. [0.3.0, WP-22; UD-15]

## 20. Cross-area decisions recorded here

These were proposals for the consolidated plan. The owner area is named for each. Where `large_lists_compatibility.md` sections 3 and 4 fixed a different choice, the consolidated choice is stated inline and wins.

- **DependencyPayload** (owner: editor; R3, QA-02, SP-01, SP-02, SP-17, BC-03; 0.3.0, WP-21). One parser, `lib/redmine_depending_custom_fields/dependency_payload.rb`.
  - Strict schema with top-level `version`, `source`, `base`, an optional `import: {mode, rows}`, `value_dependencies` and `default_value_dependencies`. Unknown keys are rejected. null, booleans and floats are rejected.
  - Before `JSON.parse`, an O(n) pre-scan rejects numeric tokens of 20 or more digits. Integers are accepted only when positive and `bit_length <= 63`, checked before `to_s`.
  - `JSON.parse(raw, max_nesting: 3, create_additions: false)`. One `MAX_BYTES = 4 MiB` for both paths.
  - `parse` returns nil for blank and a Result otherwise. It never raises. Admin: nil means unchanged. Project: nil means the `:blank` error, never a clear.
  - The Result is memoized per raw String object, and the project service exposes it to the controller re-render as `service.parsed_payload`, passed as `posted:` to `DependencyEditorConfig.for_project` (gap 1, WP-27).
  - Admin form encoding (consolidated, compat section 2.4, UD-16): the admin form switches to multipart/form-data while the editor is active, so the 4 MiB payload is reachable; the editor's size pre-check blocks or allows per enctype (WP-25). Revision 2 proposed a URL-encoded pre-check of the whole form against about 3.9 MB instead. The project form stays multipart.
- **Shared editor** (owner: editor; R4, UX-01, BC-03; 0.3.0, WP-24, WP-25 and WP-27).
  - One partial `depending_custom_fields/_dependency_editor` and one presenter `DependencyEditorConfig.for_admin/for_project`.
  - All attributes in the `data-dcf-editor-*` namespace. The project's `data-dcf-parent-values` becomes `data-dcf-editor-parent-values`, so the name never collides with the issue-form attribute.
  - The initial state comes from `data-dcf-editor-mapping`. Failed-save re-render (gap 1, compat section 3): the hidden input is always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; there is no `data-dcf-editor-echo` and no `input_value`. A server pre-fill without the dirty flag is never dirty.
  - The project Save button is disabled until the editor has initialised.
  - Editor i18n goes through `data-dcf-editor-i18n` from `DependencyEditorConfig::I18N` (gap 5; WP-24 lists only its own keys, WP-25 and WP-26 extend the map in the same commit as their locale entries).
  - Assets come only from the head hook (2.4).
  - Value options use the compact wire shape from `DependencyEditorConfig.wire_values(DependencyRules.value_options(cf))` (3.2, gap 3).
  - The values endpoint has no `accept_api_auth`. A spec asserts 401/403 on `.json` with an API key, and on a format-less URL without a session (QA-23).
- **Audit cap** (owner: limits AuditPayload; R10, SP-09; 0.1.0, WP-12). 16,384 bytes. Marker keys `payload_truncated`, `payload_bytes` and `payload_sha256` (compat section 2.4 "Audit marker keys": limits names; revision 2 proposed `truncated` and `original_bytes`), which do not collide with the project delta's own `truncated` and `mapping_sha256`. Project delta caps `LABEL_MAX_BYTES = 80` (JSON-encoded bytes) and 3 defaults per parent. For ValueTooLong, only the class name, column and byte counts are stored.
- **Storage UI** (owner: limits; R20, UX-04; server usage line 0.1.0, WP-11; editor attributes 0.3.0, WP-24).
  - Attributes `data-dcf-editor-storage-limit`, `data-dcf-editor-storage-base`, `data-dcf-editor-values-limit` and `data-dcf-editor-storage-warn`.
  - One threshold (90 percent, compat section 2.4 "Storage threshold and client key"; revision 2 proposed 80%), delimited bytes, one client key `text_dcf_storage_estimate` (owner WP-24; revision 2 proposed `text_dcf_storage_estimate_over`) and one server usage line (UD-28).
  - One model key `dcf_storage_too_large`. One service mapping `error_dcf_values_too_large` / `error_dcf_mapping_too_large`.
  - Project-page copy says "ask an administrator" without a README reference.
  - The field name is `dependencies_json` everywhere.
- **Flash XSS** (owner: limits per compat section 3 "translate_error"; SP-06; 0.1.0, WP-12). `ProjectCustomFieldConfigurationController#translate_error(error_or_key)` accepts a Symbol or an `OperationError` and applies `ERB::Util.h` to every interpolation before `l()`. WP-27 to WP-31 call it as `translate_error(e)` with the `OperationError` (gap 4), never as `translate_error(e.key, e.interpolations)`. Revision 2 proposed a separate `dcf_flash_error(key, interpolations)` helper; it is not created. No payload content ever goes into a flash.
- **Large-list generator** (owner: quality; R12; 0.0.16, WP-02). One file, `spec/support/dcf_large_list.rb`. Consolidated (compat section 2.4 "Large-list generator"): the arithmetic generator (no PRNG) with a JS twin `test/js/support/large_list.js`, pinned at SHA-256 prefix `233acf899217e962` for `names(5570, tricky_every: 97)` (quality E17), plus the `element_bytes`, `yaml_list_bytes` and `values_of_yaml_bytes` byte-target helpers. Revision 2 proposed quality's mulberry32 names; they are not used. A single spec file, `spec/quality/dcf_large_list_spec.rb`.
- **Wizard save authorization** (SP-07; SD-01, UD-03). This is a separately tracked **security** defect, outside the 9 points per D4. The minimal fix is to assign through `issue.safe_attributes = { 'custom_field_values' => values }`, or to filter by `editable_custom_field_values(User.current)`. It is recommended as its own pull request merged before tagging 0.0.16 (UD-03), and it is a hard prerequisite for tagging 0.2.0, the release that ships point 1, with a CHANGELOG "Security" entry. Until then, a request spec pins that the endpoint still requires login, issue visibility and editability, and the plan does not widen it.

## 21. Out of scope, tracked separately

- wizard save hardening: SECURITY item above, plus journal, `@can[:edit]` and the 7.0 webhook effects;
- the time-entry context menu;
- workflow-required depending children with no options;
- server-side application of `default_value_dependencies` for REST, import and mail;
- the `copy_from` enumeration-id remap;
- unifying `query_filter_values`;
- a report of stored invalid combinations and cycles;
- an optional lazily loaded wizard body (UD-13; recommended: not done, the template stays inline).
