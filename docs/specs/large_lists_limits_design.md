# Large lists and MySQL safety (cross-cutting): implementation plan, revision 2

> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: none of 1 to 9 directly (cross-cutting MySQL/MariaDB TEXT safety, README row "x"); it supports 6 (shared normalizer `storage_preview`, `FieldIndex`), 7 and 8 (editor storage attributes and client estimate) and 9 (project service error mapping, audit cap, project storage ceiling). Owner area: limits (cross-cutting MySQL TEXT safety: `StorageLimits`, the `CustomFieldValidationPatch` registration point, service error mapping, `OperationError`, `translate_error`, `AuditPayload`, `StorageReport`, `CoreColumnWidener`, rake tasks, README storage section, limits locale keys). Work packages: WP-11, WP-12, WP-13 (primary, release 0.1.0), WP-31 (project storage ceiling and value length cap, release 0.3.0); contributing: WP-02 (generator byte helpers, rails_helper tags, locale parity spec, 0.0.16), WP-05 (`FieldIndex`, 0.0.16), WP-06 (`normalized_store_pairs`, `storage_preview(custom_field, store)`, 0.0.16), WP-22 (editor transport callbacks join `CustomFieldValidationPatch`, 0.3.0), WP-24 (storage attributes, `text_dcf_storage_estimate`, 0.3.0), WP-25 (client estimate warning and `test/js/dependency_editor_storage.test.js`, 0.3.0), WP-27 (project delta caps of 6.3, 0.3.0). Decisions: UD-22, UD-25, UD-26, UD-27, UD-28; related: UD-01 (release structure), UD-03 (SD-01 timing, section 16), UD-32 (dispatch of the manual MariaDB workflow, resolved).

**Consolidation.** The final completeness critic (gap 4: `storage_preview(custom_field, store)` called as `format.storage_preview(record, record.format_store)`, one `translate_error(error_or_key)` method called as `translate_error(e)`; gap 5: `ClientConfig::I18N` and `DependencyEditorConfig::I18N`; gap 1: failed-save re-render; gap 12: client storage estimate test in WP-25) and the binding contracts of `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts", including the rows "Large-list generator", "FieldIndex API" and "Service storage error text") and section 3 ("Contract rows added during consolidation") are applied inline below. Where the revision 2 text conflicted with them, they win. Release targets follow the work packages: 0.0.16 = WP-01..WP-07, 0.1.0 = WP-08..WP-14, 0.2.0 = WP-15..WP-20, 0.3.0 = WP-21..WP-32. Storage validation, the usage hint, the service error mapping, flash escaping, the audit cap and the rake tasks ship in 0.1.0 (WP-11 to WP-13); the editor storage attributes and the client estimate ship in 0.3.0 (WP-24, WP-25); the project storage ceiling ships in 0.3.0 (WP-31, UD-22). Locale texts live only in `large_lists_i18n_registry.md`; this document names keys, interpolations and owner WPs.

Scope:
- (a) byte-size validation of `custom_fields.possible_values` and `custom_fields.format_store`;
- (b) the audit value cap;
- (c) opt-in rake tasks, README and CHANGELOG;
- (d) issue-form payload size;
- (e) server CPU, the single topology helper and memoization rules;
- (f) the consolidated deterministic large-list generator and MySQL testing without a MySQL CI job.

The plugin repo was not modified. Prototypes and logs live under `SCRATCH = <planning scratch space, not part of the repository>/design/limits/`. Revision 2 prototypes are in `SCRATCH/proto2/`.

## 0. What changed in revision 2

| Issues | Change | Section |
|---|---|---|
| R5, QA-04, BC-13, UX-04 | Limits is the single owner of the storage guard. That covers one module, one registration point, one error key, one service mapping, one `translate_error` and one `OperationError` signature. The server copy (`dcf_too_large`, `too_large?`, `report`, registration inside `CustomFieldPatch`) is dropped. The project copy (`guard_storage!`, `save_field!`, `error_value_too_large`, `text_dcf_size_detail`) is dropped too. | 2, 4, 5 |
| R8, BC-02 | The shared normalizer is sanitize-only, exactly today's before_save. D6 pruning runs only in the admin `dependencies_json` before_validation. | 4.4 |
| R10, SP-09 | There is one audit cap: `AuditPayload`, 16,384 bytes, used by `AuditRecorder`, and the project's 60,000-byte cap is dropped. Marker keys are now `payload_truncated`, `payload_bytes` and `payload_sha256`, so they no longer collide with the delta's own digest (`mapping_sha256` in the consolidated WP-27 delta; `sha256` in the revision 2 prototype) and `truncated`. Top-level scalars survive shrinking. The project delta is capped at 20 entries, 3 defaults per entry and 80 encoded bytes per label; the measured worst case is 13,603 B. A ValueTooLong row stores no DB message. | 5.3, 6 |
| R11, QA-05, UX-03 | This area's locale registry: `field_value_dependencies` ("Dependency mapping") is owned here. Duplicate and dropped keys are listed. The parity spec gets a duplicate-key check. | 11 |
| R12 | One generator. Revision 2 proposed quality's mulberry32 `DcfLargeList` (pinned `0634a624422f2f06`); consolidation adopted the arithmetic generator instead (WP-02, 0.0.16: pinned `233acf899217e962` for the names and `466b240daca61be9` for the partition, JS twin; compat section 2.4 row "Large-list generator"). The byte-target helpers from this area are Ruby-only functions of that module. | 10.1 |
| R13 | The storage attributes are adapter-dependent. The fixture spec stubs `column_limit` and puts a placeholder in place of `storage-base`. | 10.4 |
| R18 | One topology helper (`FieldIndex`, server names `load`/`children_ids`, WP-05) and one report (`StorageReport`). `DependencyRules::Graph` and `StorageLimits.report` are removed. | 7.2, 9.3 |
| R20, UX-04 | One set of client attributes in the `data-dcf-editor-*` namespace, one 90% threshold for the server hint and the client warning, one client key, byte units everywhere, and `dependencies_json` used as the name throughout. | 4.9, 4.10 |
| R1, QA-01, UX-02, BC-01, SP-04 | This area no longer specifies issue-form map pruning. It defers to the server-owned canonical attribute table (map sanitized, not pruned). | 8 |
| SP-06 | `translate_error` HTML-escapes every interpolation before `l()`. No payload content is ever put into a flash. Callers holding an `OperationError` call `translate_error(e)` (gap 4). | 5.4 |
| SP-19 | The widener validates character set and collation names as identifiers and refuses the ALTER otherwise. | 7.3 |
| R3, QA-02, BC-03, SP-01, SP-02, SP-17 | The adopted payload contract this area relies on is stated in one place. | 12 |
| BC-14 | CHANGELOG lines including Upgrade notes for this area. | 7.7 |
| SP-07 | Listed as a separately tracked SECURITY defect. | 16 |

## 1. Evidence

Revision 1 evidence, verified on a real MariaDB 10.11.14 server installed in the sandbox:
- Redmine 5.1 (Rails 6.1.7.10, Ruby 3.2.6) and Redmine 7.0 (Rails 8.1.4, Ruby 3.3.6) copied to `SCRATCH/redmine-{5.1,7.0}-mysql`, with `adapter: mysql2`;
- core and plugin migrated, probes run with `bin/rails runner -e test`.

| # | Fact | Evidence |
|---|---|---|
| V1 | `CustomField.columns_hash['possible_values'/'format_store'].limit` is 65535 on TEXT, 16777215 on MEDIUMTEXT and 4294967295 on LONGTEXT, on Rails 6.1 and 8.1. | `SCRATCH/probe_mysql.{5.1,7.0}.out` |
| V2 | AR sessions are strict by default (`STRICT_ALL_TABLES`). An oversized value raises `ActiveRecord::ValueTooLong`. | same |
| V3 | In a non-strict session, 5,570 values are stored as exactly 65,535 bytes and reload as 2,469 values. A cut landing after `- ` loads a nil element, and core `CustomField#possible_values` then raises `FrozenError` on every read (core-5.1 `app/models/custom_field.rb:181`, core-7.0 `:206`). | `SCRATCH/probe_nonstrict{,2}.rb` |
| V4 | `CustomField.type_for_attribute(col).serialize(value).bytesize` equals `LENGTH(col)` in the DB: possible_values 49,314 = 49,314, post-normalization format_store 61,062 = 61,062. The pre-normalization value is 10 bytes off. | `SCRATCH/probe_validation.{5.1,7.0}.out` |
| V5 | Exact boundary: a 65,535-byte YAML list saves; 65,536 is rejected with an i18n message. | same |
| V6 | An explicit `ALTER TABLE ... MODIFY col MEDIUMTEXT CHARACTER SET x COLLATE y NULL` preserves charset, collation and nullability. A naive revert that hard-codes a collation silently changes it. | `SCRATCH/probe_mysql.*.out` |
| V7 | Narrowing back to TEXT under strict mode with an 87,504-byte row fails instead of truncating. | same |
| V8 | A running process keeps the old 65,535 limit after an ALTER until `reset_column_information` (a restart). This is the safe direction. | `SCRATCH/probe_schema_cache.rb` |
| V9 | The rake tasks register under `redmine:depending_custom_fields:*`, plugin `lib/` eager-loads under Zeitwerk, and report and widener work end to end on 5.1 and 7.0. | `SCRATCH/probe_tasks.{5.1,7.0}.out` |
| V10 | Service integration on MariaDB: an oversized save becomes an audited `OperationError` with interpolations and the DB is unchanged. An unknown limit falls through to the `ValueTooLong` safety net. | `SCRATCH/probe_services.7.0.out` |
| V11 | The suite is green on MariaDB: 259 examples, 0 failures (5.1 and 7.0), unchanged and patched. Registering `validate` inside `CustomFieldPatch.prepended` broke 14 examples of `spec/patches/custom_field_required_validation_spec.rb`, whose stand-in class (`:31-33`, prepend at `:60`) has no callback API. A separate prepended module fixed it. | `SCRATCH/run/rspec{51,70}_mysql{,_patched}.log` |
| V12 | A symbol `validate` registered from a `prepended` hook is deduplicated when init.rb runs twice. | `SCRATCH/probe_dedup.rb` |
| V13 | Psych array dumps are additive: `dump(list) == 4 + sum(element bytes)`. | `SCRATCH/proto/additivity_check.rb` |
| V14 | Raw-regex extraction of `parent_custom_field_id` takes 0.041 ms vs 16.6 ms for a YAML parse (S1 row); 9/9 YAML shape cases are correct. | `SCRATCH/proto/field_index_bench.rb` |
| V17 | Revision 1 prototypes parse under TargetRubyVersion 2.7. | `SCRATCH/rc/` |

New in revision 2:

| # | Fact | Evidence |
|---|---|---|
| V19 | AuditPayload v2 tests: 8 runs, 40 assertions, 0 failures on ActiveSupport 8.1.4 / Ruby 3.3.6 and on ActiveSupport 6.1.7.10 / Ruby 3.2.6. <br>- Project delta worst case, with CAP 20, 3 defaults per entry and labels cut to 80 encoded bytes, over 5 adversarial label classes (`<`, emoji, `"`, `\u0001`, `é`, 400 chars each): 12,963 to 13,603 B. It is returned byte-identical, never shrunk. <br>- An S1-like full mapping of 162,452 B shrinks to 16,322 B. <br>- A forced shrink keeps the delta's own `sha256` (renamed `mapping_sha256` in the consolidated WP-27 delta), `truncated` and `added`. <br>- Adversarial inputs stay under the cap. | `SCRATCH/proto2/audit_payload.rb`, `label_cap.rb`, `dependency_delta_v3.rb`, `audit_payload_test.rb` |
| V20 | Generator prototype (quality's revision 2 mulberry32 algorithm plus this area's helpers): `names(5570, seed: 42)` SHA-256 prefix `0634a624422f2f06`. `values_of_yaml_bytes` hits 16 / 1,000 / 65,535 / 65,536 / 200,000 bytes exactly. Additivity holds with stressors, and the S1 YAML is 83,009 B. Ruby 3.2.6 and 3.3.6: 6 runs, 16 assertions, 0 failures. The mulberry32 base is withdrawn by consolidation (10.1); the ASCII-padding byte-target technique does not depend on the base and carries over to the adopted arithmetic generator (WP-02 pins `values_of_yaml_bytes(1_000 / 65_535 / 65_536)` exact). | `SCRATCH/proto2/dcf_large_list.rb`, `dcf_large_list_test.rb` |
| V21 | Widener with a fake connection: a malicious collation name is refused with exit 1 and no SQL. The `max_allowed_packet` warning prints below 16 MB, the dry-run SQL is exact, and CONFIRM sets strict mode before the ALTER. 4 runs, 17 assertions, 0 failures. | `SCRATCH/proto2/core_column_widener.rb`, `core_column_widener_test.rb` |
| V22 | Revision 2 production prototypes have 0 offenses under `Lint/Syntax` at TargetRubyVersion 2.7, and 0 offenses under core 7.0 `.rubocop.yml` with plugins un-excluded plus the quality overlay (TargetRubyVersion 2.7, TargetRailsVersion 6.1). | session run against `SCRATCH/../research/redmine-7.0` |

