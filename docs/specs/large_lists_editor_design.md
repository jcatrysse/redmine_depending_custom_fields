# Admin dependency editor, shared editor component, single JSON transport, CSV import/export (revision 2)

> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 7, 8 (admin side); section 7 fixes the editor contract that point 9 implements. Owner area: editor (payload schema and parser, admin JSON transport, values endpoint and value wire format, shared editor partial, presenter and JS, CSV import/export, editor locale keys). Work packages: WP-21, WP-22, WP-23, WP-24, WP-25, WP-26 (primary, release 0.1.0 (M3)); WP-27 (project page on the shared editor, section 7) and WP-31 (project storage limit on the editor root), both 0.1.0 (M3); prerequisites WP-05 (`DependencyRules.prune_mapping`, `value_keys`, `value_options`, `resolve_parent_for_save`, `parent_of`, 0.1.0 (M1)), WP-11 (`CustomFieldValidationPatch`, `StorageLimits`, 0.1.0 (M1)), WP-16 (`spec/support/dcf_js_fixtures.rb`, 0.1.0 (M2)) and WP-18 (head hook and `ClientConfig`, 0.1.0 (M2)). Decisions: UD-01, UD-15, UD-16, UD-17, UD-18, UD-19, UD-20, UD-22, UD-23.

