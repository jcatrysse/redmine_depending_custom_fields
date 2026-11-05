# Full branch review of 2026-11-05 (Claude)

Branch `claude/festive-noether-2y8x7c`, base of the fixes `2d3a6d1`. The review
looked at what the per-package reviews of WP-01 to WP-38 and the OpenAI review
of the full diff could miss: integration across packages, the security model
as a whole, dead or duplicated code, inconsistencies, performance (per-row
queries, lists of 25,000 values) and the differences between Redmine 5.1 and
7.0. 36 findings were confirmed by a second, independent reading. Each entry
below gives the area, the verified severity, the file and line as reported,
the problem, the verdict of that reading and a `Resolution:` line. The file
and line are given as the finding reported them; some line numbers count in
the reviewed diff rather than in the file at `2d3a6d1`.

User-visible changes have a CHANGELOG line, the same line in section 3 of
`docs/specs/large_lists_work_packages.md` (end of the M3 list) and a PC row in
`docs/specs/large_lists_compatibility.md` (PC-81 to PC-91). New examples are in
`spec/models/dcf_full_review_rules_spec.rb`,
`spec/requests/dcf_full_review_project_pages_spec.rb`,
`spec/requests/dcf_full_review_context_menu_spec.rb`,
`spec/models/dcf_full_review_extended_user_spec.rb`,
`spec/quality/stylesheet_direction_spec.rb`, a new test in
`test/js/dcf_dependency_editor.test.js` and an assertion in
`spec/system/dcf_dependency_editor_spec.rb`; existing examples that pinned the
old behaviour carry a 'Changed by the full review of 2026-11-05' note.

## Server rules

### rules-1: a hidden child is named on versions, users, groups and documents

- Area: server rules, security model. Severity: major.
- File: `lib/redmine_depending_custom_fields/depending_format_methods.rb:90`
  (also `init.rb:77-86`, `non_editable_dependencies.rb:9-15`).
- Problem: only Issue, Project and TimeEntry get the placement of
  NonEditableDependencies. Core validates every custom value of a version,
  user, group, document or enumeration and files the D1 'is invalid' under
  the field's own name, so a child the user cannot see was named (UD-07
  recorded it as accepted), against the rule that such a field is never
  named.
- Verdict: confirmed (traced on 5.1 and 7.0: a manager changes the visible
  parent of a version while a hidden child holds a value the new parent value
  does not allow; core answers 'C-name is invalid').
- Fix: `NonEditableDependencies.judged_by_record?` is true for a value
  User.current cannot see on any record but an issue or a project, so the
  formats leave its D1 error out; the new
  `Patches::HiddenDependenciesValidationPatch`, prepended to Version, User,
  Group, Document and Enumeration, calls `NonEditableDependencies
  .validate_hidden` inside core's gate: the dedicated message on the changed
  parent field when the user can see it, else on base. An administrator and a
  visible child keep core's 'is invalid' under the child's name.

Resolution: fixed in this commit.

### rules-2: a role-hidden time entry parent on 5.1 and 6.0

- Area: server rules, 5.1 to 7.0 differences. Severity: minor.
- File: `lib/redmine_depending_custom_fields/dependency_rules.rb:226`.
- Problem: core 5.1 and 6.0 `TimeEntry#safe_attributes=` remove a parent the
  user cannot see from `custom_field_values`; `read_parent_state` then gave an
  unavailable, changed parent with nothing allowed, so a stored visible child
  was refused on any edit (6.1 and 7.0 accept the same request; WP-38 open
  input 2).
- Verdict: confirmed on 5.1 (red run below); 6.1 and 7.0 unaffected.
- Fix: `DependencyRules.dropped_parent_values`: for a saved time entry that
  no longer lists the parent but holds saved rows of it, those values give an
  available, unchanged parent (values and baseline). Issues and projects keep
  UD-05. No query (the rows are loaded).

Resolution: fixed in this commit.

### rules-3: value_from_keyword reads every value per call

- Area: performance (imports, email). Severity: major.
- File: `lib/redmine_depending_custom_fields/depending_format_methods.rb:118`.
- Problem: each call built the folded index of the whole option list; for a
  depending enumeration that instantiated every active enumeration per row
  and field.