Facts inherited from research_limits.json:
- TEXT break-even: about 4,251 list values, 3,749 list links or 5,024 enumeration links.
- S1 (27 x 5,570 list): possible_values 85,869 B, format_store 98,292 B.
- YAML parse costs 13.7 ms (S1) to 211.9 ms (S3) per CustomField load.
- Set vs Array lookups: 115 ms vs 3.6 ms.
- Validation runs before the plugin's before_save sanitization.

## 2. Single owners and removed alternatives

| Concern | Single owner and name | Removed alternatives |
|---|---|---|
| Size measurement and validation | `RedmineDependingCustomFields::StorageLimits` (`lib/redmine_depending_custom_fields/storage_limits.rb`), this area | server `StorageLimits` sketch (`dcf_too_large`, `too_large?`, `report`), project `guard_storage!` |
| Registration of every new CustomField callback | `RedmineDependingCustomFields::Patches::CustomFieldValidationPatch` (new file), prepended in init.rb. It hosts the storage validation from this area and the editor's `dependencies_json` virtual attribute and callbacks. | registration inside `CustomFieldPatch.prepended` (server S13, editor 2.3) |
| Model error key | `activerecord.errors.messages.dcf_storage_too_large`, `%{size}`/`%{limit}` | `dcf_too_large` with `%{bytes}` |
| Service error mapping | `BaseService` maps `RecordInvalid` carrying a storage violation to `:error_dcf_values_too_large` / `:error_dcf_mapping_too_large`, and `ValueTooLong` to `:error_dcf_value_too_long` | project pre-check `save_field!`/`guard_storage!`, `error_value_too_large`, `text_dcf_size_detail` |
| `OperationError` signature | `OperationError.new(key, http_status: :unprocessable_entity, audit_status: 'validation_failed', summary: nil, interpolations: nil, payload: nil)` | the separate limits and project kwarg sets |
| Flash translation | controller `translate_error(error_or_key)` (one method, one parameter), which escapes interpolations; callers holding an `OperationError` call `translate_error(e)` (gap 4; WP-12, and WP-27 to WP-31) | `translate_error(key, interpolations)`, `translate_error(e.key, e.interpolations)` |
| Audit value cap | `AuditPayload` (16,384 B), used by `AuditRecorder` | project `AuditRecorder::MAX_VALUE_BYTES = 60_000` |
| Field topology | `RedmineDependingCustomFields::FieldIndex` (server-owned file with the server names `load`/`children_ids`, WP-05, 0.0.16; this area contributes the raw-regex extraction and the acceptance criteria of 9.3) | `DependencyRules::Graph`, per-hop `find_parent` ancestor walk, per-page child loading in `UsageCalculator`, this area's revision 2 names `build`/`child_ids`/`children` |
| Size report | `RedmineDependingCustomFields::StorageReport` | `StorageLimits.report` |
| Large-list generator | `DcfLargeList` in `spec/support/dcf_large_list.rb` (WP-02, 0.0.16): the arithmetic generator owned by quality (pinned `233acf899217e962` for `names(5570, tricky_every: 97)`, `466b240daca61be9` for the partition, JS twin `test/js/support/large_list.js`) plus the Ruby-only byte helpers from this area | the mulberry32 generator and its pinned hash `0634a624422f2f06` (proposed by revision 2 of this area), `spec/lib/dcf_large_list_spec.rb`, `spec/quality/large_list_parity_spec.rb` |
| Client storage estimate inputs | `data-dcf-editor-storage-limit`, `-storage-base`, `-values-limit`, `-storage-warn`, rendered by `DependencyEditorConfig` (WP-24, 0.3.0) | `data-dcf-storage-*` (revision 1), the editor's constant `+256` |

## 3. Architecture: four layers, fail closed

1. **Transport guard** (editor area, section 12; WP-21 and WP-22, 0.3.0): the single `dependencies_json` field is rejected above 4 MiB before decoding.
2. **Storage validation** (this area, WP-11, 0.1.0): `StorageLimits` measures the exact bytes ActiveRecord will write and compares them with the column limit. It runs for the admin form, the plugin JSON API, the core `/custom_fields` API, other plugins and every project service, because all of them go through `CustomField#save`/`save!`.
3. **Service mapping** (this area, WP-12, 0.1.0): `BaseService#call` turns a storage violation into a specific, translated, audited `OperationError`. A database `ValueTooLong` that got past the validation (a limit the app does not know) becomes a generic audited error instead of an HTTP 500.
4. **Audit cap** (this area, WP-12, 0.1.0): every audit before/after value is at most 16,384 bytes, so the audit insert inside the change transaction can never overflow TEXT and roll the change back.

Operations tooling (report, widening; WP-13, 0.1.0) and documentation sit beside these layers and never run automatically. The project storage ceiling (4.11; WP-31, 0.3.0, UD-22) is an additional, smaller limit on project-page writes inside layer 2.

## 4. (a) Size validation

Release: 4.1 to 4.9 ship in 0.1.0 (WP-11; UD-25, UD-28). The client estimate contract of 4.10 ships in 0.3.0 (attributes and key in WP-24, warning and its test in WP-25). The project storage ceiling of 4.11 ships in 0.3.0 (WP-31, UD-22).

### 4.1 Files and registration

- `lib/redmine_depending_custom_fields/storage_limits.rb` (new, stateless, `module_function`), required from `lib/redmine_depending_custom_fields.rb` with `require_relative`.
- `lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb` (new):

```ruby
# frozen_string_literal: true

module RedmineDependingCustomFields
  module Patches
    # Every CustomField callback added by this plugin version lives here, not in
    # CustomFieldPatch: spec stand-in classes prepend CustomFieldPatch without a
    # callback API (spec/patches/custom_field_required_validation_spec.rb:31-33,60).
    module CustomFieldValidationPatch
      def self.prepended(base)
        base.before_validation :dcf_apply_dependencies_json   # body: editor area (D6 pruning lives here)
        base.validate :dcf_validate_dependencies_json         # body: editor area
        base.validate :dcf_validate_storage_limits            # body: this area
      end

      # dependencies_json= / dependencies_json / dcf_apply_dependencies_json /
      # dcf_validate_dependencies_json: editor area, unchanged from its design 2.3.

      private

      def dcf_validate_storage_limits
        RedmineDependingCustomFields::StorageLimits.validate(self)
      end
    end
  end
end
```

- In `init.rb`, require it next to the other patch requires and add `CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldValidationPatch` right after the existing `CustomField.prepend ...CustomFieldPatch` (init.rb:61). This is the same convention as today: no `to_prepare`.
- Symbol callbacks are deduplicated if init.rb runs twice (V12). The quality design removes the second load anyway.
- `CustomFieldPatch.prepended` registers no new callback. Its `after_save` dispatch disappears with point 1 (WP-18, 0.2.0).
- Staging of the module: WP-11 (0.1.0) creates it with only `validate :dcf_validate_storage_limits`; WP-22 (0.3.0) adds the two editor transport callbacks shown above to the same module; WP-31 (0.3.0) adds the non-persisted `dcf_storage_ceiling` accessor (4.11). There is no separate `CustomFieldStoragePatch` or transport patch module (compat section 2.4 row "CustomField callback registration").
- Ordering: every `before_validation` runs before every `validate`. The storage validation therefore always measures the decoded and pruned mapping.
- Why not the formats' `validate_custom_field`: core iterates `format.validate_custom_field(self).each do |attribute, message|` (core-5.1 `app/models/custom_field.rb:146`, core-7.0 `:160`). That drops interpolation options and error details, and the core `list` and `enumeration` formats are not plugin classes.

### 4.2 API

Prototype: `SCRATCH/proto/storage_limits.rb`. Revision 2 renames the signatures to the ones below.

```ruby
module RedmineDependingCustomFields
  module StorageLimits
    MYSQL_TEXT_BYTES = 65_535
    WARN_PERCENT = 90
    COLUMNS = { 'possible_values' => :possible_values, 'format_store' => :value_dependencies }.freeze
    GUARDED_FORMATS = %w[list enumeration depending_list depending_enumeration].freeze
    MAPPING_KEYS = %w[value_dependencies default_value_dependencies].freeze
    ERROR = :dcf_storage_too_large
    Violation = Struct.new(:custom_field_id, :custom_field_name, :column, :attribute, :bytes, :limit,
                           keyword_init: true)
    Usage = Struct.new(:column, :attribute, :bytes, :limit, :percent, keyword_init: true)

    module_function

    def mysql?                                   # Redmine::Database.mysql?, rescue StandardError => false
    def column_limit(column, model = CustomField) # 4.3; the spec seam
    def guarded?(record)                         # GUARDED_FORMATS.include?(record.field_format.to_s)
    def check_column?(record, column)            # record.new_record? || record.will_save_change_to_attribute?(column)
    def preview_value(record, column)            # 4.4; format_store: record.format.storage_preview(record, record.format_store)
    def serialized_bytesize(model, column, value)
      dumped = model.type_for_attribute(column.to_s).serialize(value)
      dumped.nil? ? 0 : dumped.to_s.bytesize
    end
    def preview_bytes(record, column)            # serialized_bytesize(record.class, column, preview_value(record, column))
    def violations(record)                       # [] unless guarded?; per COLUMNS entry: limit, changed, bytes > limit
    def validate(record)
      violations(record).each do |v|
        record.errors.add(v.attribute, ERROR,
                          size: delimited(v.bytes), limit: delimited(v.limit),
                          bytes: v.bytes, max_bytes: v.limit, column: v.column)
      end
    end
    def violation_in(record)                     # first Violation rebuilt from record.errors.details (COLUMNS order), or nil
    def usage(record)                            # 4.9; Usage rows at or above WARN_PERCENT, [] otherwise
    def base_bytes(record)                       # serialized_bytesize(CustomField, 'format_store', store without MAPPING_KEYS)
    def delimited(number)                        # ActiveSupport::NumberHelper.number_to_delimited(number) in the current locale
  end
end
```

The `errors.add` call passes explicit keys and values; there is no Ruby 3.1 hash shorthand anywhere. `too_large?` and `report` do not exist: callers use `violation_in`, and the rake report uses `StorageReport`.

WP-31 (0.3.0) extends this API for the project storage ceiling (4.11): `effective_limit(record, column)` returning `[limit, source]`, `violations` comparing against it, `Violation` gaining `source`, and `errors.add` passing `source: v.source` with an explicit key. Until WP-31 the limit is `column_limit` alone.

### 4.3 Column limit

```ruby
def column_limit(column, model = CustomField)
  col = model.columns_hash[column.to_s]
  return nil unless col

  limit = col.limit
  limit = MYSQL_TEXT_BYTES if limit.nil? && col.type == :text && mysql?
  limit
end
```

