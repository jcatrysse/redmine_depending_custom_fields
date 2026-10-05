# Large lists: repo-specific quality protocol

> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 to 9 (cross-cutting: the gates, tooling and test strategy apply to every point; no point is implemented here). Owner area: quality (quality protocol, gates G1 to G12, `.codex` scripts, RuboCop ratchet and Ruby 2.7 syntax gate, JS toolchain, test strategy, fixture infrastructure, the large-list generator, the locale parity spec, CI policy, the per-WP definition of done). Work packages: WP-01 (tooling: `.codex` scripts, ratchet, JS toolchain, manual workflows) and WP-02 (test hygiene, shared test infrastructure, generator, locale parity and no-dash specs), primary, release 0.0.16; WP-04 (characterization specs, 0.1.0 (M1)); quality-owned infrastructure delivered inside other WPs: WP-16 (`spec/support/dcf_js_fixtures.rb` and the generated markup fixtures, 0.1.0 (M2)), WP-18 (head fixtures and the `ClientConfig::I18N` parity example, 0.1.0 (M2)), WP-23 (payload golden files, 0.1.0 (M3)) and WP-24 (editor fixtures, `value_options.json` and the `DependencyEditorConfig::I18N` parity example, 0.1.0 (M3)); the gates and the definition of done (sections 3 and 7) apply to every WP-01 to WP-32, and the release WPs WP-07, WP-14, WP-20 and WP-32 rerun the full matrix. Decisions: UD-29, UD-30, UD-31, UD-32 (resolved), UD-33, UD-34; related: UD-01 (release structure), UD-03 (SD-01 timing), UD-10 (required '(none)', former C7), UD-16 (editors need JavaScript, admin multipart switch), UD-27 (optional manual MariaDB workflow).

**Consolidation.** The final completeness critic (gaps 1, 5, 8, 10, 12 and 15, plus the quality parts of gaps 2, 3, 4 and 13) and the binding contracts of `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts", subsection 4 of the compatibility matrix) and section 3 ("Contract rows added during consolidation") are applied inline below. Where the revision 2 text of this document conflicted with them, they win; section 2 of this document is aligned with them and with the owning area designs, never the other way round. Release targets follow the work packages: 0.0.16 = WP-01..WP-03 and WP-07, 0.1.0 (M1) = WP-04..WP-06 and WP-08..WP-14, 0.1.0 (M2) = WP-15..WP-20, 0.1.0 (M3) = WP-21..WP-32. Locale texts live only in `large_lists_i18n_registry.md`; this document names keys, owners and the G8 conventions.

| Topic | Consolidated rule | Sections |
|---|---|---|
| Measured baseline | Plugin specs: 259 examples, 0 failures on Redmine 5.1 (Ruby 3.2.6), 6.0, 6.1 and 7.0 (Ruby 3.3.6), measured with a local replica of the CI steps (PostgreSQL 16; `libpq-dev` installed for the `pg` gem). RuboCop with core 7.0's config and `plugins/**` un-excluded: 107 offenses in 38 files (39 files inspected). These are the reference numbers for G2 and the G3 ratchet. | 1, 3, 4.8 |
| Work package ids | Revision 2 used provisional ids WP0 to WP8. They map to the final ids as follows: WP0 = WP-01 (tooling) and WP-02 (test hygiene); WP1 = WP-04; WP2 = WP-05, WP-06, WP-08, WP-09, WP-10; WP3 = WP-15, WP-16, WP-18 (server part), WP-19 (sentinel), plus WP-03 (cache hotfix); WP4 = WP-17, WP-18, WP-19 (client part); WP5 = WP-21 to WP-26; WP6 = WP-27 to WP-31; WP7 = WP-11, WP-12, WP-13 (and WP-31 for project pages); WP8 = the release WPs WP-07, WP-14, WP-20, WP-32. Every WP reference below uses the final ids. | 3.13, 4.9, 5, 9, 11 |
| Releases and deprecations | Four releases (UD-01). JS shims `setup`/`requestSetup` and `CustomFieldVisibility` are deprecated in 0.1.0, kept at least throughout 0.1.x, removable no earlier than 0.2.0. Project nested params on `update_dependencies` are deprecated in 0.1.0, accepted throughout 0.1.x, removable no earlier than 0.2.0. Admin nested safe attributes stay permanently (UD-15). The version bump happens only in the release WPs. | G7, G9, 9 |
| Failed-save re-render (gap 1) | Hidden input always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; no `data-dcf-editor-echo`, no `input_value`. Project: `posted: service.parsed_payload` passed to `DependencyEditorConfig.for_project`. WP-22, WP-25 and WP-27 each assert: mapping attribute holds the posted mapping, dirty=1, hidden input blank. | 2.4 P2, 8 FM-21 |
| Canonical names (gaps 2, 3, 4) | `DependencyRules.parent_of(cf)` is the memoized raw parent lookup (WP-05); client emission uses `effective_parent_id` (WP-16). `DependencyRules.value_options` returns `[key, label, active]` tuples; the editor wire shape comes only from `DependencyEditorConfig.wire_values`, and `test/js/fixtures/value_options.json` is written from it (WP-24). `storage_preview(custom_field, store)` is called as `format.storage_preview(record, record.format_store)`. Flash errors go through `translate_error(e)` (one method `translate_error(error_or_key)`, WP-12). | 2.1, 2.2, 2.4, 2.5 |
| i18n constant maps (gap 5) | The WP-02 parity spec iterates `RedmineDependingCustomFields::ClientConfig::I18N` and `DependencyEditorConfig::I18N`, each when it is defined. WP-18 and WP-24 each add an example proving their map is checked. The name `I18N_KEYS` is not used anywhere. | 2.3, G8 |
| Locale registry (gap 8) | `large_lists_i18n_registry.md` is the single source for every new key (owner WP, en/de/fr/nl text). Section 2.7 keeps only a summary of key names and owners. | 2.7, G8 |
| Parity allowlist (gap 10) | Adds de and nl `text_dcf_live_message`; pre-lists fr `label_dcf_inactive`, fr `label_dcf_import_mode` and nl `label_dcf_tab_char`. The full allowlist lives in the registry. | 2.7, G8 |
| Failure modes without a test (gap 12) | Assigned: WP-09 unrelated bulk update on legacy combinations; WP-19 bulk partial failure, mixed-tracker selection and parent `__none__` cascade; WP-27 unauthorized PATCH with a hostile payload; WP-25 same-origin check before fetching the values URL and `test/js/dependency_editor_storage.test.js`; WP-16 inactive-id scenarios (QA-21); WP-26 "Add missing child values" absent on the project fixture and for enumeration children; WP-31 plugin settings page spec; WP-22 `CustomField.safe_attribute_names`. | G5, G7, 8 |
| Ruby 2.7 syntax (gap 15) | No Ruby 3.1 hash shorthand anywhere; WP-18 writes `tag.meta(name: META_NAME, content: payload.to_json)`. The WP-01 syntax gate fails otherwise. | 2.3, G3, 4.8 |
| CI dispatch (UD-32, resolved) | Claude may deliberately dispatch the manual (`workflow_dispatch`-only) workflows after the local gates pass, at most once per workflow per SHA unless a fix was pushed, never editing triggers, always reporting workflow, SHA, run URL and result. CI never gets automatic triggers. | G11, 6, 10 |
| Binding contracts that replace revision 2 choices (compat section 2.4) | No parent attributes on stored cycles and self-parents (effective parent); legacy marker `data-dcf-stored`; one UMD runtime file (no separate rules asset); meta `dcf-i18n` with the frontend's 10 keys; compact value wire shape; `column_limit(column, model = CustomField)`; 90 percent storage threshold; audit markers `payload_truncated`, `payload_bytes`, `payload_sha256`; payload-too-large key `error_dcf_dependencies_too_large_to_send`; editor conflict and submit-gate names; admin form multipart switch (UD-16); D2 bulk semantics as revised (UD-09); FieldIndex server names `load`/`children_ids`. | 2.2 to 2.5, G4, G12 |
| Definition of done | The per-WP report follows the owner OUTPUT FORMAT: 1 minimal context/commands, 2 plan, 3 code changes, 4 tests added/updated, 5 independent review report, 6 QA report, 7 UX/consistency report, 8 gate checklist with PASS/FAIL and evidence, 9 next actions and exact diffs on FAIL. | 6, 7 |

Scope: the improved, repo-specific version of the owner's generic quality prompt for the 9-point plan of `redmine_depending_custom_fields`. It covers:
- the gates G1..G12 with measurable PASS evidence;
- the canonical cross-area contracts the gates test against (section 2), because the area designs disagreed on several shared contracts and a gate that tests two contracts tests none;
- the exact local commands and the `.codex` scripts;
- the test strategy, including ONE fixture mechanism shared by RSpec and jsdom and ONE large-list generator shared by Ruby and JS;
- the per-WP definition-of-done template (owner OUTPUT FORMAT), a failure-mode checklist, the upgrade-notes register for the CHANGELOG and the policy for deliberately triggering the manual CI workflows.

Paths: `$S` = `<planning scratch space, not part of the repository>`. The plugin repo was not modified. Everything marked "verified" was run in a scratch copy in this session.

## 0. Revision summary (review issues to sections)

| Issue(s) | Where fixed |
|---|---|
| R1, QA-01, UX-02, BC-01, SP-04, R6 | 2.2 issue-form contract (one table, owner server), 5.5 one fixture mechanism with mandatory cases |
| R2 | 2.3 head hook (script order, one meta tag, one key set) |
| R3, QA-02, BC-03, SP-01, SP-02, SP-17, R20 | 2.4 editor and payload contract, G5/G6 payload tests, 5.6 payload golden files |
| R4, UX-01 | 2.4 (one partial, one presenter, initial state from a data attribute, failed-save re-render through `data-dcf-editor-mapping` plus `data-dcf-editor-dirty="1"` with a blank hidden input (gap 1; the revision 2 echo flag is withdrawn), project Save disabled until init) |
| R5, R10, R18, SP-09, UX-04, BC-02, BC-13 | 2.5 storage, audit and topology (owner limits) |
| R7 | 2.4 P8 value options: Ruby `[key, label, active]` tuples, compact wire shape from `DependencyEditorConfig.wire_values`, `value_options.json` fixture (gap 3; the revision 2 hash contract spec is dropped) |
| R14 | 2.6 D1 per value, shared case table on both sides |
| R11, QA-05, UX-03, UX-16 | 2.7 locale registry summary (texts in `large_lists_i18n_registry.md`, gap 8), G8 parity spec (duplicate keys, constant maps `ClientConfig::I18N` and `DependencyEditorConfig::I18N`, allowlist incl. gap 10, plurals, quotes, no dashes) |
| R12, QA-16 | 5.7 one generator (limits algorithm, JS twin, tricky values), verified parity E17 |
| R13 | 5.5 fixed id ranges, normalizer, sequence-bump self check, two seeds |
| R16, QA-13c, QA-25, SP-20 | G6 rewritten (resolution from loaded objects, differential and invariance style only), E22 |
| QA-13a | G3 inline-script check covers `javascript_tag`, asserted on rendered HTML, E25 |
| R17, QA-13b, UX-06 | G4 accepts native details/summary; hint pattern fixed in 2.2 C10 |
| QA-13d | 2.3 H3 one asset owner, T-ASSET aligned |
| UX-10 | G4 icon rule and screenshots |
| SP-06 | 2.5 S4 escaped flash interpolations in `translate_error(error_or_key)`, called as `translate_error(e)` (gap 4), G5 spec |
| SP-07 | section 11, reclassified as a security defect (SD-01, UD-03) with a schedule; G5 pinning spec |
| BC-14 | section 9 upgrade-notes register UN-01..UN-62 (with final WP ids, releases and compat PC ids), G9 checks it; version targets |
| Consolidation (critic gaps 1, 5, 8, 10, 12, 15; UD-32 resolved) | consolidation table at the top; 2.2 to 2.7, G3, G5, G7, G8, G11, 3.13, 7, 8, 10 |

## 1. Evidence collected for this design

All of it was run in scratch. The reference implementation of the tooling and test-hygiene work (revision 2 called it WP0; final WP-01 and WP-02) is a scratch clone `$S/design/qa/plugin`, branch `qa-proto`, commits `cc1b2d8..2535f1d` on top of `fa0adaf`. Revision-2 probes are in `$S/design/qa/probe2/` and `$S/design/qa/gen2/`.

**Measured baseline (before any change, `fa0adaf`).** Plugin specs: `259 examples, 0 failures` on Redmine 5.1 (Ruby 3.2.6), 6.0, 6.1 and 7.0 (Ruby 3.3.6). They were run with a local replica of the CI steps of `.github/workflows/rspec-*.yml` (`$S/baseline/run_baseline.sh`): PostgreSQL 16, and `libpq-dev` installed (after `apt-get update`, E21) because the `pg` gem needs `pg_config` on 5.1 and 6.x. Logs: `$S/baseline/log-5.1.txt`, `log-6.0.txt`, `log-6.1.txt`, `log-7.0.txt`. There is no CI workflow for 6.1 yet; WP-01 adds a manual one. RuboCop with core 7.0's `.rubocop.yml` and `plugins/**` un-excluded, on `app lib config db init.rb`: 107 offenses in 38 files (39 files inspected), stored in `$S/baseline/rubocop_baseline.json`. This is the starting point of the G3 "no new offenses" ratchet (informational, never an allowlist). JavaScript tests: none exist; WP-01 and WP-02 add `node --test` with jsdom.

| # | What was proven | Observed output | Where |
|---|---|---|---|
| E1 | The `.codex` chain (clone, setup, test) reproduces the baseline on all four versions | `5.1 16eb9e6 Ruby 3.2.6`, `6.0 b78af69`, `6.1 c70b6eb`, `7.0 86d128c` (Ruby 3.3.6 except 5.1). With the WP-01/WP-02 prototype (the baseline 259 plus the prototype's quality examples): `267 examples, 0 failures` on each version and `lint exit=0 SYNTAX PASS COMPAT PASS RATCHET PASS` | `$S/design/qa/work/logs/*`, `$S/design/qa/chain*.log` |
| E2 | RuboCop baseline reproduced exactly | Core 7.0 config, plugins un-excluded, on `app lib config db init.rb`: 107 offenses in 38 files (39 files inspected), identical to `baseline/rubocop_baseline.json`. With spec/, test/ and Gemfile: 182 offenses in 75 files (76 files inspected) | `$S/design/qa/rc1.json`, `rc2.json` |
| E3 | Raw core 7.0 config pushes Ruby 3.1+ / Rails 8 / Rack 3.1 idioms | It asks for `:unprocessable_content` (5x), `params.expect` (1x), anonymous block forwarding (1x), `Array#intersect?` (1x). On rack 2.2.24 (5.1) `Rack::Utils.status_code(:unprocessable_content)` raises `ArgumentError` | session probe; `rc2.json` |
| E4 | A plugin-local overlay (TargetRubyVersion 2.7, TargetRailsVersion 6.1, `Rails/HttpStatusNameConsistency` off) removes those hazards | 171 offenses in 76 files; 0 hazard cops left | `$S/design/qa/overlay_orig.json` |
| E5 | Core's root RuboCop run never reads a plugin `.rubocop.yml` | Core skips `plugins/**`; explicit `-c plugins/x/.rubocop.yml` inspects the plugin | `$S/design/qa/tree` |
| E6 | Ruby 2.7 syntax gate through the RuboCop parser | Flags the 7 endless defs plus 1 cascade in `spec/patches/custom_field_required_validation_spec.rb` (lines 44, 45, 47, 264, 265, 266, 268, 312), hash shorthand and anonymous forwarding in a probe | `$S/design/qa/syn` |
| E7 | Ratchet detects regressions in changed, new and uncommitted files | `NEW lib/.../sanitizer.rb:50 Performance/MapCompact`, `NEW spec/rails_helper.rb:83 Layout/TrailingEmptyLines`, `NEW .codex/lib/rubocop_ratchet.rb:10 Style/ReduceToHash` (exit 1); clean runs `RATCHET PASS` (exit 0) | `$S/design/qa/work/logs/7.0-lint-*.log` |
| E8 | Opt-in system specs work on 5.1 and 7.0 with core's capybara + selenium | `1 example, 0 failures` on both via `.codex/test_plugin.sh <v> --suite system`; Selenium Manager picks Chrome 154 + driver 154; `CHROME_BIN=/opt/pw-browsers/chromium` (141) fails with a driver/browser mismatch | `$S/design/qa/work/logs/*-system-*.log` |
| E9 | Selenium treats every `<option>` of a visible `<select>` as displayed, even with `hidden` | Capybara visible options `["", "a1", "a2", "b1"]` while the DOM state is `["", "a1", "a2"]` | probe output |
| E10 | Redmine 7.0 has no `#loggedas` | Login is checked with `a.logout` (visible: :all), present on 5.1..7.0 | probe |
| E11 | Random order is safe today | Seeds 1, 4242, 31337 on 7.0: `263 examples, 0 failures` each | session |
| E12 | Dropping the second `init.rb` execution from `spec/rails_helper.rb` | Suite green on 5.1, 6.0, 6.1, 7.0 | `chain6.0.log`, `chain6.1.log`, logs |
| E13 | Locale parity probe | 74 keys in each of de/en/fr/nl, same `%{}` variables; identical-to-English values: de 2, fr 3, nl 1; the only used-but-undefined key is `label_default_value`; core `field_default_value` exists in all four locales on 5.1 and 7.0 | proto `spec/quality/locale_parity_spec.rb` |
| E14 | CI policy check | Psych reads the key `on:` as `true`; the check flags an added `push` trigger | proto `spec/quality/ci_workflows_spec.rb` |
| E15 | JS tooling | `npm ci` 1.3 s, node_modules 30 MB; `node --test "test/js/**/*.test.js"` passes; acorn `--ecma2017` rejects `?.`, `??`, object spread (exit 1; `--silent` masks the exit code, so it is not used); current assets and the frontend/admin prototypes pass ES2017 | `$S/design/qa/jsproto`, `$S/design/qa/es` |
| E16 | Core stylelint config (7.0, stylelint 16.26.1) on plugin CSS | exit 0 | `$S/design/qa/stylelint` |
| E17 | ONE large-list generator (the limits algorithm, arithmetic, no PRNG) with a JS twin is byte-identical across languages | `names(5570, tricky_every: 97)` SHA-256 prefix `233acf899217e962` on Ruby 3.2.6, Ruby 3.3.6 and Node 22.22.0; `JSON.generate(partition(names(27, prefix: 'P'), names(5570, tricky_every: 97)))` prefix `466b240daca61be9` on all three; `sizes()` hashes for (5570,27), (25000,5000), (1000,7), (50000,13) identical; YAML of the 5,570 names 81,239 B (> 65,535, reproduces the MySQL overflow); 25,000 names in 112 ms (Ruby) / 38 ms (JS). Requires `sizes()` to sum weights with a naive left fold, because Ruby `Array#sum` uses Kahan-Babuska summation and JS does not | `$S/design/qa/gen2/{dcf_large_list.rb,large_list.js,parity.rb,parity.js}` |
| E18 | Plugin specs on MariaDB 10.11 (limits area) | 5.1 and 7.0: `259 examples, 0 failures`; `format_store` limit 65535 live | `$S/design/limits/run/rspec51_mysql.log`, `rspec70_mysql.log` |
| E19 | Rack status deprecation warnings in the baseline | 0 on 5.1; 11 per run on 6.0/6.1/7.0, all from `have_http_status(:unprocessable_entity)` | `$S/baseline/log-*.txt` |
| E20 | Fork vs upstream | `jcatrysse/redmine` 5.1-stable = upstream (16eb9e6); fork 6.1-stable `93051bd` lags upstream `c70b6eb` (6.1.5) | `$S/research/redmine-*` |
| E21 | Prerequisite learned from the baseline | `apt-get install libpq-dev` failed with 404 until `apt-get update` ran | `$S/baseline/apt.log` |
| E22 | Parent resolution cost on the issue form (5 depending children with 5 DISTINCT list parents, one parent role-restricted, non-admin member) | Resolving each parent from `issue.available_custom_fields` (the instances core already used for `editable_custom_field_values`) plus `visible_by?` and reading the parent value: **0 queries** on 5.1 and 7.0. `CustomField.find_by(id: parent_id)` per parent: **5 queries on 7.0, 6 on 5.1** (one extra roles load). `format_store` is `ActiveRecord::Type::Serialized` with `ActiveRecord::Store::IndifferentCoder` on both | `$S/design/qa/probe2/g6_probe.rb` |
| E23 | Fixture records with explicit ids in a fixed high range are stable while sequence ids drift | Two renders in savepoints, the second after creating 3 throwaway fields: fixed ids 9100001/9100002/9200001 identical, sequence ids 1008 vs 1012 (5.1) and 1993 vs 1997 (7.0); `custom_fields_id_seq` never reaches the fixed range (PostgreSQL) | `$S/design/qa/probe2/fixed_id_probe.rb` |
| E24 | Duplicate locale keys are silent and detectable | `YAML.safe_load` keeps the last duplicate; a `Psych.parse_stream` tree walk reports `en.activerecord.errors.messages.m (lines 7, 8)` and `en.a (lines 2, 9)` on Psych 5.0.1 and 5.1.2; the four current plugin locale files have no duplicates | `$S/design/qa/probe2/dupkeys.rb` |
| E25 | The current inline script is emitted with `javascript_tag` | `lib/redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook.rb:27`; a grep for `<script` alone misses it | repo |
| E26 | Frontend prototype facts | Any `data-dcf-context` other than `bulk` is treated as `form` (`design/frontend/proto/depending_custom_fields.js:72`); it reads `data-dcf-allowed` (`:65`); hints get `role=status` (`:152`) | `$S/design/frontend/proto` |
| E27 | En and em dash counts today | README.md 14, CHANGELOG.md 3, locale files 0, docs/specs about 200 | `grep -c` |
| E28 | jc-redmine_extended_api writes custom fields through `safe_attributes=` | `lib/redmine_extended_api/patches/custom_fields_controller_patch.rb:105-110` | `$S/research/jc-redmine_extended_api` |