- Verdict: confirmed (900 CustomFieldEnumeration rows instantiated for two
  keywords on a 300-value field).
- Fix: the label index is memoized on the CustomField record
  (`dcf_memo(:dcf_keyword_index)`); an enumeration keyword is looked up first
  with one query on the active names (`LOWER(TRIM(name)) = LOWER(?)`, plucked,
  then checked with the same Unicode folding, first by position), and the
  full index is built only when that finds nothing (folded forms such as
  'STRASSE' for 'Straße'). `CustomFieldPatch#dcf_memoized?` is new. The folding
  and first-label-wins rules are unchanged; a core import builds new field
  records per row, so for a List the per-row cost stays one pass over the
  values, as core's own detect.

Resolution: fixed in this commit.

### rules-4: a multi-value label with a comma cannot be imported

- Area: server rules (imports, email). Severity: minor.
- File: `lib/redmine_depending_custom_fields/depending_format_methods.rb:129`.
- Problem: a multiple keyword was split on ';' and ',' first, so a label
  such as 'Berlin, Germany' never matched and was dropped silently.
- Verdict: confirmed.
- Fix: the keyword is split on ';' and each part is read longest label first,
  as core `parse_keyword` reads a ',' list (an unknown first segment is
  skipped). The 0.0.16 oracle of `spec/lib/depending_format_methods_spec.rb`
  and the characterization example 'cannot import a value that contains a
  comma' were changed and flipped with a note.

Resolution: fixed in this commit.

### rules-5: a project copy is not judged against its source

- Area: server rules (UD-06). Severity: minor.
- File: `lib/redmine_depending_custom_fields/dependency_rules.rb:269`.
- Problem: `baseline_source` knew only issue copies; the new project of
  `projects/copy` had no baseline, so a stored child value under an unchanged
  parent value was refused although the same project edits fine.
- Verdict: confirmed.
- Fix: `ProjectValidationPatch#copy` keeps the source of `Project#copy` in
  `@dcf_copied_from` for the first save, and `baseline_source` reads it for a
  new project. A changed parent value and a new value stay strict. The
  format-singleton scan allows this record-level variable.

Resolution: fixed in this commit.

### rules-6: the enumeration filter values read the project for nothing

- Area: performance, consistency. Severity: nit.
- File: `lib/redmine_depending_custom_fields/depending_enumeration_format.rb:233`.
- Problem: `query_filter_values` looked up the parent value on the query's
  project for every depending enumeration.
- Verdict: partly not a defect: the branch is not dead, it restricts a
  project field's values by the project's own parent value, as 0.0.15 did
  (pinned by `spec/lib/depending_enumeration_format_spec.rb` and the
  characterization). For an issue or time entry field it can never restrict,
  and it cost a project values load and a parent lookup per field and filter
  build.
- Fix: the lookup runs only when the project carries the field
  (`DependencyRules.carries?`); the project-field restriction is kept.

Resolution: fixed in this commit (the wasted lookup); the restriction for
project fields is kept as 0.0.15 behaviour, not a defect.

### rules-7: dead rules code

- Area: dead code. Severity: nit.
- File: `lib/redmine_depending_custom_fields/dependency_rules.rb:337`.
- Problem: `allowed_set`, `allowed_values`, `default_values`,
  `DependencyRules.descendant_ids`, `in_cycle?` and
  `Sanitizer.replace_none_values_with_blank` have no caller in lib, app or
  init.rb.