- PostgreSQL and SQLite report `nil`: no check, no cost.
- MySQL and MariaDB report 65535 (V1). This covers mysql2, and trilogy on 6.1/7.0, because core-7.0 `lib/redmine/database.rb:60-61` matches `/mysql|trilogy/i`; 5.1 matches `/mysql/i`.
- The fallback covers a `nil` limit on a text column. Another adapter that reports a limit is honoured as reported.
- The limit comes from the schema cache. After widening, a running process keeps validating against 65,535 until it is restarted (V8). That is conservative, and it is documented.

### 4.4 Exact bytes: one sanitize-only normalizer (R8)

- **possible_values.** Core `possible_values=` normalizes at assignment. Preview = `record.read_attribute('possible_values')`.
- **format_store.** The depending formats normalize in `before_custom_field_save`, which core calls from `before_save` after validation. The shared depending-format module (point 6, `DependingFormatMethods`, server area, WP-06, 0.0.16) exposes ONE normalizer used by both paths. It is exactly today's before_save logic (`depending_list_format.rb:18-28`, `depending_enumeration_format.rb:18-28`) and contains no pruning. The canonical code is server design section 5; the excerpt below shows the parts this area relies on:

```ruby
# in DependingFormatMethods (point 6, WP-06)
def normalized_store_pairs(custom_field)    # ordered [[key, value], ...] exactly as before_save assigns them
  pairs = []
  if custom_field.parent_custom_field_id.present?
    pairs << ['parent_custom_field_id', DependencyRules.resolve_parent_for_save(custom_field)&.id]
  end
  pairs << ['value_dependencies', Sanitizer.sanitize_dependencies(custom_field.value_dependencies)]
  pairs << ['default_value_dependencies',
            Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)]
  pairs
end

# Called by StorageLimits.preview_value as format.storage_preview(record, record.format_store) (gap 4).
# There is no one-argument form.
def storage_preview(custom_field, store)
  preview = store.respond_to?(:to_hash) ? store.to_hash : {}
  normalized_store_pairs(custom_field).each { |k, v| preview[k] = v }
  preview
end

def before_custom_field_save(custom_field)
  super
  pairs = normalized_store_pairs(custom_field)
  pairs.each { |k, v| custom_field.public_send("#{k}=", v) }
  parent = pairs.assoc('parent_custom_field_id')
  custom_field.default_value = nil if parent && parent.last
end
```

- `StorageLimits.preview_value(record, 'format_store')` returns `record.format.storage_preview(record, record.format_store)` when the format responds to `storage_preview` (compat section 3 row "storage_preview"), and the raw store otherwise. Core `list` and `enumeration` inherit the no-op `Base#before_custom_field_save` (core-5.1 `lib/redmine/field_format.rb:339`, core-7.0 `:341`), so their raw store is exactly what gets written. The measurement is therefore exact for all four guarded formats.
- `DependencyRules.resolve_parent_for_save` memoizes on the record, never on the format singleton, keyed by the raw id string. Validation and before_save then do one lookup.
- Key order: an existing store key keeps its position when overwritten in both paths, and new keys are appended in the same order. The YAML is therefore byte-identical (V4). The store's IndifferentCoder converts a plain Hash to HashWithIndifferentAccess before dumping, so the copy made with `to_hash` serializes identically.
- **D6 pruning is NOT part of the normalizer.** It runs only in `dcf_apply_dependencies_json` (editor area, `before_validation`, admin JSON transport, only when JSON was posted). The following paths therefore never prune:
  - the plugin JSON API, which saves before `assign_enumerations` (`app/controllers/depending_custom_fields_api_controller.rb:43-47,61-65`);
  - jc-redmine_extended_api's `safe_attributes=` then save;
  - project cascades (`child.save!`, `base_service.rb:236-261`);
  - `SetDefaultValueService`;
  - admin saves where the editor is not dirty.
- Hard requirement for the transport areas: `dependencies_json` is decoded and assigned in `before_validation` (admin, WP-22) or inside `DependencyMappingService#perform!` before `save!` (project, WP-27), never in `before_save`. Otherwise validation would measure the old mapping. Spec: "preview bytes equal stored bytes" (section 10.2).

### 4.5 Only changed columns

`check_column?(record, column)` is `record.new_record? || record.will_save_change_to_attribute?(column)`.
- Serialized attributes are compared by their dumped form, so an unchanged textarea or store is not re-checked. V5: renaming a field whose stored columns exceed a simulated 1,000-byte limit saves; adding a value is rejected.
- An existing oversized row, which is only possible after a limit drop, never blocks unrelated edits.
- Cost per changed column is one dump for the dirty check plus one for the preview: 55.8 ms (7.0) and 66.4 ms (5.1) for a 27 x 3,600 field with both columns changed. Admin and configuration saves only.

### 4.6 Guarded formats

`list`, `enumeration`, `depending_list` and `depending_enumeration`: the four formats the plugin writes through (project services, JSON API `field_formats`, `depending_custom_fields_api_controller.rb:84-88`).
- Enumeration values are rows (`custom_field_enumerations.name`, model max 60), so for enumeration formats only format_store matters.
- Other formats are never touched.
- Guarding core `list` matters: a 5,000-city parent list is 77 KB and today fails with a 500 or truncates. This choice is owner decision UD-25 (recommended: yes; WP-11 `GUARDED_FORMATS`, upgrade note).

### 4.7 Error, i18n, details

- `record.errors.add(:possible_values | :value_dependencies, :dcf_storage_too_large, size: "98,292", limit: "65,535", bytes: 98292, max_bytes: 65535, column: "format_store")`.
- The message key `activerecord.errors.messages.dcf_storage_too_large` is nested, for the Rails default lookup and `errors.of_kind?`.
- Labels: `:value_dependencies` uses `field_value_dependencies`, owned by this area with the wording "Dependency mapping" (section 11). `:possible_values` uses core `field_possible_values`. Redmine `human_attribute_name` looks up `field_<attr>` (core-7.0 `app/models/application_record.rb:23-32`, core-5.1 `config/initializers/10-patches.rb:6-17`).
- Numbers use the locale's `number.format.delimiter` at validation time: en on 7.0 `65,536`, en on 5.1 `65536` (empty core 5.1 delimiter), de `65.536`, fr `65 536`, nl `65.536` (V5).
- Full messages (illustrative; the authoritative en/de/fr/nl texts are in `large_lists_i18n_registry.md`):
  - en: `Possible values is too large to store (65,536 bytes, the database allows at most 65,535 bytes)`.
  - de: `Abhängigkeitszuordnung ist zu groß zum Speichern (93.725 Bytes, die Datenbank erlaubt höchstens 65.535 Bytes)`.
  - "Value dependencies is too large" would be ungrammatical in every locale; this is the reason the label wording was chosen (UX-03).
- `errors.details` keep the integers, which `violation_in` reads.

### 4.8 Where it applies

| Path | Mechanism | Result |
|---|---|---|
| Admin new/edit (core `CustomFieldsController#create/update`, core-7.0 `app/controllers/custom_fields_controller.rb:47-59,69-86`) | validation fails; core re-renders with `error_messages_for` | message in the form. On the failed-save re-render the hidden input stays blank and the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"` (no `data-dcf-editor-echo`, no `input_value`; compat section 3 row "Failed-save re-render", gap 1; editor area, WP-22 and WP-25, 0.3.0), so no work is lost. |
| Plugin JSON API create/update (`depending_custom_fields_api_controller.rb:52-56,70-74`) | `save`/`update` returns false | HTTP 422 `{"errors":["Dependency mapping is too large to store (98,292 bytes, the database allows at most 65,535 bytes)"]}`. The contract is unchanged (same key, same status as any validation error). Create rolls back the enumerations transaction. |
| Core `/custom_fields` API, jc-redmine_extended_api | model validation | 422 with the same message |
| Project services (every BaseService subclass, including source=import and the A-Z sort) | `save!` raises RecordInvalid (from WP-31, through `BaseService#save_field!` with the project ceiling, 4.11) | `OperationError` with interpolations, 422 page with an escaped flash via `translate_error(e)`, audited `validation_failed` (section 5) |
| Admin custom field reorder | columns unchanged | no check |
| Enumeration `update_all` in the sort service | guarded columns untouched | no check |

### 4.9 Server usage hint (Should; UD-28, WP-11, 0.1.0)

- **Admin custom field form.** New hook `RedmineDependingCustomFields::Hooks::CustomFieldStorageHook#view_custom_fields_form_upper_box` (core `app/views/custom_fields/_form.html.erb:21`, identical in 5.1 and 7.0, context `custom_field:`). It renders `custom_fields/_dcf_storage_usage` with explicit locals `usage:` and `admin: true`.
- **Project values and dependency pages.** Helper `dcf_storage_usage_hint(field)` renders the same partial with `admin: false`.
- **When it shows.** `StorageLimits.usage(record)` returns rows only when all of these hold: `mysql?`, persisted, guarded, and a column at or above `WARN_PERCENT` (90).
- **How it measures.** It reads raw bytes with one query: `CustomField.where(id: record.id).pick(Arel.sql('LENGTH(possible_values)'), Arel.sql('LENGTH(format_store)'))`. MySQL `LENGTH` counts bytes, so no YAML dump is needed.
- **Failure handling.** The hook and the helper rescue `StandardError` and return `''`, because a hint must never break a form.
- **Markup:**

```erb
<% usage.each do |u| %>
  <p class="dcf-storage-usage"><em class="info"><%= l(:text_dcf_storage_usage,
       label: CustomField.human_attribute_name(u.attribute), size: StorageLimits.delimited(u.bytes),
       limit: StorageLimits.delimited(u.limit), percent: u.percent) %></em></p>
<% end %>
<% if admin && usage.any? %>
  <p class="dcf-storage-usage"><em class="info"><%= l(:text_dcf_storage_admin_help) %></em></p>
<% end %>
```

  Rendered output: `Dependency mapping: 61,062 of 65,535 bytes used in the database (93%).` Only the admin variant mentions the README; project managers never get a README reference (UX-04).
- `em.info` carries no icon, so the hint renders the same on 5.1 to 7.0 (UX-10).
- The hint never runs on issue pages.

### 4.10 Client estimate contract (R20; WP-24 and WP-25, 0.3.0)

The single presenter `DependencyEditorConfig.for_admin/for_project` (editor area, WP-24) renders these on the single editor root, in the editor namespace, using `StorageLimits`:

| Attribute | Value | When |
|---|---|---|
| `data-dcf-editor-storage-limit` | `StorageLimits.column_limit('format_store')`; in project mode from WP-31 on, the effective limit `ProjectStoragePolicy.format_store_limit(field)` (4.11) | only when not nil |
| `data-dcf-editor-storage-base` | `StorageLimits.base_bytes(field)`: bytes of the in-memory format_store without the two mapping keys | with the limit |
| `data-dcf-editor-values-limit` | `StorageLimits.column_limit('possible_values')` | admin + list children only, when not nil |
| `data-dcf-editor-storage-warn` | `StorageLimits::WARN_PERCENT` (90) | with any limit |

- **Mapping estimate** (editor JS): `storage-base + ceil(utf8Bytes(JSON.stringify({value_dependencies, default_value_dependencies})) * ratio)`, with ratio 1.2 for list and 1.6 for enumeration children. The ratios come from the editor's measurement of YAML vs JSON: list 1.09 to 1.17, enumeration ids 1.42 to 1.51.
- **possible_values estimate** (admin list, including "add missing child values"): `4 + sum(utf8Bytes(v) + 3)`. This is exact for plain scalars (V13) and slightly low for values YAML must quote.
- **Warning.** When an estimate reaches `storage-warn` percent of its limit, the editor shows ONE `div.flash.warning` near Save with `text_dcf_storage_estimate`, interpolating `label` (the field label: `field_value_dependencies` or `field_possible_values`), `size` and `limit` (delimited bytes via `Intl.NumberFormat(<html lang>)`) and `percent`.
  - The text is the same on both pages and does not mention the README.
  - It is advisory; the server validation stays authoritative.
  - The editor builds the icon per UX-10.