**Consolidation.** The final completeness critic (gaps 1, 8, 9 and 12, plus the editor parts of gaps 2 to 5 and 14) and the binding contracts of `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts") and section 3 ("Contract rows added during consolidation") are applied inline below. Where the revision 2 text conflicted with them, they win. Release targets follow the work packages: 0.0.16 = WP-01..WP-03 and WP-07, 0.1.0 (M1) = WP-04..WP-06 and WP-08..WP-14, 0.1.0 (M2) = WP-15..WP-20, 0.1.0 (M3) = WP-21..WP-32; everything in this document ships in 0.1.0 (M3). Locale texts live only in `large_lists_i18n_registry.md`; this document names keys, JS keys and owner WPs.

| Topic | Consolidated rule | Sections |
|---|---|---|
| Release | All editor items ship in 0.1.0 (M3) (UD-01; WP-21 to WP-27, WP-31, release WP-32). Project nested params on `update_dependencies` are deprecated in 0.1.0 (accepted throughout 0.1.x) and removable no earlier than 0.2.0. | 7, 14, 15 |
| Failed-save re-render (gap 1) | Hidden input always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; no `data-dcf-editor-echo`, no `input_value`. Project: `posted: service.parsed_payload` passed to `DependencyEditorConfig.for_project`. Tests in WP-22, WP-25 and WP-27. | 3.4, 5.2, 5.3, 7, 11, 13 |
| Callback registration | The transport callbacks live in the single `Patches::CustomFieldValidationPatch` created by WP-11 (compat section 2.4), registered before the storage validation; there is no separate `CustomFieldDependenciesTransportPatch` module. | 1, 3.1, 10, 13 |
| Storage attributes | `StorageLimits.column_limit(column, model = CustomField)`, `StorageLimits.base_bytes(field)`, new `data-dcf-editor-storage-warn` (`StorageLimits::WARN_PERCENT`, 90); one client key `text_dcf_storage_estimate` (owner WP-24). Project mode uses `ProjectStoragePolicy.format_store_limit(field)` (WP-31, UD-22). | 5.3, 5.9, 8, 9 |
| Value options (gap 3) | `DependencyRules.value_options` returns `[key, label, active]` tuples, consumed as `\|key, label, active\|`; the wire shape comes only from `DependencyEditorConfig.wire_values`; `test/js/fixtures/value_options.json` is written from it (WP-24). | 4.1, 4.2 |
| Key ownership (gap 8) | Every editor key has one owner WP (section 9): WP-22 model errors; WP-24 `text_dcf_editor_help`, `text_dcf_editor_noscript`, `text_dcf_editor_select_parent`, `text_dcf_storage_estimate`; WP-25 `error_invalid_dependency_payload`, `error_dcf_dependencies_too_large_to_send` and the other editor keys; WP-26 import/export keys; WP-28 `text_dcf_no_matches` unless WP-25 landed it. `DependencyEditorConfig::I18N` is created by WP-24 with only WP-24's keys; WP-25 and WP-26 extend it in the same commit as their locale entries. | 7, 9 |
| Locale texts (gap 9) | en, de, fr and nl texts only in `large_lists_i18n_registry.md` (with the UX-16 corrections and de „…“ / fr « … » quotes). English strings quoted elsewhere in this document are illustrative; the registry wins. | 9 |
| Tests added (gap 12) | Same-origin check before fetching `data-dcf-editor-values-url` with a jsdom test (WP-25); `test/js/dependency_editor_storage.test.js` (WP-25); jsdom assertion that "Add missing child values" is not rendered on the project fixture or for enumeration children (WP-26). | 5.6, 5.9, 6.5, 13 |
| Fixture ids | Per-kind fixed ranges from WP-02 through `spec/support/dcf_js_fixtures.rb` (WP-16, owner quality); the 1.9e9 id base of revision 2 is superseded. | 8 |

Scope: points 7 and 8 (admin side), the shared editor that point 9 reuses on the project page, and the single owner of the cross-area contracts listed in section 8: the payload schema and parser, the editor DOM contract, the value wire format and the editor locale key list (key names, JS keys and owner WPs; the texts are in `large_lists_i18n_registry.md`). The plugin repo is read-only for this design. Scratchpad root `$S` = `<planning scratch space, not part of the repository>`. Revision 1 prototypes are in `$S/design/admin_editor/proto/`; revision 2 prototypes and probes are in `$S/design/admin_editor/rev/`.

## 0. Evidence

### 0.1 Prototypes (all green)
- `proto/dependency_payload.rb` + test (revision 1): parse, prune, digest.
- `rev/dependency_payload.rb` + `rev/dependency_payload_test.rb` (revision 2, the unified parser of section 2): 11 runs, 0 failures on Ruby 3.3.6 (44 assertions) and Ruby 3.2.6 (42 assertions), json 2.21.2. RuboCop 1.88.2 `Lint/Syntax` at `TargetRubyVersion: 2.7`: no offenses.
- `proto/dcf_dependency_editor_model.js` + `model.test.js` and `proto/dcf_dependency_editor.js` + `editor.test.js` (revision 1): 29 pass under jsdom 29.1.1, Node 22.22.0.
- `rev/proto2/` (revision 1 JS plus the null-prototype serialize fix of QA-11 and a new test): 30 pass, 0 fail (`NODE_PATH=$S/design/probe/node_modules node --test model.test.js editor.test.js proto_fix.test.js`). Tests compare payloads through a `JSON.parse(JSON.stringify(...))` helper because null-prototype objects are not `deepStrictEqual` to object literals.

### 0.2 Probes run for this revision
| Probe | Result |
|---|---|
| `rev/proto_serialize.js` | Confirms QA-11: revision 1 `serialize()` drops a parent key `__proto__` and its default (`{"value_dependencies":{"constructor":["b"],"Belgium":["a"]},"default_value_dependencies":{}}`). |
| `rev/proto_key.js` | `JSON.stringify` keeps `__proto__` on an `Object.create(null)` dictionary and on `Object.defineProperty` keys; `JSON.parse` creates `__proto__` as an own property. |
| `rev/prescan*.rb` | Two-stage string-aware digit scan (`/\d{20}/` then `/"[^"\\]*(?:\\.[^"\\]*)*"\|\d{20}/m`, the `\|` being the regex alternation escaped for the table): 4 MB adversarial payloads 0.11-0.19 s, a 1,000,000-digit literal rejected in under 1 ms, digits inside strings never flagged. Parse of a 3,966,709-byte payload with 100,000 keys including the scan: 0.41-0.61 s. |
| `rev/rack_admin_probe.rb` | Admin-shaped PUT (`_method=put`, 40 role ids, JSON): JSON 2,025,234 B is 3,377,263 B urlencoded (1.67x) and passes; JSON 3,015,234 B is 5,027,263 B urlencoded and raises `Rack::QueryParser::QueryLimitError`, while the same form as multipart (3,019,441 B) arrives as PUT with the JSON intact. Same on rack 3.2.7 and rack 2.2.24. |
| `design/project/rack_probe.out` | With `_method=patch`, a 6 MB urlencoded body is downgraded to POST (route 404) on rack 3.2.7 and 2.2.24; multipart stays PATCH. |

### 0.3 Rack limits (verified in the installed gems)
- Urlencoded body: `BYTESIZE_LIMIT` 4,194,304 (rack-3.2.7 `lib/rack/query_parser.rb:54`, rack-2.2.24 `:48`). Params: 4,096 (rack-3.2.7 `:57`).
- Multipart non-file buffer: `BUFFERED_UPLOAD_BYTESIZE_LIMIT` 16 MiB (rack-3.2.7 `lib/rack/multipart/parser.rb:80`, rack-2.2.24 `:45`). Total parts: `multipart_total_part_limit` 4,096 (rack-3.2.7 `lib/rack/utils.rb:80`, rack-2.2.24 `:78`), the same order as the params limit, and the editor adds exactly one part.
- All are overridable by `RACK_*` environment variables; the editor uses the defaults and documents that.

### 0.4 Core facts relied on
- **Form placement.** The format partial renders inside `.box.tabular` of `.splitcontentleft` (core-5.1/7.0 `app/views/custom_fields/_form.html.erb:3-19`). The edit form is `labelled_form_for ... :html => {:method => :put, :id => 'custom_field_form'}` with no multipart, identical in 5.1, 6.0, 6.1 and 7.0 (`app/views/custom_fields/edit.html.erb:3`).
- **Tabular CSS.** `.tabular p` has a 180px start padding (core-7.0 `application.css:1305-1311`) and beats `.nodata, .warning` (`padding-inline: 30px 4px`, `:1513-1517`) on specificity; `.tabular label` floats bold at -180px (`:1320-1329`).
- **/new format switch.** `$('#custom_field_field_format').change(...)` is a jQuery handler bound on the element that serializes the whole form into a GET (core-7.0 `app/views/custom_fields/new.html.erb:9-17`).
- **Helpers.** `include_all_helpers = false` (core-7.0 `config/application.rb:73`): plugin helpers are not available in core views, hence a plain Ruby presenter.
- **Mass assignment.** `safe_attributes=` assigns only present keys through public setters (core-5.1 `lib/redmine/safe_attributes.rb:84-91`). jc-redmine_extended_api writes custom fields through `custom_field.safe_attributes = attributes` (`$S/research/jc-redmine_extended_api/lib/redmine_extended_api/patches/custom_fields_controller_patch.rb`, `assign_filtered_attributes`).
- **Callback order.** `before_validation`, then `validate` (including `validate_custom_field`), then `before_save` / `before_custom_field_save` (core-7.0 `app/models/custom_field.rb:38-48`).
- **possible_values.** `possible_values=` splits on `/[\n\r]+/`, strips each value, drops blanks, does not dedupe (core-5.1 `app/models/custom_field.rb:193-200`).
- **Error labels.** `human_attribute_name` resolves `field_<attr>` (core-5.1 `config/initializers/10-patches.rb:6-13`, `ApplicationRecord` in 6.x/7.0).
- **Unsaved-changes warning.** Core `warnLeavingUnsaved` tracks textareas through `window.onbeforeunload` (core-7.0 `application-legacy.js:1058-1075`) unless `pref.warn_on_leaving_unsaved == '0'` (core-7.0 `application_helper.rb:1810-1818`).
- **Icons.** `sprite_icon` and `notice_icon` exist in 6.0, 6.1, 7.0 (`app/helpers/icons_helper.rb`), not in 5.1. `createSVGIcon(icon)` exists in 6.1 and 7.0 (`application-legacy.js:73`) and clones `#icon-copy-source svg`; it is absent in 5.1 and 6.0. 5.1 `div.flash.warning` uses a background image; 6.0 keeps `:not(:has(svg))` fallbacks.
- **CSV.** `l(:general_csv_separator)` is `,` in en and `;` in de, fr, nl; `general_csv_encoding` is ISO-8859-1 in all four (core-7.0 `config/locales/en.yml:153,155`, `de.yml:405-406`, `fr.yml:167,169`, `nl.yml:295-296`).
- **Reusable CSS.** `.badge.badge-status-locked`, `.hidden-for-sighted`, `.box`, `.nodata`, `.warning`, `div.flash.{error,warning}`, `table.list`, `em.info` exist in 5.1 and 7.0.
- **Reused core locale keys** present in 5.1, 6.0, 6.1 and 7.0: `button_collapse_all`, `button_clear`, `button_export`, `label_preview`, `label_fields_separator`, `label_comma_char`, `label_semi_colon_char`, `general_text_Yes`, `general_text_No`, `field_default_value`, `field_status`, `text_warn_on_leaving_unsaved`.

### 0.5 Plugin facts relied on (at fa0adaf)
- `spec/patches/custom_field_required_validation_spec.rb` builds stand-in classes that define only `def self.after_save(*); end` (lines 32 and 252) and prepend `CustomFieldPatch` (lines 60 and 285). Any `before_validation`/`validate` registered in `CustomFieldPatch.prepended` raises NoMethodError there (limits V11: 14 failures).
- `init.rb:43-53` lists `value_dependencies` and `default_value_dependencies` as safe attributes; the plugin JSON API uses `params.require(:custom_field).permit(...)` plus `update` (`app/controllers/depending_custom_fields_api_controller.rb:61,130`) and never safe_attributes.
- Existing keys reused: `text_dcf_no_default`, `warning_required_child_no_options`, `error_stale_edit`, `notice_dependencies_saved` ("Dependency mapping saved."), whose terminology (de "Abhängigkeitszuordnung", fr "Mappage des dépendances", nl "Afhankelijkheidskoppeling") the editor follows.

## 1. Architecture

```
Admin form (core CustomFieldsController, PUT/POST)          Project page (ProjectCustomFieldConfigurationController, PATCH)
  _depending_list / _depending_enumeration                     edit_dependencies.html.erb (point 9)
        |  render 'depending_custom_fields/dependency_editor', editor: DependencyEditorConfig.for_admin / .for_project
        v
  fieldset.dcf-dep-editor[data-dcf-editor][data-dcf-editor-*] + ONE named hidden input (blank at render)
        |  JS: DcfDependencyEditorModel (pure, UMD) + DcfDependencyEditor (DOM); assets only via the head hook
        v
  custom_field[dependencies_json] (admin, form switched to multipart)   dependencies_json (project, multipart form)
        |                                                                   |
  CustomFieldValidationPatch (WP-11 module, transport callbacks WP-22)  DependencyMappingService#perform!
    before_validation: DependencyPayload.parse (memoized)                 DependencyPayload.parse! (audited, fail closed)
      -> base check -> DependencyRules.prune_mapping (D6)                 strict DependencyRules.mapping_problems
    validate: payload / stale / too-large errors on :value_dependencies   compact delta with source + import
    after_save: reset                                                      |
        |                                                                   |
  value_dependencies / default_value_dependencies (format_store Hash, unchanged storage)
        |
  validate (limits StorageLimits, server cycle check), before_save: sanitize only (BC-02)
```

Live parent change on the admin form uses `GET /dcf_dependency_editor/values?custom_field_id=&type=&kind=` (admin-only, session, no format). The plugin JSON API (`/depending_custom_fields/*.json`) is untouched.

## 2. Payload contract v1 and the single parser (owner: editor area; WP-21, 0.1.0 (M3))

One file, one constant, one spec, used by the admin virtual attribute AND `DependencyMappingService` (resolves R3, QA-02, BC-03, SP-02).

### 2.1 Schema

```json
{
  "version": 1,
  "source": "import",
  "import": {"mode": "replace", "rows": 5570},
  "base": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "value_dependencies": {"Belgium": ["Brussels", "Ghent"], "Foo [x]": ["a]"]},
  "default_value_dependencies": {"Belgium": "Ghent"}
}
```

| key | rule |
|---|---|
| `version` | optional, must be the Integer `1` |
| `source` | optional, `"editor"` (default) or `"import"`. The editor sets `"import"` while an applied import is not undone. Admin ignores it; the project audit delta records it (D7). |
| `import` | optional Object, allowed only with `source: "import"`, exactly the keys `mode` (`"merge"` or `"replace"`) and `rows` (Integer 0..10,000,000). Describes the last applied import. Bounded, so it cannot inflate the audit delta (R10). |
| `base` | optional, 64 lowercase hex characters: `DependencyPayload.digest` of the stored mapping when the page was rendered. Admin lost-update guard (AD-6). The project ignores it (it has `state_hash`); the editor omits it in project mode. |
| `value_dependencies` | optional Object (missing = `{}`). Keys: parent value keys (list value string, or enumeration id as a string). Values: Arrays of String or Integer. |
| `default_value_dependencies` | optional Object (missing = `{}`). Values: String, Integer, or an Array of them. |
| anything else, including `meta` | rejected as `unknown_key` |

Scalars: Strings are kept; Integers are accepted only when `positive?` and `bit_length <= 63` (checked before `to_s`, SP-01) and stringified. Booleans, Floats, `null`, nested Objects or Arrays inside arrays are rejected. Blank keys and values are dropped, duplicates removed keeping order. Storage stays `Hash<String, Array<String>>` / `Hash<String, String|Array<String>>` in format_store.

### 2.2 Parser `lib/redmine_depending_custom_fields/dependency_payload.rb` (prototype `rev/dependency_payload.rb`)

Constants: `VERSION = 1`, `MAX_BYTES = 4 * 1024 * 1024` (both entry points), `MAX_NESTING = 3` (top object, value_dependencies object, array), `MAX_INTEGER_BITS = 63`, `MAX_IMPORT_ROWS = 10_000_000`, `TOP_LEVEL_KEYS`, `IMPORT_KEYS`, `SOURCES`, `IMPORT_MODES`.

```ruby
Result = Struct.new(:value_dependencies, :default_value_dependencies, :source, :import, :base,
                    :error, :bytes, keyword_init: true) do
  def ok?
    error.nil?
  end
end

class Invalid < StandardError        # raised by parse! only
  attr_reader :reason, :bytes        # message: "dependencies_json rejected: <reason> (<bytes> bytes)"
end
```

API:
- `parse(raw)`: returns `nil` when `raw` is nil or a blank String (unchanged), otherwise a `Result` that is `ok?` or carries `error`. Never raises.
- `parse!(raw)`: project entry point. Raises `Invalid(:blank)` when `parse` returns nil and `Invalid(result.error)` when not ok; returns the ok `Result`.
- `digest(vd, dd)`: SHA-256 of canonical JSON (keys sorted, values as sorted strings, blanks and empties dropped). Order-insensitive, HashWithIndifferentAccess safe, nil equals `{}`.
- `stored_digest(cf)`: `digest` of `cf.attribute_in_database('format_store')` values (`{}` for a new record).

Algorithm of `parse` (order matters):
1. nil returns nil; non-String gives `:not_a_string`.
2. A non-UTF-8 String is re-tagged as UTF-8; invalid bytes give `:invalid_json`.
3. Blank returns nil.
4. `bytesize > MAX_BYTES` gives `:too_large`.
5. `long_number?(raw)` gives `:number_too_long` (SP-01): stage 1 `raw.match?(/\d{20}/)` (returns false for almost every real payload), stage 2 `raw.scan(/"[^"\\]*(?:\\.[^"\\]*)*"|\d{20}/m)` returning true on the first token that is not a string. Digits inside strings never match; an unterminated string ending in 20 digits is flagged too (still fail closed). Floats with 20 or more mantissa digits and huge exponents are caught here as well.
6. `JSON.parse(raw, max_nesting: 3, create_additions: false)`; `JSON::ParserError`, `JSON::NestingError` and `EncodingError` give `:invalid_json`.
7. Schema checks in this order: `:not_an_object`, `:unknown_key`, `:unsupported_version`, `:invalid_source`, `:invalid_import`, `:invalid_base`, `:invalid_links`, `:invalid_defaults`.

Error codes are only logged or put into audit summaries as `dependencies_json rejected: <code> (<bytes> bytes)`; payload content never appears in logs, audit rows or flashes (SP-06, SP-09).

Pruning is not in this module: the single implementation is `DependencyRules.prune_mapping` (server area, R18), with this contract required by the admin transport:

```ruby
# parent_keys: ordered keys of the parent (inactive enumerations included) or nil (keep all parent keys)
# child_keys:  ordered keys of the field itself (inactive included)
# multiple:    true or false (the field's multiple?)
# returns [vd, dd]: vd ordered by parent order then child order, unknown keys/values removed;
#   dd keeps only linked values; single field -> first kept value as a String, multiple -> Array
# Required keyword arguments; written out explicitly (Ruby 2.7, no hash shorthand).
DependencyRules.prune_mapping(vd, dd, parent_keys: parent_keys, child_keys: child_keys, multiple: multiple)
```

### 2.3 Performance and DoS budget
- Worst realistic 4 MiB payload (100,000 keys): 0.41-0.61 s including the scan (Ruby 3.2.6 and 3.3.6).
- Adversarial 4 MiB payloads: scan 0.11-0.19 s; a 1,000,000-digit integer is rejected in under 1 ms before `JSON.parse` (which alone would take 0.4 s parse plus 5.3 s `to_s`, `$S/design/secperf/results.txt`).
- The parse result is memoized per request on both paths, so a payload is parsed at most once (SP-17, sections 3.1 and 7).

### 2.4 Error mapping per entry point
| parser outcome | admin (model error on `:value_dependencies`) | project (`OperationError`, audited `validation_failed`) |
|---|---|---|
| nil (absent or blank) | unchanged, no error | `parse!` raises `:blank`: `error_invalid_dependency_payload` (fail closed, never a clear) |
| `:too_large` | `:dcf_dependencies_too_large_to_send` with `size`, `limit` (delimited) | `error_dcf_dependencies_too_large_to_send` with `size`, `limit` |
| any other error | `:dcf_invalid_dependencies_payload` | `error_invalid_dependency_payload` |

`size` and `limit` are integers formatted with `StorageLimits.delimited` (limits area helper), so interpolations never carry user content.

Key owners (gap 8, section 9): the admin model errors are added by WP-22; the flash keys `error_invalid_dependency_payload` and `error_dcf_dependencies_too_large_to_send` are added by WP-25 (the client pre-check uses the latter too) and reused, never redefined, by WP-27. The project design's `error_dcf_dependency_payload_too_large` (`%{max}`) is not created (compat section 2.4, row "Payload-too-large key").

## 3. Admin transport (WP-22, 0.1.0 (M3))

### 3.1 Transport callbacks in the single validation module (R5, BC-13; WP-22)

Consolidated (compat section 2.4, row "CustomField callback registration"): the transport lives in `lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb`, the ONE module `RedmineDependingCustomFields::Patches::CustomFieldValidationPatch` that WP-11 (0.1.0 (M1)) creates and prepends in `init.rb` right after the existing `CustomField.prepend ...CustomFieldPatch` (init.rb:61). WP-22 adds the transport callbacks and methods below to that module, registered before WP-11's storage validation, so the storage check always measures the decoded and pruned mapping. Revision 2's separate `CustomFieldDependenciesTransportPatch` file and the limits area's separate `CustomFieldStoragePatch` are not created. `CustomFieldPatch` gets no new callbacks, so the stand-in classes of `spec/patches/custom_field_required_validation_spec.rb` keep working unchanged (WP-04 rewrites that spec DB-backed anyway). Symbol callbacks are deduplicated if init.rb runs twice (limits V12).

```ruby
# frozen_string_literal: true

module RedmineDependingCustomFields
  module Patches
    # Single registration point for new CustomField callbacks (WP-11).
    # WP-22 adds the transport of the dependency editor
    # (custom_field[dependencies_json]). Kept out of CustomFieldPatch:
    # stand-in classes in specs prepend that patch without ActiveModel callbacks.
    module CustomFieldValidationPatch
      def self.prepended(base)
        base.before_validation :dcf_apply_dependencies_json   # WP-22
        base.validate :dcf_validate_dependencies_json         # WP-22, before the storage check
        base.validate :dcf_validate_storage_limits            # WP-11
        base.after_save :dcf_reset_dependencies_json          # WP-22
      end

      # Write-only virtual attribute (safe attribute 'dependencies_json').
      def dependencies_json=(raw)
        @dcf_dependencies_json = raw
        @dcf_dependencies_error = nil
        @dcf_dependencies_validated = false
      end

      # Submitted input is never echoed (SP-11); the editor re-renders from the
      # in-memory mapping and from dcf_dependencies_conflict.
      def dependencies_json
        nil
      end

      # The posted version when this request's save was refused as stale.
      def dcf_dependencies_conflict
        return nil unless @dcf_dependencies_validated && @dcf_dependencies_error == :dcf_stale_dependencies

        @dcf_dependencies_conflict
      end

      private

      def dcf_dependencies_payload
        raw = @dcf_dependencies_json
        memo = @dcf_dependencies_payload_memo
        return memo[1] if memo && memo[0].equal?(raw)

        result = RedmineDependingCustomFields::DependencyPayload.parse(raw)
        @dcf_dependencies_payload_memo = [raw, result]
        result
      end

      def dcf_apply_dependencies_json
        @dcf_dependencies_error = nil
        @dcf_dependencies_conflict = nil
        @dcf_dependencies_validated = true
        return unless RedmineDependingCustomFields::DependencyRules.depending?(self)

        result = dcf_dependencies_payload
        return if result.nil?

        unless result.ok?
          Rails.logger.warn('[redmine_depending_custom_fields] dependencies_json rejected for custom field ' \
                            "#{id.inspect}: #{result.error} (#{result.bytes} bytes)")
          @dcf_dependencies_error = if result.error == :too_large
                                      :dcf_dependencies_too_large_to_send
                                    else
                                      :dcf_invalid_dependencies_payload
                                    end
          @dcf_dependencies_error_bytes = result.bytes
          return
        end

        if result.base && persisted? &&
           result.base != RedmineDependingCustomFields::DependencyPayload.stored_digest(self)
          @dcf_dependencies_error = :dcf_stale_dependencies
          @dcf_dependencies_conflict = {
            'value_dependencies' => result.value_dependencies,
            'default_value_dependencies' => result.default_value_dependencies,
            'source' => result.source, 'import' => result.import
          }
          return
        end

        rules = RedmineDependingCustomFields::DependencyRules
        parent = rules.resolve_parent_for_save(self)
        vd, dd = rules.prune_mapping(result.value_dependencies, result.default_value_dependencies,
                                     parent_keys: parent ? rules.value_keys(parent) : nil,
                                     child_keys: rules.value_keys(self), multiple: multiple?)
        self.value_dependencies = vd
        self.default_value_dependencies = dd
      end

      def dcf_validate_dependencies_json
        case @dcf_dependencies_error
        when nil
          nil
        when :dcf_dependencies_too_large_to_send
          limits = RedmineDependingCustomFields::StorageLimits
          errors.add(:value_dependencies, :dcf_dependencies_too_large_to_send,
                     size: limits.delimited(@dcf_dependencies_error_bytes),
                     limit: limits.delimited(RedmineDependingCustomFields::DependencyPayload::MAX_BYTES))
        else
          errors.add(:value_dependencies, @dcf_dependencies_error)
        end
      end

      def dcf_reset_dependencies_json
        @dcf_dependencies_json = nil
        @dcf_dependencies_payload_memo = nil
        @dcf_dependencies_validated = false
      end
    end
  end
end
```

Why `before_validation`, not the writer: `parent_custom_field_id`, `possible_values` and `multiple` are assigned by the same `safe_attributes=` call in arbitrary order and are final by then; the JSON deterministically wins over legacy nested params of the same request; StorageLimits (limits area, `validate`) and the cycle check (server area) see the final pruned mapping. The callback is idempotent and memoized (one parse per request even when `valid?` runs twice). `after_save` resets the virtual attribute, so a second `save` of the same instance neither re-applies the payload nor trips the stale guard (SP-11).

Errors are attached to `:value_dependencies`, whose label `field_value_dependencies` ("Dependency mapping", owned by the limits area) reads correctly with singular verbs in all four languages (UX-03). No `field_dependencies_json` key exists.

### 3.2 Safe attributes and API
- `init.rb` adds `'dependencies_json'` to `CustomField.safe_attributes(...)` (WP-22; spec: `CustomField.safe_attribute_names` includes `value_dependencies`, `default_value_dependencies` and `dependencies_json`, BC-04).
- `'value_dependencies'` and `'default_value_dependencies'` stay safe attributes PERMANENTLY (UD-15). Deviation from D5 with a concrete reason: jc-redmine_extended_api assigns custom field attributes through `safe_attributes=` (evidence in 0.4); removing them would silently ignore its clients' mappings. The admin form simply stops posting them.
- The plugin JSON API permits Hashes and calls `update`; `dependencies_json` is not permitted there, so the API contract is unchanged. A spec pins that a posted `dependencies_json` is ignored by the API.

### 3.3 Pruning (D6), only on the JSON path (BC-02)
| item | kept when | ordering |
|---|---|---|
| parent key | a valid parent resolves AND the key is in `value_keys(parent)`, inactive enumerations included. No valid parent (blank, wrong family, deleted): keys kept as submitted; before_save sets the parent to nil as today (D9). | parent value order |
| child value | in `value_keys(self)`, inactive included (new depending_enumeration: empty, so all pruned) | child value order |
| default | key still has links and the value is among them | single: first kept value as String; multiple: Array |

Requirement on the server and limits areas (BC-02): `before_custom_field_save` and `storage_preview` stay sanitize-only, exactly as today. D6 pruning happens only here, when `dependencies_json` was posted. API saves, extended-API saves, project-service saves (including rename and remove cascades) and untouched admin saves never prune. Specs in section 13 pin this.

### 3.4 Interplay on the admin form
- **Absent versus `{}`.** The editor posts `''` until dirty (a tick, a default, an import, a conflict choice, or a parent change). Unrelated saves never rewrite the mapping. A "nothing linked" state is serialized with empty objects, so unticking everything clears (research_admin fact 10).
- **Malformed or oversize payload.** Form re-rendered with the error; the DB is unchanged; the hidden input re-renders blank. The client pre-check (5.9) makes the oversize case unreachable for honest clients.
- **Failed save for another reason** (name blank, StorageLimits `dcf_storage_too_large`, cycle). The in-memory record already holds the pruned posted mapping, so the presenter renders it with `data-dcf-editor-dirty="1"` (digest differs from stored) and the editor starts dirty: resubmitting carries the mapping. No raw echo exists.
- **Failed-save re-render rule (binding on both pages, compat section 3, gap 1).** The hidden input is always rendered blank; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`. There is no `data-dcf-editor-echo` attribute and no `input_value` option (quality P2's echo variant and the project design's raw `input_value:` echo are superseded). Admin: the payload is the in-memory record after the transport applied it. Project: `posted: service.parsed_payload` passed to `DependencyEditorConfig.for_project` (section 7). The failed-save tests of WP-22, WP-25 and WP-27 assert: mapping attribute holds the posted mapping, dirty is `1`, hidden input blank.
- **Lost-update guard (AD-6, UD-17) and conflict (UX-09).** If the stored mapping changed after render (another admin, a project-level save, a cascade, the API), the save is refused with `dcf_stale_dependencies`, nothing is applied, and the editor shows the current version plus a conflict panel built from `dcf_dependencies_conflict` (5.8). The same panel is used on a project 409 (section 7), so both pages behave the same.
- **default_value.** Server rule unchanged (nil when a valid parent exists). The partials always render the core default_value control inside `<p data-dcf-default-value-row>`, hidden with `dcf-hidden` while a parent is set; the editor toggles it live.
- **Required warning.** Server-rendered from the in-memory record (`is_required?`, a parent, an active parent value without links); kept live by JS from the links and `#custom_field_is_required`.
- **New field.** depending_list: full editor on /new (children from the textarea, parent fetched). depending_enumeration: "Save this field and add its values before linking them."; hidden input stays `''`.
- **Parent changed in the form.** Fetch, rebuild, notice with the dropped count, dirty; server prunes against the new parent anyway. Fetch failure: error notice, state posted with old keys, server prunes. Parent cleared: hidden `''`, stored mapping stays inert. Without JS: today's behavior (old keys stored under the new parent), documented.
- **Enumeration children edited on the core values page.** Values come from the DB at render; hint "Reload this page after changing them."; server pruning uses the DB at save.
- **Copy.** depending_list: copied mapping shown, dirty, posted and pruned. depending_enumeration: copied ids point at the source field (no remap, D6 out of scope); shown as orphans; removed at the first dirty editor save of the copy.
- **Legacy nested params.** Still assigned through safe_attributes; when both arrive, the JSON wins.
- **Non-depending formats.** `dependencies_json` is ignored entirely.
- **GET /custom_fields/new?custom_field[dependencies_json]=...** The writer stores it, validation never runs, nothing is applied or rendered (SP-11).

## 4. Values endpoint and the value wire format (R7; WP-24, 0.1.0 (M3))

### 4.1 Wire format (one shape everywhere)
Ruby side: `DependencyRules.value_options(cf)` (server area) returns ordered tuples `[[key, label, active], ...]` (list: possible_values order, label = key, active = true; enumeration: all enumerations by position, inactive included). One function turns them into the wire format, used by the endpoint and by both presenter modes:

```ruby
# DependencyEditorConfig.wire_values(options) -> [{'key' => '11', 'label' => 'Red'}, {'key' => '12', 'label' => 'Old', 'active' => false}]
def self.wire_values(options)
  options.map do |key, label, active|
    entry = { 'key' => key.to_s }
    entry['label'] = label.to_s unless label.to_s == key.to_s
    entry['active'] = false if active == false
    entry
  end
end
```

JS decode rule (model `ValueList.fromWire`): `label = Object.prototype.hasOwnProperty.call(o, 'label') ? String(o.label) : String(o.key)`, `active = o.active !== false`. Compact: a 5,570-value list saves about 200 KB versus always emitting all three keys. The project area's `DependencyEditorData` presenter is dropped; its label lookups use `value_options`.

Consolidated (gap 3, compat section 3, row "value_options"): Ruby consumers (WP-27 labels and delta, WP-28 `ValuesPage` rows) consume `value_options` as `|key, label, active|` tuples; there is no hash-shaped contract and no `spec/lib/dcf_value_options_contract_spec.rb`. Quality P8's full-triple wire shape is superseded by the compact shape above. `test/js/fixtures/value_options.json` is written from `DependencyEditorConfig.wire_values` (WP-24), never directly from `value_options`.

### 4.2 Endpoint (admin only)
- Route: `get 'dcf_dependency_editor/values', to: 'dcf_dependency_editor#values', as: 'dcf_dependency_editor_values'` (prefix cannot be shadowed by `depending_custom_fields/:id`).
- `app/controllers/dcf_dependency_editor_controller.rb`: `before_action :require_admin`; `KIND_FORMATS = {'list' => %w[list depending_list], 'enumeration' => %w[enumeration depending_enumeration]}`; 404 JSON `{"error":"not_found"}` unless the field exists, its format is in the kind's family and `cf.type == params[:type]`.
- Response: `{"id":6,"name":"Region","kind":"enumeration","values":[{"key":"11","label":"North"},{"key":"12","label":"Old","active":false}]}` with `values` from `wire_values`.
- No `accept_api_auth`, no `.json`: `api_request?` is false and the session is used; non-admins 403, anonymous XHR 401.
- Contract spec: for the same field, the endpoint's `values` equals the presenter's `data-dcf-editor-parent-values` and the committed `test/js/fixtures/value_options.json` (endpoint == presenter == fixture, WP-24).
- The client fetches this URL only after the same-origin check of 5.6 (SP-15).

## 5. Shared editor component (single owner of the editor DOM contract: R4, QA-03, UX-01; WP-23 model, WP-24 partial and presenter, WP-25 DOM layer and CSS, 0.1.0 (M3))

### 5.1 Files
| File | Purpose |
|---|---|
| `app/views/depending_custom_fields/_dependency_editor.html.erb` | the ONLY editor partial, both pages (WP-24) |
| `lib/redmine_depending_custom_fields/dependency_editor_config.rb` | the ONLY presenter: `for_admin(field, view)`, `for_project(field:, parent:, view:, posted: nil, conflict: nil)`, `wire_values`, `I18N` map, limits constants (WP-24; `I18N` extended by WP-25 and WP-26, project storage limit by WP-31) |
| `assets/javascripts/dcf_dependency_editor_model.js` | pure UMD (`module.exports` / `window.DcfDependencyEditorModel`) (WP-23; import/export additions WP-26) |
| `assets/javascripts/dcf_dependency_editor.js` | DOM layer, IIFE, `window.DcfDependencyEditor = {init(root), get(root)}` (WP-25; panels WP-26) |
| `assets/stylesheets/dcf_dependency_editor.css` | editor CSS (5.12) (WP-25) |

Assets are included ONLY by the head hook (R2, R4, BC-13): the server area's `ClientConfig.editor_page?(controller)` (class name string `CustomFieldsController` or `ProjectCustomFieldConfigurationController`) and `ClientConfig.editor_asset_tags(view)`, which returns, in this order, `javascript_include_tag('dcf_dependency_editor_model', plugin: 'redmine_depending_custom_fields')`, `javascript_include_tag('dcf_dependency_editor', plugin: ...)`, `stylesheet_link_tag('dcf_dependency_editor', plugin: ...)`. Project views must not include them through `content_for` (they may include `dcf_config.css`). The editor script has a load guard against double inclusion. JS language level ES2017.

### 5.2 Partial markup

```erb
<%= content_tag :fieldset, class: 'dcf-dep-editor', data: editor.data_attributes do %>
  <legend><%= l(:field_value_dependencies) %></legend>
  <%= hidden_field_tag editor.input_name, '', id: editor.input_id, autocomplete: 'off',
                       data: { dcf_editor_input: 1 } %>
  <p class="dcf-dep-editor__help"><em class="info"><%= l(:text_dcf_editor_help) %></em></p>
  <noscript><p class="warning"><%= l(:text_dcf_editor_noscript) %></p></noscript>
  <p class="dcf-dep-editor__placeholder<%= ' dcf-hidden' if editor.parent %>" data-dcf-editor-placeholder><em class="info"><%= l(:text_dcf_editor_select_parent) %></em></p>
  <p class="dcf-dep-editor__required<%= ' dcf-hidden' unless editor.required_warning? %>" data-dcf-editor-required-warning><%= editor.required_warning_html %></p>
  <div class="dcf-dep-editor__app" data-dcf-editor-app hidden></div>
<% end %>
```

- The hidden input is the ONLY named element of the editor and ALWAYS renders blank, also on a failed-save re-render on both pages (gap 1): the partial has no `input_value` option and the root never carries `data-dcf-editor-echo`. Initial state never comes from it (R4).
- The three server-rendered texts of the partial (`text_dcf_editor_help`, `text_dcf_editor_noscript`, `text_dcf_editor_select_parent`) are owned by WP-24, which adds the partial (section 9).
- `required_warning_html`: `view.content_tag(:span, view.respond_to?(:sprite_icon) ? view.sprite_icon('warning', text) : text, class: 'icon icon-warning')` (UX-10; 5.1 uses the class background).
- Names: admin `custom_field[dependencies_json]` / `custom_field_dependencies_json`; project `dependencies_json` / `dcf_dependencies_json`.
- Rails JSON-encodes and HTML-escapes Hash and Array `data:` values; nil values are omitted (Rails 6.1 to 8.1).

Admin partials (UX-11 order):
- `_depending_list.html.erb`: textarea; `<p data-dcf-default-value-row class="(dcf-hidden if parent)">` default value; url_pattern; parent select (server's `parent_candidates`) plus cycle warning; hide_when_disabled; edit_tag_style; then the editor (`DependencyEditorConfig.for_admin(@custom_field, self)`).
- `_depending_enumeration.html.erb`: same order.
- `_dependencies_matrix.html.erb` and `_default_dependencies.html.erb`: deleted.

### 5.3 Root data attributes (exact names, `data-dcf-editor-*` namespace only)
| attribute | value | when |
|---|---|---|
| `data-dcf-editor` | `1` (discovery selector `[data-dcf-editor]`) | always |
| `data-dcf-editor-mode` | `admin` / `project` | always |
| `data-dcf-editor-kind` | `list` / `enumeration` (child family) | always |
| `data-dcf-editor-field-id` | child id | persisted |
| `data-dcf-editor-field-type` | e.g. `IssueCustomField` | always |
| `data-dcf-editor-field-name` | child name (export header) | always |
| `data-dcf-editor-parent-id`, `data-dcf-editor-parent-name` | resolved valid parent | when a parent resolves |
| `data-dcf-editor-parent-values` | wire values (4.1) | when a parent resolves, else `[]` |
| `data-dcf-editor-child-values` | wire values | omitted for admin + list (textarea is the source); always present otherwise |
| `data-dcf-editor-mapping` | `{"value_dependencies":{...},"default_value_dependencies":{...}}`, sanitized, unpruned (orphans visible to the client). Admin: the in-memory record (on a failed save: the posted mapping as applied by the transport). Project: the posted ok Result on a 422 re-render (`posted: service.parsed_payload`), else the stored mapping. | always |
| `data-dcf-editor-dirty` | `1` when the rendered mapping differs from the stored one (digest compare): failed-save re-render (both pages, gap 1), admin copy or nested GET params | only when true |
| `data-dcf-editor-conflict-mapping` | `{"value_dependencies":...,"default_value_dependencies":...,"source":"import","import":{...}}`: the user's refused version | admin stale save; project 409 |
| `data-dcf-editor-base` | `DependencyPayload.stored_digest(field)` | admin, persisted |
| `data-dcf-editor-multiple`, `data-dcf-editor-required` | `0` / `1` | always |
| `data-dcf-editor-values-url` | `dcf_dependency_editor_values_path` (relative_url_root aware; fetched only after the same-origin check of 5.6) | admin |
| `data-dcf-editor-parent-source` | `#custom_field_parent_custom_field_id` | admin |
| `data-dcf-editor-values-source` | `#custom_field_possible_values` | admin + list |
| `data-dcf-editor-multiple-source` | `#custom_field_multiple` | admin |
| `data-dcf-editor-required-source` | `#custom_field_is_required` | admin |
| `data-dcf-editor-format-source` | `#custom_field_field_format` | admin |
| `data-dcf-editor-default-value-row` | `[data-dcf-default-value-row]` | admin |
| `data-dcf-editor-allow-add-values` | `1` | admin + list |
| `data-dcf-editor-always-submit` | `1` | project |
| `data-dcf-editor-max-payload-bytes` | `DependencyPayload::MAX_BYTES` (4,194,304) | always |
| `data-dcf-editor-max-form-bytes` | `{"multipart":16252928,"urlencoded":4128768}` (Rack defaults minus margins, `DependencyEditorConfig::MAX_FORM_BYTES`) | always |
| `data-dcf-editor-csv-separator`, `data-dcf-editor-csv-encoding` | `l(:general_csv_separator)`, `l(:general_csv_encoding)` | always |
| `data-dcf-editor-storage-limit` | admin: `StorageLimits.column_limit('format_store')` (signature `column_limit(column, model = CustomField)`, compat section 2.4); project: `ProjectStoragePolicy.format_store_limit(field)`, the effective limit including the project storage ceiling (WP-31, UD-22) | only when not nil (admin: MySQL) |
| `data-dcf-editor-storage-base` | `StorageLimits.base_bytes(field)` = `serialized_bytesize(CustomField, 'format_store', store without the two mapping keys)` | with storage-limit |
| `data-dcf-editor-values-limit` | `StorageLimits.column_limit('possible_values')` | admin + list, when not nil |
| `data-dcf-editor-storage-warn` | `StorageLimits::WARN_PERCENT` (90) | with any storage or values limit |
| `data-dcf-editor-warn-unsaved` | `1` unless `User.current.pref.warn_on_leaving_unsaved == '0'` | always |
| `data-dcf-editor-i18n` | JSON `{jsKey: translated}` from `DependencyEditorConfig::I18N` (created by WP-24, extended by WP-25 and WP-26; never named `I18N_KEYS`) | always |

Inner markers: `data-dcf-editor-input`, `-placeholder`, `-required-warning`, `-app`; the project Save button carries `data-dcf-editor-submit`. None match the issue-form runtime's `[data-dcf-parent]` or its `data-dcf-*` attributes (UX-01: the project's former `data-dcf-parent-values` is gone).

The storage attributes replace the limits area's `data-dcf-storage-limit`, `data-dcf-storage-base` and `data-dcf-values-limit` names (R20: one attribute set, editor namespace). The attribute set matches limits design 4.10 (including `data-dcf-editor-storage-warn`); WP-24 renders them, WP-31 switches the project mode to the effective limit (spec: `for_project` storage limit equals `ProjectStoragePolicy.format_store_limit(field)`).

### 5.4 Lifecycle
1. **Bootstrap.** On `DOMContentLoaded` (or immediately) `init(document)`; a MutationObserver on `document.body` (childList, subtree) inits added nodes that are or contain `[data-dcf-editor]` (the /new AJAX re-render). A WeakMap keeps one instance per root. A missing model module logs `console.warn` once and the editor stays inert.
2. **Fail closed on bad data (QA-24).** Every JSON data attribute is parsed inside try/catch and shape-checked (objects, arrays of `{key}`). On any failure the editor stays inert, shows `text_dcf_editor_unavailable` as `div.flash.error[role=alert]` inside the root, never writes the hidden input, never enables `[data-dcf-editor-submit]`, never switches the form encoding.
3. **Read live form state** (back/forward restores controls): children from the textarea (admin list), `multiple` and `required` from the checkboxes; a parent select value different from `data-dcf-editor-parent-id` triggers a parent change immediately.
4. **Initial state** = `data-dcf-editor-mapping`; dirty = `data-dcf-editor-dirty == "1"`. When dirty (admin) or always (project), the payload is written immediately.
5. **After successful init.** Admin: `form.enctype = 'multipart/form-data'` (AD-19, UD-16). Project: enable every `[data-dcf-editor-submit]` in the form (AD-25, UD-16). Conflict panel when `data-dcf-editor-conflict-mapping` is present.
6. **Delegated listeners on the root:** `click`, `change`, `input` (filters, 150 ms debounce), `keydown` (Enter in text/search inputs is prevented; Escape clears a non-empty filter), `toggle` in the capture phase.
7. **Listeners outside the root:** `change` on the parent source; `input` on the values source (300 ms debounce); `change` on the multiple and required sources; form `submit` (flush, then size pre-check 5.9); one `beforeunload`; a CAPTURE-phase `change` listener on `document` for the format source (5.10).

### 5.5 Client state and serialization
- `ValueList`: items `{key,label,active,index,folded}`, `byKey` Map, exact and NFC case-key Maps for import; duplicate keys ignored.
- `State` is a superset: `links: Map<parentKey, Set<childKey>>`, `defaults: Map<parentKey, childKey[]>`, keys unknown to the current lists kept (textarea edits never lose links). Unlinking a child removes it from that key's defaults.
- **No plain object keyed by user values anywhere (QA-11).** Lookups use `Map`/`Set`; JSON output dictionaries are built with `Object.create(null)` and `Object.defineProperty` (`put(obj, key, value)`), so `__proto__`, `constructor`, `toString` and `hasOwnProperty` survive (verified in `rev/proto2`). The same rule is required of the issue-form runtime and rules module.
- `serialize(state, parents|null, children, {multiple, base, importMeta})`: intersects with current lists; parent order then child order; default shape by `multiple`; adds `version`, `source`, `import` (only when source is import) and `base` (admin). `parents == null` (fetch failed) keeps all parent keys.
- Hidden input: admin `dirty ? JSON : ''`; project always JSON. Written 150 ms after a change and synchronously on submit after flushing pending debounces.

### 5.6 UI built by JS (inside `[data-dcf-editor-app]`)

```
div.dcf-dep-editor__notices                          (div.flash.warning / div.flash.error; errors role=alert; SVG icon on 6.1/7.0)
div.dcf-dep-editor__conflict (5.8, only on conflict)
div.dcf-dep-editor__toolbar
  label "Filter parent values" input[type=search][data-dcf-ed-parent-filter]
  label input[type=checkbox][data-dcf-ed-only-unlinked] "Only parent values without links"
  button[type=button][data-dcf-ed-collapse-all] "Collapse all"
p.dcf-dep-editor__status                             (visible counters, not live)
p.hidden-for-sighted[role=status][aria-live=polite]  (the single live region)
div.dcf-dep-editor__sections
  details.dcf-dep-section[data-dcf-ed-section=<parentKey>]
    summary: span.dcf-dep-section__label, [span.badge.badge-status-locked "inactive"],
             span.dcf-dep-section__counts "2 of 5 linked" (--none modifier when 0),
             [span.dcf-dep-section__default "Default: Ghent"]
    div.dcf-dep-section__body   (only while open)
      div.dcf-dep-section__tools
        label "Filter child values" input[type=search][data-dcf-ed-child-filter]
        label "Show" select[data-dcf-ed-child-view] all | linked | not_linked | unlinked
        button[data-dcf-ed-check-shown] "Check all shown (N)"
        button[data-dcf-ed-uncheck-shown] "Uncheck all shown (N)"
      p.dcf-dep-section__default-row
        label "Default value" select[data-dcf-ed-default] ("(no default)" + linked children; multiple: select[multiple][size=5])
        [button[data-dcf-ed-clear-default] "Clear"]   (multiple only)
      ul.dcf-dep-section__rows > li > label > input[type=checkbox][data-dcf-ed-child-key=<key>] + text [+ inactive badge]
      [button[data-dcf-ed-more-rows] "Show more (N remaining)"]
button[data-dcf-ed-more-sections] "Show more (N remaining)"
details.dcf-dep-editor__unlinked > summary "Child values not linked to any parent value (N)" + ul (first 200, rendered on open)
details.dcf-dep-editor__panel.dcf-dep-editor__import  (section 6)
details.dcf-dep-editor__panel.dcf-dep-editor__export  (section 6)
```

Text only through `textContent`, `setAttribute`, `createTextNode` (never `innerHTML`). No ids derived from values; labels wrap their controls. JS notices: `div.flash.<type>`, with `createSVGIcon('warning')` prepended only when `typeof createSVGIcon === 'function'` and `document.querySelector('#icon-copy-source svg')` exists (6.1, 7.0); 5.1 and 6.0 rely on the class background (UX-10). Empty states use the editor's own keys on both pages (`text_dcf_editor_no_parent_values`, `text_dcf_editor_no_child_values`), shown as `p > em.info`.

Behaviors:
- **Lazy rendering (UD-20).** At most 100 section summaries at once ("Show more" adds 100); a body is built on `toggle` open (guarded against a double build) and removed on close; rows render 200 at a time; "Show more" moves focus to the first new checkbox.
- **Search.** `fold(s)`: NFKD, combining marks stripped, special letters mapped (ß ss, æ ae, œ oe, ø o, đ d, ł l, ı i, þ th), lowercase, whitespace collapsed; tokens must all be contained; folded labels cached.
- **Filters.** Parent filter AND "only parent values without links"; per section child filter AND view (`all`, `linked`, `not_linked`, `unlinked` = not linked to any current parent value).
- **Check/uncheck all shown** acts on all matches including rows not yet rendered; the label shows the count.
- **Counters** (Intl.NumberFormat with `<html lang>`): section "linked/total"; status line: parent values shown/total, parent values without links, child values not linked anywhere.
- **Orphans.** Stored links to values that no longer exist are counted at init: notice `text_dcf_editor_orphans`; `data-dcf-ed-orphans` set for tests. Same on both pages (UX-01).
- **Per-parent default.** Single: "(no default)" plus linked children; multiple: multi-select plus "Clear"; rebuilt on link changes; disabled when nothing is linked; summary shows it while closed.
- **Same-origin check before the values fetch (SP-15, gap 12; WP-25).** Before any request the editor resolves `data-dcf-editor-values-url` with `new URL(url, document.baseURI)` and fetches only when the resolved `origin` equals `window.location.origin` (session cookies are never sent elsewhere). A cross-origin or unparsable URL issues no request and is handled exactly like a fetch failure: `error_dcf_editor_load_failed` notice (role=alert), state posted with the old keys, server prunes. jsdom test in `test/js/dcf_dependency_editor.test.js`: with a cross-origin URL no fetch is made and the `load_failed` notice is shown.
- **Live updates (admin).** Parent select: fetch (after the same-origin check) with a request token (stale responses ignored), `aria-busy`, rebuild, dirty. Notices are derived state recomputed on every parent change: the "parent changed" notice shows only while the current parent differs from the rendered parent, with the dropped count against the current lists (UX-11). Fetch failure: `error_dcf_editor_load_failed` (role=alert), unpruned post. Blank parent: placeholder, hidden `''`, state kept. Textarea (300 ms): rebuild children, re-render, rewrite payload if dirty. `multiple`: re-render default controls, dirty. `is_required`: required warning. Default value row hidden while a parent is selected.

### 5.7 Unsaved changes
One `beforeunload` listener warns only when dirty, not submitting, `data-dcf-editor-warn-unsaved="1"` and the root is still connected; text `text_warn_on_leaving_unsaved` (core). An untouched project page is not dirty (no prompt), because initial state comes from the data attribute (R4, QA-03).

### 5.8 Conflict panel (UX-09; admin stale save and project 409)
Rendered when `data-dcf-editor-conflict-mapping` is present. The editor shows the CURRENT version (fresh mapping, fresh `base` or fresh `state_hash`), not dirty, plus:

```
div.dcf-dep-editor__conflict.flash.warning[role=alert]
  p  text_dcf_editor_conflict (%{only_mine}, %{only_current}: link pairs present only in one version, current lists)
  p  button "Use my version" | button "Keep the current version" | button "Export my version (CSV)"
```

- "Use my version": state = the conflict mapping (superset), `source`/`import` taken from it, dirty; notice `text_dcf_editor_conflict_mine_loaded`. Saving then replaces the current version deliberately, against the fresh base.
- "Keep the current version": closes the panel, state unchanged.
- "Export my version (CSV)": `buildCsv` over the conflict mapping, so the posted state is never lost.
- A three-way "re-apply my changes" merge is not offered: the original base mapping is not available after the refused submit. Posting a client-side delta to enable it is listed as a follow-up and a user decision (UD-17).

### 5.9 Size pre-check before submit (QA-10, SP-02, SP-13)
On `submit`, after the flush:
1. `payloadBytes = utf8(hidden value)` (TextEncoder). Above `max-payload-bytes`: block (`preventDefault`), `div.flash.error[role=alert]` with `error_dcf_dependencies_too_large_to_send` (`size`, `limit`), focus it.
2. Form estimate for the encoding the form actually uses (`form.enctype` read at submit), over all successful named controls (`form.elements`, enabled, checked checkboxes/radios, selected options): multipart `sum(utf8(name) + utf8(value) + 100)`; urlencoded `sum(encodeURIComponent(name).length + encodeURIComponent(value).length + 2)`. Above the matching entry of `max-form-bytes`: block with `error_dcf_editor_form_too_large`.
3. Same code on both pages (the project form is multipart, server-rendered).

Ceilings after this change: the mapping JSON up to 4 MiB (S1 transport 43.7 KB; full 27 x 5,570 matrix about 2.6 MB; 5,000 x 25,000 about 1.3 MB) and the whole form up to about 15.5 MiB. Reverse proxies can cut earlier (nginx `client_max_body_size` defaults to 1 MB); the pre-check cannot see that, the README documents it.

Client storage estimate (admin: MySQL only; project: whenever the effective limit of WP-31 is set; limits policy R20, limits design 4.10): `estimate = storage-base + ceil(utf8(JSON{vd,dd}) * (1.2 list | 1.6 enumeration))` from the measured YAML/JSON ratios (`admin_editor/yaml_ratio.rb`); possible values `4 + sum(utf8(v) + 3)` against `values-limit`. Consolidated rule (compat section 2.4, row "Storage threshold and client key"): when an estimate reaches `data-dcf-editor-storage-warn` percent (90) of its limit, one advisory `div.flash.warning` with the single key `text_dcf_storage_estimate` (owner WP-24; interpolations `label` = `field_value_dependencies` or `field_possible_values`, `size` and `limit` as delimited bytes, `percent`); without the attribute no warning is shown. Not blocking; the server validation `dcf_storage_too_large` is authoritative. Revision 2's `text_dcf_storage_estimate_over` and "warn only above the limit" are superseded. The server usage line (`text_dcf_storage_usage`, at `StorageLimits::WARN_PERCENT`, 90 percent) is the limits area's server hook, in the same units.

Test `test/js/dependency_editor_storage.test.js` (WP-25, gap 12): warning with `text_dcf_storage_estimate` at or above `data-dcf-editor-storage-warn` percent of `data-dcf-editor-storage-limit`; no warning without the attribute; the possible-values estimate is checked against `data-dcf-editor-values-limit`.

### 5.10 Format switch on /new (UX-11)
The capture-phase listener on `document` sees the `change` of `#custom_field_field_format` before core's jQuery handler bound on the element. When the editor is dirty it asks `window.confirm(text_dcf_editor_format_change_confirm)`; on cancel it calls `stopImmediatePropagation()` (propagation stops before reaching the target, so core's AJAX does not run) and restores the previously selected format (tracked at init and on each accepted change). When confirmed or not dirty, it empties the hidden input so core's GET serialization cannot hit 414.

### 5.11 Accessibility
- Native `details`/`summary` (keyboard and expanded state for free); no interactive content in `summary`; `fieldset`/`legend`; every control wrapped by its label; buttons `type="button"`.
- Inactive state as visible text in a badge.
- One polite live region (`p.hidden-for-sighted[role=status]`), updated debounced 400 ms after a filter change, check/uncheck all shown, a parent change, import apply or undo, and conflict choices; individual ticks are not announced. Errors use `role=alert`; `aria-busy` while loading. This matches UX-06; quality G4 must accept native details/summary as the collapsible pattern.

### 5.12 CSS (`assets/stylesheets/dcf_dependency_editor.css`)

```css
.dcf-dep-editor { margin: .6em 0; padding: 4px 8px 8px; min-inline-size: 0; }
.dcf-dep-editor > legend { font-weight: bold; padding: 0 4px; }
.tabular .dcf-dep-editor p:not(.warning):not(.nodata):not(.icon) { padding-inline-start: 0; }
.tabular .dcf-dep-editor p.warning, .tabular .dcf-dep-editor p.nodata { padding-inline-start: 30px; } /* core flash padding; .tabular p would win */
.tabular .dcf-dep-editor label { float: none; margin-inline-start: 0; inline-size: auto; font-weight: normal; text-align: start; line-height: inherit; }
.dcf-dep-editor .dcf-hidden, .tabular p.dcf-hidden { display: none !important; }
.dcf-dep-editor__toolbar, .dcf-dep-section__tools, .dcf-dep-editor__options { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 12px; margin-block: 4px; }
.dcf-dep-editor__status { font-size: .9em; color: var(--oc-gray-7, #555); margin-block: 4px; }
.dcf-dep-editor__sections { border: 1px solid var(--oc-gray-3, #e4e4e4); border-radius: 3px; }
.dcf-dep-section + .dcf-dep-section { border-block-start: 1px solid var(--oc-gray-3, #e4e4e4); }
.dcf-dep-section > summary { cursor: pointer; padding: 4px 6px; }
.dcf-dep-section[open] > summary { background-color: var(--oc-gray-1, #f6f7f8); }
.dcf-dep-section__counts, .dcf-dep-section__default { margin-inline-start: .8em; font-size: .9em; color: var(--oc-gray-7, #555); }
.dcf-dep-section__counts--none { color: var(--oc-red-9, #c22); }
.dcf-dep-section__body { padding: 4px 8px 8px 22px; }
.dcf-dep-section__rows { list-style: none; margin: 4px 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(14em, 1fr)); gap: 0 1em; max-block-size: 24em; overflow-y: auto; }
.dcf-dep-section__rows label { display: block; overflow-wrap: anywhere; }
.dcf-dep-editor .badge { bottom: 0; inset-block-end: 0; }
.dcf-dep-editor__panel { margin-block-start: 8px; }
.dcf-dep-editor__panel > summary { cursor: pointer; font-weight: bold; }
.dcf-dep-editor__panel textarea { inline-size: 95%; font-family: monospace; }
.dcf-dep-editor__panel textarea:disabled { opacity: .6; }
.dcf-dep-editor__preview table.list td { text-align: start; }
.dcf-dep-editor__notices .flash, .dcf-dep-editor__conflict { margin-block: 4px; }
```

Removed from `depending_custom_fields.css`: `.dependencies-matrix*`, `.dependencies-defaults*`, `.dcf-dependencies-matrix td.center`. Reused core classes: `box`, `tabular`, `warning`, `flash warning`/`flash error`, `icon icon-warning`, `badge badge-status-locked`, `table.list`, `em.info`, `hidden-for-sighted`, `buttons`.

## 6. Import and export (client-side, pure model, node tests; WP-26, 0.1.0 (M3))

Nothing posts until the normal Save; import inputs have no `name`.

### 6.1 Parser `parseRecords(text, sep)`
- Input at most 10,000,000 characters (`err_too_large`); at most 200,000 records (`error_dcf_import_too_many_lines`, parsing stops, SP-13).
- Leading U+FEFF stripped. CRLF, CR and LF end a record outside quotes.
- RFC 4180: `"` quotes when it is the first non-space character; `""` is a literal quote; newlines inside quotes are kept and the record keeps its START line; a `"` inside an unquoted field is literal; text after a closing quote gives `bad_quote` (skip to end of line, continue); an unterminated quote gives `unterminated_quote` at the record start.
- Unquoted cells trimmed; trailing empty cells removed; all-blank lines skipped; exactly 2 cells (`columns`); a blank cell gives `blank_value`.
- Separator `auto`: tab, `;`, `,` tried on the first 64 KB, picking the one giving exactly two non-blank cells on most of the first 20 records (tie order tab, `;`, `,`); quoted separators respected. Manual override: Semicolon, Comma, Tab.
- Errors capped at 200 ("Further errors not shown: N").

### 6.2 Header (select: Detect automatically / Yes / No)
Auto: row 1 is a header unless it is a valid pair, when cell 1 equals the parent field name or `parent`, or cell 2 equals the child field name or `child` (case-insensitive), or both cells are unknown values. A skipped first row is shown prominently as `div.flash.warning` listing its cells (`text_dcf_import_header_skipped` with `%{cells}`), with the hint to choose "No" (QA-11 c). Export writes the field names, so export then import round-trips.

### 6.3 Matching
- Order: exact trimmed label; exact NFC label; unique case-insensitive NFC match (`NFC` + `toLowerCase`, accents significant); several candidates without an exact match give `ambiguous_parent`/`ambiguous_child`.
- Enumerations by name with the same rule, inactive included (D7, UD-19: name only, no `#<id>` cell syntax in this release); an active and an inactive value with the same name are ambiguous (QA-11 d); inactive matches give the non-blocking warning `inactive`.
- NFD spellings in the file match NFC values (QA-11 e).
- Unknown parent: error. Unknown child: error unless "Add missing child values" is checked. Duplicate pairs counted, not errors.
- Optional "Remove the formula protection added by the export" (default off, UD-18): strips one leading `'` only when the remainder starts with `=`, `+`, `-`, `@`, TAB or CR (SP-14).

### 6.4 Plan, preview, apply, undo
- `planImport(text, state, parents, children, {separator, header, mode, addMissing, unprotect, parentName, childName})` returns `{ok, errors[], warnings[], pairs[], added, existing, removed, duplicates, newValues[], headerSkipped, headerCells, separator, lines, estimatedPayloadBytes}`.
- `merge` (default) adds links; `replace` replaces all links; defaults whose link disappears are dropped on apply.
- All-or-nothing: "Apply to the editor" is enabled only with no errors and at least one pair (or replace mode) AND `estimatedPayloadBytes <= max-payload-bytes` (otherwise `error_dcf_dependencies_too_large_to_send`, SP-13).
- Apply snapshots the state, mutates it, sets `source = "import"` and `importMeta = {mode, rows: pairs.length}` (last applied import), marks dirty, re-renders, collapses the panel, announces, and shows "Import applied (links added: N, removed: M). Save to store the changes." with "Undo import" (restores the snapshot, `source`, `importMeta` and, for list fields, the textarea).
- Any import input change invalidates the preview.

### 6.5 Add missing child values (admin, list children, `data-dcf-editor-allow-add-values`)
- Unknown children are collected once each (NFC, case-insensitive, first-seen order), trimmed and NFC-normalized; the preview reports "Child values to add to the possible values: N".
- A value containing CR or LF is a line error `error_dcf_import_multiline_value`: core `possible_values=` would split it into several values and the link would be pruned (QA-11 b). Surrounding whitespace is not an error: the importer trims exactly as core strips, so the stored value equals the link key.
- Apply appends to `#custom_field_possible_values` (newline-joined after trimming trailing whitespace), dispatches `input` and `change` (core `warnLeavingUnsaved` sees it), rebuilds children synchronously, links the pairs; the storage estimate re-evaluates. Not offered for enumeration children or on the project page: the checkbox is rendered only when `data-dcf-editor-allow-add-values="1"` (admin + list, 5.3). WP-26 jsdom test (gap 12): "Add missing child values" is not rendered on the project fixture nor for enumeration children (admin enumeration fixture).

### 6.6 Files and encodings
`input[type=file][accept=".csv,.txt,text/csv,text/plain"]`, no name, at most 10 MB, read with `file.arrayBuffer()`. `TextDecoder('utf-8', {fatal: true})`, then `TextDecoder(csv-encoding)` falling back to `windows-1252`, with the info line `text_dcf_import_decoded_as`. While a file is loaded, the paste area is disabled with `text_dcf_import_file_used` (UX-11); the reset button is labelled with core `button_clear` and clears paste, file and preview.

### 6.7 Export
- `buildCsv(state, parents, children, {separator, parentName, childName, protect})`: header of field names; one row per current link (parent order, child order); list values or enumeration names; CRLF; a cell is quoted when it contains the separator, `"`, CR or LF, or has surrounding spaces; UTF-8 BOM.
- Separator select (Comma, Semicolon, Tab), default `data-dcf-editor-csv-separator`.
- Optional "Protect cells that a spreadsheet would run as formulas" (default off, SP-14, UD-18): prefixes `'` to cells starting with `=`, `+`, `-`, `@`, TAB or CR; the import option of 6.3 reverses it exactly. The help text warns about formulas.
- Download: `Blob(['\uFEFF' + csv], {type: 'text/csv;charset=utf-8'})`, `URL.createObjectURL`, temporary `a[download]`, `revokeObjectURL`; guarded when `createObjectURL` is missing. Filename `<folded field name, non [a-z0-9_.-] as _>_dependencies.csv`, fallback `dependencies.csv`.
- Exports the editor state including unsaved changes; orphans and defaults are not exported (two columns, D7).

### 6.8 Panels (JS-built, unnamed)

```
details.dcf-dep-editor__panel.dcf-dep-editor__import > summary "Import links (CSV)"
  p > em.info (help)
  p > label "Paste lines" textarea[data-dcf-ed-import-text][rows=8][spellcheck=false]   (disabled while a file is loaded)
  p > label "Or choose a file" input[type=file][data-dcf-ed-import-file] [span file info + text_dcf_import_file_used]
  p.dcf-dep-editor__options
    label "Field separator" select[data-dcf-ed-import-separator] auto|;|,|tab
    label "First line is a header" select[data-dcf-ed-import-header] auto|yes|no
    label "Mode" select[data-dcf-ed-import-mode] merge|replace
    [label input[type=checkbox][data-dcf-ed-import-add-missing] "Add missing child values to the possible values"]
    label input[type=checkbox][data-dcf-ed-import-unprotect] "Remove the formula protection added by the export"
  p button "Preview" | button[disabled] "Apply to the editor" | button "Clear"
  div.dcf-dep-editor__preview[role=region]
    div.flash.error[role=alert] p + ul (line errors)
    div.flash.warning (header skipped with cells; inactive warnings)
    ul (summary: lines read, to add, already present, to remove, new values, duplicates, separator used, decoded as)
    table.list > caption "First links read" > thead(parent name | child name | Status) > first 20 pairs
details.dcf-dep-editor__panel.dcf-dep-editor__export > summary "Export links (CSV)"
  p > em.info (help with formula warning)
  p label "Field separator" select[data-dcf-ed-export-separator]
    label input[type=checkbox][data-dcf-ed-export-protect] "Protect cells that a spreadsheet would run as formulas"
    button[data-dcf-ed-export] "Export"
```

Panels are hidden when there are no parent or child values.

## 7. Project-level integration contract (point 9 implements in WP-27, 0.1.0 (M3); editor owns the contract)

- **View.** `edit_dependencies.html.erb` keeps its PATCH `form_tag(..., multipart: true)` and `state_hash`, renders the parent-not-available notice itself (server side, before the editor), and otherwise renders `render 'depending_custom_fields/dependency_editor', editor: RedmineDependingCustomFields::DependencyEditorConfig.for_project(field: @field, parent: @parent, view: self, posted: @posted_payload, conflict: @conflict_payload)` followed by `<p class="buttons"><%= submit_tag l(:button_save), disabled: true, data: { dcf_editor_submit: 1 } %> cancel link</p>`. Without JS (or with an inert editor) Save stays disabled: a no-op is never reported as success and nobody is told to reload (UX-01). The page does not render `text_dependency_matrix_help` (deleted by WP-27, its last user) nor its own orphan or empty-state copy; the editor provides help, orphans and empty states on both pages. No editor assets through `content_for`.
- **Parent notices (gap 2).** The parent-missing and parent-not-available notices (`text_dcf_parent_missing`, `text_dcf_parent_not_available`, project keys) are decided with `DependencyRules.parent_of(field)` (WP-05: memoized raw lookup, nil for blank, dangling, wrong type or family, or self); the editor is rendered only when a parent is available.
- **Shared/global fields (UD-23).** Only the scope banner (WP-27, `dcf_flash_box`); no server-side confirmation panel for dependency saves, including replace imports.
- **Controller.**
  - `params.key?(:dependencies_json)` selects the JSON path; a blank value raises (via `parse!`) `error_invalid_dependency_payload`, audited, never a clear.
  - Key absent: legacy nested params with today's semantics (nothing posted clears), deprecated in 0.1.0 (accepted throughout 0.1.x, with a deprecation log), removable no earlier than 0.2.0.
  - 422 re-render: `@posted_payload = service.parsed_payload` (the service's memoized `Result`, no second parse, SP-17) when ok, passed as `posted:` to `DependencyEditorConfig.for_project`. Failed-save rule (gap 1): the hidden input stays blank, the parsed payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; no `input_value`, no `data-dcf-editor-echo`. When the payload did not parse, the stored mapping is rendered, not dirty.
  - 409 re-render: the service never parsed (state_hash preamble), so the controller parses once: `@conflict_payload = DependencyPayload.parse(params[:dependencies_json])` when ok; the editor shows the fresh mapping and the conflict panel (5.8), identical to the admin stale case (UX-09).
  - Flash interpolations go through the project area's escaping helper (SP-06), called as `translate_error(e)` with the `OperationError` (gap 4, compat section 3); editor interpolations are integers only.
  - Locale keys: WP-27 reuses `error_invalid_dependency_payload` and `error_dcf_dependencies_too_large_to_send` (owned by WP-25) and adds none of the dropped project keys `text_dcf_editor_pending_conflict`, `button_dcf_editor_pending_*`, `error_dcf_dependency_payload_too_large`, `text_dcf_orphan_entries`, `text_dcf_editor_requires_javascript` (gap 8).
- **Service.** `DependencyMappingService#perform!` calls `DependencyPayload.parse!` inside the BaseService transaction, memoized as `parsed_payload` (attr_reader). `Invalid` becomes `OperationError` per 2.4 with summary `dependencies_json rejected: <reason> (<bytes> bytes)`. Strict validation through `DependencyRules.mapping_problems` with Sets (unknown key, child or default gives `error_invalid_dependency`); inactive enumerations valid. The compact audit delta records `source` from `result.source` and, when present, `import` (`mode`, `rows`) from `result.import`; `base` is ignored. Storage check before `save!` per the limits area.
- **Request specs owned by point 9, required by this contract:** blank `dependencies_json` gives 422 and a `validation_failed` row; the real-model payload fixtures (13) save and record `source=import`; 409 re-render contains `data-dcf-editor-conflict-mapping`; Save rendered disabled with `data-dcf-editor-submit`; failed-save re-render: mapping attribute holds the posted mapping, dirty is `1`, hidden input blank (gap 1); unauthorized PATCH `update_dependencies` with a malformed or 1,000,000-digit payload gives 403, an `authorization_failed` audit row, and `DependencyPayload.parse` is not called (SP-20b, gap 12). Project-mode import is verified end to end with the WP-26 import panel (gap 14).

## 8. Cross-area contract ownership (what this design fixes for others)
| contract | owner | consumers |
|---|---|---|
| payload schema + `DependencyPayload` (parse, parse!, digest, stored_digest) | editor (WP-21) | admin transport, DependencyMappingService, editor JS serializer |
| `prune_mapping(vd, dd, parent_keys:, child_keys:, multiple:)` (required keyword parameters; callers pass them explicitly, 2.2) | server (DependencyRules, WP-05), contract in 2.2 | admin transport |
| `value_options` `[key, label, active]` tuples, consumed as `\|key, label, active\|` | server (WP-05) | `wire_values` (editor, WP-24), endpoint, both presenter modes, project delta labels (WP-27), values page (WP-28) |
| `DependencyRules.parent_of(cf)` (memoized raw parent lookup) | server (WP-05) | project parent notices (WP-27) |
| editor DOM contract (partial, presenter, `data-dcf-editor-*`, `data-dcf-editor-submit`) | editor (WP-24, WP-25) | project view (WP-27) |
| failed-save re-render (hidden input blank, posted payload in `data-dcf-editor-mapping`, dirty `1`, no echo) | editor (compat section 3) | admin form (WP-22, WP-25), project page (WP-27) |
| editor assets in the head hook | server hook spec (ClientConfig, WP-18), list fixed in 5.1 (added by WP-25) | both pages |
| storage limits API (`column_limit(column, model = CustomField)`, `base_bytes`, `serialized_bytesize`, `delimited`, `WARN_PERCENT`, `dcf_storage_too_large`) and the client key `text_dcf_storage_estimate` (text from the limits design, added by WP-24) | limits (WP-11) | editor attributes and client warning |
| project effective storage limit `ProjectStoragePolicy.format_store_limit(field)` | project (WP-31, UD-22) | `for_project` storage attributes |
| `translate_error(e)` | limits (WP-12) | project controller flashes (WP-27 to WP-31) |
| JS fixture mechanism `spec/support/dcf_js_fixtures.rb` | quality (created by WP-16, id ranges from WP-02; compat section 2.4, row "Fixture ids") | editor fixtures (WP-24), frontend markup fixtures, payload fixtures |
| editor locale keys (section 9) | editor (owner WP per key) | both pages |

Consolidated (compat section 2.4, row "Fixture ids"): fixture records get explicit ids from the quality per-kind ranges of WP-02 through `dcf_fixture_record` (CustomField 9_100_001+, CustomFieldEnumeration 9_200_001+, Issue 9_300_001+, Project 9_400_001+, User 9_500_001+, Role 9_600_001+, Tracker 9_700_001+, IssueStatus 9_800_001+), with the normalizer, the sequence-bump self check and two seeds (quality protocol 5.5). The `ID_BASE = 1_900_000_000` scheme of the next paragraph is the superseded revision 2 proposal, kept for traceability; its scrub and write-or-compare behavior is what WP-16 implements.

Shared JS fixture mechanism (R13, QA-01; revision 2 proposal): `DcfJsFixtures` provides `dcf_fixed_id(kind, n)` with `ID_BASE = 1_900_000_000` and per-kind offsets (`custom_field` 0, `enumeration` 1,000,000, `project` 2,000,000, `tracker` 3,000,000, `issue_status` 4,000,000), far above any sequence the suite reaches (large-list specs insert at most tens of thousands of enumerations); `dcf_scrub_fixture(html)` replacing `authenticity_token` values, csrf meta, `state_hash` values and asset fingerprints with placeholders; `dcf_check_fixture!(relative_path, content)` writing when `DCF_WRITE_JS_FIXTURES=1`, comparing otherwise. Fixture records are created with fixed ids (`record.id = dcf_fixed_id(...)` before `save!`; enumerations via `insert_all` with ids), so enumeration ids, field ids, project ids, URLs and the `base` digest are deterministic.

## 9. i18n key list for the editor (R11, UX-03, QA-05, BC-13; texts in large_lists_i18n_registry.md)

**Single source of truth for texts (gap 9).** The en, de, fr and nl texts of every key below live only in `large_lists_i18n_registry.md`. This section keeps the key names, the JS keys, the owner WP (gap 8) and the interpolation variables. The registry carries the UX-16 corrections that revision 2 still lacked (fr `label_dcf_show_not_linked_anywhere`, `text_dcf_status_unlinked_children`, `label_dcf_unlinked_children_list`, `label_dcf_linked_count`, `text_dcf_editor_parent_changed`; nl `text_dcf_no_matches`) and the per-locale quotes of quality section 2.7 (en and nl ASCII double quotes, de „%{value}“, fr « %{value} ») in `error_dcf_import_unknown_parent`/`_child`, `error_dcf_import_ambiguous_parent`/`_child`, `error_dcf_import_multiline_value`, `warning_dcf_import_inactive` and the quoted labels of `text_dcf_import_header_skipped`, so the WP-02 quote check accepts them. WP-25, WP-26 and WP-28 copy their texts from the registry. `text_dcf_editor_help` uses the editor revision 2 text (gap 8), not quality's neutral variant. The superseded revision 2 text tables are kept for traceability only in `$S/design_out/design_editor.md` section 9; they are not a source for locale files.

**Ownership rules (gap 8).** Every key has exactly one owner WP, which adds it to all four locale files.
- WP-22: the three model error messages under `activerecord.errors.messages`.
- WP-24: `text_dcf_editor_help`, `text_dcf_editor_noscript`, `text_dcf_editor_select_parent`, `text_dcf_storage_estimate`. WP-24 creates `DependencyEditorConfig::I18N` listing only its own keys.
- WP-25: `error_invalid_dependency_payload`, `error_dcf_dependencies_too_large_to_send` and the remaining editor keys except import/export. WP-27 reuses the two payload keys and does not redefine them.
- WP-26: the import/export keys (from `label_dcf_import_links` to `label_dcf_export_protect_formulas`).
- WP-28: `text_dcf_no_matches`, unless WP-25 landed it first; the later WP reuses the key (one definition, so the duplicate-key check stays green). WP-25 adds the `no_matches` entry of `DependencyEditorConfig::I18N` either way.
- WP-25 and WP-26 extend `DependencyEditorConfig::I18N` in the same commit as their locale entries, so every map value resolves at every commit.
- WP-27 deletes `text_dependency_matrix_help` (its last user is the project page) and adds none of the dropped project keys `text_dcf_editor_pending_conflict`, `button_dcf_editor_pending_*`, `error_dcf_dependency_payload_too_large`, `text_dcf_orphan_entries`, `text_dcf_editor_requires_javascript`.

Keys used but owned elsewhere (one text each, not redefined here): `field_value_dependencies` ("Dependency mapping", limits; also the legend), `activerecord.errors.messages.dcf_storage_too_large` (limits, WP-11); core keys of 0.4; plugin keys `text_dcf_no_default`, `warning_required_child_no_options`, `error_stale_edit`. The client storage key is `text_dcf_storage_estimate` (text designed by the limits area, added by WP-24, row below); revision 2's reference to the limits key `text_dcf_storage_estimate_over` is superseded (compat section 2.4).

Removed from revision 1: `label_dcf_dependencies`, `field_dependencies_json`, `field_default_value_dependencies`, the editor's copy of `field_value_dependencies`, `text_dcf_storage_near_limit`. Also not created: `text_dcf_storage_estimate_over` and quality's `activerecord.errors.messages.dcf_dependencies_payload_too_large` (the admin size error is `dcf_dependencies_too_large_to_send`, WP-22). Deleted existing key: `text_dependency_matrix_help` (no longer referenced; deleted by WP-27). The project area's `text_dcf_editor_requires_javascript`, `text_dcf_orphan_entries` and its copy of `error_invalid_dependency_payload` are replaced by the editor keys below.

Reviewed identical-to-English values for the parity spec allowlist: fr `label_dcf_inactive` "inactive", fr `label_dcf_import_mode` "Mode", nl `label_dcf_tab_char` "Tab". WP-02 pre-lists all three in its allowlist (gap 10).

The parity spec (quality area, WP-02) must fail on duplicate mapping keys at any level (Psych parse-tree walk) and resolve every value of `RedmineDependingCustomFields::ClientConfig::I18N` and `DependencyEditorConfig::I18N`, each when defined, in all four locales (gap 5; never `I18N_KEYS`). WP-24 adds an example proving `DependencyEditorConfig::I18N` is iterated.

Nested under `activerecord.errors.messages` (full message: label "Dependency mapping" + message):
| key | owner WP | interpolations | en, de, fr, nl texts |
|---|---|---|---|
| dcf_invalid_dependencies_payload | WP-22 | none | see large_lists_i18n_registry.md |
| dcf_stale_dependencies | WP-22 | none | see large_lists_i18n_registry.md |
| dcf_dependencies_too_large_to_send | WP-22 | `%{size}`, `%{limit}` | see large_lists_i18n_registry.md |

Flat keys (JS key in parentheses when sent through `data-dcf-editor-i18n`):
| key (JS key) | owner WP | interpolations | en, de, fr, nl texts |
|---|---|---|---|
| error_invalid_dependency_payload (project flash) | WP-25 (reused by WP-27) | none | see large_lists_i18n_registry.md |
| error_dcf_dependencies_too_large_to_send (too_large_to_send) | WP-25 (reused by WP-27) | `%{size}`, `%{limit}` | see large_lists_i18n_registry.md |
| error_dcf_editor_form_too_large (form_too_large) | WP-25 | `%{size}`, `%{limit}` | see large_lists_i18n_registry.md |
| text_dcf_editor_help | WP-24 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_noscript | WP-24 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_unavailable (unavailable) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_select_parent | WP-24 | none | see large_lists_i18n_registry.md |
| text_dcf_storage_estimate (storageEstimate, limits design 4.10) | WP-24 (text designed by the limits area) | `%{label}`, `%{size}`, `%{limit}`, `%{percent}` | see large_lists_i18n_registry.md |
| text_dcf_editor_no_parent_values (no_parent_values) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_no_child_values (no_child_values) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_enumeration_save_first (enumeration_save_first) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_enumeration_values_hint (enumeration_hint) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_loading (loading) | WP-25 | none | see large_lists_i18n_registry.md |
| error_dcf_editor_load_failed (load_failed) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_parent_changed (parent_changed) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_editor_orphans (orphans) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_editor_format_change_confirm (format_change_confirm) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_conflict (conflict) | WP-25 | `%{only_mine}`, `%{only_current}` | see large_lists_i18n_registry.md |
| button_dcf_use_my_version (use_mine) | WP-25 | none | see large_lists_i18n_registry.md |
| button_dcf_keep_current_version (keep_current) | WP-25 | none | see large_lists_i18n_registry.md |
| button_dcf_export_my_version (export_mine) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_editor_conflict_mine_loaded (mine_loaded) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_filter_parent_values (filter_parents) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_filter_child_values (filter_children) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_only_parents_without_links (only_parents_without_links) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_show_children (show) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_show_all (show_all) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_show_linked (show_linked) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_show_not_linked_here (show_not_linked) | WP-25 | none | see large_lists_i18n_registry.md |
| label_dcf_show_not_linked_anywhere (show_unlinked) | WP-25 | none | see large_lists_i18n_registry.md |
| button_dcf_check_shown (check_shown) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| button_dcf_uncheck_shown (uncheck_shown) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| button_dcf_show_more (show_more) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| label_dcf_linked_count (linked_count) | WP-25 | `%{linked}`, `%{total}` | see large_lists_i18n_registry.md |
| label_dcf_default_summary (default_summary) | WP-25 | `%{value}` | see large_lists_i18n_registry.md |
| label_dcf_inactive (inactive) | WP-25 | none | see large_lists_i18n_registry.md |
| text_dcf_no_matches (no_matches) | WP-28, or WP-25 if it lands first (the later WP reuses it) | none | see large_lists_i18n_registry.md |
| text_dcf_status_sections (status_sections) | WP-25 | `%{shown}`, `%{total}` | see large_lists_i18n_registry.md |
| text_dcf_status_parents_without_links (status_parents_without_links) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_status_unlinked_children (status_unlinked_children) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| label_dcf_unlinked_children_list (unlinked_list) | WP-25 | `%{count}` | see large_lists_i18n_registry.md |
| label_dcf_import_links (import_title) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_import_help (import_help) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_paste (import_paste) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_file (import_file) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_import_file_used (file_used) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_auto_detect (auto) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_tab_char (tab) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_header (import_header) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_mode (import_mode) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_mode_merge (mode_merge) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_mode_replace (mode_replace) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_add_missing (add_missing) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_unprotect_formulas (unprotect) | WP-26 | none | see large_lists_i18n_registry.md |
| button_dcf_import_apply (apply) | WP-26 | none | see large_lists_i18n_registry.md |
| button_dcf_import_undo (undo) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_import_applied (applied) | WP-26 | `%{added}`, `%{removed}` | see large_lists_i18n_registry.md |
| text_dcf_import_lines (lines) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_to_add (to_add) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_existing (existing) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_to_remove (to_remove) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_new_values (new_values) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_duplicates (duplicates) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_header_skipped (header_skipped) | WP-26 | `%{cells}` | see large_lists_i18n_registry.md |
| text_dcf_import_separator_used (separator_used) | WP-26 | `%{separator}` | see large_lists_i18n_registry.md |
| text_dcf_import_decoded_as (decoded_as) | WP-26 | `%{encoding}` | see large_lists_i18n_registry.md |
| text_dcf_import_preview_rows (preview_rows) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_status_new (status_new) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_import_status_existing (status_existing) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_import_errors (errors_intro) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_import_more_errors (more_errors) | WP-26 | `%{count}` | see large_lists_i18n_registry.md |
| text_dcf_import_nothing (nothing) | WP-26 | none | see large_lists_i18n_registry.md |
| error_dcf_import_columns (err_columns) | WP-26 | `%{line}`, `%{count}` | see large_lists_i18n_registry.md |
| error_dcf_import_blank_value (err_blank_value) | WP-26 | `%{line}` | see large_lists_i18n_registry.md |
| error_dcf_import_unknown_parent (err_unknown_parent) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| error_dcf_import_unknown_child (err_unknown_child) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| error_dcf_import_ambiguous_parent (err_ambiguous_parent) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| error_dcf_import_ambiguous_child (err_ambiguous_child) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| error_dcf_import_unterminated_quote (err_unterminated_quote) | WP-26 | `%{line}` | see large_lists_i18n_registry.md |
| error_dcf_import_bad_quote (err_bad_quote) | WP-26 | `%{line}` | see large_lists_i18n_registry.md |
| error_dcf_import_too_large (err_too_large) | WP-26 | `%{max}` | see large_lists_i18n_registry.md |
| error_dcf_import_too_many_lines (err_too_many_lines) | WP-26 | `%{max}` | see large_lists_i18n_registry.md |
| error_dcf_import_multiline_value (err_multiline_value) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| error_dcf_import_unreadable (err_unreadable) | WP-26 | none | see large_lists_i18n_registry.md |
| warning_dcf_import_inactive (warn_inactive) | WP-26 | `%{line}`, `%{value}` | see large_lists_i18n_registry.md |
| label_dcf_export_links (export_title) | WP-26 | none | see large_lists_i18n_registry.md |
| text_dcf_export_help (export_help) | WP-26 | none | see large_lists_i18n_registry.md |
| label_dcf_export_protect_formulas (protect) | WP-26 | none | see large_lists_i18n_registry.md |

Reused through the JS map: core `button_collapse_all` (collapse_all), `button_clear` (clear), `button_export` (export), `label_preview` (preview), `label_fields_separator` (separator), `label_comma_char` (comma), `label_semi_colon_char` (semicolon), `general_text_Yes` (yes), `general_text_No` (no), `field_default_value` (default_value), `field_status` (status), `text_warn_on_leaving_unsaved` (unsaved); plugin `text_dcf_no_default` (no_default); `text_dcf_storage_estimate` (storageEstimate, owner WP-24, in the table above; replaces revision 2's limits `text_dcf_storage_estimate_over` (storage_over)). Map entries for reused keys are added by the WP whose UI uses them: WP-25 `collapse_all`, `clear`, `default_value`, `unsaved`, `no_default`; WP-26 `export`, `preview`, `separator`, `comma`, `semicolon`, `yes`, `no`, `status`; WP-24 `storageEstimate`. Phrasing avoids plural forms ("Label: %{count}"). JS interpolates `%{name}` tokens; `%{size}`/`%{limit}` are delimited with Intl.NumberFormat. YAML: values containing `"` single-quoted (en and nl); de and fr use „…“ and « … » instead of ASCII quotes (registry).

## 10. File-by-file changes
| file | change | WP (all 0.1.0 (M3) unless noted) |
|---|---|---|
| `init.rb` | add `'dependencies_json'` to `CustomField.safe_attributes` (nested attributes stay permanently, UD-15); no new prepend: `CustomFieldValidationPatch` is already prepended after `CustomFieldPatch` by WP-11 (revision 2's `CustomFieldDependenciesTransportPatch` prepend is superseded) | WP-22 |
| `lib/redmine_depending_custom_fields.rb` | `require_relative` `dependency_payload` and `dependency_editor_config` | WP-21, WP-24 |
| `lib/redmine_depending_custom_fields/dependency_payload.rb` | NEW (section 2) | WP-21 |
| `lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb` | transport callbacks and methods added (3.1) to the module created by WP-11 (0.1.0 (M1)); replaces revision 2's NEW `custom_field_dependencies_transport_patch.rb` | WP-22 |
| `lib/redmine_depending_custom_fields/dependency_editor_config.rb` | NEW presenter (5.3, 4.1, 9); `I18N` extended by WP-25 and WP-26; project storage limit from `ProjectStoragePolicy.format_store_limit(field)` | WP-24 (WP-25, WP-26, WP-31) |
| `lib/redmine_depending_custom_fields/patches/custom_field_patch.rb` | no editor change | - |
| `app/controllers/dcf_dependency_editor_controller.rb`, `config/routes.rb` | NEW endpoint and route (4.2) | WP-24 |
| `app/views/depending_custom_fields/_dependency_editor.html.erb` | NEW (5.2) | WP-24 |
| `app/views/custom_fields/formats/_depending_list.html.erb`, `_depending_enumeration.html.erb` | new order; default row always rendered; editor last; old inline required warning removed | WP-25 |
| `app/views/custom_fields/formats/_dependencies_matrix.html.erb`, `_default_dependencies.html.erb` | DELETED | WP-25 |
| `app/views/project_custom_field_configuration/edit_dependencies.html.erb` | point 9 per section 7 | WP-27 |
| `lib/redmine_depending_custom_fields/client_config.rb` (server area, created by WP-18 in 0.1.0 (M2)) | `editor_asset_tags` list of 5.1 | WP-25 |
| `assets/javascripts/dcf_dependency_editor_model.js`, `dcf_dependency_editor.js` | NEW | WP-23 (model), WP-25 (DOM layer), WP-26 (import/export additions) |
| `assets/stylesheets/dcf_dependency_editor.css` | NEW; matrix rules removed from `depending_custom_fields.css` | WP-25 |
| `config/locales/{en,de,fr,nl}.yml` | section 9 keys (texts from `large_lists_i18n_registry.md`); `text_dependency_matrix_help` deleted | owner WP per key (WP-22, WP-24, WP-25, WP-26, WP-28); deletion WP-27 |
| `spec/support/dcf_js_fixtures.rb` | shared fixture mechanism (section 8), used by the editor fixtures | created by WP-16 (0.1.0 (M2)); used by WP-24 |
| `test/js/fixtures/editor/*.html`, `test/js/fixtures/payload/*.json` (WP-23 path; revision 2 wrote `payloads/`), `test/js/fixtures/value_options.json` | NEW generated fixtures | WP-24 (editor, value_options), WP-23 (payload), WP-26 (import goldens) |
| `test/js/dcf_dependency_editor.test.js`, `test/js/dependency_editor_storage.test.js` | NEW jsdom tests (including the same-origin and storage cases of gap 12) | WP-25 (WP-26, WP-27 extend the first) |
| `README.md`, `CHANGELOG.md` | section 15 | WP-25, WP-26, WP-27, WP-32 |

## 11. Behavior table (admin form unless noted)
| scenario | before | after |
|---|---|---|
| untick every box, save | old mapping kept (bug) | `{}` posted, mapping cleared |
| parent value with `]` or `[` | garbage key or 400, mapping wiped for lone `]` | exact round trip |
| more than 4,096 links | 400 on 6.x/7.0, 500 on 5.1, PUT edit form actually 404 (critic A1) | one param; saved |
| mapping JSON of 3 MB | n/a (param-limited) | multipart form, saved (urlencoded would fail at 4 MiB, rack probe) |
| mapping JSON above 4 MiB or form above 15.5 MiB | n/a | blocked before submit with a size message; server backstop gives a size error, never "could not be read" |
| 27 x 5,570 page weight | about 21 MB HTML, 300k nodes, about 5.1 s render | data attributes about 0.2-0.3 MB, 100 closed sections |
| inactive enumerations | not rendered, links dropped on every save | shown with "inactive" badge, links kept |
| parent changed in the form | old keys stored under the new parent | live rebuild with dropped-count notice (cleared when reverted); server prunes |
| default options | from page-load mapping; "Translation missing: label_default_value" | live from links; label `field_default_value` |
| required warning | static | live, sprite icon on 6.0+ |
| save without touching the dependencies | whole matrix re-posted and pruned | payload `''`, mapping untouched |
| concurrent change during edit (admin and project) | silently overwritten (admin); project 409 lost the user's state | refused; editor shows the current version, a conflict panel and the user's version (use, keep, export) |
| failed save for another reason (admin and project) | matrix re-rendered from params | editor re-rendered dirty from the posted state (`data-dcf-editor-mapping`, `data-dcf-editor-dirty="1"`); hidden input blank; no raw echo (gap 1) |
| GET /new with `custom_field[dependencies_json]` | n/a | ignored, never rendered |
| format switch on /new with unsaved dependency edits | n/a | confirmation; cancel keeps the format |
| no JavaScript (admin) | matrix usable | noscript message; saving leaves the mapping unchanged (UD-16) |
| no JavaScript (project) | matrix usable | noscript message; Save disabled (UD-16) |
| values URL pointing to another origin (tampered attribute) | n/a | no request, `load_failed` notice, unpruned post (SP-15) |
| bad editor data attributes | n/a | editor inert, error notice, nothing written |
| values named `__proto__` / `constructor` | n/a | preserved through serialize, import and export |
| bulk import / export | none | client CSV import with preview, header display, record cap, add-missing; export with BOM and optional formula protection |
| API, extended API, project cascades | mapping as written | unchanged, never pruned by the editor rules (BC-02) |

## 12. Edge cases
- **Duplicate list values** collapse to one key.
- **Crafted self-parent or cycle**: the endpoint returns values; the server cycle validation rejects the save; the posted state is re-rendered dirty.
- **Parent deleted while the page is open**: fetch 404, error notice, unpruned post; `resolve_parent_for_save` nil, parent set to nil (D9), keys inert.
- **multiple turned off** with multi defaults: first in child order (client and server).
- **RTL**: logical CSS properties. **Long labels** wrap.
- **Two editors on one page**: instance per root, no global ids.
- **Back/forward**: hidden payload never restored (`autocomplete=off`, always blank at render); textarea and parent select re-read at init.
- **/new AJAX re-render** removes the old instance (WeakMap); `beforeunload` checks `isConnected`.
- **Stale check race**: digest compared in `before_validation`; a write between check and commit is not detected (no row lock). Accepted and documented.
- **Rack limits changed by environment variables**: the editor uses defaults; README notes `RACK_*` overrides and proxy limits.
- **Import**: CRLF/CR/LF mix; quoted newline keeps the start line; BOM stripped; Excel trailing separators tolerated; tab-separated paste auto-detected; ambiguous names fail; NFD matches NFC; more than 200,000 records refused.
- **Export then import** round-trips, with or without formula protection.

## 13. Tests (summary; details in `tests`)
- Ruby: one payload spec for both entry points (WP-21); transport spec `spec/models/custom_field_dependencies_transport_spec.rb` (callbacks in `CustomFieldValidationPatch`, registered before the storage validation, stand-in spec unaffected, single parse, after_save reset, GET new no echo; WP-22); `CustomField.safe_attribute_names` includes `value_dependencies`, `default_value_dependencies` and `dependencies_json` (BC-04, WP-22); admin request specs (including the over-limit urlencoded 404 and the multipart 3 MB save; WP-22, WP-25); BC-02 preservation specs (WP-22); endpoint spec with the wire-format contract, endpoint == presenter == `test/js/fixtures/value_options.json` (WP-24); presenter spec, including `storage-warn` and the storage attributes only with a limit (WP-24) and `for_project` storage limit == `ProjectStoragePolicy.format_store_limit(field)` (WP-31); view spec (WP-24); editor fixture spec with fixed ids from the WP-02 ranges and a sequence-advance self-check (WP-24); locale parity example proving `DependencyEditorConfig::I18N` is iterated (WP-24); payload contract spec posting the JS-generated payload fixtures to the admin (WP-23) and project (WP-27) endpoints.
- Failed-save re-render (gap 1), asserted in WP-22 (model and admin request), WP-25 (admin form) and WP-27 (project page): `data-dcf-editor-mapping` holds the posted mapping, `data-dcf-editor-dirty="1"`, hidden input blank, no `data-dcf-editor-echo`.
- JS: model tests (node --test, no DOM; WP-23, WP-26) and jsdom editor tests on the generated fixtures (WP-25, WP-26, WP-27); scale tests use the single shared large-list generator chosen by the consolidated plan (R12), no editor-specific generator.
- JS cases added by the final critic (gap 12): WP-25 jsdom, cross-origin `data-dcf-editor-values-url` gives no fetch and the `load_failed` notice; WP-25 `test/js/dependency_editor_storage.test.js` (warning with `text_dcf_storage_estimate` at or above `data-dcf-editor-storage-warn` percent of `data-dcf-editor-storage-limit`, no warning without the attribute, possible-values estimate against `data-dcf-editor-values-limit`); WP-26 jsdom, "Add missing child values" is not rendered on the project fixture nor for enumeration children.
- Opt-in system spec (`DCF_SYSTEM_SPECS=1`; WP-25, WP-26, WP-27).
- QA step for R13: `bundle exec rspec spec/frontend --seed 1` and `--seed 4242` both compare clean.
- Characterization first: admin nested-param behavior (including documented bugs) and the project update, pinned in WP-04 (0.1.0 (M1)) and flipped in the switching commits (WP-25 admin, WP-27 project) with listed flips.

## 14. Implementation order
1. Characterization request specs (admin nested params, project update). WP-04, 0.1.0 (M1).
2. `DependencyPayload` + spec (both entry points). WP-21.
3. Transport callbacks in `CustomFieldValidationPatch`, safe attribute, model error locales, admin request specs, BC-02 specs (needs server `prune_mapping`, `value_keys`, `resolve_parent_for_save` from WP-05 and the module from WP-11). WP-22.
4. Endpoint + route + wire format + spec. WP-24.
5. Presenter + partial + view/presenter specs; editor fixture spec on the shared fixture helper of WP-16. WP-24. Format partials reordered and the old matrix deleted: WP-25.
6. Model JS + node tests (payload fixtures written here). WP-23 (after WP-21 and WP-22; WP-25 depends on it).
7. Editor JS + CSS + hook asset list + jsdom tests (conflict panel, pre-check, multipart switch, inert mode, same-origin check, storage estimate). WP-25.
8. Import/export UI + tests. WP-26.
9. Project page integration with point 9 + payload contract spec. WP-27 (project storage limit attribute: WP-31).
10. Locales at parity (key list of section 9, texts from `large_lists_i18n_registry.md`), README, CHANGELOG, system spec. Each owner WP adds its own keys and lines in its own commit (section 9); WP-32 finalizes CHANGELOG and README for 0.1.0 (M3).

All steps from 2 on ship in 0.1.0 (M3) (WP-21 to WP-27, WP-31, release WP-32); the old matrix is deleted in WP-25, together with the switch of the admin form to the editor.

## 15. CHANGELOG lines (editor area, for the 0.1.0 (M3) section; BC-14 items 19-30)

These lines go into the 0.1.0 (M3) section. The canonical wording is the 0.1.0 (M3) CHANGELOG list of `large_lists_work_packages.md` section 3; where the two differ, that list wins. Owner WPs: WP-25 (editor, transport switch, no-JS behavior, removed partials), WP-26 (import/export), WP-27 (project page and deprecation), WP-32 (release).
- Added: dependency editor for the admin custom field form (collapsible sections per parent value, search, check or uncheck all shown, filters for values without links, counters, inactive values), also used on the project dependency page.
- Added: CSV import (paste or file, preview, merge or replace, undo) and CSV export of the dependency mapping, with optional formula protection; "Add missing child values" for List (depending) fields in the admin import.
- Added: live update of the editor when the parent field or the possible values change in the admin form.
- Added: a save is refused when someone else changed the dependency mapping after the page was opened; the editor then shows the current version and your version (use, keep or export yours).
- Changed: the admin form sends the dependency mapping as one field (`custom_field[dependencies_json]`) and is submitted as multipart/form-data while the editor is active.
- Changed: saving the admin form without touching the dependencies leaves the stored mapping unchanged (before: re-posted and pruned).
- Changed: changing the parent field in the admin form removes links that do not match the new parent's values (before: kept under the new parent).
- Changed: the default value field stays visible until a parent field is chosen.
- Changed: editor saves store defaults as one value for single-value fields and as a list for multi-value fields; API GET output can change after an editor save (normalized order and default shape); the JSON API itself is unchanged.
- Changed: the dependency editors need JavaScript. Without it the admin form keeps the mapping unchanged and the project page disables Save.
- Changed: the admin form asks for confirmation before a format change that would discard unsaved dependency edits, warns before leaving with unsaved edits, and now places the dependency editor after 'Hide when no valid options' and the edit style. (WP-25, gap 11)
- Fixed: unticking every link now clears the mapping; parent values containing `[` or `]` and mappings with more than 4,096 links can be saved; the "Translation missing: label_default_value" header is gone.
- Fixed: links to inactive key/value entries are kept on admin saves. Links already dropped by earlier versions cannot be restored.
- Fixed: orphan links (to values that no longer exist, including keys corrupted by `[` or `]` in earlier versions) are reported and removed at the next editor save; affected parent values must be re-linked once.
- Deprecated: project page nested params `value_dependencies[...]` (deprecated in 0.1.0, accepted throughout 0.1.x, removed no earlier than 0.2.0). The admin safe attributes `value_dependencies` and `default_value_dependencies` remain permanently for integrations such as jc-redmine_extended_api.
- Removed: partials `custom_fields/formats/_dependencies_matrix` and `_default_dependencies`; CSS classes `.dependencies-matrix*`, `.dependencies-defaults*`, `.dcf-dependencies-matrix`; locale key `text_dependency_matrix_help` (WP-27).
- Upgrade notes: copied Key/Value list (depending) fields keep links to the source field's entries (no remap); they show as orphans and are removed at the first editor save. Reverse proxies limit request bodies (nginx `client_max_body_size` is 1 MB by default): raise it for very large mappings. Restart Redmine after upgrading (new asset files).