- Verdict: confirmed for all six; three of them serve as a reference.
- Fix: `descendant_ids`, `in_cycle?` and `replace_none_values_with_blank` are
  removed (their examples use `FieldIndex#descendant_ids` and
  `cycle_member_ids`). `allowed_set`, `allowed_values` and `default_values`
  are kept: they are the server reference of the shared rule cases
  (`test/js/fixtures/shared/rules_cases.json`, read by
  `spec/lib/dependency_rules_spec.rb` and the runtime's JS tests), which pin
  that the browser's filter and default union equals the server's; a comment
  now says so and that validation uses `allowed_for`.

Resolution: fixed in this commit for the three unused methods; the three
reference methods are not fixed: they back the cross-layer rule cases, so
removing them would drop that contract test.

## Admin dependency editor

### admin-editor-1: the toolbar ignores the hidden attribute

- Area: editor CSS. Severity: minor.
- File: `assets/stylesheets/dcf_dependency_editor.css:28`.
- Problem: `.dcf-dep-editor__toolbar { display: flex }` beats the browser's
  `[hidden]` rule, so the filter, the checkbox and 'Collapse all' stayed
  above 'no parent values' or 'no child values'.
- Verdict: confirmed in Chromium (system example).
- Fix: `.dcf-dep-editor [hidden] { display: none !important; }`.

Resolution: fixed in this commit.

### admin-editor-2: one default select rebuild per click

- Area: editor performance. Severity: nit.
- File: `assets/javascripts/dcf_dependency_editor.js:816`.
- Problem: every link toggle rebuilt the default select of the section, one
  option per linked child.
- Verdict: confirmed.
- Fix: `Editor#defaultOption` adds or removes the toggled child's option in
  place, in child order, and updates the disabled state of the select and of
  Clear; check shown, clear and the multiple switch still rebuild.

Resolution: fixed in this commit.

### admin-editor-3: a copied depending enumeration keeps dangling links

- Area: admin, data integrity. Severity: minor.
- File: `lib/redmine_depending_custom_fields/dependency_editor_config.rb:171`.
- Problem: core `copy_from` copies `format_store`, so the links name the
  source's enumeration ids, while the copy gets new entries; nothing pruned
  them, so a required copy could not be filled until relinked.
- Verdict: confirmed (the copy saved the source's ids).
- Fix: `CustomFieldPatch#copy_from` clears both mappings of a copied
  depending enumeration; a List (depending) copy keeps its mapping. The
  upgrade note now says that copies made by earlier versions keep the old
  links (shown as orphans).

Resolution: fixed in this commit.

### admin-editor-4: unused ValueList methods

- Area: dead code. Severity: nit.
- File: `assets/javascripts/dcf_dependency_editor_model.js:174`.
- Problem: `ValueList#has`, `#get` and `#match` have no production caller.
- Verdict: confirmed for `has` and `get`; `match` is a one-line wrapper of
  `candidates`, which the import uses, so the two cannot drift.
- Fix: `has` and `get` are removed (tests use `byKey`); `match` stays as the
  public seam of `candidates`, with a comment.

Resolution: fixed in this commit for `has` and `get`; `match` not removed:
it is the tested seam of the import lookup and cannot diverge from it.

## Project settings pages

### project-pages-1: the dependency page names a hidden parent

- Area: security. Severity: major.
- File: `app/controllers/project_custom_field_configuration_controller.rb:231`.
- Problem: the page named the parent and sent its values
  (`data-dcf-editor-parent-name`, `-parent-values`) without a visibility
  check; the notice named a parent not used in the project; the save read its
  labels into the audit summary.
- Verdict: confirmed.
- Fix: `prepare_dependencies` names the parent only when
  `UsageCalculator.nameable_child?` holds (administrator, or used in the
  project and visible for the role); otherwise the new key
  `text_dcf_parent_not_available_generic` (en, de, fr, nl) and no editor.
  `DependencyMappingService` answers 404 for such a parent before reading it.

Resolution: fixed in this commit.

### project-pages-2: removing the default enumeration keeps the default

- Area: project services. Severity: major.
- File: `app/services/redmine_depending_custom_fields/remove_value_service.rb:201`.
- Problem: `remove_enum!` left `default_value` on a deactivated or destroyed
  enumeration; a depending enumeration then failed its own save ('Default
  value is invalid') and the removal rolled back with a generic error.
- Verdict: confirmed.
- Fix: the default is cleared with the value and the summary says
  'default value cleared'.

Resolution: fixed in this commit.

### project-pages-3: the overview tab loads every value and project

- Area: performance. Severity: minor.
- File: `app/services/redmine_depending_custom_fields/field_relevance.rb:258`.
- Problem: `relevant_fields` preloaded `:projects` and `:enumerations` on
  every Project > Settings page to print counts.
- Verdict: confirmed (40 enumeration rows instantiated for one field).
- Fix: nothing is preloaded; `FieldRelevance.overview_counts` gives the value
  counts, project counts and shared fields in three grouped queries, and
  `FieldRelevance.scope` uses one `exists?` query when no counts are given.

Resolution: fixed in this commit.

### project-pages-4: enumeration names above 60 characters

- Area: project services, UX. Severity: minor.
- File: `app/services/redmine_depending_custom_fields/add_value_service.rb:457`.
- Problem: core's 60-character limit surfaced as the generic 'could not be
  saved'.
- Verdict: confirmed.
- Fix: `BaseService#check_enum_name_length!` (add, rename, batch table; a
  stored name may stay) raises `error_dcf_value_length` with max 60 before
  any write. The suggested `maxlength` attributes were not added: the server
  message is enough and the list inputs have none either.

Resolution: fixed in this commit.

### project-pages-5: a list with a repeated value cannot be reordered

- Area: project services. Severity: minor.
- File: `app/services/redmine_depending_custom_fields/reorder_values_service.rb:485`.
- Problem: the permutation check used the raw list while the page shows
  distinct values.
- Verdict: confirmed.
- Fix: the order is checked against the distinct values; the save stores the
  submitted order (the repeat goes).

Resolution: fixed in this commit.

### project-pages-6: the standard-field setting blocks a depending child's mapping

- Area: project pages. Severity: minor.
- File: `app/controllers/project_custom_field_configuration_controller.rb:231`.
- Problem: the parent test used `relevant?`, which includes the
  `manage_standard_custom_fields` switch, so a standard parent hid the editor
  with a wrong notice and the save answered 404.
- Verdict: confirmed.
- Fix: the page and `DependencyMappingService` test the parent with
  `in_project?` (plus the naming rule of project-pages-1).

Resolution: fixed in this commit.

### project-pages-7: the audit summary holds a hidden field's id

- Area: security. Severity: minor.
- File: `app/services/redmine_depending_custom_fields/base_service.rb:84`.
- Problem: the storage refusal of a cascaded field the manager cannot see
  stored '(custom field #id)' in the summary the manager reads.
- Verdict: confirmed.
- Fix: `storage_error(violation, include_field:)` leaves the id out when the
  field is not nameable; column, bytes and limit stay.

Resolution: fixed in this commit.

### project-pages-8: one count per deactivated value

- Area: performance. Severity: minor.
- File: `app/services/redmine_depending_custom_fields/update_enumerations_service.rb:410`.
- Problem: `deactivated_usage` ran one capped COUNT per value.
- Verdict: confirmed.
- Fix: one capped count over all deactivated ids
  (`value_rows(...).limit(USAGE_CAP + 1).count`).

Resolution: fixed in this commit.

### project-pages-9: duplicated counts and child loads

- Area: performance. Severity: nit.
- File: `app/services/redmine_depending_custom_fields/usage_calculator.rb:26`.
- Problem: `usage_other` counted `usage_here` again, and the children were
  loaded three times per rename or removal.
- Verdict: confirmed.
- Fix: `UsageCalculator.usage_split` (two counts); `BaseService
  #dependent_children` loads the children once for the impact, the panel and
  the cascade (`parent_key_refs` and `affected_child_fields` take
  `children:`).

Resolution: fixed in this commit.

### project-pages-10: one project query per audit row

- Area: performance. Severity: nit.
- File: `app/views/dcf_config_audit/index.html.erb:25`.
- Problem: `event.project&.name` ran a query per row.
- Verdict: confirmed.
- Fix: `DcfConfigAuditController#index` reads the names of the page in one
  query.

Resolution: fixed in this commit.

### project-pages-11: a closed project is called archived

- Area: texts. Severity: nit.
- File: `app/services/redmine_depending_custom_fields/base_service.rb:116`.
- Problem: `error_project_archived` says archived for a closed project.
- Verdict: confirmed.
- Fix: the text says 'closed or archived' in en, de, fr and nl.

Resolution: fixed in this commit.

### project-pages-12: dead helpers and readers

- Area: dead code. Severity: nit.
- File: `app/helpers/project_custom_field_configuration_helper.rb:57`.
- Problem: `dcf_visible_project_names`, `dcf_icon` and the readers
  `ConfigAuditEvent#project`, `#custom_field`, `#acting_user` and
  `#affected_child_field_ids_list` have no caller.
- Verdict: confirmed.
- Fix: removed, with their examples and the locale key
  `label_n_other_projects` that only `dcf_visible_project_names` used.

Resolution: fixed in this commit.

## Issue form

### issue-form-1: physical margins in right-to-left languages

- Area: CSS. Severity: nit.
- File: `assets/stylesheets/depending_custom_fields.css:1`.
- Problem: `margin-left` and `margin-right` put the child indent and the
  wizard column gap on the wrong side in ar, fa and he.
- Verdict: confirmed.
- Fix: `margin-inline-start` and `margin-inline-end`;
  `spec/quality/stylesheet_direction_spec.rb` keeps physical properties out
  of the plugin stylesheets.

Resolution: fixed in this commit.

### issue-form-2: the record branch of possible_values_options

- Area: dead code. Severity: nit.
- File: `lib/redmine_depending_custom_fields/depending_format_methods.rb:59`.
- Problem: core 5.1 to 7.0 never pass an Issue, TimeEntry or Version here.
- Verdict: confirmed for core; the branch is the 0.0.15 behaviour of
  `CustomField#possible_values_options(record)` for other callers and is
  pinned by many examples.
- Fix: a comment states that core never reaches it and that it is kept for
  callers that pass a record, as the finding allows.

Resolution: not removed: the branch is public behaviour since 0.0.15 for
callers outside core; the comment is added in this commit.

### issue-form-3: data attributes no script reads

- Area: markup contract. Severity: nit.
- File: `lib/redmine_depending_custom_fields/client_data.rb:34`.
- Problem: `data-dcf-kind`, `data-dcf-multiple` and `data-dcf-blank` are not
  read by the runtime.
- Verdict: not a defect: the README Integration table documents
  `data-dcf-kind` and `data-dcf-multiple` as informational attributes for
  integrators and `data-dcf-blank` as the marker of the blank sentinel; the
  contract fixtures and the server specs pin them. Removing them would break
  that documented contract within 0.1.0.

Resolution: not a defect: documented integration contract (README,
Integration, Data attributes).

## Context menu

### context-menu-1: the value 'none' is saved as blank

- Area: wizard save. Severity: minor.
- File: `app/controllers/context_menu_wizard_controller.rb:131`.
- Problem: the literal 'none' was mapped to '' like core's '__none__'.
- Verdict: confirmed.
- Fix: only '__none__' clears (single, multiple and the legacy fieldId
  parameters).

Resolution: fixed in this commit.

### context-menu-2: wizard saves have no journal

- Area: wizard save. Severity: major.
- File: `app/controllers/context_menu_wizard_controller.rb:260`.
- Problem: no `init_journal`, so no history entry and no notification.
- Verdict: confirmed.
- Fix: `issue.init_journal(User.current)` before `safe_attributes=`, as core
  `bulk_update`.

Resolution: fixed in this commit.

### context-menu-3: tracker-specific edit permission ignored

- Area: permissions, UX. Severity: minor.
- File: `lib/redmine_depending_custom_fields/hooks/context_menu_hook.rb:13`.
- Problem: the entry and the body tested `allowed_to?(:edit_issues,
  project)`, while core's menu uses `attributes_editable?` (tracker
  permissions), so the save answered 403 afterwards.
- Verdict: confirmed.
- Fix: the hook and `ContextMenuWizardController#show` require
  `issue.attributes_editable?(user)` for every issue (false on a closed
  project, true for 'Edit own issues' on the author's issues, as core).

Resolution: fixed in this commit.

### context-menu-4: identical error lines without the issue

- Area: wizard UX. Severity: nit.
- File: `app/controllers/context_menu_wizard_controller.rb:262`.
- Problem: N failing issues gave N identical lines.
- Verdict: confirmed.
- Fix: each line is '#<id>: <message>', as core's bulk failure notice names
  the issues.

Resolution: fixed in this commit.

## Storage, API and boot

### storage-api-boot-1: the import loads every user per token

- Area: performance (imports). Severity: minor.
- File: `lib/redmine_depending_custom_fields/patches/issue_import_patch.rb:23`.
- Problem: `Principal.detect_by_keyword(User.all, keyword)` per token loaded
  every user and ran one mail query per user for a name.
- Verdict: confirmed (users queries grew with the number of users).
- Fix: `dcf_detect_user` uses login, mail, 'firstname lastname' and name
  indexes built once per import object from `User.preload(:email_address)`,
  with core's order and ASCII case rule; `spec/patches/issue_import_patch_spec.rb`
  now runs against real records.

Resolution: fixed in this commit.

### storage-api-boot-2: '42 Jane Roe' selects user 42

- Area: imports. Severity: minor.
- File: `lib/redmine_depending_custom_fields/patches/issue_import_patch.rb:24`.
- Problem: `String#to_i` read a number prefix as an id.
- Verdict: confirmed.
- Fix: the id fallback is used only for a plain number.

Resolution: fixed in this commit.

### storage-api-boot-3: validation builds every user option

- Area: performance. Severity: minor.
- File: `lib/redmine_depending_custom_fields/extended_user_format.rb:33`.
- Problem: core's RecordList validation built the whole option list per
  value.
- Verdict: confirmed.
- Fix: `ExtendedUserFormat#validate_custom_value` checks the submitted ids
  with one query on the field's filter and keeps an existing stored user
  (core's value_was rule); a group marker or a non-numeric value is refused
  with core's message.

Resolution: fixed in this commit.

### storage-api-boot-4: users the viewer may not see

- Area: security. Severity: minor.
- File: `lib/redmine_depending_custom_fields/extended_user_format.rb:106`.
- Problem: the options, the filter values and the validation used every
  user, ignoring the role setting 'Users visibility'.
- Verdict: confirmed.
- Fix: for a viewer who is not an administrator, `filtered_users` keeps only
  `Principal.visible(viewer)` without its active-only rule, so the field's own
  status options still decide; a stored value is kept.

Resolution: fixed in this commit.

### storage-api-boot-5: a field without show_active lists nobody

- Area: API. Severity: minor.
- File: `lib/redmine_depending_custom_fields/extended_user_format.rb:98`.
- Problem: a missing show_active was stored as false. The second reading
  corrected the claim: a saved field's form shows the stored false; the
  defect is the API default.
- Verdict: confirmed as corrected.
- Fix: a missing show_active counts and is stored as true; an explicit false
  stays.

Resolution: fixed in this commit.

### storage-api-boot-6: blocks that never run and unused methods

- Area: dead code. Severity: nit.
- File: `lib/redmine_depending_custom_fields.rb:23`.
- Problem: core `FieldFormat.add` takes no block; `validate_single_value`,
  `value_to_s` and `cast_single_value` of ExtendedUserFormat are not used or
  duplicate RecordList.
- Verdict: confirmed.
- Fix: the blocks and the three methods are removed; `register_formats` keeps
  re-registering the same instances (used at init and by specs).

Resolution: fixed in this commit.

## Evidence

All runs on PostgreSQL with the prepared checkouts of `.codex` (logs in
`$DCF_WORK_DIR/logs`).

- Red first, against the unchanged production code (the new spec files and
  the existing examples changed to the new behaviour): 7.0
  `7.0-rspec-subset-20261105-124907`, `500 examples, 43 failures`, every
  failure the expected one (for example rules-1 'is invalid' under the hidden
  version child, rules-3 900 enumeration rows instantiated, project-pages-1
  the hidden parent's name in the body, context-menu-2 no journal); 5.1
  `5.1-rspec-subset-20261105-124419` for rules-2 (the visible time entry
  child refused under the dropped hidden parent; green on 7.0 before the fix,
  as expected). JS: the new editor test failed on the unchanged editor
  ('same select after a tick'). System: the new toolbar assertion failed in
  Chromium on 7.0 without the CSS rule (`7.0-system-20261105-133739`, `1
  example, 1 failure`: the toolbar 'Filter parent values, Only parent values
  without links, Collapse all' was visible).
- After the change: `.codex/test_matrix.sh --suite rspec --suite js --suite
  lint`: `version=5.1 exit=0 suite=rspec exit=0 2842 examples, 0 failures
  suite=js exit=0 # pass 577 # fail 0`, the same on 6.0, 6.1 and 7.0 (seeds
  59189, 48138, 2988, 1710; logs `5.1-rspec-20261105-134140`,
  `6.0-rspec-20261105-135301`, `6.1-rspec-20261105-140701`,
  `7.0-rspec-20261105-142059`), `lint exit=0 SYNTAX PASS COMPAT PASS RATCHET
  PASS files=175 base_offenses=129 head_offenses=92 fixed=29`. The sha256 of
  the diff plus the status was the same before and after the matrix
  (`e3d70ab1...`); this report's evidence section was written afterwards.
  `npm run check`: 'ok ES2017' for the six assets. System specs
  (`.codex/test_plugin.sh <v> --suite system`): 7.0 `29 examples, 0
  failures` (`7.0-system-20261105-133804`), 5.1 `29 examples, 0 failures`
  (`5.1-system-20261105-133948`). rspec grew from 2794 to 2842 examples, JS
  from 576 to 577 tests.
- Mutation checks (each file copied to the scratchpad, mutated, the matching
  new spec file run, the file restored from the copy and its sha256
  checked, all 'OK'): rules-1 (no prepend) 7.0 `18 examples, 3 failures`;
  rules-2 (dropped parent ignored) 5.1 `18 examples, 2 failures`; rules-3 (no
  narrowed enumeration lookup) `1 failure`; rules-4 (split on ';' and ',')
  `2 failures`; rules-5 (no copy source) `1 failure`; rules-6 (no carries?
  guard) `1 failure`; admin-editor-3 (copy keeps links) `1 failure`;
  project-pages-1 (parent always nameable) `14 examples, 2 failures`;
  project-pages-6 (relevant? again) `1 failure`; project-pages-2 (default
  kept) `2 failures`; project-pages-3 (enumerations loaded in the overview)
  `1 failure`; project-pages-4 (no 60-character check) `1 failure`;
  project-pages-5 (raw list compared) `1 failure`; project-pages-7 (id kept)
  `1 failure`; project-pages-8 (one count per id) `1 failure`;
  project-pages-9 (children loaded per call) `1 failure`; project-pages-10
  (lookup per row) `1 failure`; project-pages-11 (old text) `1 failure`;
  context-menu-1 ('none' mapped to blank) `5 examples, 1 failure`;
  context-menu-2 (no init_journal) `1 failure`; context-menu-3 (allowed_to?
  again) `1 failure`; context-menu-4 (no issue number) `1 failure`;
  storage-api-boot-1 (detect over User.all per token) `8 examples, 1
  failure`; storage-api-boot-2 (number prefix as id) `1 failure`;
  storage-api-boot-3 (validation override removed) first `0 failures`: the
  example ran as the anonymous user, whose Users visibility already kept the
  list small; the example now runs as an administrator and the same mutation
  gives `1 failure` (`7.0-rspec-subset-20261105-133654`); storage-api-boot-4
  (no visibility rule) `1 failure`; storage-api-boot-5 (nil as false) `1
  failure`; issue-form-1 (margin-left again) `4 examples, 1 failure`;
  admin-editor-1 (no [hidden] rule) `1 failure`, and in Chromium as above;
  admin-editor-2 (select rebuilt per click) `node --test
  test/js/dcf_dependency_editor.test.js`: `tests 64, pass 63, fail 1`.
- G9 (a `python3 -I` script): the Unreleased lines equal the section 3 lines
  of 0.1.0 (88 each, no duplicate) and their order is the stable partition by
  group (15, 36, 22, 2, 3, 4, 1, 5); no internal id in the Unreleased
  section; the eleven new lines are quoted by PC-81 to PC-91 and the edited
  upgrade note by PC-65; no en or em dash in README.md, CHANGELOG.md or this
  report. `locale_parity_spec` and `no_dash_spec` are green in the matrix.
- Logs: after the runs `log/test.log` of the four checkouts (5.1, 6.0, 6.1,
  7.0) under the work directory was truncated to 0 bytes.
- Not done here: seeds beyond the matrix's random seeds, MariaDB, and the
  owner's own verification (the commit title says so).