- The editor's separate Rack body pre-check (SP-02, about 3.9 MB URL-encoded) uses its own message. It is about the request size, not storage.
- The key reaches JS through `DependencyEditorConfig::I18N` (`storageEstimate: :text_dcf_storage_estimate`; key owned by WP-24, gap 8). The editor's `text_dcf_storage_near_limit` (KB, 90%, constant +256) is dropped.
- **Test (WP-25, gap 12).** `test/js/dependency_editor_storage.test.js` (jsdom, on the editor fixtures of 10.4):
  - the warning with `text_dcf_storage_estimate` appears at or above `data-dcf-editor-storage-warn` percent of `data-dcf-editor-storage-limit`;
  - no warning without the attribute (PostgreSQL/SQLite admin form);
  - the possible-values estimate is checked against `data-dcf-editor-values-limit`.
  The server side (attributes present only when `column_limit` is non-nil, exact `storage-base`) is covered by the WP-24 presenter and fixture specs (10.4).
- The JSON field is called `dependencies_json` everywhere: `custom_field[dependencies_json]` on the admin form and `dependencies_json` on the project page. Revision 1's `value_dependencies_json` was a naming error.

### 4.11 Project storage ceiling (SP-03; WP-31, 0.3.0, UD-22)

On PostgreSQL and SQLite `column_limit` is nil, so without a ceiling a project manager could grow a field without bound. WP-31 adds an application ceiling that applies only to project-page writes. The project area owns `ProjectStoragePolicy` and `save_field!` (project design sections 2.4 and 9); the `StorageLimits` and `CustomFieldValidationPatch` additions below land in this area's files.

- **Setting.** Plugin setting `project_storage_ceiling_kib`, default 2,048, minimum 64 (values below are raised to 64 KiB; a value that is not a plain non-negative integer falls back to 2,048 KiB). `ProjectStoragePolicy.ceiling_bytes` reads it and rescues to the default.
- **Accessor.** `CustomFieldValidationPatch` adds the non-persisted `attr_accessor :dcf_storage_ceiling` (Integer bytes or nil). It is nil by default, so the admin form, the APIs and other plugins are never affected.
- **Effective limit.** `StorageLimits.effective_limit(record, column)` returns `[limit, source]`:
  - `limit` is the smaller of `column_limit(column)` and the effective ceiling; `source` is `'column'` or `'ceiling'`;
  - the ceiling counts only when `record.dcf_storage_ceiling` is set;
  - the effective ceiling is `max(dcf_storage_ceiling, persisted_bytes)`, where `persisted_bytes` (one serialize of `attribute_in_database`) is computed lazily only when the new bytes exceed the ceiling. A field an admin already made larger than the ceiling can still shrink or keep its size from project pages, but not grow.
  - On MySQL TEXT the 65,535 column limit stays the smaller limit.
- **Writes.** `BaseService#save_field!` sets `record.dcf_storage_ceiling = ProjectStoragePolicy.ceiling_bytes`, calls `save!` and resets the accessor in `ensure`. It replaces every custom field `save!` of the project services (add, rename, remove, reorder, set default, update enumerations default clearing, mapping, sort, `cascade_parent_key!`). A violation surfaces through the unchanged 5.2 mapping (`error_dcf_values_too_large` / `error_dcf_mapping_too_large`), whose neutral wording is correct for both sources.
- **Value length cap.** New or renamed list values from project services are capped at 255 characters (`ProjectStoragePolicy::LIST_VALUE_MAX_CHARS`, `OperationError(:error_dcf_value_length, interpolations: { max: 255 })`, audited `validation_failed`); existing longer values are untouched.
- **Client estimate.** In project mode the presenter renders `data-dcf-editor-storage-limit` from `ProjectStoragePolicy.format_store_limit(field)` (WP-31 lists `lib/redmine_depending_custom_fields/dependency_editor_config.rb`, gap 14).
- **Tests (WP-31).** Setting parse, default, minimum and rescue; with a stubbed small ceiling on PostgreSQL, `add_value` over it gives an audited 422, `remove_value` on a field already above the ceiling succeeds, and `save_field!` resets the accessor after an exception; 256-character add or rename gives 422 `error_dcf_value_length`; the admin form, API and import are unaffected; `DependencyEditorConfig.for_project` storage limit equals `ProjectStoragePolicy.format_store_limit(field)` (gap 14); the plugin settings page renders `project_storage_ceiling_kib` in en and de and a non-numeric POST falls back to 2,048 KiB (gap 12).

## 5. Service mapping, OperationError and flash escaping

Release: section 5 ships in 0.1.0 (WP-12). WP-27 to WP-31 (0.3.0) call `translate_error(e)` from their new actions (gap 4).

### 5.1 OperationError (one signature for all areas)

```ruby
class OperationError < StandardError
  attr_reader :key, :http_status, :audit_status, :summary, :interpolations, :payload

  def initialize(key, http_status: :unprocessable_entity, audit_status: 'validation_failed',
                 summary: nil, interpolations: nil, payload: nil)
    @key = key
    @http_status = http_status
    @audit_status = audit_status
    @summary = summary
    @interpolations = interpolations || {}
    @payload = payload
    super(key.to_s)
  end
end
```

- `summary` is the audit `changes_summary` of the failure row (project area).
- `interpolations` are the flash values (this area).
- `payload` is the already parsed `DependencyPayload::Result`, which the controller reuses on a 422 re-render so the input is parsed once per request (SP-17, project area). Only an ok payload is re-rendered: it goes to the editor as `posted: service.parsed_payload` of `DependencyEditorConfig.for_project`, which renders it in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"` while the hidden input stays blank (gap 1; WP-27, 0.3.0).
- Defaults keep every existing call valid.

### 5.2 BaseService (`app/services/redmine_depending_custom_fields/base_service.rb`)

The rescue chain of `call` (today `:69-75`) becomes:

```ruby
rescue ConfirmationRequired
  raise
rescue OperationError => e
  record_failure(e.audit_status, e.key.to_s, e.summary)
  raise
rescue ActiveRecord::RecordInvalid => e
  violation = StorageLimits.violation_in(e.record)
  if violation
    error = storage_error(violation)
    record_failure(error.audit_status, error.key.to_s, error.summary)
    raise error
  end
  record_failure('save_failed', AuditPayload.error_message(e.message))
  raise OperationError.new(:error_save_failed)
rescue ActiveRecord::ValueTooLong => e          # safety net: a limit unknown to the app
  record_failure('save_failed', 'error_dcf_value_too_long', value_too_long_summary(e))
  raise OperationError.new(:error_dcf_value_too_long, audit_status: 'save_failed')
end
```

Private helpers:

```ruby
def record_failure(status, error_message, summary = nil)
  @recorder.record_failure!(action: failure_action(status), status: status,
                            error_message: error_message, summary: summary)
rescue StandardError
  nil
end

def storage_error(violation)
  key = violation.column == 'possible_values' ? :error_dcf_values_too_large : :error_dcf_mapping_too_large
  OperationError.new(
    key,
    summary: "#{violation.column}: #{violation.bytes} bytes exceeds #{violation.limit} " \
             "(custom field ##{violation.custom_field_id})",
    interpolations: { field: violation.custom_field_name.to_s,
                      size: StorageLimits.delimited(violation.bytes),
                      limit: StorageLimits.delimited(violation.limit) }
  )
end
```

- There is ONE service mapping: no pre-check before `save!`. The model validation already covers all four guarded formats, because it is a CustomField validation, not a format validation.
- `e.record` is the record that failed, so a rename cascading into a child names the child field.
- Exactly one failure row is written. An exception raised inside a rescue clause is not caught by sibling clauses. The success row never exists, because the transaction rolled back. The failure row is written in its own transaction (`AuditRecorder#record_failure!`).
- Services keep calling plain `save!` in 0.1.0. From WP-31 (0.3.0) every custom field write of the project services goes through `BaseService#save_field!`, which sets the project ceiling and still calls `save!`, so this mapping is unchanged (4.11).

### 5.3 ValueTooLong row without DB content (SP-09)

```ruby
def value_too_long_summary(error)
  column = error.message.to_s[/column '([A-Za-z0-9_]+)'/, 1] || 'unknown'
  sizes = StorageLimits::COLUMNS.keys.map { |c| "#{c}_bytes=#{StorageLimits.preview_bytes(field, c)}" }
  "ActiveRecord::ValueTooLong column=#{column} field_id=#{field&.id} #{sizes.join(' ')}"
rescue StandardError
  'ActiveRecord::ValueTooLong'
end
```

- Stored: the class name, a column identifier constrained by the regex, the field id and byte counts.
- Never stored: SQL, the DB message or values.
- `error_message` is the key string. The project audit view (`audit.html.erb:30`) shows `changes_summary` or `error_message`, both through `h()`.

### 5.4 translate_error (one signature, escaped interpolations: SP-06)

One method with one parameter, `translate_error(error_or_key)`. Every caller that holds an `OperationError` calls `translate_error(e)` (gap 4, compat section 3 row "translate_error"): the existing call sites in WP-12 and the new actions of WP-27, WP-28, WP-29, WP-30 and WP-31. The form `translate_error(e.key, e.interpolations)` from the project revision 2 text does not exist.

Redmine renders flash messages with `v.html_safe` (core-5.1 `app/helpers/application_helper.rb:487`, core-7.0 `:527`), and `l()` does not escape.

```ruby
# ProjectCustomFieldConfigurationController (private)
def translate_error(error_or_key)
  if error_or_key.is_a?(RedmineDependingCustomFields::OperationError)
    key = error_or_key.key
    values = error_or_key.interpolations
  else
    key = error_or_key
    values = {}
  end
  escaped = values.each_with_object({}) { |(k, v), h| h[k.to_sym] = ERB::Util.html_escape(v.to_s).to_str }
  l(key, escaped.merge(default: key.to_s))
end
```

- Redmine `l(key, hash)` calls `::I18n.t(key, **hash)` (core-5.1 `lib/redmine/i18n.rb:28-39`, core-7.0 `:30-41`).
- The call sites `:77` and `:147` change from `translate_error(e.key)` to `translate_error(e)`. `render_field_error` (`:217-218`) and the archived-project path (`:119-120`) keep passing symbols.
- Rule: flash messages carry only the field name and numbers. Offender keys, values, labels and import rows go to the audit summary only.
- Example flash (`error_dcf_mapping_too_large`): it names the field ("Municipality"), the size (98,292 bytes) and the limit (65,535 bytes) and suggests asking an administrator. The text uses the neutral wording "at most %{limit} bytes can be stored for this field" (compat section 2.4 row "Service storage error text"), which is also correct for the WP-31 project ceiling, and has no README reference (UX-04). The exact en/de/fr/nl texts are in `large_lists_i18n_registry.md`; revision 2's "the database allows at most" wording for this flash is superseded.

### 5.5 What the other areas drop

| Area | Drops |
|---|---|
| Server | its `StorageLimits` module and registration, `dcf_too_large`, `too_large?`, `report`, its `field_value_dependencies` text |
| Project | the revision 1 pre-check `save_field!` with `guard_storage!` (WP-31 reintroduces `save_field!` only as the ceiling wrapper of 4.11, with no pre-check), `error_value_too_large`, `text_dcf_size_detail`, its own `translate_error` body and the `translate_error(e.key, e.interpolations)` calls (it calls the one above as `translate_error(e)`), `AuditRecorder::MAX_VALUE_BYTES` |
| Editor | registration in `CustomFieldPatch.prepended` (its callbacks move to `CustomFieldValidationPatch`), `text_dcf_storage_near_limit`, the constant +256 estimate |

## 6. (b) Audit value cap

Release: 6.1 and 6.2 ship in 0.1.0 (WP-12). The project delta sizing of 6.3 is implemented by the project area's `DependencyDelta` in 0.3.0 (WP-27).

### 6.1 AuditPayload v2 (`app/services/redmine_depending_custom_fields/audit_payload.rb`, Zeitwerk-autoloaded)

Prototype and tests: `SCRATCH/proto2/audit_payload.rb` (V19).