## 2. Canonical cross-area contracts (the single source the gates test against)

The area designs specified several shared contracts twice. Each contract below has ONE owner area, ONE data shape and ONE test source. Every gate and every test in this document refers to these definitions. The owning area's design must match them in the consolidated plan; deviations require changing this section first (reviewer sign-off), never a second definition.

Consolidation: this section is aligned with `large_lists_compatibility.md` section 2.4 ("Reconciled cross-area contracts", binding for all WPs) and section 3 ("Contract rows added during consolidation"), and with the owning area designs (server section 2, editor sections 3 to 9, limits sections 4 to 6). Where a revision 2 choice of this section lost in that reconciliation, the text below states the adopted rule and names the superseded one, so a reviewer can trace the change. If a future WP finds a remaining difference, the compatibility document wins until this section is corrected.

### 2.1 Ownership register

| Shared artifact | Single owner | Consumers | Single test source |
|---|---|---|---|
| Issue-form data attributes (2.2) | server (WP-16, WP-19) | frontend runtime, wizard | generated markup fixtures `test/js/fixtures/markup/*.html` (5.5) |
| Head hook output: scripts, CSS, meta (2.3) | server (WP-18; editor assets WP-25) | frontend runtime, `context_menu_wizard.js`, editor | generated head fixtures `test/js/fixtures/head/<locale>.html` + `spec/hooks/view_layouts_base_html_head_hook_spec.rb` |
| `DependencyPayload` schema and parser (2.4) | editor (WP-21) | admin virtual attribute, `DependencyMappingService`, editor JS serializer | `spec/lib/dependency_payload_spec.rb` + payload golden files `test/js/fixtures/payload/*.json` (5.6) |
| Shared editor partial, presenter, DOM contract (2.4) | editor (WP-24, WP-25) | admin form, project `edit_dependencies` | generated editor fixtures `test/js/fixtures/editor/*.html` |
| Value options (2.4 P8): Ruby tuples and the compact wire shape | server (`DependencyRules.value_options`, `[key, label, active]` tuples, WP-05); editor (`DependencyEditorConfig.wire_values`, WP-24) | editor endpoint, presenter, editor JS; project values page and project dependency page consume the tuples as `\|key, label, active\|` (WP-27, WP-28) | `spec/lib/dependency_rules_spec.rb` (tuple order, inactive handling) + `test/js/fixtures/value_options.json` written from `DependencyEditorConfig.wire_values`, with a spec asserting endpoint == presenter == fixture (WP-24, gap 3); no hash contract spec |
| `StorageLimits`, model error key, service mapping, client storage attributes (2.5) | limits (WP-11, WP-12; client attributes WP-24) | admin form, JSON API, BaseService, editor | `spec/lib/storage_limits_spec.rb`, `spec/services/dcf_storage_mapping_spec.rb` |
| `AuditPayload` cap and marker (2.5 S5) | limits (WP-12) | AuditRecorder, project delta | `spec/services/dcf_audit_payload_spec.rb` |
| Topology helper `FieldIndex`; context-menu `SelectionGraph` (2.5 S6) | `FieldIndex`: one class with the server names `load`/`children_ids`, delivered by WP-05 (compat section 2.4 "FieldIndex API"; the limits area keeps the storage report); `SelectionGraph`: server (WP-15) | cycle check, parent select, usage, values page; context menu | `spec/lib/field_index_spec.rb`, `spec/models/selection_graph_spec.rb` |
| Storage report for rake (2.5 S6) | limits (`StorageReport`, WP-13) | `report_sizes` task | `spec/lib/storage_report_spec.rb` |
| D1 leniency rule (2.6) | server (WP-05 table, WP-09 D1 rows) | frontend rules (WP-17) | shared case table `test/js/fixtures/shared/rules_cases.json` |
| Locale key registry (2.7; texts in `large_lists_i18n_registry.md`) | quality maintains the registry; each key has one owner area and one owner WP (gap 8) | all | `spec/quality/locale_parity_spec.rb` (WP-02), which also iterates `ClientConfig::I18N` and `DependencyEditorConfig::I18N` when defined (gap 5) |
| Fixture infrastructure, generator, query/YAML counters | quality | all specs | `spec/support/dcf_js_fixtures.rb` (delivered by WP-16), `spec/support/dcf_large_list.rb`, `test/js/support/large_list.js`, `spec/support/query_counter.rb` (WP-02) |
| Upgrade-notes register (section 9) | quality | CHANGELOG, README | G9 checklist |

### 2.2 Issue-form data contract (owner: server)

Rendered by the shared depending-format module's `edit_tag` / `bulk_edit_tag` into `options[:data]` (merged with caller data, never mutating it), so the attributes land on the `<select>` or on `span.check_box_group`. The canonical table is the server design's section 2.2 (WP-16 emits it, additive; WP-19 adds the sentinel and the required '(none)' option); the table below mirrors it for the gates. "Managed field" means a depending field whose effective parent (`DependencyRules.effective_parent_id`: exists, same type and family, not self, acyclic through `FieldIndex`) is visible to the user (`parent.visible_by?(scope_project, user)` in form context, for every selected project in bulk; exceptions count as not visible).

| Attribute | Value | Presence |
|---|---|---|
| `data-dcf-field` | child CF id | always on a depending field |
| `data-dcf-kind` | `list` or `enumeration` | always |
| `data-dcf-context` | `form` (from `edit_tag`, new and edit records alike) or `bulk` (from `bulk_edit_tag`: issue and time-entry bulk edit, context-menu wizard). Missing or unknown is read as `form` by the client | always |
| `data-dcf-multiple` | `1` | only when `cf.multiple?` |
| `data-dcf-parent` | effective parent CF id | managed fields only: stored cycles, self-parents and dangling parents EXCLUDED (compat section 2.4 "Emission on stored cycles and self-parents"; revision 2 emitted on cycles and self-parents). `DependencyRules.parent_of(cf)` (gap 2, WP-05) is the memoized raw lookup `effective_parent_id` builds on; client emission never uses it directly. Discovery selector `[data-dcf-parent]` |
| `data-dcf-parent-name` | `"<prefix>[custom_field_values][<parent id>]"` | with `data-dcf-parent`, when the tag name matches the prefix pattern |
| `data-dcf-map` | JSON object, string keys; list values as JSON strings, canonical enumeration ids (`/\A[1-9]\d*\z/`) as JSON numbers; `{}` when empty | with `data-dcf-parent`. **Sanitized, NOT pruned**: it is exactly the mapping server validation uses, so a stored legacy parent value that left the parent's list still maps |
| `data-dcf-defaults` | JSON object, parent key to a child key or an array | with `data-dcf-parent`, only when non-empty |
| `data-dcf-hide` | `1` | with `data-dcf-parent`, when `hide_when_disabled` is true; ignored by the client in `bulk` |
| `data-dcf-parent-values` | JSON array of strings: the parent keys currently stored on the record; `[]` when blank or when the parent is not available on the record | `form` context only, only with a single `customized` record, and only on managed fields (so only when `parent.visible_by?(project, user)` is true; exceptions treated as not visible). Replaces the frontend's `data-dcf-allowed`, which is dropped |
| `data-dcf-parent-label` | `parent.name` (plain text) | same condition as `data-dcf-parent-values`; used by the client only for hints when the parent control is absent from the scope |
| `data-dcf-stored` | JSON object `{"child": [...], "parent": [...]}`, all strings: the server D1 baseline (2.6). Persisted record: `value_was` of child and parent; issue copy (single, bulk, project copy): the copy source's stored values (UD-06, gap 6) | managed, `form` context, and the record is persisted or is a copy with a baseline source; absent for every other new record (the runtime's new-record flag, UD-12). Compat section 2.4 "Legacy marker" |
| sentinel `input[type=hidden][name=<tag_name>][value=""][data-dcf-blank=1]`, no `id` | | managed, `form` context, single-value (not multiple) depending child with `edit_tag_style == 'check_box'` (radios), immediately BEFORE `span.check_box_group` (WP-19). The only element the override adds in form context |
| option `<option value="__none__" data-dcf-required-none="1">` right after "(no change)" | | managed, `bulk` context, REQUIRED child (core omits `__none__` for required fields); enabled by the client only while the parent selection allows no value (UD-10, WP-19) |

Decisions behind the table (C1..C10):
- **C1 context `form|bulk`.** `edit_tag` also renders new-record forms, so `edit` is misleading; the frontend prototype and its 37 tests already use `form` (E26). The server design's `edit` is renamed.
- **C2 parent-values with a visibility gate, no `data-dcf-allowed`; legacy marker `data-dcf-stored`.** (Consolidated: the server also emits `data-dcf-stored`, so the client keeps, enables, marks and posts exactly the stored values the server tolerates, including copied legacy values; gap 6, WP-16, WP-17.) `data-dcf-allowed` computed from a role-invisible parent identifies the hidden parent value (SP-04). With the gate, the client computes `allowed = allowedFor(map, parentValues)` itself, which equals what `data-dcf-allowed` would carry, with a smaller payload. Behaviour rows: workflow read-only (visible) parent filters by the stored value (frontend F13); role-invisible parent leaves the child unfiltered (server validates); parent not available for the tracker gives `[]`, so nothing new is allowed, which matches server validation (allowed set empty).
- **C3 no emission on stored cycles (consolidated).** Adopted rule (compat section 2.4): stored cycle members and self-parents get no parent attributes, because server validation treats fields in or below a stored cycle as unconstrained until fixed (UD-08, WP-10), so client and server agree on leaving them unfiltered. The client's visited-set guard (frontend FD-16) stays as defense for chains. Superseded revision 2 rule, kept for traceability: "emit on cycles, because server validation still validates cycle members"; that premise no longer holds after UD-08.
- **C4 map not pruned.** Client and server must see the same mapping. Child values without an option are ignored by the client anyway. On MySQL the store is at most 64 KB, so the attribute is bounded (limits measured about 95 KB worst case). The limits recommendation L11 to prune is withdrawn.
- **C5 enumeration ids as JSON numbers** (limits F27, frontend FD-3, server S5 agree).
- **C6 radio sentinel** (frontend FD-7). Server guarantee 1 becomes: "adds attributes, plus the id-less blank sentinel for single radio children (and, in bulk, the required '(none)' option); nothing else; `label for=` unchanged".
- **C7 bulk `__none__` for required children (frontend FD-22)** is owner decision UD-10 (recommended: adopted, implemented by WP-19 with `data-dcf-required-none`). Both outcomes are specified in the tests: adopted means parent "(none)" clears required descendants; rejected means the README and the CHANGELOG state that D2's clear-on-(none) does not apply to required children and the runtime shows the `empty` hint (frontend B3r).
- **C8 one fixture mechanism.** `spec/fixtures/dcf_client_contract.json` and the server's comparison of rendered attributes against it are dropped; `spec/lib/client_data_spec.rb` keeps unit assertions on the Hash only. The canonical contract is the markup the real helpers render (5.5), consumed by the jsdom suites.
- **C9 client output** `data-dcf-state` (`ok|waiting|empty|legacy|none|unfiltered`) and the `dcf:updated` event are frontend-owned outputs, never read back.
- **C10 hint accessibility (resolves the G4 conflict).** The hint is created by JS on first evaluation as `em.info.dcf-hint` with an id `dcf-hint-<n>` from a module counter (never derived from values) and that id is appended to `aria-describedby` of the select (or of each input of a check box group), preserving existing tokens. No `role=status` per hint. Changes are announced through ONE page-level polite live region (`div#dcf-live.hidden-for-sighted[role=status][aria-live=polite]`), debounced 400 ms, one announcement per cascade. A JS-generated id is safe: `replaceIssueFormWith` copies only input/select/textarea values (core-7.0 `application-legacy.js:727-737`) and `custom_field_tag_with_label` scans only the server-rendered tag (core-7.0 `custom_fields_helper.rb:122-131`). Frontend FD-14 is updated accordingly.

Mandatory fixture cases (each a generated markup fixture plus a jsdom test asserting the filtering outcome on that markup; WP-16 generates them, WP-18 and WP-19 regenerate them): list single, list required, multi select, single radio, single radio required (with sentinel), multi checkbox, enumeration (integer ids), chain of three, workflow read-only parent, role-invisible parent (non-admin member: no parent attributes, no `data-dcf-parent-values`), parent not available for the tracker (`[]`), stored cycle A to B to A (no parent attributes), self-parent (no parent attributes), dangling parent (no parent attributes), legacy parent value not in the parent list, legacy value on a persisted issue (`data-dcf-stored` from `value_was`), issue copy holding a legacy combination (`data-dcf-stored` from the copy source), new issue (no `data-dcf-stored`), issue plus time_entry prefixes, project form, user form, bulk single, bulk multi, bulk required (with the `data-dcf-required-none` option), bulk chain, time-entry bulk, wizard partial, tricky values from the generator (`[x]`, `a]`, quotes, `semi;colon`, non-ASCII), and the inactive cases of QA-21 (gap 12, WP-16): a stored inactive child id, a stored inactive parent value, a per-parent default on an inactive id, inactive ids in `data-dcf-map` without a matching option.

### 2.3 Head hook (owner: server)

- **H1 order (consolidated, WP-18).** After core's jQuery: `<meta name="dcf-i18n">`, `depending_custom_fields.js`, `context_menu_wizard.js`, `depending_custom_fields.css`, then (editor pages only, H3) the editor assets. There is ONE UMD runtime file that holds the pure rules and the DOM runtime (compat section 2.4 "Rules asset"); `depending_custom_fields_rules.js` is not created, so there is no "rules missing" inert mode. Superseded revision 2 rule: a separate rules file before the runtime, with the runtime inert without `window.DependingCustomFieldsRules`.
- **H2 one meta tag, flat payload, one key set (consolidated, compat section 2.4 "i18n meta tag").** `<meta name="dcf-i18n">` whose content is a flat JSON object with the frontend's 10 runtime keys `selectParent`, `noOptions`, `noOptionsGeneric`, `legacy`, `legacyLocked`, `legacyGeneric`, `bulkDefault`, `bulkCleared`, `liveMessage`, `saveFailed`, built per request in the current locale from `RedmineDependingCustomFields::ClientConfig::I18N` (gap 5): `text_dcf_hint_select_parent`, `text_dcf_hint_no_options`, `text_dcf_hint_no_options_generic`, `text_dcf_hint_legacy`, `text_dcf_hint_legacy_locked`, `text_dcf_hint_legacy_generic`, `text_dcf_hint_bulk_default`, `text_dcf_hint_bulk_cleared`, `text_dcf_live_message` (owner WP-18) and the existing `error_save_failed`. The frontend owns the key list, the server emits it. The hook writes it with `tag.meta(name: META_NAME, content: payload.to_json)`; the explicit `name: META_NAME` is required, because Ruby 3.1 hash shorthand fails the WP-01 Ruby 2.7 syntax gate (gap 15). Superseded revision 2 payload: 4 keys (`waiting`, `empty`, `legacy`, `saveFailed`) from `text_dcf_hint_select_parent_first`, `text_dcf_hint_no_options` and `text_dcf_hint_legacy_value`; those two `_first`/`_value` keys are not created. The server's `redmine-depending-custom-fields` meta with a nested `i18n` object and the `label_dcf_hint_*` keys stay dropped: the only non-i18n configuration the old global carried (`basePath`) is replaced by the wizard form `action`, so a nested config object has no content. Both the runtime and `context_menu_wizard.js` read this meta; English fallbacks when it is missing. The constant is never called `I18N_KEYS` (for example `ViewLayoutsBaseHtmlHeadHook::I18N_KEYS` does not exist).
- **H3 one asset owner for the editor (WP-25, 0.1.0 (M3)).** The head hook adds `dcf_dependency_editor_model.js`, `dcf_dependency_editor.js` and `dcf_dependency_editor.css` (after the base assets) when `context[:controller].class.name` is `CustomFieldsController` or `ProjectCustomFieldConfigurationController`, for every action (needed for the `/custom_fields/new` AJAX re-render). Project views do NOT `content_for` editor assets; they include only `dcf_config.css`, plus `dcf_value_reorder.js` when sortable and `dcf_values_page.js` in page mode (WP-30). Project test T-ASSET becomes: editor assets present on every `ProjectCustomFieldConfigurationController` page and absent on issue pages; every script `src` appears exactly once in the rendered head.
- **H4 no inline script, no database, no cache.** The hook output contains no `<script>` element without `src` and performs no query (asserted with the query counter: 0 queries).