- **Limits.** `MAX_BYTES = 16_384` per before/after value, `MAX_IDS = 1_000`, `MAX_ERROR_CHARS = 4_000`, `TOP_KEYS = 50`, `TOP_STRING = 200`.
- **`encode(value, max_bytes: MAX_BYTES)`.**
  - `nil` stays `nil`.
  - JSON at or under the cap is returned byte-identical to `ActiveSupport::JSON.encode`, so today's small rows and the compact project delta never change.
  - Above the cap, keys are stringified and the value is shrunk level by level until the JSON fits:

| level | array elements | hash keys | string chars | nesting kept below top |
|---|---|---|---|---|
| 1 | 20 | 50 | 500 | 5 |
| 2 | 10 | 20 | 200 | 4 |
| 3 | 5 | 10 | 80 | 3 |
| 4 | 1 | 5 | 40 | 2 |

- **Top level.** The first 50 entries are kept at every level. Scalar values survive every level, with strings cut at 200 chars. Nested values shrink with the level. As a result, counts and digests such as `v`, `links`, `added` and `mapping_sha256` (named `sha256` in the revision 2 prototype) are never lost.
- **Cut markers.** Cut arrays end with `"(+N more)"`, the same wording as `UpdateEnumerationsService#capped`. Cut hashes get `"(more)": N`. Cut strings end with `...`. Deeper levels become `"(N keys)"` or `"(N items)"`.
- **Marker keys** are added to the top-level object: `"payload_truncated": true`, `"payload_bytes": <original JSON bytes>`, `"payload_sha256": "<hex SHA-256 of the full original JSON>"`.
  - The names cannot collide with the project delta's own `mapping_sha256` (the canonical mapping digest; `sha256` in the revision 2 prototype) or `truncated` (samples capped). Both keep their meaning (compat section 2.4 row "Audit marker keys").
  - If a value is not a Hash, or already contains a marker key, it is wrapped as `{"payload_truncated":true,"payload_bytes":..,"payload_sha256":..,"value":<shrunk>}`.
- **Fallback.** The final fallback is the marker alone (about 120 bytes). The output is deterministic.
- **`encode_ids(ids)`** keeps the first 1,000 ids, still as a JSON Array, so `ConfigAuditEvent#affected_child_field_ids_list` keeps working.
- **`error_message(text)`** cuts at 4,000 characters plus `...`.

### 6.2 AuditRecorder (`app/services/redmine_depending_custom_fields/audit_recorder.rb`)

- `serialize` (`:66-70`) calls `AuditPayload.encode`.
- `serialize_ids` (`:72-76`) calls `AuditPayload.encode_ids`.
- `record_failure!` stores `AuditPayload.error_message(error_message)`. `changes_summary` stays cut at 1,000 chars.
- Bound per row: before and after at most 16 KB each, ids under 12 KB, error under 16 KB. All are far below 65,535.
- No migration widens the plugin's audit table. The cap makes it unnecessary and avoids an ALTER (table copy) of an append-only table on MySQL.

### 6.3 Project delta sizing (applies to the project area's `DependencyDelta`, WP-27, 0.3.0)

- **Caps.** Sample entries: `CAP = 20`. `DEFAULTS_PER_PARENT_CAP = 3`. The consolidated WP-27 delta (v2) additionally caps each sample list at 4,000 JSON-encoded bytes and names its digest `mapping_sha256`.
- **Labels.** Labels are cut by ENCODED bytes, not characters: `LABEL_MAX_BYTES = 80`. A label is shortened until its `ActiveSupport::JSON.encode` form fits 80 bytes, then `...` is appended inside the budget (`SCRATCH/proto2/label_cap.rb`). A character cap cannot bound bytes, because `<` encodes as `<` (6 bytes) under Rails' `escape_html_entities_in_json`.
- **Measured worst case (V19).** 13,603 B, with 20 added, 20 removed and 20 defaults samples of 3 labels each, all at the cap, plus import metadata. It stays under 16,384, so `update_dependencies` rows are always stored byte-identical. The shrink path is only a defensive bound. With the additional 4,000-byte per-list cap of WP-27 the project area measured 12,028 B on ActiveSupport 6.1 and 8.1 (project decision P-D4), also under the cap.
- The project test T-AUD-10 asserts the 16,384 cap and the `payload_*` marker, replacing the 60 KB assertion.

## 7. (c) Opt-in rake tasks, README and CHANGELOG

Release: the rake tasks, `StorageReport`, `CoreColumnWidener`, the README section "MySQL / MariaDB and large lists", `.codex/test_setup.sh --db mysql` and the optional manual MariaDB workflow ship in 0.1.0 (WP-13; UD-26, UD-27). The README "Performance notes" (7.6 item 7) ship in 0.3.0 (WP-31).

### 7.1 Files

- `lib/tasks/redmine_depending_custom_fields.rake` (prototype `SCRATCH/proto/redmine_depending_custom_fields.rake`) holds thin wrappers.
  - Redmine loads every plugin rake file on every rake run (core `lib/tasks/redmine.rake:213` on 5.1, `:222` on 6.0/6.1/7.0), so nothing touches the database at load time.
  - The classes are required inside the task bodies.
  - Core RuboCop excludes `**/lib/tasks/**/*`, so all logic lives in the two classes below, where the ratchet lints it.
- `lib/redmine_depending_custom_fields/storage_report.rb` and `lib/redmine_depending_custom_fields/core_column_widener.rb`.
  - Plugin `lib/` is eager-loaded (core-7.0 `lib/redmine/plugin_loader.rb:77-86`), verified in V9.
  - They require only `csv`, which is in core's Gemfile on all versions.

### 7.2 `redmine:depending_custom_fields:report_sizes` (read-only, every adapter; the ONE report implementation)

- **ENV.** `FORMAT=table|csv` (default table). `ALL=1` (all formats instead of GUARDED_FORMATS). `WARN_AT=90` (percent, default `StorageLimits::WARN_PERCENT`). `FAIL_ABOVE=<percent>`: exit 1 when any field reaches it, for monitoring. Otherwise exit 0.
- **Reading.** Raw rows are read with `connection.select_all(CustomField.unscoped.select(:id, :type, :name, :field_format, :possible_values, :format_store).order(:id)[.where(field_format: GUARDED)].to_sql)`, so a corrupt row cannot raise during the read. Enumeration counts come from one grouped COUNT.
- **Columns per field:** `value_count`, `links`, `parents` (from the parsed mapping), `pv_bytes`, `pv_pct`, `fs_bytes`, `fs_pct`, `load_ms` (the time to deserialize both columns, i.e. the per-request YAML cost of that field), and `status`.
- **Status values:**
  - `CORRUPT`: a column cannot be deserialized, or possible_values has a nil entry (V3).
  - `SUSPECT`: a column does not end with the newline Psych always writes, or is exactly at the column limit. It was probably truncated by a non-strict server.
  - `OVER`, `WARN`, `ok`.
  - `n/a (no column limit)`.
- **MySQL header:** adapter, session `sql_mode` with "strict: yes / NO, oversized values are silently truncated", `max_allowed_packet`, and both column types and limits.

### 7.3 `redmine:depending_custom_fields:widen_core_columns` (MySQL/MariaDB only)

Prototype: `SCRATCH/proto2/core_column_widener.rb` (V21).

- **ENV.** `CONFIRM=1` applies; without it the task is a dry run. `TYPE=mediumtext|longtext` (default mediumtext, UD-26). `REVERT=1` targets TEXT.
- **Not MySQL.** Prints "Not a MySQL/MariaDB database: text columns are not size limited, nothing to do." and exits 0.
- **Packet check.** Prints `max_allowed_packet` and warns below 16 MB: "values larger than max_allowed_packet cannot be written whatever the column type".
- **Column facts.** Read from `information_schema.COLUMNS` (`TABLE_SCHEMA = DATABASE()`, `TABLE_NAME = CustomField.table_name`, so table prefixes work) for `format_store` and `possible_values`: DATA_TYPE, CHARACTER_SET_NAME, COLLATION_NAME, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT.
- **Plan per column:**
  - `refuse` when the column is missing, the type is not text/mediumtext/longtext, or the default is anything other than NULL.
  - `refuse` when CHARACTER_SET_NAME or COLLATION_NAME does not match `IDENTIFIER = /\A[A-Za-z0-9_]+\z/` (SP-19). These names are interpolated into the ALTER; the comment goes through `quote`.
  - `skip` when the column is already the requested type, or already wider. It never narrows unless REVERT.
  - `refuse` on REVERT when `MAX(LENGTH(col)) > 65,535`.
  - Otherwise `modify`.
- **One statement for all modified columns.** It is atomic, needs one table copy and gives exact dry-run output. It preserves charset, collation, nullability and comment (V6):
  `ALTER TABLE `custom_fields` MODIFY `format_store` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL, MODIFY `possible_values` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL`
- **Before executing:** `SET SESSION sql_mode = CONCAT(@@SESSION.sql_mode, ',STRICT_ALL_TABLES')`, so a revert can only fail and never truncate (V7).
- **After executing:** `CustomField.reset_column_information`, print the new types, and print "Restart Redmine so running processes use the new limit."
- **Exit codes.** 0 for not_mysql, up_to_date, dry_run and applied. 1 for an invalid TYPE or a refusal.
- **Idempotent.** It is never called from a migration, from init.rb or from install/upgrade steps.

### 7.4 MEDIUMTEXT by default (UD-26, recommended; WP-13)

- 16,777,215 bytes is 6 times the largest measured realistic case (S1 full matrix 2.62 MB).
- The 4 MiB transport cap (JSON) maps to at most about 6.4 MB of YAML (ratio 1.6), so on widened MySQL the transport cap is the effective ceiling and validation stays a meaningful backstop.
- InnoDB stores MEDIUMTEXT and LONGTEXT the same way (off-page).
- `TYPE=longtext` mirrors core's `limit: 16.megabytes` pattern. LONGTEXT by default is the UD-26 alternative.

### 7.5 Revert and uninstall

- `REVERT=1` (dry run), then `REVERT=1 CONFIRM=1`. It is refused while any row exceeds 65,535 bytes, runs in strict mode and preserves the collation.
- Uninstalling the plugin does not revert the widening; the wider columns are harmless.
- Redmine 5.1 to 7.0 contain no migration that changes these columns. Run `report_sizes` again before a Redmine upgrade.

### 7.6 README: new section "MySQL / MariaDB and large lists" plus "Performance notes"

The README is written in English, using only plain hyphens.

1. **Storage.** Redmine stores possible values (`custom_fields.possible_values`) and format settings, including this plugin's dependency mapping (`custom_fields.format_store`), as YAML in two TEXT columns. On MySQL/MariaDB a TEXT column holds at most 65,535 bytes; PostgreSQL and SQLite have no such limit.
2. **Approximate ceilings** for values of about 12 characters:
   - about 4,250 list values;
   - about 3,750 links for a List (depending) field;
   - about 5,000 links for a Key/Value list (depending) field.
   The plugin measures the exact bytes.
3. **What happens on overflow.** The save is refused with a validation error naming the field and the sizes, in the administration form, the JSON API (HTTP 422) and the project pages, where the attempt is audited. Nothing is ever truncated. Before this version MySQL either answered with an internal error or silently cut the data, which could make a field unreadable.
4. **Check.** `bundle exec rake redmine:depending_custom_fields:report_sizes RAILS_ENV=production`, with the columns, statuses and options explained. CORRUPT/SUSPECT rows were probably truncated in the past: restore their values from a backup.
5. **Widen (optional).**
   - Back up, run a dry run, then `CONFIRM=1`, then restart Redmine.
   - `TYPE=longtext` is available. The task is idempotent and never narrows.
   - It changes a core table; the plugin never does this by itself. Uninstall does not revert it; `REVERT=1` does.
   - Check `max_allowed_packet`.
   - On Galera clusters, run it in a maintenance window.
6. **Very large lists.** Prefer Key/Value list (depending): values are rows, the mapping stores ids, and the issue-form payload is about 2.7 times smaller.
7. **Performance notes** (WP-31, 0.3.0).
   - Per-request YAML parse cost; `load_ms` in the report.
   - Select sizes: keep selects below about 10,000 options.
   - The editors post one JSON field (4 MiB cap). Rack limits a urlencoded body to 4 MB. Reverse proxies often limit bodies to 1 MB by default (nginx `client_max_body_size`).
8. **Development.** The manual MySQL recipe (10.5) and the optional manual workflow `.github/workflows/rspec-mysql.yml` (workflow_dispatch only, UD-27).

### 7.7 CHANGELOG lines owned by this area (BC-14)

These lines belong to the 0.1.0 CHANGELOG (WP-11 to WP-13). The canonical wording is the 0.1.0 list in `large_lists_work_packages.md` section 3; the lines below are this area's input to it. The project storage ceiling lines (plugin setting, 255-character cap, PostgreSQL/SQLite upgrade note) belong to 0.3.0 (WP-31) and are listed there.

- **Added:**
  - size validation against MySQL/MariaDB TEXT limits for list, enumeration and both depending formats;
  - rake tasks `redmine:depending_custom_fields:report_sizes` and `:widen_core_columns` (opt-in, dry run by default);
  - a database storage hint on the custom field form and the project pages at 90% of the column limit (UD-28);
  - README section "MySQL / MariaDB and large lists".
- **Changed:** audit before/after values above 16 KB are stored shrunk, with `payload_truncated`, `payload_bytes` and the SHA-256 of the full value (`payload_sha256`).
- **Fixed:**
  - saving a too-large value list or mapping on MySQL no longer answers HTTP 500 (strict mode) and no longer silently truncates (non-strict mode);
  - a large mapping save on widened columns no longer rolls back because its audit row overflowed;
  - error messages in project settings no longer interpret HTML in field names (WP-12, SP-06).
- **Upgrade notes:**
  - "On MySQL servers running without strict mode, saves that used to be silently truncated are now refused with a validation error."
  - "Core List and Key/Value list fields are size-checked too."
  - "The plugin never alters core tables: widening is an explicit rake task, and running Redmine processes keep the old limit until restarted."
  - "Run report_sizes once after upgrading: fields reported CORRUPT or SUSPECT were truncated by an earlier version on a non-strict server and need their values restored from a backup."

## 8. (d) Issue-form payload: aligned with the server-owned canonical table

- **Owner.** The issue-form attribute contract has ONE owner, the server area (attribute table, fixture rendered by the real helpers in all four rspec workflows and consumed by jsdom). This area no longer specifies its own variant. Revision 1's "pruned map" (former L11) is withdrawn.
- **What this area relies on:**
  - `data-dcf-map` is `Sanitizer.sanitize_dependencies(cf.value_dependencies)`, NOT pruned. A stored legacy parent value (D1) must still find its child list.
  - Enumeration child ids are JSON numbers when canonical (`/\A[1-9]\d*\z/`), strings otherwise.
  - `data-dcf-defaults` is emitted only when non-empty.
  - The map is emitted only by `edit_tag`/`bulk_edit_tag` of fields actually rendered.
- This area endorses the server's privacy variant: `data-dcf-parent-values`, gated by `parent.visible_by?` with a fail-closed rescue. The size table below does not depend on that choice.
- Release: the attribute contract ships in 0.2.0 (WP-16 emits it additively, WP-18 switches the issue form over). This area adds no code there.

Measured with ActionView 8.1.4 escaping (`SCRATCH/proto/payload_bench.rb`):

| Shape | data attribute | deflate | alternative | option markup it accompanies |
|---|---|---|---|---|
| S1 list 27 x 5,570 | 139,158 B | 15.5 KB (46.2 KB with research names) | index-encoded 28,443 B | 279,415 B |
| S2 enum 27 x 5,570, string ids | 107,525 B | 14.1 KB | integer ids 40,361 B | 260,679 B |
| S3 list 5,000 x 25,000 | 1,043,424 B | 117.5 KB | index-encoded 474,756 B | 1,254,139 B |

- **Size bound without pruning.** The attribute is bounded by the stored YAML. On MySQL TEXT the store is at most 64 KB, so a list attribute stays under about 95 KB (ratio 139,158 / 97,544). Orphan keys add only what is stored. On PostgreSQL an "everything ticked" mapping can reach 3.8 MB; this is documented as a known limit.
- **No option-index encoding**, because it couples the payload to the exact rendered option list: legacy values appended by core, bulk and wizard option sets, overlays.

## 9. (e) Server CPU, topology and memoization

### 9.1 Set-based lookups (acceptance criteria for the point 6 rules module and services)

| Code path | Today | Required |
|---|---|---|
| `DependencyMappingService#validate_mapping!` | `Array#include?` 115 ms (S1), 4.6 s (5,000 x 25,000) | Set or `Hash#key?` lookups: 3.6 ms / 37 ms |
| `possible_values_options` filter | 34 ms per render at 5,570 x 853 | `DependencyRules.allowed_set` (a Set): 2 ms |
| `value_from_keyword` | filtered options, then a linear scan per keyword | full option list (critic C2), one pass into a downcased label to value Hash per call |
| D6 prune, import matching, JS rules | n/a | Set/Map |

Where these criteria land: `DependencyRules.allowed_set`, `prune_mapping` and the format module's `possible_values_options` and `value_from_keyword` in 0.0.16 (WP-05, WP-06; `prune_mapping` first used by the admin JSON transport, WP-22, 0.3.0); the JS rules in 0.2.0 (WP-17); `DependencyMappingService#validate_mapping!` Set validation in 0.3.0 (WP-27); import matching in 0.3.0 (WP-26). The 5,000 x 25,000 `validate_mapping` budget (under 1 s) is an opt-in `:perf` spec of WP-31.

### 9.2 YAML parse cost per request

- Inherent to "storage stays a Hash in format_store": each CustomField instance parses its format_store once. That is 13.7 ms at S1 and 100 to 210 ms at S3/S4, so a page with N depending fields pays N parses.
- Avoidable costs, removed by 9.3:
  - `FieldRelevance.children_of` loading and parsing every depending field per value row on the values page (`usage_calculator.rb:61,71`);
  - ancestor walks that parse each ancestor.

### 9.3 FieldIndex: the single topology helper (R18)

`lib/redmine_depending_custom_fields/field_index.rb` defines `RedmineDependingCustomFields::FieldIndex`. It ships in 0.0.16 (WP-05). Consolidation (compat section 2.4 row "FieldIndex API") adopted the server names in one class: the server area owns the file and its canonical API is server design section 4; this area contributes the raw-regex extraction (V14), the cycle-safe walks and the acceptance criteria below. This area's revision 2 names (`build(type:)`, `child_ids`, `children`, `type_of`, `include?`, `PARENT_LINE`, `MAX_CHAIN`) are not created. Canonical API, as adopted:

```ruby
class FieldIndex
  PARENT_RE = /^parent_custom_field_id: *(?:'(\d*)'|"(\d*)"|(\d*)) *$/.freeze
  Row = Struct.new(:id, :type, :field_format, :parent_id)
  def self.load(scope = CustomField.where(field_format: DependencyRules::DEPENDING_FORMATS)) # 1 raw select_all, no deserialization
  def initialize(records: {}, rows: {})   # lazy: rows from loaded read-only records materialize on first access
  def ensure(ids)                         # one raw select for ids not yet known (id, type, field_format, format_store)
  def row(id); def parent_id(id); def exists?(id)
  def ancestor_ids(id)                    # visited Set, cap 1,000, stops at non-depending or unknown rows; terminates on stored cycles
  def descendant_ids(id); def children_ids(id)  # BFS with a visited Set; meaningful on an index built by .load
  def effective_parent_id_for(child_id, child_type, child_format, pid)
  def cycle_from(id)                      # member ids when id is on or reaches a cycle, else []
  def self.parent_id_from_raw(raw)        # regex; deserialization fallback only when the regex misses but the key is present
end
```

Mapping from this area's revision 2 sketch: `build(type:)` is `load` (optionally with a scope), `child_ids` is `children_ids`, `children(id)` is `DependencyRules.children_of(field, index: index)` (loads only the child records, ordered by `CustomField.sorted` instead of revision 2's `[position || 0, id]` sort inside the index), `type_of(id)` is `row(id).type`, `include?(id)` is `exists?(id)`, and `MAX_CHAIN` is the cap of 1,000.

- **Extraction.** The parent id comes from the raw YAML with `PARENT_RE`, which anchors at column 0, so nested mapping keys and block scalars cannot match. If the regex does not match but the substring is present, that row is deserialized with `CustomField.type_for_attribute('format_store')` (V14: 0.04 ms vs 16.6 ms per S1 row).
- **Consumers.** `DependencyRules::Graph` and the per-hop `find_parent` ancestor walk are removed. The server functions use `FieldIndex.load` or take an optional `index:`:
  - `ancestor_ids`, `descendant_ids`, `in_cycle?`, `cycle_member_ids` and `parent_candidates` (point 5 parent select; WP-10, 0.1.0);
  - `parent_errors`: the cycle check is `candidate.id == cf.id || FieldIndex.load.ancestor_ids(candidate.id).include?(cf.id)`. The candidate comes from `resolve_parent_for_save`, and stored ancestors are unaffected by the current save;
  - `children_of(field, index: nil)`, which computes `(index || FieldIndex.load).children_ids(field.id)` and loads only those records; `FieldRelevance.children_of` delegates to it (WP-05);
  - the project `UsageCalculator.page_usage` (WP-28, 0.3.0), which builds one `FieldIndex.load` per page and passes it as `index:`, so child records are loaded once per page.
- **Never used on issue pages or in the context menu.** Those use the already loaded `available_custom_fields` (server SelectionGraph).

### 9.4 Query invariance (R16)

- `StorageLimits.validate` runs only on CustomField saves. It issues no query except the memoized parent resolution shared with before_save. `columns_hash` comes from the schema cache.
- The usage hint issues one query, on the admin custom field form and project configuration pages only.
- None of this area's code runs on issue new/edit/bulk pages or in the context menu, so it adds nothing to the G6 invariance gates.
- This area's own query assertions use the invariance style: the cycle check costs the same for 1 and 25 depending fields of the type, because one FieldIndex query replaces the per-hop lookups.

### 9.5 Memoization rules (safe across requests and threads)

1. No class-level, module-level or `Rails.cache` caches of mappings or topology.
2. Never memoize on format objects. `Redmine::FieldFormat.find` returns process-wide singletons (core `lib/redmine/field_format.rb:24-25,64`).
3. Allowed: instance variables on CustomField records, keyed by what they derive from (for example the raw parent id string, or the raw `dependencies_json` String object for the parsed payload: SP-17). Also allowed: explicit per-operation objects, such as a `FieldIndex` built once per page or validation and passed down.
4. No `ActiveSupport::CurrentAttributes`.
5. Rejected: a process-level cache of parsed mappings. A dedicated mapping table is a long-term option for a major version.

## 10. (f) Fixtures and testing the MySQL path

Release: the generator, the `rails_helper` tags and the locale parity spec ship in 0.0.16 (WP-02). The storage specs of 10.2 and 10.3 ship with WP-11, WP-12 and WP-13 (0.1.0), the project ceiling specs with WP-31 (0.3.0). The editor fixture normalization of 10.4 ships in 0.3.0 (WP-24).

### 10.1 One generator (R12): `spec/support/dcf_large_list.rb` (WP-02, 0.0.16)