### 2.4 Editor and payload (owner: editor)

- **P1 one partial, one presenter.** `app/views/depending_custom_fields/_dependency_editor.html.erb` fed by `RedmineDependingCustomFields::DependencyEditorConfig.for_admin(field, view)` / `.for_project` with the keyword arguments `field`, `parent`, `view`, `posted` and `conflict` (WP-24). The project's `DependencyEditorData` and the helper `dcf_editor_i18n` are not created; the presenter provides `i18n` (resolving `DependencyEditorConfig::I18N`, created by WP-24 with only WP-24's keys and extended by WP-25 and WP-26 in the same commit as their locale entries, gap 8). Root `fieldset.dcf-dep-editor[data-dcf-editor]`, every attribute in the `data-dcf-editor-*` namespace (so nothing collides with the issue-form `data-dcf-parent*` names). The project page uses `data-dcf-editor-parent-values` / `data-dcf-editor-child-values`, not `data-dcf-parent-values`.
- **P2 initial state and dirtiness (failed-save rule, gap 1; compat section 3).** Initial state always comes from `data-dcf-editor-mapping`. The hidden input is ALWAYS rendered blank on both pages, on a GET and on every re-render. A failed save re-render renders the parsed ok payload in `data-dcf-editor-mapping` and sets `data-dcf-editor-dirty="1"`; only then does the editor start dirty (and writes the payload into the hidden input itself). There is no `data-dcf-editor-echo` attribute and no `input_value` option. Project: the controller passes `posted: service.parsed_payload` (the service's memoized `Result`, P7) to `DependencyEditorConfig.for_project`. Tests (WP-22 admin, WP-25 editor JS, WP-27 project): after a failed save the mapping attribute holds the posted mapping, `data-dcf-editor-dirty` is `1` and the hidden input is blank. The `beforeunload` warning therefore never fires on an untouched page. Superseded revision 2 rule: posted JSON in the hidden input plus `data-dcf-editor-echo="1"`. On the project page the submit button carries `data-dcf-editor-submit` and is rendered `disabled`; the editor enables it after init, so a no-JS user can never post a blank payload and is never told to reload (the `noscript` text explains that JavaScript is required). On the admin form a blank input means unchanged (core's Save stays usable for other attributes).
- **P3 payload schema v1** (both pages): top-level keys `version` (optional, `1`), `source` (optional, `editor` or `import`), `base` (optional String, admin lost-update digest), `value_dependencies` (optional Object), `default_value_dependencies` (optional Object), `import` (optional Object `{mode: "merge"|"replace", rows: Integer 0..10,000,000}`). Any other key is rejected (`unknown_key`). No `meta` wrapper. The editor JS writes `source: "import"` and `import` after an applied import.
- **P4 one parse API.** `DependencyPayload.parse(raw)` returns `nil` for nil or a blank String, otherwise a `Result` with `ok?`, `error` (Symbol), `bytes`, `value_dependencies`, `default_value_dependencies`, `source`, `base`, `import`. It never raises. Entry-point policy: admin `nil` means unchanged; project `nil` while `params.key?(:dependencies_json)` means error `:blank`. Project failures raise `OperationError` inside the BaseService subclass, so they are audited.
- **P5 limits and hardening (SP-01, SP-02).** `MAX_BYTES = 4 MiB` on both paths; `max_nesting: 3`; `create_additions: false`. Before `JSON.parse`, an O(n) pre-scan rejects any numeric token of 20 or more digits (`:number_too_long`). Integers are accepted only when positive and `bit_length <= 63`, checked before `to_s`. Floats, booleans and `null` are rejected everywhere. Error to message mapping: `:too_large` maps to the size messages, never to "could not be read": admin model error `activerecord.errors.messages.dcf_dependencies_too_large_to_send` (WP-22) and flash or client message `error_dcf_dependencies_too_large_to_send` (WP-25, reused by WP-27), both with `%{size}`/`%{limit}` (compat section 2.4 "Payload-too-large key"). Superseded revision 2 keys, not created: `dcf_dependencies_payload_too_large` and `error_dcf_dependency_payload_too_large`.
- **P6 transport sizes (consolidated, compat section 2.4 "Admin form encoding", UD-16).** Project form stays `multipart/form-data` (Rack 16 MB multipart buffer, so 4 MiB of JSON fits). The admin form is core's urlencoded PUT (Rack 4 MB body, overflow becomes a 404 via MethodOverride); after a successful init the admin editor switches it to `multipart/form-data` (WP-25), so the 4 MiB payload is reachable. Both editors pre-check the payload against `data-dcf-editor-max-payload-bytes` (4 MiB, `error_dcf_dependencies_too_large_to_send`) and the whole form, for the encoding the form actually uses at submit, against `data-dcf-editor-max-form-bytes` (`{"multipart":16252928,"urlencoded":4128768}`, `error_dcf_editor_form_too_large`), and show an i18n message instead of submitting. Superseded revision 2 rule: the admin form stays urlencoded with a 3.9 MB URL-encoded pre-check.
- **P7 parse once.** The admin parse `Result` is memoized on the CustomField instance, keyed by the identity of the raw String; `DependencyMappingService` exposes its `Result` as `service.parsed_payload` so the controller re-render reuses it (P2).
- **P8 value options and wire shape (consolidated, gap 3; compat section 2.4 "Value option wire shape").** `DependencyRules.value_options(cf)` (WP-05) returns Ruby tuples `[key, label, active]` (key and label Strings, active true or false), ordered by possible-values order or enumeration position then id, inactive enumerations included. Ruby consumers read them as `|key, label, active|` (WP-27, WP-28). The wire shape is compact and produced only by `DependencyEditorConfig.wire_values` (WP-24): `{key}`, `label` only when it differs from the key, `active: false` only when inactive; the editor JS (`ValueList.fromWire`) defaults the label to the key and treats a missing `active` as true. The endpoint `GET /dcf_dependency_editor/values` and the presenter use exactly this shape; `test/js/fixtures/value_options.json` is written from `wire_values`, and a WP-24 spec asserts endpoint == presenter == fixture. Superseded revision 2 rule: a full `{ 'key', 'label', 'active' }` hash from `value_options` with a hash contract spec (dropped).
- **P9 storage attributes** (with limits): on the editor root `data-dcf-editor-storage-limit`, `data-dcf-editor-storage-base`, `data-dcf-editor-storage-warn` (`StorageLimits::WARN_PERCENT`, 90) and (admin list children) `data-dcf-editor-values-limit`, all absent when no column limit (project mode: the effective limit of `ProjectStoragePolicy.format_store_limit(field)`, WP-31). One threshold policy (compat section 2.4 "Storage threshold and client key"): the client estimate message `text_dcf_storage_estimate` (owner WP-24, shown by WP-25) appears at or above `data-dcf-editor-storage-warn` percent of the limit; the server line `text_dcf_storage_usage` (WP-11, UD-28) appears at 90 % or more of the persisted bytes. Units: delimited bytes on both sides. Test (gap 12, WP-25): `test/js/dependency_editor_storage.test.js` covers the warning at or above the threshold, no warning without the attribute, and the possible-values estimate against `data-dcf-editor-values-limit`. Superseded revision 2 threshold: 80 %.
- **P10 names.** The virtual attribute and param are `dependencies_json` everywhere (`custom_field[dependencies_json]` on admin, `dependencies_json` on project); the name `value_dependencies_json` is not used.

### 2.5 Storage, audit, topology (owner: limits)