Consolidation (compat section 2.4 row "Large-list generator", WP-02) adopted the arithmetic generator of quality revision 2 (this area's original algorithm, no PRNG). The mulberry32 base that revision 2 of this area proposed (`names(count, seed: 42)`, `partition(parents, children, seed: 42)`, pinned `0634a624422f2f06`) is withdrawn.

- **Base.** `DcfLargeList.name`, `names(count, prefix:, offset:, tricky_every:)` (bijective base-60 syllable stems, one accent when `i % 3 == 0`, place prefixes), `sizes` (naive left fold `inject(0.0) { |acc, w| acc + w }` for JS parity), `partition`, `full`, `first_child_defaults` (quality protocol 5.7). Its JS twin is `test/js/support/large_list.js` (`names`, `name`, `sizes`, `partition`, `TRICKY`).
- **Pinned hashes.** SHA-256 prefix `233acf899217e962` for `names(5570, tricky_every: 97)` and `466b240daca61be9` for the partition, asserted in `spec/quality/dcf_large_list_spec.rb` and `test/js/large_list_parity.test.js` (E17: identical on Ruby 3.2.6, 3.3.6 and Node 22.22.0).
- **Stressors and skew** (this area's revision 2 helpers, now part of the base):
  - the tricky values `yes`, `no`, `null`, `1.0`, `a: b`, `# hash`, `- dash`, `O'Brien`, `say "hi"`, `[x]`, `a]`, `semi;colon`, `comma, value`, tab, `Ünïcødé ñ`, each suffixed with its index so names stay unique, are injected by `tricky_every:` (every 97th name in S1); revision 2's separate `STRESSORS` / `with_stressors(list, every: 97)` are not created;
  - S1 partitions with the IBGE 27-state sizes (realistic skew, the largest parent has 853 children); revision 2's separate `BRAZIL_SIZES` / `partition_sizes` names are not created.
- **Ruby-only byte helpers from this area** (not part of the JS parity hash; prototype `SCRATCH/proto2/dcf_large_list.rb`, V20):
  - `element_bytes(v)` = `Psych.dump([v]).bytesize - 4` and `yaml_list_bytes(values)`.
  - `values_of_yaml_bytes(target)`: generator names plus one ASCII padding value `Zz...z`, whose YAML is exactly `target` bytes. Any target of 16 or more is reachable; 65,535 / 65,536 are the boundary cases. WP-02 asserts 1,000 / 65,535 / 65,536 exactly.
- **DB builders.** Use the existing `dcf_list_field(format:, values:)`, `dcf_enum_field(format:, names:)` and `dcf_set_dependencies` (`spec/support/dcf_config_helpers.rb:50-81`), plus quality's `dcf_large_list_field!`, `dcf_large_enum_field!` and `dcf_large_pair!`. Enumerations are bulk-created with `CustomFieldEnumeration.insert_all`.
- **One spec file.** The byte-target examples go into `spec/quality/dcf_large_list_spec.rb`. There is no `spec/lib/dcf_large_list_spec.rb` and no `spec/quality/large_list_parity_spec.rb`.

### 10.2 Testing on PostgreSQL CI (no automatic MySQL job; optional manual workflow per UD-27, 10.5)

- **Seam.** `allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit).and_return(limit)`, with `limit` derived from the measured bytes (`bytes` passes, `bytes - 1` fails). Small fixtures keep specs fast; one scale spec uses the real 65,535 with S1-sized data.
- **Fallback branch.** Tested by stubbing `CustomField.columns_hash` (a double column `type: :text, limit: nil`) and `Redmine::Database.mysql?`, in an example that calls only `column_limit`.
- **Exactness on any adapter.** Helper `dcf_stored_bytes(record, column)` reads raw bytes with `octet_length` (PostgreSQL), `LENGTH` (MySQL) or `length(CAST(col AS BLOB))` (SQLite). It must equal `StorageLimits.preview_bytes(record, column)` taken just before save, for all of these:
  - list and both depending formats;
  - a string parent id, an invalid parent, blank keys, defaults with blanks;
  - an admin `dependencies_json` payload (generated by the editor model's `serialize()` fixture);
  - a project service payload.
- **No-prune specs (R8):**
  - an API PUT that changes only the name leaves `value_dependencies` byte-identical, orphan and bracket-corrupted keys included;
  - a `safe_attributes=`-then-save (extended API style) does not prune;
  - a rename cascade `child.save!` keeps unrelated keys.
- **Widener specs** use a fake connection (`select_all`, `select_value`, `execute`, `quote`, `quote_column_name`, `quote_table_name`) with `mysql: true`, and assert the exact SQL strings.
- **Report rows** are written with raw SQL (`connection.exec_update`), because `update_all` would serialize the string again.
- **`spec/rails_helper.rb`** (WP-02, 0.0.16):
  - `config.filter_run_excluding :mysql unless Redmine::Database.mysql?`;
  - `config.filter_run_excluding :perf unless ENV['DCF_PERF_SPECS'] == '1'`;
  - `require_relative 'support/dcf_large_list'`.
  These coexist with quality's random order and system-spec opt-in.

### 10.3 MySQL-only specs (tag `:mysql`, skipped on PostgreSQL, run by the manual recipe; `spec/mysql/storage_limits_mysql_spec.rb` in WP-11, `spec/mysql/core_column_widener_mysql_spec.rb` in WP-13)

- The real limit is 65,535.
- A 65,535-byte list saves and 65,536 is rejected.
- `save(validate: false)` of an oversized list raises `ActiveRecord::ValueTooLong`.
- The report header shows strict mode.
- The widener dry-run SQL contains the real charset and collation.
- The schema cache keeps the old limit until `reset_column_information`.

### 10.4 Fixture normalization for this area's attributes (R13)

- The storage attributes appear only on the editor root and depend on the adapter.
- The editor fixture spec (`spec/frontend/editor_fixtures_spec.rb`, editor area, WP-24) stubs `StorageLimits.column_limit` to `nil` for every default scenario. Its fixtures are then identical on PostgreSQL CI and on the manual MariaDB run.
- One scenario, `mysql_limit`, stubs 65,535 and asserts all four attributes.
- `data-dcf-editor-storage-base` contains the parent id digits, which depend on DB sequences. The fixture spec replaces its value with `{{BYTES}}`. A request spec asserts the exact value equals `StorageLimits.base_bytes(field)`.
- This area renders no other fixture markup.

### 10.5 Manual MySQL/MariaDB run (verified for 5.1 and 7.0 with MariaDB 10.11: 259 examples, 0 failures)

```bash
docker run --rm -d --name dcf-mariadb -p 3307:3306 \
  -e MARIADB_ROOT_PASSWORD=root -e MARIADB_USER=redmine -e MARIADB_PASSWORD=redmine mariadb:10.11
docker exec dcf-mariadb mariadb -uroot -proot -e "GRANT ALL ON *.* TO 'redmine'@'%'"
# in the Redmine checkout used by the CI steps (plugin in plugins/redmine_depending_custom_fields):
cat > config/database.yml <<'YML'
test:
  adapter: mysql2            # trilogy also works on Redmine 6.1/7.0
  database: redmine_dcf_test
  host: 127.0.0.1
  port: 3307
  username: redmine
  password: redmine
  encoding: utf8mb4
  variables:
    tx_isolation: "READ-COMMITTED"   # MySQL 8 / MariaDB 11.1+: transaction_isolation
YML
rm -f db/schema.rb    # a schema.rb dumped by PostgreSQL contains expression indexes MySQL cannot load
bundle install
RAILS_ENV=test bundle exec rake db:drop db:create db:migrate redmine:plugins:migrate
RAILS_ENV=test bundle exec rspec plugins/redmine_depending_custom_fields/spec   # :mysql specs now run
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:report_sizes
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns            # dry run
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns CONFIRM=1
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns REVERT=1 CONFIRM=1
```

`.codex/test_setup.sh --db mysql` (quality area script, option added by WP-13) writes the same database.yml.

**Optional manual workflow (UD-27, WP-13, 0.1.0).** `.github/workflows/rspec-mysql.yml` runs this recipe for Redmine 5.1 and 7.0 on MariaDB, with `workflow_dispatch` as its only trigger; `spec/quality/ci_workflows_spec.rb` guards that. Dispatch follows UD-32 (resolved by the owner): Claude may dispatch it deliberately only after the local gates pass, at most once per workflow per commit SHA unless a fix was pushed, never edits workflow triggers, and reports every dispatch with workflow, SHA, run URL and result. CI never gets automatic triggers. If the owner declines UD-27, the `:mysql` specs and this local recipe remain the only MySQL evidence.

## 11. Locale keys owned by this area (registry entries; de, en, fr, nl at parity)

**Single source of truth for texts:** `large_lists_i18n_registry.md` holds the en, de, fr and nl text of every key (with the de „…“ and fr « … » quote conventions). This section keeps only key names, owner WPs, interpolations and where each key is used. The revision 2 translation cells of this section are superseded by the registry; in particular `error_dcf_values_too_large` and `error_dcf_mapping_too_large` use the neutral wording "at most %{limit} bytes can be stored for this field" (compat section 2.4 row "Service storage error text", WP-12), correct for both the column limit and the WP-31 project ceiling, with no README reference (UX-04).

| Key | Owner WP | Interpolations | Used by | Texts |
|---|---|---|---|---|
| `activerecord.errors.messages.dcf_storage_too_large` (nested) | WP-11 | size, limit | model validation message after the attribute label (4.7) | see large_lists_i18n_registry.md |
| `field_value_dependencies` | WP-11 | none | attribute label of `:value_dependencies` ("Dependency mapping" wording, 4.7); also the `label` of the usage line and the client estimate | see large_lists_i18n_registry.md |
| `error_dcf_values_too_large` | WP-12 | field, size, limit | project flash for a possible_values violation (5.2) | see large_lists_i18n_registry.md |
| `error_dcf_mapping_too_large` | WP-12 | field, size, limit | project flash for a format_store violation (5.2) | see large_lists_i18n_registry.md |
| `error_dcf_value_too_long` | WP-12 | none | project flash for the `ValueTooLong` safety net (5.2) | see large_lists_i18n_registry.md |
| `text_dcf_storage_usage` | WP-11 | label, size, limit, percent | server usage line on the admin form and project pages (4.9, UD-28) | see large_lists_i18n_registry.md |
| `text_dcf_storage_estimate` (JS key `storageEstimate`) | WP-24 (gap 8) | label, size, limit, percent | editor client estimate warning (4.10; shown by WP-25) | see large_lists_i18n_registry.md |
| `text_dcf_storage_admin_help` (admin only) | WP-11 | none | admin-only README line under the usage line (4.9) | see large_lists_i18n_registry.md |

Related keys owned by the project area for 4.11 (WP-31, 0.3.0): `label_dcf_project_storage_ceiling`, `text_dcf_project_storage_ceiling_info` (`%{default}`) and `error_dcf_value_length` (`%{max}`); texts in the registry.

Notes:
- **Terminology** follows the existing plugin files: `notice_dependencies_saved` (Abhängigkeitszuordnung / Mappage des dépendances / Afhankelijkheidskoppeling, locales `:63`) and `label_depending_enumeration` (`:9`). The README section name stays English on purpose, because the README is English. No value of this area is meant to equal its en value, so no English-leftover allowlist entry is expected; the registry texts and the WP-02 allowlist are authoritative.
- **YAML quoting.** Values that start with `%{` or contain `: ` are double-quoted, with inner ASCII quotes escaped. French uses a plain space before `:` and `%`, as the existing files do.
- **Interpolation.** `%)` after `%{percent}` is left untouched by I18n interpolation (verified with the i18n gem: `(93%).`).
- **Keys dropped elsewhere** (one key per purpose): `dcf_too_large` (server), `error_value_too_large` and `text_dcf_size_detail` (project), `text_dcf_storage_near_limit` (editor), `text_dcf_storage_estimate_over` (revision 1 of this area). Server and editor remove their own `field_value_dependencies` definition.
- **Parity spec requirements** (quality G8 owner; `spec/quality/locale_parity_spec.rb`, WP-02, 0.0.16):
  - fail on a duplicate mapping key at any nesting level, by walking the `Psych.parse_stream` node tree rather than `YAML.load`;
  - flatten nested keys;
  - compare interpolation variables per key across en/de/fr/nl;
  - resolve every value of the I18N constant maps `RedmineDependingCustomFields::ClientConfig::I18N` and `DependencyEditorConfig::I18N`, when they are defined, in all four locales without "translation missing" (gap 5; there is no `I18N_KEYS` constant). `DependencyEditorConfig::I18N` includes `storageEstimate` from WP-24 on; WP-18 and WP-24 each add an example proving their map is checked.

## 12. Cross-area contracts this area relies on (adopted, with owners)

1. **Shared normalizer** (server, point 6; WP-06, 0.0.16). `normalized_store_pairs` / `storage_preview(custom_field, store)` / `before_custom_field_save` as in 4.4; `StorageLimits.preview_value` calls it as `format.storage_preview(record, record.format_store)` (gap 4, compat section 3 row "storage_preview"). It is sanitize-only, never prunes, memoizes the parent on the record, uses `Set` per 9.1 and never memoizes on the format singleton.
2. **Payload** (owner: editor area; one `RedmineDependingCustomFields::DependencyPayload` for both entry points; WP-21, 0.3.0).
   - Schema v1, strict, unknown top-level keys rejected: `{version, source ("editor"|"import"), base, value_dependencies, default_value_dependencies, import: {mode: "merge"|"replace", rows: Integer}}`.
   - `MAX_BYTES` 4 MiB on both paths; `max_nesting: 3`; `create_additions: false`.
   - A pre-scan rejects numeric tokens of 20 or more digits. Integers must be positive with `bit_length <= 63`, checked before `to_s`. Floats, booleans and null are rejected (SP-01).
   - `parse` returns `nil` (absent or blank: unchanged) or a Result with `ok?`/`error`. It is memoized on the record keyed by the raw String object.
   - The project service turns an error Result into `OperationError(:error_invalid_dependency_payload, summary: ..., payload: result)` and treats blank as an error (WP-27; the key is owned by WP-25, gap 8).
   - This area's only hard needs: decoding happens before validation (admin) or before `save!` inside the service (project), and the 4 MiB cap stays below the widened-column ceiling (7.4).
3. **Editor partial** (editor area; WP-24 and WP-25, 0.3.0). One partial and one presenter, `DependencyEditorConfig.for_admin/for_project`, render the four storage attributes of 4.10 and `storageEstimate` in `data-dcf-editor-i18n` (from `DependencyEditorConfig::I18N`, gap 5). The editor's callbacks live in `CustomFieldValidationPatch` (4.1; added by WP-22). The failed-save re-render keeps the hidden input blank and renders the parsed ok payload in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"` on both pages (gap 1). The client estimate test is `test/js/dependency_editor_storage.test.js` (WP-25, gap 12).
4. **Project area.**
   - Delta caps per 6.3 (WP-27).
   - `AuditRecorder` uses `AuditPayload` (WP-12).
   - Services keep plain `save!` and rely on the `BaseService` mapping (5.2); from WP-31 they write through `save_field!`, which still calls `save!` (4.11).
   - `translate_error(error_or_key)` per 5.4, called as `translate_error(e)` by WP-27 to WP-31 (gap 4).
   - `UsageCalculator.page_usage` uses one `FieldIndex` (WP-28).
   - The project storage ceiling (`ProjectStoragePolicy`, setting `project_storage_ceiling_kib`, `save_field!`, 255-character cap) per 4.11 (WP-31, UD-22).
5. **Server area.**
   - Cycle check, parent candidates and `children_of` use `FieldIndex` (9.3; WP-05 and WP-10).
   - No storage code of its own.
   - The issue-form attribute table is owned there (section 8).
6. **Quality area.**
   - The generator per 10.1 (WP-02).
   - Parity spec additions per 11 (WP-02).
   - The ratchet lints `storage_limits.rb`, `field_index.rb`, `storage_report.rb`, `core_column_widener.rb`, `audit_payload.rb` and `custom_field_validation_patch.rb`. The rake file is excluded by core config by design.

## 13. File-by-file changes

| File | Change |
|---|---|
| `lib/redmine_depending_custom_fields/storage_limits.rb` | NEW (4.2 to 4.10) [WP-11, 0.1.0]; `effective_limit`, `Violation#source` (4.11) [WP-31, 0.3.0] |
| `lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb` | NEW (4.1); this area owns the file, and the editor bodies go inside [WP-11 creates it with the storage validation, 0.1.0; WP-22 adds the editor callbacks, 0.3.0; WP-31 adds `dcf_storage_ceiling`, 0.3.0] |
| `init.rb` | require and `CustomField.prepend ...CustomFieldValidationPatch` after line 61; require the storage hook [WP-11]; settings default `project_storage_ceiling_kib` [WP-31] |
| `lib/redmine_depending_custom_fields.rb` | `require_relative` storage_limits [WP-11] and field_index [WP-05, 0.0.16] |
| `lib/redmine_depending_custom_fields/depending_format_methods.rb` (point 6 file) | `normalized_store_pairs`, `storage_preview(custom_field, store)`, before_save through the same pairs (4.4) [WP-06, 0.0.16; consumed by WP-11] |
| `app/services/redmine_depending_custom_fields/operation_error.rb` | consolidated signature (5.1) [WP-12, 0.1.0] |
| `app/services/redmine_depending_custom_fields/base_service.rb` | rescue chain, `record_failure(status, message, summary)`, `storage_error`, `value_too_long_summary` (5.2, 5.3) [WP-12, 0.1.0]; `save_field!` (4.11) [WP-31, 0.3.0] |
| `app/services/redmine_depending_custom_fields/audit_payload.rb` | NEW (6.1) [WP-12, 0.1.0] |
| `app/services/redmine_depending_custom_fields/audit_recorder.rb` | `serialize`, `serialize_ids` and `record_failure!` use AuditPayload (6.2) [WP-12, 0.1.0] |
| `app/controllers/project_custom_field_configuration_controller.rb` | `translate_error(error_or_key)` with escaping; call sites `:77`, `:147` pass `e` (5.4) [WP-12, 0.1.0]; new actions call `translate_error(e)` [WP-27 to WP-31, 0.3.0] |
| `lib/redmine_depending_custom_fields/field_index.rb` | NEW (9.3), server-owned file with the server names [WP-05, 0.0.16] |
| `lib/redmine_depending_custom_fields/hooks/custom_field_storage_hook.rb`, `app/views/custom_fields/_dcf_storage_usage.html.erb`, helper `dcf_storage_usage_hint` in `app/helpers/project_custom_field_configuration_helper.rb` | NEW usage hint (4.9) [WP-11, 0.1.0, UD-28] |
| `lib/redmine_depending_custom_fields/dependency_editor_config.rb` (editor file) | four storage attributes plus `storageEstimate` [WP-24, 0.3.0]; project-mode limit `ProjectStoragePolicy.format_store_limit(field)` [WP-31, 0.3.0, gap 14] |
| `test/js/dependency_editor_storage.test.js` | NEW client estimate test (4.10) [WP-25, 0.3.0, gap 12] |
| `app/services/redmine_depending_custom_fields/project_storage_policy.rb`, `app/views/settings/_dcf_project_config.html.erb` | project-owned ceiling policy and setting field (4.11) [WP-31, 0.3.0, UD-22] |
| `lib/tasks/redmine_depending_custom_fields.rake` | NEW (7.1) [WP-13, 0.1.0] |
| `lib/redmine_depending_custom_fields/storage_report.rb`, `core_column_widener.rb` | NEW (7.2, 7.3) [WP-13, 0.1.0, UD-26] |
| `.codex/test_setup.sh`, `.github/workflows/rspec-mysql.yml` | `--db mysql`; optional manual MariaDB workflow, workflow_dispatch only (10.5) [WP-13, 0.1.0, UD-27] |
| `config/locales/{en,de,fr,nl}.yml` | 8 keys (section 11) [WP-11, WP-12, WP-24 per key] |
| `README.md`, `CHANGELOG.md` | 7.6, 7.7 [WP-11 to WP-13, 0.1.0; README "Performance notes" WP-31, 0.3.0] |
| `spec/support/dcf_large_list.rb` | byte helpers in quality's arithmetic generator (10.1) [WP-02, 0.0.16] |
| `spec/rails_helper.rb`, new specs | 10 and the WP test lists [`rails_helper` tags WP-02; storage specs WP-11 to WP-13; ceiling specs WP-31] |
| `assets/stylesheets/depending_custom_fields.css` | `.dcf-storage-usage em.info { color: #a05a00; }` (optional; not in the WP-11 file list, so it ships only if WP-11 adopts it) |

## 14. Behaviour before and after

| Scenario | Before | After |
|---|---|---|
| MySQL strict: the admin form saves a value list or mapping over 64 KB | HTTP 500 `ValueTooLong`, rollback | form re-rendered with "Possible values is too large to store (85,869 bytes, the database allows at most 65,535 bytes)" |
| Same through the JSON API | HTTP 500 | HTTP 422 `{"errors":[...]}` |
| Same through a project service (add, rename with cascade, mapping save, import, sort) | HTTP 500, no audit row | 422 page, escaped flash naming field and sizes, exactly one `validation_failed` audit row |
| MySQL non-strict | the save "succeeds" with data silently cut; possible_values may become unreadable | save refused, nothing written |
| MySQL, limit unknown to the app | HTTP 500 | service: `error_dcf_value_too_long` with a `save_failed` row holding no DB message; admin and API unchanged (500) |
| API rename-only PUT of a depending field | mapping sanitized only | unchanged: sanitized only, never pruned |
| PostgreSQL / SQLite | no limit | unchanged in 0.1.0 (no check); only the audit cap applies. From 0.3.0 (WP-31, UD-22) project-page writes that grow a field beyond `project_storage_ceiling_kib` (default 2,048 KiB) are refused; admin form and API stay unlimited |
| Columns widened with the task | n/a | validation limit 16,777,215 after a restart |
| Audit value under 16 KB (every compact project delta) | full JSON | byte-identical |
| Audit value over 16 KB | full JSON; on MySQL the whole change rolls back | shrunk, top-level scalars kept, `payload_*` marker |
| Field name with markup in a size flash | n/a | rendered escaped |
| Unrelated edit of a field whose stored columns exceed the limit | n/a | allowed (only changed columns are checked) |

## 15. Edge cases

- **New records and empty stores.** New records are always checked. A nil format_store serializes to nil (0 bytes).
- **Unknown format string.** `guarded?` is false; core's inclusion validation reports it.
- **Cascades.** Cascade failures name the child field (`e.record`).
- **Two violations.** Both columns produce two messages. Services map the first, possible_values first.
- **Locale.** Number formatting uses the locale active during validation or the request.
- **Stale schema cache after widening.** Conservative until restart (V8).
- **Character sets.** latin1 tables over-estimate, because UTF-8 bytes are measured.
- **Corrupt fields.** A field corrupted by non-strict history cannot be opened in the admin form. Recovery: report_sizes, widen, restore from a backup.
- **Widener on an unexpected server.** If it returns odd character set or collation names, the plan is refused and no SQL runs.
- **Audit payload collisions.** A payload that already contains a `payload_*` key (never produced by this plugin) is wrapped under `value`.

## 16. Out of scope, tracked separately

- **SECURITY: context-menu wizard save writes non-editable custom fields.**
  - `ContextMenuWizardController#save` assigns `issue.custom_field_values = values` directly (`app/controllers/context_menu_wizard_controller.rb:31-32`). This bypasses `editable_custom_field_values(user)` (core-5.1 `app/models/issue.rb:625-626`, core-7.0 `:647-648`), so workflow read-only and role-hidden fields can be written without a journal.
  - Out of the 9 points (D4). Tracked as SD-01 (`large_lists_defects.md`) with a CHANGELOG "Security" entry. Timing is UD-03: recommended as its own PR merged before 0.0.16 is tagged; 0.2.0, the release that ships point 1, must not be tagged without it.
  - Minimal fix: assign through `issue.safe_attributes = { 'custom_field_values' => values }`, or filter by `editable_custom_field_values(User.current)`.
  - Spec: posted read-only and role-hidden fields stay unchanged; login, visibility and editability are still required.
- Wizard save hardening (journal, `@can[:edit]`; SD-02), and the time-entry context menu (SD-03) (D4).
- Rack limits on the remaining per-row forms (handled by the point 9 contracts).
- AJAX autocomplete for selects above about 10,000 options.
- A dedicated mapping table, for a future major version.
- An automatic MySQL CI job: never, CI stays `workflow_dispatch` only. The optional manual MariaDB workflow is in scope of WP-13 per UD-27 (10.5).
- `copy_from` enumeration-id remap (D6; SD-06, README note in WP-25).