- **S1 callback registration.** ALL new CustomField callbacks (editor `before_validation :dcf_apply_dependencies_json`, `validate :dcf_validate_dependencies_json`; limits `validate :dcf_validate_storage_limits`, in that order) are registered as symbols from ONE new module `RedmineDependingCustomFields::Patches::CustomFieldValidationPatch`, prepended in `init.rb` right after `CustomFieldPatch` (created by WP-11; the editor transport callbacks join it in WP-22, registered before the storage validation). `CustomFieldPatch.prepended` registers nothing new: its stand-in classes in `spec/patches/custom_field_required_validation_spec.rb` define only `after_save`, and registering there broke 14 examples (limits V11). In addition WP-04 rewrites that spec DB-backed (real fields via `DcfConfigHelpers`), so the stand-in fragility is removed, not just avoided.
- **S2 API (WP-11).** `StorageLimits.column_limit(column, model = CustomField)` (spec seam; compat section 2.4 "`column_limit` signature", limits owns StorageLimits; revision 2 of this document had `(model, column)`), `violations(record)`, `validate(record)`, `violation_in(record)`, `usage(record)`, plus `base_bytes(field)`, `serialized_bytesize`, `delimited` and `WARN_PERCENT` (90) for the editor attributes. Model error `activerecord.errors.messages.dcf_storage_too_large` with `%{size}`/`%{limit}` (locale-delimited) and integer details. The server's `dcf_too_large`, `too_large?` and `StorageLimits.report` are not created.
- **S3 one service mapping (WP-12).** `BaseService#call` maps a `RecordInvalid` carrying a storage violation to `OperationError` `:error_dcf_values_too_large` / `:error_dcf_mapping_too_large` with interpolations `{field, size, limit}` (limits L7). The project design's pre-check `guard_storage!` and `error_value_too_large` / `text_dcf_size_detail` are dropped. `ActiveRecord::ValueTooLong` maps to `:error_dcf_value_too_long`; its audit row stores only the class name, the column and the byte counts, never `e.message` (it contains SQL and the value; the project audit view shows `error_message` to non-admin managers).
- **S4 flash escaping (SP-06, WP-12; gap 4).** Redmine renders flash with `html_safe` (core-5.1 `application_helper.rb:487`, core-7.0 `:527`). One controller method `translate_error(error_or_key)` (one parameter: a Symbol or an `OperationError`) applies `ERB::Util.h` to every interpolation value before `l()`. Callers that hold an `OperationError` call `translate_error(e)` (WP-12 call sites, and the new actions of WP-27 to WP-31); `render_field_error` and the archived-project path keep passing Symbols. Every flash in `ProjectCustomFieldConfigurationController` goes through it; payload content (offender keys, values, labels, import rows) never goes into a flash, only into the audit summary. Superseded revision 2 names, not created: the helper `dcf_flash_error(key, interpolations = {})` and the two-argument `translate_error(key, interpolations)`.
- **S5 audit cap (WP-12).** One `AuditPayload`: `MAX_BYTES = 16_384` per before/after value, `MAX_IDS = 1_000`, `MAX_ERROR_CHARS = 4_000`. Marker keys `payload_truncated`, `payload_bytes`, `payload_sha256` (compat section 2.4 "Audit marker keys": the limits names, so they collide neither with the project delta's own `truncated` nor with its mapping digest `mapping_sha256`; revision 2 of this document proposed `truncated`, `original_bytes`, `payload_sha256`). The project delta (WP-27) is capped at 20 entries, 3 default labels per entry and 80 encoded bytes per label (`LABEL_MAX_BYTES = 80`), so its worst case (measured 13,603 B) stays under the cap. Project T-AUD-10 asserts truncation only above 16,384 bytes; AuditRecorder's 60,000 cap is not created.
- **S6 one topology helper, one report.** `FieldIndex` (WP-05; raw-YAML regex parent extraction, one query, cycle-safe BFS; server method names `FieldIndex.load` and `children_ids`, compat section 2.4 "FieldIndex API", the limits names `build`/`child_ids` are not created) is the only topology helper. `DependencyRules.ancestor_ids`, `descendant_ids`, `in_cycle?`, `parent_candidates` and `children_of` delegate to a `FieldIndex` built once per call or passed in; `DependencyRules::Graph` is not created; `UsageCalculator.page_usage` loads children through one `FieldIndex`. `SelectionGraph` stays (context menu, built from instances already loaded, zero queries, a different job). `StorageReport` is the only report implementation behind `report_sizes`.
- **S7 sanitize-only normalization (BC-02).** `before_custom_field_save` and `storage_preview` only sanitize (as today). The signature is `storage_preview(custom_field, store)` (WP-06), called by the storage validation as `format.storage_preview(record, record.format_store)` (gap 4, compat section 3). D6 pruning runs ONLY inside the admin JSON transport (`dcf_apply_dependencies_json`, when `dependencies_json` was posted). API saves, `safe_attributes=` saves from other plugins and project cascades never prune.

### 2.6 D1 legacy leniency per value (owner: server)

Core's own idiom is per value (`ListFormat#validate_custom_value` subtracts `value_was`). Rule: when the parent did not change (order-insensitive, or the parent is not available on the record), every child value contained in `value_was` is exempt; only newly added values are validated against the allowed set. When the parent changed, all values are validated. The whole-set rule of server design section 8 is replaced. The client keeps legacy values selectable until the first parent change (frontend F6), which is consistent; it learns the baseline from `data-dcf-stored` (2.2), including the copy source baseline for issue copies (UD-06). Releases: the server rule ships in 0.1.0 (M1) (WP-09; UD-04, UD-05, UD-06, UD-07), the client side in 0.1.0 (M2) (WP-16, WP-17), so in 0.1.0 (M1) the leniency applies to the REST API, email, bulk edit, the wizard and copies, and the issue form keeps such values from 0.1.0 (M2) on. The shared case table `test/js/fixtures/shared/rules_cases.json` holds rows `{parent_was, parent, child_was, child, map, multiple, valid}` run by the Ruby rules (spec/lib/dependency_rules_spec.rb evaluates each row through `DependencyRules.dependency_check` with a stubbed custom value and `ParentState`, server design section 8) and by the JS rules (asserting the client never produces a submission marked invalid). Mandatory rows: multi child add allowed (valid), add disallowed (invalid), remove legacy (valid), reorder (valid), keep legacy and change parent (invalid), single child change from legacy to allowed (valid), single child change legacy to another disallowed (invalid), parent not available and untouched (valid).

### 2.7 Locale key registry (summary; texts in `large_lists_i18n_registry.md`)

**Single source of truth (gap 8).** `large_lists_i18n_registry.md` lists every new or changed locale key with its owner WP, its interpolations and the en, de, fr and nl texts (including the UX-16 corrections of gap 9 and the per-locale quotes below). This section is only a summary: it keeps the key names and the winning owner of every key that two areas had defined. The full translations that revision 2 quoted here are removed; for any text, see large_lists_i18n_registry.md. Every key has exactly one owner WP, which adds it to all four locale files in one commit; a later WP that needs the key reuses it and never redefines it, otherwise the duplicate-key check of G8 fails.

| Key | Owner area, owner WP | Resolution (texts: see large_lists_i18n_registry.md) |
|---|---|---|
| `field_value_dependencies` | limits, WP-11 | "Dependency mapping" wording (grammatical with singular verbs in full messages, matches `notice_dependencies_saved`). Server and editor do not define it; the editor uses it as the legend |
| `field_dependencies_json`, `field_default_value_dependencies` | editor | not created (removed in editor revision 2) |
| `field_parent_custom_field`, `warning_dcf_parent_cycle`, `activerecord.errors.messages.dcf_circular_dependency` | server, WP-10 | as in the server design |
| `activerecord.errors.messages.dcf_storage_too_large` | limits, WP-11 | the one storage model error; `dcf_too_large` deleted |
| `activerecord.errors.messages.dcf_invalid_dependencies_payload`, `dcf_stale_dependencies`, `dcf_dependencies_too_large_to_send` | editor, WP-22 | the three admin model errors; revision 2's NEW `dcf_dependencies_payload_too_large` is not created (P5) |
| `error_invalid_dependency_payload` | editor, WP-25 (reused by WP-27) | one definition (gap 8); the project area's copy is deleted. Revision 2 of this section gave the key to the project area with the project wording; superseded |
| `error_dcf_dependencies_too_large_to_send` | editor, WP-25 (reused by WP-27 and the client pre-check) | `%{size}`, `%{limit}`; replaces revision 2's NEW project key `error_dcf_dependency_payload_too_large`, which is not created (compat section 2.4 "Payload-too-large key") |
| `error_dcf_editor_form_too_large` | editor, WP-25 | `%{size}`, `%{limit}`; the form-size pre-check of P6 |
| `error_dcf_values_too_large`, `error_dcf_mapping_too_large`, `error_dcf_value_too_long` | limits, WP-12 | texts without the README reference (shown to non-admin managers), ending with the glossary's "ask an administrator" phrase; neutral project wording (compat section 2.4 "Service storage error text"); `%{field}` escaped (S4). `error_value_too_large`, `text_dcf_size_detail` deleted |
| `text_dcf_hint_select_parent`, `text_dcf_hint_no_options`, `text_dcf_hint_no_options_generic`, `text_dcf_hint_legacy`, `text_dcf_hint_legacy_locked`, `text_dcf_hint_legacy_generic`, `text_dcf_hint_bulk_default`, `text_dcf_hint_bulk_cleared`, `text_dcf_live_message` | frontend, WP-18 | the runtime keys of `ClientConfig::I18N` (H2), `error_save_failed` reused (compat section 2.4 "Hint keys"). `label_dcf_hint_*`, `text_dcf_hint_select_parent_first` and `text_dcf_hint_legacy_value` are not created |
| `text_dcf_editor_noscript` | editor, WP-24 | the only noscript key. `text_dcf_editor_requires_javascript` not created |
| `text_dcf_editor_orphans` | editor, WP-25 | the only orphan message (client-side, both pages, plain "Label: %{count}" phrasing). `text_dcf_orphan_entries` not created |
| `text_dcf_editor_help` | editor, WP-24 | one neutral help for both pages: the editor revision 2 text (gap 8 resolved the three competing texts, including revision 2 of this section). Replaces `text_dependency_matrix_help` on the project page (the old key is deleted by WP-27 with the matrix) |
| `text_dcf_editor_select_parent` | editor, WP-24 | |
| `text_dcf_editor_no_parent_values`, `text_dcf_editor_no_child_values` | editor, WP-25 | empty states on both pages (the project page no longer uses the generic `text_no_values` for the editor) |
| `text_dcf_storage_usage` | limits, WP-11 | server line, unchanged |
| `text_dcf_storage_estimate` | added by WP-24, text designed by the limits area | the only client estimate key (compat section 2.4 "Storage threshold and client key"). `text_dcf_storage_near_limit` and `text_dcf_storage_estimate_over` not created |
| `text_dcf_no_matches` | editor key list; added by WP-28, or by WP-25 if it lands first | the later WP reuses it (gap 8) |
| fr `label_dcf_show_not_linked_anywhere`, fr `text_dcf_status_unlinked_children`, fr `label_dcf_unlinked_children_list`, fr `label_dcf_linked_count`, fr `text_dcf_editor_parent_changed`, nl `text_dcf_no_matches` | editor, WP-25 (WP-28 or WP-25 for `text_dcf_no_matches`) | UX-16 corrected texts (gap 9), only in the registry |
| `text_dcf_editor_pending_conflict`, `button_dcf_editor_pending_*`, `error_dcf_dependency_payload_too_large`, `text_dcf_orphan_entries`, `text_dcf_editor_requires_javascript` | project (dropped) | WP-27 adds none of them (gap 8); the editor conflict panel and submit-gate names are used on both pages (compat section 2.4 "Project conflict (409) and submit gate") |

Conventions enforced by G8:
- **Quotes per locale:** en and nl ASCII double quotes ("%{value}", escaped in YAML), de „%{value}“, fr « %{value} » (core fr style, `text_enumeration_destroy_question`). The editor's plain quotes in de/fr are converted: WP-25, WP-26 and WP-28 take the corrected registry texts (gap 9), so the WP-02 quote check passes.
- **Plurals:** a key whose text starts with `%{count}` or makes words agree with the count uses `one`/`other` subkeys (fr may add `zero`, like core `label_x_issues`); "Label: %{count}" phrasing needs no plural.
- **Glossary from the plugin's existing terms:** custom field = de "benutzerdefiniertes Feld", fr "champ personnalisé", nl "aangepast veld"; parent/child = de "übergeordnet"/"untergeordnet", fr "parent"/"enfant", nl "bovenliggend"/"onderliggend"; "(depending)" = "abhängig" / "dépendante" / "afhankelijk"; mapping = "Abhängigkeitszuordnung" / "mappage des dépendances" / "afhankelijkheidskoppeling"; "ask an administrator" = nl "Vraag een beheerder" (`nl.yml:48`). Core keys reused where they fit: `button_check_all`, `button_uncheck_all`, `label_search`, `label_no_change_option`, `label_none`, `field_default_value`, `button_clear`, `button_collapse_all`.
- **English-leftover allowlist** (reviewed, each entry commented; the full list lives in `large_lists_i18n_registry.md`): de `label_scope_global`, `label_dcf_position`, `text_dcf_live_message`; fr `label_scope_global`, `label_dcf_position`, `label_dcf_audit_action`, `label_dcf_import_mode` ("Mode"), `label_dcf_inactive` ("inactive"); nl `label_scope_project`, `label_dcf_tab_char` ("Tab"), `text_dcf_live_message`. Gap 10: WP-02 adds de and nl `text_dcf_live_message` (WP-18 adds the key with values identical to en) and pre-lists fr `label_dcf_inactive`, fr `label_dcf_import_mode` and nl `label_dcf_tab_char` (added by WP-25 and WP-26), so the parity spec stays green when those WPs land.
- **No en or em dash** characters in locale files, README.md and CHANGELOG.md (E27: README 14 and CHANGELOG 3 today, fixed in WP-02); added lines in docs/ and code are checked by the ratchet compat step.

## 3. Gates (G1..G12): concrete, measurable, evidence for PASS

Statuses are PASS, FAIL, NOT RUN or N/A. N/A needs a one-line justification from the applicability matrix (3.13). A WP is DONE only when every applicable gate is PASS. NOT RUN is never DONE.

Evidence rule: PASS is declared only from observed output. The report quotes the command, its exit code, the summary line and the log path, plus `plugin_worktree_sha` with `dirty=0`, `redmine_sha` and `ruby` from the `DCF SUMMARY` block. Evidence produced before the last code change is stale and must be rerun. "Should pass", "expected to pass" or "passes locally" without output do not count.

### G1 Correctness
- Every row of the WP's behaviour table maps to at least one automated test id: table `row id | before | after | test id(s)`.
- Defect rows show red-green (failing excerpt on the pre-fix commit, pass after). Mandatory for:
  - bulk edit `#bulk-edit-form` vs `bulk_edit_form` clearing untouched multi-select children (WP-03);
  - `delete_matched` raising on MemCacheStore (WP-03);
  - the admin save pruning inactive enumeration links (WP-22);
  - the `label_default_value` key missing (WP-02);
  - `GET /depending_custom_fields/options` shadowed by `:id` (WP-15);
  - the client cascade recursing on stored cycles (WP-17, WP-18);
  - an unchanged legacy child rejected on a notes-only save (D1, WP-09).
- Refactors (points 1-6) follow the characterization protocol (5.1); characterization specs pass unchanged on the refactor commit except the listed flips.
- Server invariants each have a spec: BaseService fails closed; audit in the same transaction; validation errors reach the API as 422 with an `errors` array; D1 per value (2.6) on form, bulk, REST, mail and wizard paths.
- Contract conformance: every row of 2.2, 2.3 and 2.4 has a generated fixture case and a consuming jsdom test; a contract change touches the owner's spec, the fixture and the consumer in the same commit.

### G2 Tests green
- `.codex/test_matrix.sh --setup --suite rspec` prints `version=<v> exit=0 ... N examples, 0 failures` for 5.1, 6.0, 6.1 and 7.0; N equal on all versions unless a version-specific example is documented. Reference: the measured baseline is `259 examples, 0 failures` on all four versions (section 1); the WP report states N before and after and explains the delta. `:mysql` and `:perf` specs are excluded by tag on PostgreSQL (limits 7.2).
- JS: `npm test` prints `# fail 0` and `# pass N`.
- System specs: `.codex/test_plugin.sh 5.1 --suite system` and `.codex/test_plugin.sh 7.0 --suite system` exit 0; mandatory for every WP that changes views, assets or JS behaviour.
- Random order: `config.order = :random`, the `Randomized with seed` line quoted. WPs touching specs broadly also run seeds 1, 4242, 31337 on 7.0.
- Fixture determinism (R13): the fixture specs run green under two seeds (`.codex/test_plugin.sh 7.0 --suite rspec -- spec/frontend --seed 1` and `--seed 4242`), and the in-suite sequence-bump self check passes (5.5).
- Hygiene: no `pending`/`skip`/`xit` without a linked reason; example-count delta explained; Rack status deprecation warnings at or below baseline (`grep -c 'Status code :unprocessable_entity is deprecated'` at most 11 on 6.x/7.0 logs); new specs use `have_http_status(422)`, new code `status: 422`.

### G3 Lint and style
- `.codex/rubocop_ratchet.sh` prints `SYNTAX PASS`, `COMPAT PASS`, `RATCHET PASS ...`, exit 0 (4.8). The syntax step rejects Ruby 3.x syntax: endless defs, anonymous argument or block forwarding, and hash shorthand (a keyword passed without a value, gap 15: the head hook must be written `tag.meta(name: META_NAME, content: payload.to_json)`, WP-18). Ratchet reference: 107 offenses in 38 files at the baseline (section 1).
- `npm run check` prints `ok   ES2017 <file>` for every `assets/javascripts/*.js`, exit 0.
- CSS: core 7.0 stylelint on plugin CSS (`--suite css`), exit 0.
- No inline script (from WP-18 on, 0.1.0 (M2)), checked two ways:
  - source: `git grep -nE 'javascript_tag|<script|content_tag\(:script|tag\.script' -- app lib` returns nothing (E25: the current script uses `javascript_tag`);
  - rendered: `spec/hooks/view_layouts_base_html_head_hook_spec.rb` and the fixture specs assert `Nokogiri::HTML.fragment(html).css('script:not([src])')` is empty for the hook output, the wizard partial, the editor partial and the format partials.
- Every new `html_safe` or `raw(` in the diff (`git diff -U0 <base> | grep -E '^\+.*(html_safe|raw\()'`) has a reviewer sign-off line.

### G4 UX and consistency
- System-spec screenshots (`tmp/capybara/dcf/<wp>/<name>-<v>.png`) for every changed screen on 5.1 (classic) and 7.0 (new UI): issue form, bulk edit, context menu wizard, admin custom field editor, project dependencies, project values page.
- Request specs render every new or changed page in `en` and one of de/fr/nl and assert neither `translation missing` nor `translation_missing` in the body.
- Core components only: `.box.tabular`, `.contextual`, core `pagination_links_full` / `per_page_links` / `per_page_options` (core-5.1/7.0 `lib/redmine/pagination.rb:143,217,231`), `flash[:notice]`/`flash[:error]`, labels bound to inputs.
- Icons (UX-10): new partials use `sprite_icon('warning', text)` when `respond_to?(:sprite_icon)`, else the classic `icon icon-warning` class; flash divs use `notice_icon` when available; JS-built notices prepend `createSVGIcon(...)` when `typeof createSVGIcon === 'function'` (6.1, 7.0), else rely on the class background (5.1, 6.0). The 5.1 and 7.0 screenshots must show the icon (core-7.0 `.icon-warning` styles only `svg.icon-svg`).
- Accessibility, accepted patterns (resolves R17/QA-13b/UX-06):
  - collapsible sections: native `details`/`summary` (editor), or buttons with `aria-expanded`;
  - issue-form hint: the C10 pattern (JS-generated `dcf-hint-<n>` id referenced by `aria-describedby`, existing tokens preserved, one debounced page-level polite live region, no per-hint `role=status`);
  - every new control reachable by Tab; search inputs labelled; Enter in editor filters never submits; errors use `role=alert`.
- Behaviour semantics against D1-D3 (D1 refined by UD-04 to UD-07, D2 as revised by UD-09 and UD-10): child never disabled; legacy value kept and marked; in bulk edit and the wizard '(No change)' stays available on descendants and the per-parent default is preselected with a hint; `hide_when_disabled` hides the label too, never in bulk edit.
- Empty states and errors have i18n text; no horizontal scroll at 1024 px (screenshot).
- Mode-specific controls: jsdom asserts that "Add missing child values" is not rendered on the project editor fixture nor for enumeration children (gap 12, WP-26).

### G5 Security
- Permission matrix request specs for every new or changed action: anonymous, non-member, member without the permission, member with `manage_project_custom_field_configuration`, admin; projects active, closed (writes refused by `require_active_project`), archived. Explicitly:
  - `PATCH .../values/sort`: anonymous redirect/401, non-member 403, no permission 403, closed project 403, manager and admin 200/302;
  - `GET /dcf_dependency_editor/values`: anonymous XHR 401, non-admin 403, admin 200; `/dcf_dependency_editor/values.json` with a session cookie is not session-authenticated (API request);
  - admin JSON API stays admin-only (non-admin 403), contract unchanged;
  - wizard `POST /depending_custom_fields/save`: still requires login, issue visibility and editability (pinning spec, SP-07; the write-scope fix itself is SD-01, UD-03).
- Strong params: no `permit!`; every new `CustomField.safe_attributes` entry listed in the review. BC-04 (gap 12, WP-22): a spec asserts `CustomField.safe_attribute_names` includes `value_dependencies`, `default_value_dependencies` and `dependencies_json`.
- Payload input (SP-01, SP-02, SP-20b): for the admin path (validation error) and the project path (audited 422), never a 500:
  - a 1,000,000-digit integer, a 20-digit integer and a negative integer are rejected without `JSON.parse` being called (spy `expect(JSON).not_to receive(:parse)`), plus a loose smoke bound of 1 s (the vulnerable path took 5.7 s);
  - floats, booleans, `null`, unknown top-level keys, non-object, nesting deeper than 3, more than 4 MiB are rejected with their specific error;
  - an unauthorized `PATCH update_dependencies` with a malformed or 1M-digit payload gives 403 with an `authorization_failed` audit row and `DependencyPayload.parse` is never called (SP-20b, gap 12, WP-27);
  - `batch_scope=page` with a foreign enumeration id gives 422 and nothing changes (SP-20c).
- CSRF: forms carry `authenticity_token`; `fetch` posts send `X-CSRF-Token`; asserted with forgery protection switched on (as T-ORD-12).
- Same origin (SP-15): `context_menu_wizard.js` resolves the form `action` against `location` and refuses a cross-origin action (jsdom, WP-18); the editor checks that `data-dcf-editor-values-url` is same-origin before fetching it, and a cross-origin URL gives no fetch and the `load_failed` notice (jsdom, WP-25, gap 12).
- XSS:
  - values `"><script>alert(1)</script>`, `</script>`, `[`, `]`, `&` and non-ASCII round-trip through data attributes and the editor (Ruby: escaped attribute and decoded round trip; jsdom: `textContent`/`value` only, never `innerHTML`);
  - flash interpolation (SP-06): a field named `<img src=x onerror=alert(1)>` that triggers the size error renders the escaped name in the 422 body; `git grep -n 'flash' app/controllers` additions with `l(` interpolations go through `translate_error(error_or_key)`, called as `translate_error(e)` with an `OperationError` (S4, gap 4).
- Audit hygiene: append-only and fail-closed specs stay green; a `ValueTooLong` audit row's `error_message` contains no SQL and no value (SP-09).
- The `security-review` skill (or an equivalent independent pass) runs on the WP diff; findings are triaged in the review report.

### G6 Performance (counts and bytes; wall clock only for pure computations with 10x headroom)

Style rule (R16, QA-25): no absolute query counts anywhere. Two allowed forms, both using `dcf_count_queries { }`:
- **invariance:** the same count for a small and a large input;
- **differential:** plugin overhead = count with the plugin code path minus count with it stubbed out (for example `ClientData.attributes_for` stubbed to `{}`), compared with an exact expected overhead.

The server's `plugin-added SQL queries <= 1`, project T-PAG-9 "bounded number" and limits `m_usage_queries 2 per page` are rewritten in these forms. Existing `<= 7` / `== 1` assertions are rewritten when their code is touched.

Required checks:
- **Issue new/edit** (parents resolved from `customized.available_custom_fields` first, `find_by` only for parents not available on the record; E22):
  - 1 child vs 5 children of one parent: same count;
  - 1 child of 1 parent vs 5 children of 5 DISTINCT parents, all available, one role-restricted, non-admin member: same count;
  - differential overhead 0 when all parents are available; equal to the number of distinct unavailable parents otherwise.
- **Bulk edit:** the same three checks, parents resolved from the selected issues' available fields.
- **YAML (SP-20d):** spying on `ActiveRecord::Store::IndifferentCoder#load` (E22) during an issue edit render with 3 depending fields, the plugin adds 0 `format_store` deserializations (differential), and each distinct `format_store` payload is deserialized at most once per request.
- **Context menu:** same count for 1 and 10 selected issues and for 5 and 25 custom fields in the system (no global scan, D4; WP-15). The inline wizard template stays within the 512 KB S1 budget asserted by spec (UD-13, WP-18).
- **Values page:** same count for 25 and 500 values at the same `per_page`, with and without `show_usage`; `ValueCollation.key` is computed at most once per row and once for `q` per request (spy count); a `:perf`-tagged opt-in spec (`DCF_PERF_SPECS=1`) checks search over 25,000 enumerations under 1 s.
- **Parsing (SP-17):** `DependencyPayload.parse` is called exactly once per request on the admin path (repeated `valid?` included) and on the project path (422 re-render included).
- **Payload budgets** with generator scenarios S1/S2 (5.7): the WP reports measured bytes of the issue-form attributes and of the editor JSON; specs assert the WP's declared budget; the mapping travels as 1 form param (`request.request_parameters` far below 4,096).
- **JS:** rules filter on 25,000 options with 5,000 allowed under 100 ms (measured about 3.6 ms); editor model plan + apply + serialize for 27 x 5,570 under 500 ms (measured 54 ms); lazy rendering keeps the initial DOM row count at most the section page size (jsdom count).

### G7 Backward compatibility and upgrade
- API contract snapshots: JSON key sets for list, enumeration, depending_list, depending_enumeration and extended_user unchanged; status codes unchanged except the documented 422 on cycles (D9) and on oversize (limits).
- Stored data shape unchanged: `format_store` keeps `parent_custom_field_id`, `value_dependencies`, `default_value_dependencies`, `hide_when_disabled`. Upgrade spec: 0.0.15-shaped raw YAML written with `update_column`, then load, render, save: no data loss, inactive enumerations kept (D6).
- No pruning outside the admin JSON transport (BC-02, S7):
  - `PUT /depending_custom_fields/:id.json` changing only the name leaves `value_dependencies` byte-identical, orphan and bracket-corrupted keys included;
  - an extended-API-style `safe_attributes=` save (E28) does not prune;
  - a project rename cascade `child.save!` keeps unrelated keys.
- Legacy nested params accepted (project: deprecated in 0.1.0, accepted throughout 0.1.x, removable no earlier than 0.2.0; admin `value_dependencies`/`default_value_dependencies` safe attributes: permanently, because other plugins write through `safe_attributes=`, E28, UD-15).
- `window.DependingCustomFields.setup(root)` and `requestSetup(root)` exist as deprecated aliases of `init(root)` (jsdom; deprecated in 0.1.0, kept at least throughout 0.1.x, removable no earlier than 0.2.0); `CustomFieldVisibility` likewise (deprecated in 0.1.0 by WP-15).
- No migration alters core tables (`git diff <base> -- db/` reviewed); plugin migrations reversible (`rake redmine:plugins:migrate NAME=redmine_depending_custom_fields VERSION=<prev>`, then up, exit 0).

### G8 I18n
`spec/quality/locale_parity_spec.rb` passes on all versions. It checks:
- same flattened key paths in de/en/fr/nl (nested `activerecord.errors.messages.*` included; plural subkeys must contain `one` and `other` in every locale, `zero` allowed);
- **no duplicate mapping key at any depth inside one file**, using a `Psych.parse_stream` tree walk (E24), never `YAML.load`;
- same `%{}` variables per key;
- no blank values; no English leftovers outside the reviewed allowlist (2.7 and the registry; gap 10 entries included);
- every key used in `app lib config init.rb` exists in `en` (plugin or core), where "used" covers `l()`/`t()`/`I18n.t` calls AND symbol literals with a locale prefix (`:label_*`, `:text_*`, `:field_*`, `:error_*`, `:warning_*`, `:button_*`, `:notice_*`) AND `dcf_*` error symbols (looked up under `activerecord.errors.messages`);
- every value of every I18N constant map resolves in all four locales with `raise: true`: the spec iterates `RedmineDependingCustomFields::ClientConfig::I18N` (meta tag) and `DependencyEditorConfig::I18N` (editor), each only when the constant is defined, so the WP-02 spec is green before WP-18 and WP-24 exist (gap 5). WP-18 and WP-24 each add an example proving their map is checked (for example, with the map stubbed to contain an entry pointing to a missing key, the parity check fails). The name `I18N_KEYS` is not used anywhere;
- quote convention per locale and no en/em dash characters (2.7);
- the head hook meta tag renders valid JSON with the 10 keys of `ClientConfig::I18N` in each of the 4 locales (head fixtures, WP-18).

The WP report includes a `key | owner | en | de | fr | nl` table for every new or changed key, whose texts must equal `large_lists_i18n_registry.md` (a difference is resolved by updating the registry first, with reviewer sign-off), and a native-speaker review line for de, fr and nl (reviewer name or "machine-checked only" marked as open).

### G9 Docs, CHANGELOG, version
- `CHANGELOG.md` `## Unreleased` with Added / Changed / Fixed / Security / Deprecated / Removed / Upgrade notes. G9 PASS requires every upgrade-notes register entry (section 9) that the WP touches to have its line; each release WP (WP-07, WP-14, WP-20, WP-32) checks every entry of its release against the canonical CHANGELOG lines of `large_lists_work_packages.md` section 3.
- README updated (Compatibility 5.1-7.0 written with a plain hyphen, Development with `.codex` and `npm`, MySQL rake tasks, integration notes for `data-dcf-state` and `dcf:updated`).
- `docs/specs/project_custom_field_configuration_test_plan.md` section 8 amended: system specs exist, opt-in, never required by the default suite.
- Version targets stated in the CHANGELOG (UD-01): two releases (UD-01 resolved): 0.0.16 (WP-01..WP-03, WP-07), 0.1.0 (M1) (WP-04..WP-06, WP-08..WP-14), 0.1.0 (M2) (WP-15..WP-20), 0.1.0 (M3) (WP-21..WP-32). JS shims and `CustomFieldVisibility` deprecated in 0.1.0, removable no earlier than 0.2.0; project nested params deprecated in 0.1.0, removable no earlier than 0.2.0; admin nested safe attributes stay permanently (UD-15). The version bump happens only in the release WPs.

### G10 Version matrix
- One plugin SHA, four green rspec runs plus `SYNTAX PASS`; `requires_redmine version_or_higher: '5.0'` unchanged (UD-34; 5.0 declared but not tested, Ruby 2.7 or newer documented).
- A CI run counts only if its `headSha` equals the WP SHA (section 10).

### G11 CI policy and tooling hygiene
- `spec/quality/ci_workflows_spec.rb` (WP-01): every workflow has exactly `workflow_dispatch` as trigger; every workflow declares `permissions: contents: read`; no secrets. CI never gets automatic triggers.
- Dispatch policy (UD-32, resolved by the owner; section 10): Claude may deliberately dispatch the manual workflows only after the local gates pass, at most once per workflow per SHA unless a fix was pushed, never editing triggers. Every dispatch is listed in the QA report with workflow, SHA, run URL and result; an unreported dispatch, a retry loop or a trigger edit is a G11 FAIL. A run counts as G10 evidence only when its `headSha` equals the WP HEAD.
- `node_modules/` and `coverage/` git-ignored; `package-lock.json` committed; plugin `Gemfile` unchanged (it is eval'd into every Redmine bundle: core `Gemfile` `eval_gemfile` 5.1:132, 6.0:128, 6.1:135, 7.0:133).

### G12 Data integrity and storage limits
- DB-agnostic size specs (PostgreSQL CI, `StorageLimits.column_limit(column, model = CustomField)` stubbed to `bytes` and `bytes - 1`) for `possible_values` and `format_store`; preview bytes equal stored bytes (string parent id, invalid parent, blank keys, JSON transport); generator S1 yields `dcf_storage_too_large`, never a 500, never truncation.
- Service mapping: `error_dcf_values_too_large` / `error_dcf_mapping_too_large` with escaped `%{field}`; `ValueTooLong` maps to `error_dcf_value_too_long` with a sanitized audit row.
- Audit: values above 16,384 bytes are stored with the `payload_truncated` / `payload_bytes` / `payload_sha256` marker (WP-12); the project delta's own `truncated` and `mapping_sha256` keep their meaning (WP-27).
- Rake tasks: default dry run; `CONFIRM=1` required to alter; specs assert no `ALTER` without it; nothing alters core tables automatically.
- Data-loss regressions: bulk edit leaves untouched multi-select children intact (WP-03, WP-19); a notes-only save keeps a stored legacy value (D1 per value, WP-09); a bulk update of an unrelated attribute on issues holding legacy combinations succeeds (WP-09, gap 12); an admin save keeps inactive enumeration links (D6, WP-22); unrelated saves never prune (S7).
- Bulk edge cases (QA-14, gap 12, WP-19, issues and time entries): partial failure with parent "(no change)" and a child allowed under only some issues' parents (those issues save, the others are listed in the flash); a mixed-tracker selection where the parent is not common to all selected issues; the parent `__none__` cascade through `parse_params_for_bulk_update`.
- Optional MariaDB run (UD-27; local recipe `.codex/test_setup.sh --db mysql` or the optional manual MariaDB workflow of WP-13): green and quoted.
- Project pages (WP-31, gap 12): request spec for the plugin settings page, `project_storage_ceiling_kib` renders in en and de and a non-numeric POST falls back to 2,048 KiB.

### 3.13 Applicability matrix (final WP ids)

Revision 2 grouped the work into WP0 to WP8; the rows below use the final WP-01 to WP-32 (mapping in the consolidation table). "Heavy gates" need the most evidence; every other gate still needs PASS or a one-line N/A justification. G10 (one SHA green on 5.1, 6.0, 6.1, 7.0 plus the syntax gate) and G11 apply to every WP.

| WP | Release | Scope | Heavy gates | Usually N/A |
|---|---|---|---|---|
| WP-01 | 0.0.16 | Tooling: `.codex` scripts, ratchet and syntax gate, JS toolchain, manual workflows (D10, UD-29, UD-30, UD-31) | G2 G3 G10 G11 | G4 G5 G6 G12 |
| WP-02 | 0.0.16 | Test hygiene, generator, query counters, locale parity and no-dash specs, README/CHANGELOG dash cleanup, `field_default_value` fix | G2 G3 G8 G9 G10 G11 | G4 G6 G12 |
| WP-03 | 0.0.16 | Hotfixes: MemCacheStore save crash, bulk-edit data loss (UD-02) | G1 (red-green) G2 (system) G12 | G6 G8 |
| WP-04 | 0.1.0 (M1) | Characterization specs (Ruby + jsdom legacy), DB-backed rewrite of `custom_field_required_validation_spec.rb` | G1 G2 G10 | G4 G5 G6 G12 |
| WP-05, WP-06 | 0.1.0 (M1) | Point 6 rules module (`DependencyRules`, `parent_of`, `value_options`), `FieldIndex`, shared format module, dead code removed | G1 G2 G6 G7 G10 | G4 G8 |
| WP-07 | 0.0.16 | Release 0.0.16 | G9 G10 G11 + rerun all | |
| WP-08, WP-09, WP-10 | 0.1.0 (M1) | Enumeration options fix, D1 per value incl. copies and non-editable children, effective parent and server cycle validation (point 5 server) | G1 G2 G5 G7 G8 G10 G12 | G4 (except WP-10 cycle warning) |
| WP-11, WP-12, WP-13 | 0.1.0 (M1) | MySQL 64 KB safety, service error mapping, flash escaping, audit cap, rake tasks | G1 G5 G7 G8 G9 G12 | G4 (except the usage line, UD-28) |
| WP-14 | 0.1.0 (M1) | Release 0.1.0 (M1) | G9 G10 G11 + rerun all | |
| WP-15, WP-16 | 0.1.0 (M2) | Point 1 server side: context menu without cache, wizard route, per-field data contract, generated markup fixtures | G1 G3 G5 G6 G7 G10 | G12 |
| WP-17, WP-18, WP-19 | 0.1.0 (M2) | Points 1 to 5 client runtime, switch-over (meta tag, cache removal, globals removed), radio sentinel and required '(none)' | G1 G2 (system) G3 G4 G5 G6 G7 G8 | G12 |
| WP-20 | 0.1.0 (M2) | Release 0.1.0 (M2) (not before SD-01 is merged) | G9 G10 G11 + rerun all | |
| WP-21 to WP-26 | 0.1.0 (M3) | Points 7 and 8: payload parser, admin JSON transport, editor model, values endpoint and presenter, admin editor UI, CSV import and export | all | |
| WP-27 to WP-31 | 0.1.0 (M3) | Point 9 project pages and the project storage ceiling | all | |
| WP-32 | 0.1.0 (M3) | Release 0.1.0 (M3) (version, README, CHANGELOG register, full matrix, optional CI dispatch per section 10) | G9 G10 G11 + rerun all | |

## 4. Local commands and the `.codex` scripts

### 4.1 Proven toolchain (this container)
- Ruby via rbenv (`/opt/rbenv`): 3.2.6 for 5.1 (core `ruby '>= 2.7.0', '< 3.3.0'`), 3.3.6 for 6.0, 6.1, 7.0. CI pins 3.2.5 / 3.3.9 / 3.4.5; the summary block records the Ruby used.
- PostgreSQL 16 on localhost:5432, role `redmine`/`redmine` with CREATEDB (CI credentials).
- `libpq-dev` (pg_config) for the pg gem on 5.1 and 6.x; always `apt-get update` first (E21).
- Node 22.22.0 + npm 10.9.4 (`/opt/node22/bin`). jsdom stays `~29.1.1` (30.x needs Node ^22.22.2). That PATH also contains a chromedriver 147 that breaks Selenium (E8); `test_plugin.sh --suite system` strips it.
- Network to github.com, rubygems.org, registry.npmjs.org; Selenium Manager downloads Chrome for Testing + driver on first use (`~/.cache/selenium`).
- The only one-time step needing the owner's consent (UD-33): `sudo -u postgres psql -c "CREATE ROLE redmine LOGIN PASSWORD 'redmine' CREATEDB;"`. The scripts never do it.

### 4.2 Everyday commands

```bash
export DCF_WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/redmine_depending_custom_fields"   # default, outside the repo
.codex/redmine_clone.sh 7.0          # shallow clone / refresh upstream 7.0-stable
.codex/test_setup.sh 7.0             # apt (if needed), database.yml, bundle, db reset, plugin migrate, npm ci
.codex/test_plugin.sh 7.0            # default suites: rspec js lint
.codex/test_plugin.sh 7.0 --suite system           # opt-in browser specs
.codex/test_plugin.sh 7.0 --suite rspec -- spec/frontend --seed 4242   # extra rspec args
.codex/test_plugin.sh 7.0 --write-fixtures         # regenerate test/js/fixtures in the REPO (5.5)
.codex/test_matrix.sh --setup --suite rspec --suite lint   # G2/G10: 4 versions + one lint run (about 2-4 min)
npm ci && npm run check && npm test   # JS only, no Redmine needed
```

Mapping to `$S/baseline/run_baseline.sh` and the CI steps: shallow clone of `<v>-stable` from `redmine/redmine`; plugin copied without `.git` (rsync); PostgreSQL `database.yml`; `bundle config build.pg --with-pg-config=...`; `bundle install`; `rake db:drop db:create db:migrate`; `rake redmine:plugins:migrate`; `bundle exec rspec plugins/redmine_depending_custom_fields/spec --format progress`. Observed: clone 1.5 s, setup about 23 s with preinstalled gems, rspec about 30 s per version, rspec matrix 2 min 8 s.

### 4.3 Shared conventions (`.codex/lib/common.sh`)
- Exit codes:

  | Code | Meaning |
  |---|---|
  | 0 | ok |
  | 1 | checks or tests failed |
  | 2 | usage |
  | 3 | unmanaged target dir |
  | 4 | system dependency missing |
  | 5 | database unreachable |
  | 6 | setup missing or tool error |
  | 10 | clone/fetch failed |
  | 11 | bundle install failed |
  | 12 | db setup failed |
  | 13 | plugin migration failed |

- `DCF_PLUGIN_DIR` = repo root from the script location; `DCF_SCRIPT_DIR` absolute (a relative `$(dirname "$0")` broke after `cd`, found while testing).
- `DCF_WORK_DIR` outside the repo.
- Versions: only 5.1, 6.0, 6.1, 7.0 (with or without `-stable`) unless `DCF_ALLOW_ANY_BRANCH=1`; an existing checkout's version is read from `lib/redmine/version.rb`.
- Ruby always re-selected per version (`unset RBENV_VERSION` first; an inherited value ran the 7.0 lint under 3.2.6, found while testing); `DCF_RUBY_VERSION` pins.
- `dcf_sync_plugin`: `rsync -a --delete` of the working tree into `<redmine>/plugins/redmine_depending_custom_fields/`, excluding `.git/ node_modules/ coverage/ tmp/ log/`.
- `DCF_JS_FIXTURE_DIR`: set by `--write-fixtures` to `$DCF_PLUGIN_DIR/test/js/fixtures`, so regenerated fixtures land in the repo, not in the rsynced copy that the next sync would overwrite.
- `$DCF_WORK_DIR/current` remembers the last version.

### 4.4 `.codex/redmine_clone.sh <5.1|6.0|6.1|7.0>[-stable] [--repo URL] [--force]`
Default repo `https://github.com/redmine/redmine.git` (`DCF_REDMINE_REPO` or `--repo` override). Target `$DCF_WORK_DIR/redmine-<v>`. A checkout with the marker `.dcf-managed` is refreshed (`git fetch --depth 1 origin <branch>` + `git reset --hard FETCH_HEAD`); an unmarked existing dir is never touched (exit 3) unless `--force`. Prints `REDMINE_DIR=` and `REDMINE_COMMIT=<sha> <subject>`. Verified: clone, rerun, `4.2` exit 2, unmanaged exit 3.

### 4.5 `.codex/test_setup.sh [<v>] [--keep-db] [--no-apt] [--no-js] [--db postgresql|mysql]`
1. Clones if needed.
2. Missing `pg_config`: `apt-get update && apt-get install -y build-essential libpq-dev` (sudo when not root), else exit 4.
3. `pg_isready` and a `psql ... -c 'select 1'` login check (exit 5 with a hint); never creates roles or starts services.
4. Syncs the plugin; writes `config/database.yml` (DB `dcf_test_<v without dot>`; `DCF_DB_*` overrides).
5. Selects Ruby, configures `build.pg`, `bundle install --jobs 4` (exit 11).
6. `rake db:drop db:create db:migrate` (or without drop under `--keep-db`, exit 12), then `rake redmine:plugins:migrate` (exit 13).
7. `npm ci` in the repo when `package-lock.json` exists.
8. Writes `<redmine>/.dcf-setup-ok` (`plugin_sha`, `redmine_sha`, `ruby`, `db`, `at`).

`--db mysql` (designed, not prototyped here; the limits area verified the recipe): adapter `mysql2`, `utf8mb4`, `variables: transaction_isolation: READ-COMMITTED` (MariaDB 10.x: `tx_isolation`), `rm -f db/schema.rb` before migrating on 7.0, `libmariadb-dev`. Note: explicit fixture ids (5.5) bump InnoDB AUTO_INCREMENT past the fixed range even after rollback; harmless for this suite.

### 4.6 `.codex/test_plugin.sh [<v>] [--suite rspec|system|js|lint|css|all]... [--write-fixtures] [-- <rspec args>]`
- Re-syncs, runs `rake redmine:plugins:migrate`, runs the suites. Default `rspec js lint`; `all` = `rspec system js lint css`.
- `rspec`: `env -u DCF_SYSTEM_SPECS bundle exec rspec plugins/<name>/spec --format progress`.
- `system`: strips every PATH entry containing a `chromedriver`, then `DCF_SYSTEM_SPECS=1 bundle exec rspec plugins/<name>/spec/system --format documentation`.
- `js`: `npm ci` if `node_modules` is missing, then `npm run -s check && npm test`.
- `lint`: `.codex/rubocop_ratchet.sh --redmine <7.0 checkout>`.
- `css`: core stylelint in the 7.0 checkout.
- `--write-fixtures`: runs `spec/frontend` with `DCF_WRITE_JS_FIXTURES=1 DCF_JS_FIXTURE_DIR=$DCF_PLUGIN_DIR/test/js/fixtures`, then `DCF_WRITE_JS_FIXTURES=1 node --test test/js/payload_golden.test.js` (in the repo) for the payload goldens; prints `git status --short test/js/fixtures`.
- Output tee'd to `$DCF_WORK_DIR/logs/<v>-<suite>-<timestamp>.log`. Final block:

  ```
  === DCF SUMMARY (Redmine <v>) ===
  plugin_sha=... redmine_sha=... ruby=... db=... at=...
  plugin_worktree_sha=<sha> dirty=<n>
  suite=rspec exit=0 267 examples, 0 failures  log=...
  ```

- Exit 0 only when every requested suite exited 0; exit 6 when setup is missing.

### 4.7 `.codex/test_matrix.sh [--versions "5.1 6.0 6.1 7.0"] [--setup] [--suite ...]`
Runs `test_plugin.sh` per version; lint once (pinned to the 7.0 RuboCop ~> 1.88). Prints `=== DCF MATRIX ===`. Verified:

```
version=5.1 exit=0 suite=rspec exit=0 267 examples, 0 failures
version=6.0 exit=0 suite=rspec exit=0 267 examples, 0 failures
version=6.1 exit=0 suite=rspec exit=0 267 examples, 0 failures
version=7.0 exit=0 suite=rspec exit=0 267 examples, 0 failures
lint exit=0 SYNTAX PASS COMPAT PASS RATCHET PASS files=7 base_offenses=14 head_offenses=15 fixed=0
```

### 4.8 `.codex/rubocop_ratchet.sh [--base <ref>] [--redmine <dir>]` + `.codex/lib/rubocop_ratchet.rb`
- Base: `git merge-base HEAD ${DCF_BASE_REF:-origin/main}`, extracted with `git archive`. Head = working tree (uncommitted included).
- Config: the committed plugin `.rubocop.yml` with `inherit_from` rewritten to `<redmine 7.0>/.rubocop.yml`, the same for base and head; a WP editing `.rubocop.yml` needs explicit reviewer approval.
- Step 1, Ruby 2.7 syntax: `rubocop --only Lint/Syntax` on all tracked and untracked `*.rb`, `*.rake`, `Gemfile`; must be 0. It catches endless defs (E6), anonymous forwarding and Ruby 3.1 hash shorthand (a keyword passed without a value), for example in the head hook's meta call, which WP-18 must write as `tag.meta(name: META_NAME, content: payload.to_json)` (gap 15).
- Step 2, compat grep on lines ADDED since base in `app lib config db init.rb spec assets test docs README.md CHANGELOG.md`:
  - Ruby/Rails runtime hazards (`app lib config db init.rb spec` only): `\.intersect\?\(`, `Data\.define`, `params\.expect\(`, `:unprocessable_content`, `in_order_of`, `normalizes`, `Rails\.configuration\.to_prepare`, `delete_matched`, `javascript_tag`;
  - every listed path: the en dash and em dash characters (U+2013, U+2014).
  A justified false positive carries the trailing marker `# dcf-compat-ok` (or `<!-- dcf-compat-ok -->` in Markdown).
- Step 3, ratchet: for changed files (`git diff --name-only --diff-filter=ACMR <base>` plus untracked), per (file, cop) head count at most base count; new files clean. A base file with `Lint/Syntax` offenses gets `INFO <file>: base not parseable under Ruby 2.7, baseline reset`. Output `NEW <file>:<line> <cop> <message> (base n, head m)` and `RATCHET PASS|FAIL files= base_offenses= head_offenses= fixed= [new=]`.
- RuboCop exit >= 2 gives exit 6; empty JSON is never parsed.
- Known trade-off: a count ratchet can miss an offense swap within one file and cop; the reviewer reads the diff.

Plugin `.rubocop.yml` (verified, E4/E5):

```yaml
# RuboCop overlay for .codex/rubocop_ratchet.sh. Only meaningful inside a Redmine
# checkout (plugins/redmine_depending_custom_fields) because it inherits core's
# configuration; core's own RuboCop run never reads it (core excludes plugins/**).
inherit_from: ../../.rubocop.yml

AllCops:
  # init.rb declares requires_redmine 5.0: stay Ruby 2.7 / Rails 6.1 compatible.
  TargetRubyVersion: 2.7
  TargetRailsVersion: 6.1
  Exclude:
    - '**/node_modules/**/*'
    - '**/vendor/**/*'
    - '**/tmp/**/*'
    - '**/coverage/**/*'

# :unprocessable_content raises ArgumentError on Rack 2.2 (Redmine 5.1). Use 422.
Rails/HttpStatusNameConsistency:
  Enabled: false
```

Baseline reference (informational, not an allowlist): 107 offenses in 38 files (39 inspected) with the raw core 7.0 config and `plugins/**` un-excluded, the measured baseline of section 1 / 96 with the overlay on app, lib, config, db, init; 171 on all 76 Ruby files.

### 4.9 Repo files added or changed by WP-01 and WP-02 (tooling and test hygiene; revision 2 called this WP0)

| File | Change |
|---|---|
| `.codex/lib/common.sh`, `.codex/redmine_clone.sh`, `.codex/test_setup.sh`, `.codex/test_plugin.sh`, `.codex/test_matrix.sh`, `.codex/rubocop_ratchet.sh`, `.codex/lib/rubocop_ratchet.rb` | WP-01. NEW, executable (prototypes in `$S/design/qa/plugin/.codex`) |
| `.rubocop.yml` | WP-01. NEW overlay (UD-29) |
| `package.json`, `package-lock.json`, `.gitignore` | WP-01. NEW (5.8, UD-30) |
| `test/js/support/check_assets.js` | WP-01. NEW (ES2017 gate) |
| `test/js/support/large_list.js`, `test/js/large_list_parity.test.js` | WP-02. NEW (JS twin of the generator, E17) |
| `spec/rails_helper.rb` | WP-02. `config.order = :random` + `Kernel.srand config.seed`; system opt-in (`require_relative 'support/system_driver'` when `DCF_SYSTEM_SPECS=1`, else `filter_run_excluding type: :system`); `filter_run_excluding :mysql unless Redmine::Database.mysql?`; `filter_run_excluding :perf unless ENV['DCF_PERF_SPECS'] == '1'`; `config.after { I18n.locale = I18n.default_locale }`; delete `require File.expand_path('../init', __dir__)` (E12) |
| `spec/support/system_driver.rb` | WP-02. NEW: selenium headless chrome, `CHROME_BIN` only when set, `dcf_login` (`a.logout` visible: :all), `dcf_selectable_options(dom_id)` (DOM state, E9) |
| `spec/support/dcf_large_list.rb` | WP-02. NEW: the limits generator API with the naive-fold `sizes()` (5.7) |
| `spec/support/query_counter.rb` | WP-02. NEW `dcf_count_queries { }` and `dcf_count_yaml_loads { }` |
| `spec/support/dcf_js_fixtures.rb` | WP-16 (0.1.0 (M2)), owned by quality. NEW fixture infrastructure (5.5); it uses the fixed id ranges of `dcf_fixture_record` from WP-02 |
| `spec/support/dcf_config_helpers.rb` | WP-02. `dcf_tracker`/`dcf_status` always creating dedicated records; `dcf_fixture_record(klass, n, attrs)` with fixed id ranges |
| `spec/quality/ci_workflows_spec.rb`, `spec/quality/rubocop_ratchet_spec.rb` (+ JSON fixtures in `spec/quality/fixtures/`) | WP-01. NEW |
| `spec/quality/locale_parity_spec.rb`, `spec/quality/dcf_large_list_spec.rb`, `spec/quality/no_dash_spec.rb`, `spec/system/smoke_spec.rb` | WP-02. NEW (the parity spec iterates `ClientConfig::I18N` and `DependencyEditorConfig::I18N` when defined and carries the gap 10 allowlist) |
| `spec/patches/custom_field_required_validation_spec.rb` | the 7 endless defs become normal defs (WP-01); DB-backed rewrite in WP-04 |
| `app/views/custom_fields/formats/_default_dependencies.html.erb:17` | WP-02. `l(:label_default_value)` becomes `l(:field_default_value)` (core key, parity stays at 74) |
| `README.md`, `CHANGELOG.md` | WP-02. en/em dashes replaced by commas, colons or plain hyphens (E27); Development and Compatibility sections |
| `test/spec/**`, `test/test_helper.rb` | WP-02. DELETE (never run, broken) |
| `.github/workflows/rspec-51.yml`, `rspec-60.yml`, `rspec-70.yml` | WP-01. `system_specs` input + steps, `permissions: contents: read`, rsync `--exclude node_modules/`, remove unused `nodejs` apt and `mkdir -p tmp/test-results`; `rspec-70.yml` also `lint` + `base_ref` inputs (5.9) |
| `.github/workflows/rspec-61.yml`, `.github/workflows/js-tests.yml` | WP-01. NEW, `workflow_dispatch` only (rspec-61 from upstream `redmine/redmine` 6.1-stable with Ruby 3.3.9, UD-31) |
| `docs/specs/project_custom_field_configuration_test_plan.md` section 8 | WP-02. amended (G9) |

Never add a non-table `*.yml` directly under `spec/fixtures/` (rails_helper loads every top-level `spec/fixtures/*.yml` as a DB fixture). Shared JSON tables live under `test/js/fixtures/shared/`.

## 5. Test strategy

### 5.1 Characterization first (points 1-6)
1. Before production changes, add tests pinning CURRENT behaviour:
   - Ruby, DB-backed, `spec/characterization/`: formats (`possible_values_options` for nil, a record and an Array; `query_filter_values`; `value_from_keyword` including import ordering with an unset parent; `validate_custom_value` with legacy combinations; `before_custom_field_save`); `ContextMenusControllerPatch` on the 5.x/6.x and 7.0 controller names; wizard options; routes (`options` shadowed by `:id`); admin nested-param save behaviour including its bugs; project `update_dependencies` with no params clearing the mapping;
   - JS: `test/js/legacy_characterization.test.js` loads the unmodified asset with `window.DependingCustomFieldData` (harness scenarios A0..U2).
2. Green on the base commit across the matrix; evidence in the WP-04 report.
3. Committed alone ("Characterize ..."), so a reviewer can check out and rerun.
4. Refactor commits change only listed flips (behaviour-table id each); `git diff <char-commit>..HEAD -- spec/characterization` shows only those.
5. Legacy-only characterization (JS legacy file, cache specs) is deleted in the rewrite commit with a note.
6. Mutation sanity: temporarily break each guard, record the failing spec name, revert. Guards: cycle validation; D1 per-value exemption; size validation; permission check; payload "absent = unchanged"; payload integer pre-scan; bulk "(no change)"; visibility gate on `data-dcf-parent-values`; flash escaping.

### 5.2 Ruby spec layers

| Layer | What | Location | DB |
|---|---|---|---|
| R0 pure | rules module, D1 per-value function over the shared case table, payload parser, collation key, size estimator, ratchet comparator, generator | `spec/lib`, `spec/quality` | no |
| R1 format/model | validation, cycles, D1, size validation, data attributes on real records; replaces brittle `instance_double(CustomField)` / exact `find_by` stubs | `spec/lib`, `spec/models`, `spec/patches` | yes |
| R2 service | BaseService subclasses: same-transaction audit, fail closed, `state_hash` 409, compact delta, sort, page-scoped batch, storage mapping, AuditPayload | `spec/services` | yes |
| R3 request | admin form through core `CustomFieldsController` (JSON absent/`{}`/malformed/oversize/S1 in 1 param/bracket keys/payload goldens), API snapshots + 422, project pages, issue pages, context menu (D4), wizard action under `relative_url_root`, permission matrix, locale render checks, flash escaping | `spec/requests`, `spec/routing` | yes |
| R4 contract fixtures | 5.5 | `spec/frontend` | yes |
| R5 system (opt-in) | 5.4 | `spec/system` | yes |
| Q quality | locale parity, CI manual-only, generator parity, no dashes, ratchet comparator | `spec/quality` | no |

Spec rules: English descriptions; `require_relative '../rails_helper'`; no top-level constants (use `let` or modules under `spec/support`); numeric `422`; `travel_to` for time; no `sleep` (Capybara waiting matchers in system specs); UI text asserted through `I18n.t`/`l`; query assertions only in invariance or differential form (G6).

### 5.3 Shared query and YAML counters (`spec/support/query_counter.rb`)
- `dcf_count_queries { }` subscribes to `sql.active_record` and ignores `SCHEMA`, `CACHE`, cached payloads and transaction/savepoint statements.
- `dcf_count_yaml_loads(pattern = /value_dependencies/) { }` wraps `ActiveRecord::Store::IndifferentCoder#load` with `and_call_original` and counts loads whose input matches (E22: the coder class on 5.1 and 7.0; WP-02 asserts the class on 6.0/6.1 too).
- `dcf_plugin_overhead(stub: -> { allow(RedmineDependingCustomFields::ClientData).to receive(:attributes).and_return({}) }) { |run| ... }` returns real minus stubbed counts for the differential form.
- The existing `ActiveRecord::QueryRecorder` fallback in rails_helper stays for old specs.

### 5.4 Opt-in system specs (D10)
- `DCF_SYSTEM_SPECS=1`; otherwise `filter_run_excluding type: :system`.
- Core's `capybara` + `selenium-webdriver`, `driven_by :selenium, using: :headless_chrome` with `--no-sandbox --disable-dev-shm-usage --disable-gpu`; no new gem.
- Option filtering asserted with `dcf_selectable_options` (E9); login with `dcf_login` (E10).
- Scenarios (about 5 s each, keep small):
  1. issue form: filter, hint shown and hidden with `aria-describedby` and the live region, legacy value kept and marked, hint CSS beats `em.info {display:block}`;
  2. bulk edit (D2 as revised by UD-09): a concrete parent keeps "(no change)" available on descendants and preselects the per-parent default with a hint; parent "(none)" or a value without links forces "(none)"; required child per UD-10 (the `data-dcf-required-none` option, WP-19); parent back to "(no change)" restores the children; untouched multi-select children not cleared;
  3. AJAX replacement (`updateIssueFrom`) re-initialises via the MutationObserver (gap 13: mutations of one observer callback are coalesced and added roots are initialised synchronously in that callback, no timer debounce; the jsdom twin asserts one `replaceIssueFormWith` insertion causes exactly one `init` per root, WP-17);
  4. context menu wizard save;
  5. admin editor with S1: lazy sections, search, check all shown, import preview, save round trip, form switched to multipart after init (UD-16), form-size and payload pre-check messages (P6);
  6. project editor: Save disabled before init, enabled after; untouched page leaves without a `beforeunload` prompt; after a failed save the editor starts dirty from `data-dcf-editor-mapping` with a blank hidden input (P2, gap 1);
  7. project values page: search, pagination, sort A-Z, page-scoped enumeration batch;
  8. drag-and-drop reorder at or below the threshold.
- Screenshots for G4 in `tmp/capybara/dcf/<wp>/`.

### 5.5 One fixture mechanism for every server-to-client contract (R1, R13, QA-01)
- **Generator specs:** `spec/frontend/markup_fixtures_spec.rb` (issue form, bulk, wizard), `spec/frontend/editor_fixtures_spec.rb` (admin and project editor), `spec/frontend/head_fixtures_spec.rb` (head hook per locale). All use `spec/support/dcf_js_fixtures.rb`: render through the real helpers (`custom_field_tag_with_label`, `custom_field_tag_for_bulk_edit`, the wizard and editor partials, the hook listener), normalize, then compare with `test/js/fixtures/<group>/<scenario>.html` or write it when `DCF_WRITE_JS_FIXTURES=1` (into `DCF_JS_FIXTURE_DIR`). A version-specific variant `<scenario>.redmine-<major.minor>.html` is used when present; jsdom runs every variant.
- **Deterministic ids:** every record a fixture scenario creates gets an explicit id from a fixed, disjoint range via `dcf_fixture_record`: CustomField 9_100_001+, CustomFieldEnumeration 9_200_001+, Issue 9_300_001+, Project 9_400_001+ (identifier `dcf-fixture-<n>`), User 9_500_001+, Role 9_600_001+, Tracker 9_700_001+, IssueStatus 9_800_001+. E23 shows these stay stable while sequences drift.
- **Normalizer:** removes `authenticity_token` values and the CSRF meta, replaces `state_hash` values with `{{STATE_HASH}}`, strips asset timestamps and digests, renders under `travel_to(Time.utc(2026, 1, 1))`. Then a guard parses the HTML (Nokogiri) and fails, naming the position, if any number in an id-bearing position is outside the fixed ranges: `[custom_field_values][N]`, `custom_field_values_N`, `cf_N`, `data-dcf-field`, `data-dcf-parent`, numbers in `data-dcf-map`/`data-dcf-defaults` of enumeration fields, `ids[]` values, `/issues/N`, `/custom_fields/N`, `/fields/N`, `data-dcf-editor-field-id`, `data-dcf-editor-parent-id`.
- **Sequence-bump self check:** one example renders every scenario inside a savepoint, rolls back, creates 37 throwaway rows of each kind, renders again and asserts identical normalized output.
- **Owners per generator spec:** `markup_fixtures_spec.rb` and `spec/support/dcf_js_fixtures.rb` are delivered by WP-16 (regenerated by WP-18 and WP-19), `head_fixtures_spec.rb` by WP-18, `editor_fixtures_spec.rb` by WP-24 (WP-25 and WP-27 add scenarios). WP-24 also writes `test/js/fixtures/value_options.json` from `DependencyEditorConfig.wire_values` and asserts endpoint == presenter == fixture (gap 3).
- **Consumers:** jsdom suites in `test/js/contract/*.test.js` load these files (head fixture first, then the assets in hook order: meta, the one UMD runtime, the wizard script) and assert the outcome per mandatory case (2.2). The editor jsdom tests load the editor fixtures.
- **Dropped parallel fixtures:** `spec/fixtures/dcf_client_contract.json`; any hand-written HTML fixture for a server-rendered contract. Hand-written case tables that are inputs, not renderings (`test/js/fixtures/shared/rules_cases.json`), are allowed: one file read by both Ruby and JS.

### 5.6 Payload golden files (R3, QA-02)
- `test/js/payload_golden.test.js` (WP-23) runs the real editor model `serialize()` for: list editor save, enumeration editor save (integer ids), clear (`{}` links), import merge, import replace (`source: "import"`, `import: {mode, rows}`), tricky values. It compares with `test/js/fixtures/payload/<name>.json` (or writes them with `DCF_WRITE_JS_FIXTURES=1`).
- `spec/requests/dependency_payload_contract_spec.rb` posts each golden file to the admin form (WP-23; expect save, `base` honoured, `source`/`import` ignored) and to the project page (half added by WP-27; expect save, `source=import` and `import.mode`/`rows` in the compact audit delta, `base` ignored). Either side drifting from the committed file fails.
- `spec/lib/dependency_payload_spec.rb` (WP-21) is the single parser spec for both entry points (schema, errors, limits, pre-scan, integer range, blank policy per entry point).

### 5.7 One deterministic large-list generator (R12, QA-16)
- Algorithm: the limits area's arithmetic generator (bijective base-60 syllable stems, one accent when `i % 3 == 0`, place prefixes, no PRNG), with the tricky-value injection (`yes`, `no`, `null`, `1.0`, `a: b`, `# hash`, `- dash`, `O'Brien`, `say "hi"`, `[x]`, `a]`, `semi;colon`, `comma, value`, a tab, `Ünïcødé ñ`, each suffixed with its index). `sizes()` sums weights with a naive left fold (`inject(0.0) { |acc, w| acc + w }`) for JS parity.
- Ruby `spec/support/dcf_large_list.rb` (WP-02; `DcfLargeList.name`, `names(count, ...)` with the keyword options `prefix`, `offset` and `tricky_every`, `sizes`, `partition`, `full`, `first_child_defaults`, `element_bytes`, `yaml_list_bytes`, `values_of_yaml_bytes(target)`, plus the DB builders `dcf_large_list_field!`, `dcf_large_enum_field!` with `insert_all`, `dcf_large_pair!`). JS twin `test/js/support/large_list.js` (`names`, `name`, `sizes`, `partition`, `TRICKY`); YAML byte targets are Ruby only.
- One Ruby spec `spec/quality/dcf_large_list_spec.rb` (the limits `spec/lib/dcf_large_list_spec.rb` and the earlier mulberry32 `large_list_parity_spec.rb` are not created) pins `names(5570, tricky_every: 97)` at SHA-256 prefix `233acf899217e962` and the partition hash `466b240daca61be9`; `test/js/large_list_parity.test.js` pins the same two hashes (E17).
- Scenarios shared by Ruby size, transport, rules, editor import/export round trip and jsdom tests:

  | Id | Shape |
  |---|---|
  | S1 | parents `names(27, prefix: 'P')` x children `names(5570, tricky_every: 97)`, partition with the IBGE sizes |
  | S1-full | every link |
  | S2 | S1 as an enumeration (integer ids) |
  | S3 | 25,000 values with 5,000 allowed (JS perf) |
  | S4 | a 5,000-value parent (MySQL TEXT overflow on the parent) |
  | SB | `values_of_yaml_bytes(65_535)` and `(65_536)` boundaries |

- Large-data specs are tagged `:large`, run by default (the whole suite must not grow by more than 20 %), `--tag ~large` skips them locally.

### 5.8 JS layer (`node --test` + jsdom)
- `package.json` (WP-01; devDependencies per UD-30): `private: true`, `license: "SEE LICENSE IN LICENSE"`, `engines.node ">=22.13"`, devDependencies `jsdom ~29.1.1`, `jquery 3.7.1` (core 6.1/7.0 version; serialize parity and jQuery-trigger tests), `acorn ~8.18.0` (ES2017 gate); scripts `check` (`node test/js/support/check_assets.js`), `test` (`node --test "test/js/**/*.test.js"`, quoted glob), `test:ci` (same with `--test-reporter=spec --test-reporter-destination=stdout`).
- Layers: J0 pure (rules, D1 case table, editor model, CSV parser, payload goldens, generator parity; perf budgets live here); J1 jsdom runtime on the generated markup fixtures; J2 editor DOM on the generated editor fixtures; J3 legacy characterization (deleted by the rewrite).
- Helpers in `test/js/support/`: `dom.js` (JSDOM, evaluates jQuery, rules and runtime in head-fixture order, resolves after `DOMContentLoaded`), `entries.js` (spec-compliant entry list; jsdom 29 `FormData` wrongly includes a selected disabled option), `fixtures.js`, `fire.js`, `large_list.js`.
- Known jsdom gaps covered by system specs: no `CSS.escape`, no CSS cascade for `[hidden]` vs `em.info`, about 0.4 ms per option attribute write. Debounce tests use `node:test` `mock.timers`.

### 5.9 Which manual workflow runs what

| Workflow (all `workflow_dispatch` only) | Runs | Inputs |
|---|---|---|
| `rspec-51.yml`, `rspec-60.yml`, `rspec-61.yml` (new), `rspec-70.yml` | whole `spec/` (R0-R4 + quality, fixtures in compare mode) on PostgreSQL 16; system specs only with the input, screenshots uploaded on failure | `system_specs` (boolean, default false) |
| `rspec-70.yml` extra | ratchet + Ruby 2.7 syntax + compat grep (`.codex/rubocop_ratchet.sh --redmine "$GITHUB_WORKSPACE/redmine" --base "${{ inputs.base_ref }}"`), checkout `fetch-depth: 0` | `lint` (boolean, default true), `base_ref` (default `origin/main`) |
| `js-tests.yml` (new) | `npm ci`, `npm run check`, `npm run test:ci`, then core stylelint on plugin CSS (shallow 7.0-stable clone, `yarn install`) | none |
| optional manual MariaDB workflow (`rspec-mysql.yml`; UD-27, WP-13) | whole `spec/` on MariaDB 10.11 (`:mysql` specs active) | `redmine_branch` (5.1-stable / 7.0-stable) |

Ruby in CI: 3.2.5 (5.1), 3.3.9 (6.0, 6.1), 3.4.5 (7.0). Clone source upstream `redmine/redmine` for 6.1 too (E20, UD-31). None of these workflows has an automatic trigger; Claude dispatches them only under the policy of section 10 (UD-32, resolved).

## 6. Improved owner prompt (paste-ready)

```text
QUALITY PROTOCOL: redmine_depending_custom_fields (repo-specific)

Roles (separate agents or sessions; reviewers never edit the code they review):
- Implementer: code + tests for exactly one work package (WP); commits in the order
  characterization -> refactor -> behaviour change -> docs.
- Independent Reviewer: reads only the WP definition + `git diff <base>..HEAD`; runs the
  checklist and the security-review skill; reports findings as file:line + severity.
- QA/Test Engineer: runs the commands, owns the gate evidence, performs the mutation checks.
- UX/Consistency Reviewer: screenshots on 5.1 and 7.0, keyboard/aria, i18n (native-speaker
  review for de/fr/nl), consistency with core Redmine components.

Targets: Redmine 5.1, 6.0, 6.1, 7.0. init.rb keeps requires_redmine 5.0, so code stays
Ruby 2.7 + Rails 6.1 compatible (no endless defs, no hash shorthand such as a key passed
without a value, no anonymous argument/block forwarding, no Data, no Array#intersect?, no
params.expect, no :unprocessable_content; use numeric 422). CI is manual-only
(workflow_dispatch) and must stay so. No en or em dash characters in code, locales, README,
CHANGELOG or docs additions.

Baseline (measured before any change): plugin specs 259 examples, 0 failures on Redmine
5.1 (Ruby 3.2.6), 6.0, 6.1 and 7.0 (Ruby 3.3.6), via a local replica of the CI steps with
PostgreSQL 16 and libpq-dev; RuboCop (core 7.0 config, plugins un-excluded): 107 offenses
in 38 files. Releases: 0.0.16 = WP-01..WP-03 and WP-07, 0.1.0 (M1) = WP-04..WP-06 and WP-08..WP-14, 0.1.0 (M2) = WP-15..WP-20,
0.1.0 (M3) = WP-21..WP-32.

Shared contracts: the canonical definitions in the plan's "canonical cross-area contracts"
section (issue-form attributes, head hook, payload schema and parser, editor DOM, value
options, storage and audit API, D1 per value, locale registry) are the only definitions;
large_lists_compatibility.md section 2.4 and section 3 are binding, and locale texts live
only in large_lists_i18n_registry.md. A WP that needs a different shape changes that
section first, then the owner spec, the generated fixture and every consumer in the same
commit.

Mandatory commands (repo root; logs in $DCF_WORK_DIR/logs):
  .codex/redmine_clone.sh <5.1|6.0|6.1|7.0>
  .codex/test_setup.sh <version>
  .codex/test_plugin.sh <version> [--suite rspec|system|js|lint|css|all] [--write-fixtures]
  .codex/test_matrix.sh --setup --suite rspec --suite lint      # all four versions
  .codex/test_plugin.sh 5.1 --suite system && .codex/test_plugin.sh 7.0 --suite system
  .codex/test_plugin.sh 7.0 --suite rspec -- spec/frontend --seed 1   (and --seed 4242)
  npm ci && npm run check && npm test
(`yarn` in the generic prompt maps to npm for the plugin and to core's stylelint via
 `--suite css`.)

Gates (each PASS needs the quoted command, exit code, summary line, log path,
plugin_worktree_sha with dirty=0, redmine_sha and ruby from the DCF SUMMARY block):
 G1 Correctness       behaviour rows -> tests; red-green for defects; characterization unchanged
                      except listed flips; contract rows -> generated fixture + jsdom consumer.
 G2 Tests green       4 x "N examples, 0 failures"; npm "# fail 0"; system specs on 5.1 + 7.0
                      when views/JS change; seed printed; fixture specs green under 2 seeds and
                      the sequence-bump self check; deprecation warnings <= 11 on 6.x/7.0.
 G3 Lint/Style        SYNTAX/COMPAT/RATCHET PASS; npm run check; stylelint; no inline script
                      (source grep incl. javascript_tag + rendered-HTML assertion); html_safe signed off.
 G4 UX                screenshots 5.1 + 7.0 incl. icons; no "translation missing"; core
                      components; details/summary or aria-expanded; hint via aria-describedby +
                      one live region; D1-D3 semantics; empty states.
 G5 Security          permission matrix per action incl. sort, values endpoint, wizard pin;
                      payload pre-scan/limits/strict schema, parse only after authorization;
                      CSRF; XSS incl. escaped flash interpolation; sanitized audit errors;
                      security-review triaged.
 G6 Performance       invariance or differential query counts only (parents from loaded objects;
                      5 distinct parents incl. role-restricted == 1 parent); 0 extra YAML loads;
                      parse once; collation keys once per row; byte budgets S1/S2; JS budgets.
 G7 Compatibility     API snapshots; format_store shape; upgrade spec; no pruning outside the
                      admin JSON transport; legacy params + JS shims; admin safe attributes kept.
 G8 I18n              parity incl. duplicate keys, plurals, constant maps (ClientConfig::I18N,
                      DependencyEditorConfig::I18N), used symbols, quotes, no dashes; texts equal
                      the registry; key table with owner; native-speaker review line.
 G9 Docs              CHANGELOG Unreleased incl. Security and Upgrade notes covering the
                      upgrade-notes register; README; docs/specs; version targets stated.
 G10 Matrix           one SHA green on 5.1/6.0/6.1/7.0 + Ruby 2.7 syntax gate.
 G11 CI/tooling       workflows manual-only (spec), read-only permissions, lockfile committed,
                      node_modules ignored, plugin Gemfile unchanged; every dispatch reported
                      (workflow, SHA, run URL, result).
 G12 Data/storage     size validation with i18n error, never truncation; audit cap marker;
                      rake tasks dry-run by default, CONFIRM=1; data-loss regressions covered.

Redmine checks: cite core sources as core-<version>:path:line from the redmine_clone.sh
checkouts (upstream redmine/redmine). Check permissions per action, strong params /
safe_attributes, N+1, i18n de/en/fr/nl, partial structure (explicit locals, no instance
variables read inside new partials), deterministic specs (random order, no sleep, no
Tracker.first, dedicated records, fixed fixture ids, mock.timers, the shared generator),
service objects under app/services/redmine_depending_custom_fields (BaseService, audit in the
same transaction, fail closed), alias_method for the settings tab patch, no
Rails.configuration.to_prepare, new CustomField callbacks only in the validation patch module.

Rules: PASS only from observed output in this session; stale evidence is rerun; NOT RUN is
never PASS. Never weaken or delete an assertion to get green without the reviewer's written
approval in the report. CI dispatch (UD-32, resolved by the owner): Claude may deliberately
dispatch the manual (workflow_dispatch-only) workflows after the local gates pass, at most
once per workflow per SHA unless a fix was pushed; never edit triggers; always report
workflow, SHA, run URL and result. CI never gets automatic triggers.

OUTPUT FORMAT per WP: 1 minimal context/commands, 2 plan, 3 code changes, 4 tests
added/updated, 5 independent review report, 6 QA report, 7 UX/consistency report,
8 gate checklist with PASS/FAIL and evidence, 9 next actions and exact diffs on FAIL.
```

## 7. Per-WP definition-of-done template (owner OUTPUT FORMAT)

Every WP-01 to WP-32 is DONE only with this report (the "Definition of done" line of each WP in `large_lists_work_packages.md` points here). The nine sections follow the owner OUTPUT FORMAT exactly, in this order: 1 minimal context/commands, 2 plan, 3 code changes, 4 tests added/updated, 5 independent review report, 6 QA report, 7 UX/consistency report, 8 gate checklist with PASS/FAIL and evidence, 9 next actions and exact diffs on FAIL. Sections 5, 6 and 7 are written by the reviewer roles of section 6, never by the implementer.

```markdown
# WP-<nn>: <title>   (release: 0.0.16 | 0.1.0 (M1) | 0.1.0 (M2) | 0.1.0 (M3), points: <..>, decisions: UD-<..> (default decisions D<..> where relevant), status: DONE | NOT DONE)

## 1. Minimal context and commands
- Base: origin/main @ <sha>; branch <name>; HEAD <sha>; dirty=0
- Redmine checkouts (from DCF SUMMARY): 5.1 <sha> ruby <v> | 6.0 <sha> | 6.1 <sha> | 7.0 <sha>
- Baseline reference: 259 examples, 0 failures on 5.1/6.0/6.1/7.0; RuboCop 107 offenses in 38 files (section 1)
- Core sources consulted: core-<ver>:<path>:<line> - <why>
- Canonical contracts touched (section 2 ids, e.g. 2.2 C2, 2.4 P3; compat section 2.4 or 3 row) and whether section 2 changed
- Commands run, verbatim and in order (with exit codes); nothing else (minimal context)

## 2. Plan
- Behaviour table rows in scope: | id | before | after | test id(s) |
- Characterization tests added first (refactor WPs): files + commit sha
- Upgrade-notes register entries touched (UN-xx, PC-xx) and CHANGELOG lines of the WP's release
- Locale keys owned by this WP (from large_lists_i18n_registry.md)
- Out of scope (with tracking reference, e.g. SD-xx)
- Applicable gates (matrix 3.13) and N/A justifications

## 3. Code changes
- Commits: <sha> Characterize ... | <sha> Refactor ... | <sha> Change ... | <sha> Docs ...
- Per file: what and why (one line each)
- New i18n keys: | key | owner WP | interpolations | en | de | fr | nl | (texts identical to the registry)
- New safe_attributes / params / routes / permissions / callbacks (module)

## 4. Tests added/updated
- Added / changed / deleted specs and JS tests (deleted: reason)
- Regenerated fixtures (git diff --stat test/js/fixtures) and why
- Flipped characterization assertions: | spec:line | behaviour row id |
- Counts: rspec examples per version before -> after; JS tests before -> after
- Mutation checks: | guard | mutation | failing test observed | reverted |

## 5. Independent review report
- Reviewer (role, session) and diff reviewed: <base>..<head> (<files> files, +<a>/-<d>)
- Checklist: permissions | strong params | CSRF | same origin | XSS (incl. flash) | N+1 | transactions/audit |
  Ruby 2.7/Rails 6.1 | partial structure | i18n | contracts vs section 2 and compat 2.4/3 | shims/legacy params | dead code
- Findings: | id | severity | file:line | finding | status (fixed <sha> / accepted: reason) |
- security-review output summary

## 6. QA report
- Matrix (pasted DCF MATRIX block) + system suite lines + npm summary
- Seeds run (incl. spec/frontend under 2 seeds); deprecation warning counts
- Failure-mode checklist (section 8) with status per row
- Exploratory checks performed (scenario -> observed result)
- CI dispatches (section 10, UD-32): | workflow | ref | SHA | run URL | result | or "none"

## 7. UX/consistency report
- Screens: | screen | 5.1 screenshot | 7.0 screenshot | notes (icons, layout) |
- Keyboard/aria checks; locale spot checks (de/fr/nl) with observed strings; native-speaker review
- Consistency notes vs core components; open UX issues

## 8. Gate checklist with PASS/FAIL and evidence
| Gate | Status (PASS / FAIL / NOT RUN / N/A) | Evidence (command -> exit -> summary line -> log; N/A: one-line justification) |
|---|---|---|
| G1 Correctness | PASS | ... |
| G2 Tests green | PASS | ... |
| G3 Lint and style | PASS | ... |
| G4 UX and consistency | PASS | ... |
| G5 Security | PASS | ... |
| G6 Performance | PASS | ... |
| G7 Backward compatibility | PASS | ... |
| G8 I18n | PASS | ... |
| G9 Docs, CHANGELOG, version | PASS | ... |
| G10 Version matrix | PASS | ... |
| G11 CI policy and tooling | PASS | ... |
| G12 Data integrity and storage | PASS | ... |

## 9. Next actions and exact diffs on FAIL
- For each FAIL / NOT RUN: classification (product bug | test bug | environment | flaky),
  root cause, owner role, fix, exact rerun command. Environment problems are fixed in the
  environment, not by changing code or tests. Flaky: rerun with the same seed, fix the cause.
- For each FAIL caused by code, tests or docs: the exact proposed diff (unified `git diff`
  format with file paths and hunks), not a description; for environment problems the exact
  commands. A diff that weakens or deletes an assertion needs the reviewer's written approval.
- After 3 failed fix iterations: stop and escalate to the owner with evidence.
- Empty ("none") only when every gate is PASS or N/A.
```

## 8. Failure-mode checklist template (with plan-specific seed rows)

Columns: `id | failure mode | trigger / scenario | detection (test id or command) | mitigation | status (covered / not covered / accepted) | evidence`.

| id | failure mode | trigger | detection |
|---|---|---|---|
| FM-01 | Data loss: stored child value cleared | notes-only save with a legacy combination; read-only child; unrelated bulk update on issues holding legacy combinations | R1 D1 per-value specs + shared case table + system scenario 1 (WP-09, WP-17); unrelated bulk update spec (WP-09, gap 12) |
| FM-02 | Data loss: bulk edit clears untouched children | `bulk_edit_form` id, multi-select `['']` | system scenario 2 + R3 params spec (WP-03 hotfix, WP-19 time-entry and required cases) |
| FM-03 | Mapping pruned | admin save drops inactive enumerations; parent change; import replace; unrelated API/plugin saves | R3 admin transport spec, G7 no-pruning specs, upgrade spec |
| FM-04 | Silent truncation / 500 on MySQL | S1 sizes over 65,535 | G12 specs, optional MariaDB run |
| FM-05 | JS not initialised | AJAX replacement, context menu, jQuery `trigger`, runtime or meta tag missing or out of order (one UMD file, no separate rules file) | J1 tests, head fixture order assertion, system scenario 3; one `replaceIssueFormWith` insertion causes exactly one `init` per root (gap 13, WP-17) |
| FM-06 | Field missing data attributes | other customized types or prefixes | R4 markup fixtures per prefix |
| FM-07 | Version drift | Rack 2/3, controller names, sprite_icon, propshaft | matrix G10, compat grep, version-specific fixture variants |
| FM-08 | Infinite loop | stored cycles in the client cascade or the wizard | J1 stored-cycle fixture test (no parent attributes on cycle members, visited-set guard on chains), R1 cycle validation (WP-10, WP-17) |
| FM-09 | Permission bypass | direct URL, closed/archived project, non-admin API, wizard save, cross-origin wizard action or values URL | G5 matrix specs, wizard pin spec (write scope: SD-01), same-origin jsdom tests (WP-18 wizard, WP-25 values URL, gap 12) |
| FM-10 | XSS / CSV injection | values with markup, formula prefixes, field names in flash | G5 specs, export review |
| FM-11 | N+1 / global scans | many fields, many distinct parents, many issues | G6 invariance and differential specs |
| FM-12 | Rack limit 404/400 | over 4096 params; admin urlencoded body over 4 MB | R3 large transport spec, multipart switch after init (UD-16) and form-size pre-check jsdom test (WP-25) |
| FM-13 | i18n silent fallback or last-wins duplicate | missing key in de/fr/nl; same key defined twice in one file (for example `text_dcf_no_matches` added by both WP-25 and WP-28); a map value of `ClientConfig::I18N` or `DependencyEditorConfig::I18N` without a locale entry | locale parity spec (duplicate walk, constant maps when defined, WP-18 and WP-24 examples; one owner WP per key in the registry, gap 8) |
| FM-14 | Test pollution / order dependency | constants, I18n.locale, init double-load, YAML in spec/fixtures, sequence-dependent ids | random order, fixture self check, quality specs |
| FM-15 | Stale concurrent edit | two managers or admin plus manager save the same field | `state_hash` 409 and `dcf_stale_dependencies` specs |
| FM-16 | External JS callers break | `setup`/`requestSetup` | J1 shim test |
| FM-17 | Contract drift between server and client | attribute renamed on one side | generated fixtures consumed by jsdom (both sides fail together) |
| FM-18 | CPU DoS through the payload | huge integer literals, deep nesting, 16 MB bodies; hostile payload from an unauthorized user | G5 payload specs (pre-scan, spy on JSON.parse, WP-21); unauthorized PATCH gives 403, `authorization_failed` audit row, parse never called (SP-20b, WP-27, gap 12) |
| FM-19 | New callback breaks stand-in specs | callback registered in `CustomFieldPatch.prepended` | DB-backed spec rewrite + module rule, matrix |
| FM-20 | Leak of role-restricted parent values | `data-dcf-parent-values` / allowed set for an invisible parent | role-invisible fixture case asserting absence |
| FM-21 | False dirty state / blank project save / lost correction after a failed save | pre-filled hidden input; no-JS submit; failed-save re-render | jsdom untouched-page test, project Save disabled spec; failed-save specs (WP-22, WP-25, WP-27, gap 1): mapping attribute holds the posted mapping, `data-dcf-editor-dirty="1"`, hidden input blank, no `data-dcf-editor-echo` |
| FM-22 | Bulk partial failure hidden or wrong issues changed | parent "(no change)" with a child allowed under only some issues' parents; mixed-tracker selection where the parent is not common; parent `__none__` cascade | bulk specs for issues and time entries (QA-14, WP-19, gap 12): allowed issues save, the others are listed in the flash |
| FM-23 | Inactive values mishandled on the form | stored inactive child id or parent value; per-parent default on an inactive id; inactive ids in `data-dcf-map` without an option | markup fixtures plus jsdom (QA-21, WP-16, gap 12) |
| FM-24 | Storage estimate wrong or missing in the editor | mapping near the column or project limit | `test/js/dependency_editor_storage.test.js` (WP-25, gap 12) |
| FM-25 | Admin-only control shown in the wrong mode | "Add missing child values" on the project page or for enumeration children | jsdom on the project and enumeration fixtures (WP-26, gap 12) |
| FM-26 | Settings page silently stores garbage | non-numeric `project_storage_ceiling_kib` | settings request spec in en and de, fallback 2,048 KiB (WP-31, gap 12) |
| FM-27 | Other plugins lose write access | `safe_attribute_names` loses `value_dependencies`, `default_value_dependencies` or `dependencies_json` | BC-04 spec (WP-22, gap 12) |
| FM-28 | Ruby 2.7 syntax regression | hash shorthand, endless def or anonymous forwarding in new code (for example the head hook meta call) | WP-01 syntax gate (`SYNTAX PASS`), gap 15 |

## 9. Upgrade-notes register (BC-14) and version targets

Every change an existing 0.0.15 user can notice has one CHANGELOG line. G9 checks the lines of the entries a WP touches; each release WP (WP-07, WP-14, WP-20, WP-32) checks every entry of its release. The canonical CHANGELOG wording per release is `large_lists_work_packages.md` section 3; the "Compat PC" column links each entry to the perceptible change of `large_lists_compatibility.md` section 4, which carries the release and the exact line. Section: A Added, C Changed, F Fixed, S Security, D Deprecated, R Removed, U Upgrade notes (an entry can have both its section and an U line).

| id | Change | Sections | WP (release) | Compat PC |
|---|---|---|---|---|
| UN-01 | Child fields are never disabled; disallowed options hidden and disabled; hint under the field | C U | WP-17, WP-18 (0.1.0 (M2)) | PC-22 |
| UN-02 | Stored values that no longer fit the parent are kept, marked and accepted until the parent changes (D1, per value) | C F U | WP-09 (0.1.0 (M1)); WP-16, WP-17 (0.1.0 (M2)) | PC-06, PC-23 |
| UN-03 | Untouched child whose parent is not available on the record is accepted (UD-05) | C U | WP-09 (0.1.0 (M1)) | PC-07 |
| UN-04 | A read-only or hidden-from-form (but visible) parent now filters the child by the stored value; `hide_when_disabled` can hide that child | C U | WP-16, WP-17, WP-18 (0.1.0 (M2)) | PC-25 |
| UN-05 | `hide_when_disabled` works on single-record forms only, never while a legacy value is shown, never in bulk edit | C U | WP-17 (0.1.0 (M2)) | PC-27 |
| UN-06 | `change` fires only on a real value change; new `dcf:updated` event | C A U | WP-17, WP-18 (0.1.0 (M2)) | PC-33 |
| UN-07 | Last pick per parent value remembered across AJAX form refreshes | A | WP-17 (0.1.0 (M2)) | PC-66 |
| UN-08 | Without JavaScript, enumeration options are no longer filtered by the server; server still validates | C U | WP-18 (0.1.0 (M2)) | PC-35 |
| UN-09 | Enumeration gives one "is invalid" error and no duplicate option | F | WP-08 (0.1.0 (M1)) | PC-13 |
| UN-10 | Required radio children can be cleared (sentinel) | F | WP-19 (0.1.0 (M2)) | PC-38 |
| UN-11 | Fields rendered without Redmine's custom field helpers are no longer filtered in the browser (README Integration) | C U | WP-18 (0.1.0 (M2)) | PC-34 |
| UN-12 | Bulk edit no longer clears untouched multi-value children (data loss) | F | WP-03 (0.0.16); WP-19 (0.1.0 (M2), time-entry and required cases) | PC-02 |
| UN-13 | A concrete parent in bulk edit or the wizard keeps "(no change)" on descendants, preselects the per-parent default with a hint and forces "(none)" only for parent "(none)" or a value without links (UD-09, revised D2); required children get a marked "(none)" (UD-10, former C7) | C U | WP-17, WP-19 (0.1.0 (M2)) | PC-28, PC-39 |
| UN-14 | Parent back to "(no change)" restores the child | C | WP-17 (0.1.0 (M2)) | PC-28 |
| UN-15 | The wizard opens every field, including the root, on "(no change)"; saving without choosing changes nothing (UD-11; it used to write the root default) | C U | WP-18 (0.1.0 (M2)) | PC-29 |
| UN-16 | Wizard errors are shown and the wizard stays open | F | WP-18 (0.1.0 (M2)) | PC-30 |
| UN-17 | Context menu hides only children available in the selection and their parents; dangling-parent children show as plain lists | C U | WP-15 (0.1.0 (M2)) | PC-31 |
| UN-18 | Context menu responses include dependency data for wizard fields and can be larger for very big mappings | C U | WP-18 (0.1.0 (M2)) | PC-32 |
| UN-19 | The admin editor replaces the matrix and needs JavaScript | C U | WP-25 (0.1.0 (M3)) | PC-45, PC-55 |
| UN-20 | Unrelated admin saves no longer touch the mapping | F | WP-22 (0.1.0 (M3)) | PC-48 |
| UN-21 | Unticking every link clears the mapping | F | WP-22 (0.1.0 (M3)) | PC-47 |
| UN-22 | Links to inactive enumerations are kept; links dropped by earlier versions are not restored | F U | WP-22 (0.1.0 (M3)) | PC-49, PC-65 |
| UN-23 | Orphan links (including keys corrupted by `[`/`]` in earlier versions) are reported and removed at the next editor save; re-link once | C U | WP-25, WP-27 (0.1.0 (M3)) | PC-51, PC-65 |
| UN-24 | A parent change in the form prunes links to the new parent's values | C | WP-22, WP-25 (0.1.0 (M3)) | PC-50 |
| UN-25 | Stale-mapping guard rejects an admin save after a concurrent change | A U | WP-22, WP-25 (0.1.0 (M3)) | PC-52 |
| UN-26 | Default value field shows until a parent is chosen | C | WP-25 (0.1.0 (M3)) | PC-53 |
| UN-27 | Parent select excludes descendants; cycle warning shown | C | WP-10 (0.1.0 (M1)) | PC-11, PC-12 |
| UN-28 | Values with brackets and mappings above 4,096 links now save | F | WP-22, WP-25, WP-27 (0.1.0 (M3)) | PC-47 |
| UN-29 | CSV import and export of links | A | WP-26 (0.1.0 (M3)) | PC-56 |
| UN-30 | Matrix partials and their CSS classes removed | R U | WP-25, WP-27 (0.1.0 (M3)) | PC-64 |
| UN-31 | Circular parent gives a form error or HTTP 422 | C U | WP-10 (0.1.0 (M1)) | PC-10, PC-21 |
| UN-32 | On MySQL, oversize values give a validation error instead of a 500 or silent truncation, core list and enumeration fields included; non-strict servers now refuse | F U | WP-11 (0.1.0 (M1)) | PC-14, PC-15 |
| UN-33 | Saves from the admin editor normalize the stored mapping, which can change API GET output | C U | WP-22, WP-25 (0.1.0 (M3)) | PC-54 |
| UN-34 | Saves work on MemCacheStore | F | WP-03 (0.0.16) | PC-01 |
| UN-35 | Project dependency editor, no-JS notice, scope banner, parent-not-available notice, orphans removed on save (audited) | C A U | WP-27 (0.1.0 (M3)) | PC-45, PC-51, PC-55, PC-67 |
| UN-36 | Compact audit values; values over 16 KB truncated with a marker | C U | WP-12 (0.1.0 (M1), cap and marker); WP-27 (0.1.0 (M3), compact delta) | PC-18, PC-57 |
| UN-37 | Values page: search box above 25 values (`FILTER_MIN`), pagination above 500 values, drag only at 500 or fewer unfiltered values, A-Z/Z-A sort, page-scoped enumeration save; `sort_values` granted to holders of `manage_project_custom_field_configuration` | A C U | WP-28, WP-29, WP-30 (0.1.0 (M3)) | PC-59, PC-60, PC-61 |
| UN-38 | "Show usage" counts are exact | C U | WP-28 (0.1.0 (M3)) | PC-59 |
| UN-39 | Redirects keep `q` and `page` | C | WP-28 (0.1.0 (M3)) | PC-59 |
| UN-40 | Globals `DependingCustomFieldData` and `ContextMenuWizardConfig` removed; `setup`/`requestSetup` and `CustomFieldVisibility` deprecated in 0.1.0 (removable no earlier than 0.2.0) | R D U | WP-15, WP-18 (0.1.0 (M2)) | PC-41, PC-42 |
| UN-41 | Removed: `MappingBuilder`, `ParentMenuBuilder`, `QueryCustomFieldColumnPatch`, `ContextMenuWizardController#options`, the `after_custom_field_save` dispatch, `data-depending-*` attributes, `depending_cf_N` ids, hidden mirror inputs | R U | WP-06 (0.1.0 (M1), QueryCustomFieldColumnPatch); WP-15, WP-18 (0.1.0 (M2)) | PC-04, PC-42 |
| UN-42 | Project nested params deprecated in 0.1.0 (accepted throughout 0.1.x, removable no earlier than 0.2.0); admin nested safe attributes kept permanently (UD-15) | D U | WP-22, WP-27 (0.1.0 (M3)) | PC-63 |
| UN-43 | Cache key `depending_custom_fields/mapping` no longer used; rollback note | R U | WP-18 (0.1.0 (M2)) | PC-43 |
| UN-44 | New asset files; restart (and on 5.1 `rake redmine:plugins:assets`) needed | U | WP-18 (0.1.0 (M2)); WP-25 (0.1.0 (M3)) | PC-43, PC-65 |
| UN-45 | Ruby >= 2.7 | U | WP-02, WP-07 (0.0.16) | PC-05 |
| UN-46 | Admin form header shows Default value (core `field_default_value`) | F | WP-02 (0.0.16) | PC-03 |
| UN-47 | Issue copies keep unchanged legacy combinations | C F U | WP-09 (0.1.0 (M1)); WP-16 (0.1.0 (M2)) | PC-08 |
| UN-48 | Non-editable dependent field no longer blocks a parent change | C | WP-09 (0.1.0 (M1)) | PC-09 |
| UN-49 | Opt-in rake tasks `report_sizes` and `widen_core_columns` | A | WP-13 (0.1.0 (M1)) | PC-16 |
| UN-50 | Storage usage line at 90 percent | A | WP-11 (0.1.0 (M1)) | PC-17 |
| UN-51 | Audit overflow no longer rolls back saves | F | WP-12 (0.1.0 (M1)) | PC-19 |
| UN-52 | Flash messages escape field names | F | WP-12 (0.1.0 (M1)) | PC-20 |
| UN-53 | Per-parent defaults at load only for new records | C | WP-17 (0.1.0 (M2)) | PC-24 |
| UN-54 | Invisible parent: child unfiltered, no mapping leak | C | WP-16, WP-18 (0.1.0 (M2)) | PC-26 |
| UN-55 | No browser recursion on cycles | F | WP-10 (0.1.0 (M1)); WP-17 (0.1.0 (M2)) | PC-36 |
| UN-56 | Mapping no longer embedded in every page | F | WP-18 (0.1.0 (M2)) | PC-37 |
| UN-57 | Hints announced to screen readers | A | WP-17, WP-18 (0.1.0 (M2)) | PC-40 |
| UN-58 | Wizard writes only editable fields (SD-01) | S | separate SD-01 PR (0.1.0 (M2) at the latest) | PC-44 |
| UN-59 | Admin form sends one JSON field and is multipart while the editor is active | C U | WP-22, WP-25 (0.1.0 (M3)) | PC-46 |
| UN-60 | Corrected resubmit after a failed project save no longer gives 409 | F | WP-27 (0.1.0 (M3)) | PC-58 |
| UN-61 | Project storage ceiling setting and 255-character cap | A C U | WP-31 (0.1.0 (M3)) | PC-62 |
| UN-62 | Format-change confirmation, leave warning, editor placement on the admin form | C | WP-25 (0.1.0 (M3)) | PC-68 |

Security line (separately tracked as SD-01, section 11; UN-58, PC-44): the context-menu wizard save writes read-only and role-hidden fields. Recommended as its own pull request merged before tagging 0.0.16 (UD-03); it is merged before 0.0.16 is tagged (UD-03 resolved) and therefore long before 0.1.0, the release that ships point 1.

Suggested Upgrade-note wording for entries no area design listed (from BC-14): UN-04 "Dependent fields whose parent is read-only on the form are now filtered by the stored parent value and may be hidden when 'Hide when no valid options' is set."; UN-08 "Without JavaScript, Key/Value list (depending) fields show all active values; the server still rejects invalid combinations."; UN-11 "Fields rendered without Redmine's custom field helpers are no longer filtered in the browser; see README Integration."; UN-15 "The context-menu wizard opens every field on '(No change)'; saving without choosing changes nothing (it used to write the root field's default)." (UD-11; revision 2's wording "applies the root field's default and its cascade as soon as it opens" is superseded); UN-18 "Context menu responses include dependency data for the wizard fields and can be larger for very big mappings."; UN-22 "Links removed by earlier versions (inactive key/value entries) cannot be restored."; UN-23 "Links stored under parent values containing [ or ] were saved under corrupted keys by earlier versions and never took effect; the editor lists them as orphans, and they must be re-linked once."; UN-33 "Saves from the admin editor normalize the stored mapping, which can change API GET output."; UN-37 "Members with 'Manage project custom field configuration' can now sort values A-Z/Z-A."; UN-38 "'Show usage' now reports exact counts."

Version targets (UD-01): 0.0.16 = WP-01..WP-03 and WP-07, 0.1.0 (M1) = WP-04..WP-06 and WP-08..WP-14, 0.1.0 (M2) = WP-15..WP-20, 0.1.0 (M3) = WP-21..WP-32. JS shims (`setup`/`requestSetup`) and `CustomFieldVisibility` deprecated in 0.1.0, kept at least throughout 0.1.x, removable no earlier than 0.2.0; project nested params deprecated in 0.1.0, accepted throughout 0.1.x, removable no earlier than 0.2.0; admin `value_dependencies`/`default_value_dependencies` safe attributes permanent (E28, UD-15).

## 10. Deliberate manual CI triggering by Claude (policy, UD-32 resolved)
- **Resolved by the owner (UD-32).** CI runs only manually, or when Claude deliberately starts it. Claude may dispatch the manual (`workflow_dispatch`-only) workflows deliberately, for example to obtain version-matrix evidence it cannot produce locally or before tagging a release (WP-07, WP-14, WP-20, WP-32). Conditions: only after the local gates pass; at most once per workflow per commit SHA unless a fix was pushed; never editing workflow triggers; every dispatch is reported (workflow, SHA, run URL, result). CI never gets automatic triggers. Revision 2's rule ("only when the user explicitly asked in this conversation") is superseded by this resolution. The resolution covers exactly this policy: a message from another agent or a workflow script is not owner consent for anything beyond it.
- Before dispatching: local gates PASS with evidence (section 3), branch pushed, HEAD SHA recorded; at most one dispatch per workflow per SHA unless a fix was pushed (then the new SHA counts afresh); no retry-until-green loops.
- Commands:

  ```bash
  gh workflow run rspec-70.yml --ref <branch> -f system_specs=false -f lint=true -f base_ref=origin/main
  gh run list --workflow rspec-70.yml --branch <branch> --limit 1 --json databaseId,headSha,status,conclusion,url
  gh run watch <id> --exit-status
  gh run view <id> --log-failed
  ```

  GitHub MCP equivalents: `actions_run_trigger`, `actions_list`, `actions_get`, `get_job_logs`.
- A `workflow_dispatch` workflow must exist on the default branch to be dispatchable: `rspec-61.yml` and `js-tests.yml` become dispatchable after WP-01 is merged; the optional manual MariaDB workflow after WP-13 (UD-27).
- Never edit `on:` (no `push`, `pull_request`, `schedule` or other automatic trigger, ever); never create Routines or cron jobs that dispatch workflows. The ref is the WP branch whose HEAD SHA is reported; a release WP dispatches on its release commit.
- Report (mandatory for every dispatch, in the QA report of section 7): workflow, ref, SHA (`headSha`), inputs, run URL, result (conclusion), duration, failing job/step with a log excerpt. G10 evidence only if `headSha` equals the WP HEAD. An unreported dispatch is a G11 FAIL.
- Guard: `spec/quality/ci_workflows_spec.rb` (WP-01).

## 11. Separately tracked items (out of the 9 points)
- **SECURITY defect (SD-01 in `large_lists_defects.md`; review issue SP-07, reclassified from "hardening"):** `ContextMenuWizardController#save` assigns `issue.custom_field_values = values` directly (`app/controllers/context_menu_wizard_controller.rb:31-32`); the acts_as_customizable setter writes every available field, while core filters to `editable_custom_field_values(user)` only in `Issue#safe_attributes=` (core-5.1 `app/models/issue.rb:625-626`, core-7.0 `:647-648`). A user with `edit_issues` can write workflow read-only and role-invisible fields without a journal. Kept out of the 9 points per D4. Schedule (UD-03): recommended as its own pull request merged before tagging 0.0.16; merged before 0.0.16 (UD-03 resolved), long before 0.1.0, the release that ships point 1; CHANGELOG "Security" entry (PC-44). Minimal fix: keep only keys in `issue.editable_custom_field_values(User.current)`, or assign through `issue.safe_attributes = { 'custom_field_values' => values }`. Spec: a read-only field and a role-hidden field posted to save are not changed. Until then WP-15 (named save route) pins that the endpoint still requires login, issue visibility and editability and does not widen.
- Wizard save hardening beyond the security fix (journal, `@can[:edit]`, 7.0 webhooks / `updated_on`): SD-02.
- Time-entry context menu (leaks `__group_*` rows, unfiltered depending fields): SD-03.
- `copy_from` enumeration-id remap: SD-06 (README note in WP-25).
- Optional MySQL CI job: decision UD-27 (optional manual MariaDB workflow, WP-13); not an SD item.
- Workflow-required depending children with no options (`Issue#validate_required_fields`): SD-04.
