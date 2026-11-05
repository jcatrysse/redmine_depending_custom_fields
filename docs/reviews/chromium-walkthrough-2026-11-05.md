# Chromium walkthrough of 2026-11-05: confirmed findings and fixes

Branch `claude/festive-noether-2y8x7c`, base of the fixes `84d3d68` (the
commit of the full branch review, docs/reviews/claude-full-review-2026-11-05.md).
A Playwright walkthrough in Chromium on Redmine 5.1 and 7.0 (development
servers on PostgreSQL, a seeded data set with role-restricted fields, large
lists and legacy values) produced 22 findings; a second reading confirmed
them and the owner approved the scope below. Each entry gives the finding,
the versions, the verdict and a `Resolution:` line. User-visible changes
have a CHANGELOG line, the same line in section 3 of
`docs/specs/large_lists_work_packages.md` (end of the M3 list) and a PC row
in `docs/specs/large_lists_compatibility.md` (PC-92 to PC-102; PC-86
changed). New locale keys are in `docs/specs/large_lists_i18n_registry.md`.

New examples are in `spec/requests/dcf_walkthrough_fixes_spec.rb`,
`test/js/runtime_walkthrough.test.js` and a new test in
`test/js/dcf_dependency_editor.test.js`; existing examples that pinned the
old behaviour carry a 'Changed by the Chromium walkthrough of 2026-11-05'
note.

## Project configuration pages

### admin-1: a permission holder sees fields hidden for the role

- Versions: 5.1 and 7.0. Severity: major (privacy).
- Problem: with the permission 'Manage custom fields' given to a role that
  may not see Secret Code and Clearance (role-restricted fields), the
  project Settings tab listed both fields with links, their values pages and
  the dependency page of Secret Code rendered every value in editable
  inputs, and the update actions accepted changes.
- Reproduced at `84d3d68` with the walkthrough scenario `permissions`
  (step 'hard-rule-permission-holder-without-visibility', the Developer role
  given the permission) on both versions: the Settings tab, the overview,
  `fields/9`, `fields/9/dependencies` and `fields/10` answered 200 with the
  hidden names and values. The dependency page of the visible child Access
  Area no longer named its hidden parent Clearance: that part was fixed by
  the full review commit (project-pages-1).
- Fix: one rule for a field on its own, `UsageCalculator.nameable?`
  (administrator, or used in the project and visible for the role; the rule
  of `nameable_child?`, which now delegates to it). The Settings tab lists
  only such fields (`FieldRelevance.relevant_fields(project, user:)`); the
  controller's `find_field` answers 404 with the unknown-field text for any
  other field on the values page, the dependency page and every update
  action; `BaseService#preamble!` refuses it the same way (defense in
  depth); the project audit page leaves out the rows of such fields and of
  deleted fields for a user who is not an administrator. A visible child of
  a hidden parent keeps the generic parent text of the full review and gets
  no parent values.

Resolution: fixed in this commit (the hidden parent of a visible child was
fixed by the full review commit).

### admin-2: the storage refusal does not explain the limit

- Versions: 5.1 and 7.0. Severity: nit.
- Problem: under a project ceiling of 64 KiB, adding a value to a field of
  275,004 bytes gave 'at most 275,004 bytes can be stored for this field',
  the field's own size, without saying why.
- Fix: a refusal by the project ceiling (violation source `ceiling`) uses
  the new keys `error_dcf_values_over_ceiling` and
  `error_dcf_mapping_over_ceiling` (en, de, fr, nl): both sizes stay, and
  the text names the configured size in KiB and says that a field already
  larger may keep its size but not grow. A column limit (MySQL and MariaDB)
  keeps the old texts.

Resolution: fixed in this commit.

### admin-3: confirmation panels answer 422 or 409

Resolution: not a defect: confirmation panels and conflicts answer 422 or
409 on purpose so an unsaved form is never reported as a success to
non-JavaScript clients and API callers; the console line is the browser's
normal report of that status.

### admin-4, ux-6: parentheses in subtitles, the Value column and the drag note

- Versions: 5.1 and 7.0. Severity: nit.
- Problem: 'Part (List (depending))' and '(Edit dependencies)' as
  subtitles; the Value header and inputs centred with a wide gap before the
  Delete button; a drag note on a table without a handle column.
- Fix: the subtitles show the format and the page name without
  parentheses; the handle column is rendered only when drag and drop is
  offered; the Value column and the audit cells start at the cell start
  (`dcf_config.css`); the drag note is ux-15.

Resolution: fixed in this commit.

### ux-3: raw keys and developer text in the audit logs

- Versions: 5.1 and 7.0. Severity: minor.
- Problem: the Action and Status columns showed `validation_failed`,
  `sort_values` and similar keys; the Summary of a refusal showed
  `error_stale_edit` or 'possible_values: 275014 bytes exceeds 275004
  (custom field #18)'.
- Fix: both audit pages translate at render time (stored rows unchanged):
  `label_dcf_audit_action_*` and `label_dcf_audit_status_*` (en, de, fr,
  nl); a refusal shows the text of its stored error key, a storage refusal
  the new `text_dcf_audit_values_too_large` or
  `text_dcf_audit_mapping_too_large` with both sizes read from the stored
  summary and no field name (the field over its size may be a dependent
  field the viewer may not see). An unknown action, status or raw message is
  shown as stored. Success summaries are shown as stored: they are sentences
  about the field's own values. Hidden fields: admin-1.

Resolution: fixed in this commit.

### ux-5: counts without thousands separators

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: the Settings tab project and value counts and the filter line of the
  values page use `number_with_delimiter`. The pager '(1-25/25000)' is
  core's `pagination_links_full`, which prints the raw count on every core
  list too, and is left unchanged.

Resolution: fixed in this commit for the Settings tab and the filter line;
not changed for the pager (core markup, the same on core's issue list).

### ux-14: the confirmation panel looks like an error

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: the heading is the first line of the flash box, beside the warning
  icon (no empty first row); the box keeps core's warning background and
  icon and uses the page's text color (`.dcf-confirm-panel > .flash.warning
  { color: inherit }`), so it reads as a question, not as an error.

Resolution: fixed in this commit.

### ux-15: the drag note above 500 values

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: `text_dcf_drag_reorder_large` says that drag and drop is not
  available for fields with more than %{max} values (en, de, fr, nl) and is
  not shown on an empty match; the two sort buttons form one group with
  core's `label_sort` as its accessible name.

Resolution: fixed in this commit.

## Dependency editor

### ux-4: a large section opens on unrelated child values

- Versions: 5.1 and 7.0. Severity: minor.
- Problem: opening A123 ('50 of 25,000 linked') showed the first 200 child
  values of 'All child values', all unchecked.
- Fix: a section opens in the 'Linked' view when its parent value has links
  and the child list is longer than one row page (200); otherwise in 'All
  child values'. The check and uncheck buttons form one group, so on 7.0
  they wrap together instead of leaving 'Uncheck all shown' alone on a
  second line (the toolbar is a wrapping flex row of the plugin CSS).

Resolution: fixed in this commit.

## Issue forms, bulk edit and the context-menu wizard

### issue-1, ux-2: the wizard refusal repeats messages

- Versions: 5.1 and 7.0. Severity: minor.
- Check of the full review fix (context-menu-4): at `84d3d68` the alert
  listed one '#<id>: <message>' line per issue and message, so two issues
  gave six lines.
- Fix: one line per message with the issue numbers, as core's bulk edit
  (`bulk_edit_error_messages`): 'City is invalid: #41, #42', no duplicates.
  The alert stays the feedback (unchanged).

Resolution: fixed in this commit.

### issue-2, ux-13: wizard panel layout

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: more space between a field and the next one and under a hint; the
  field name is bold as core's bulk edit labels and has a title (and core's
  dotted underline) only when the field has a description. The columns stay
  one per level of the hierarchy: balancing them would mix levels, which is
  not a small CSS change.

Resolution: fixed in this commit for the spacing and the labels; columns
not rebalanced (they show the levels by design).

### issue-3: humanized names and a reset forced value

Resolution: not a defect: humanized field names are core Redmine; a forced
invalid value is not kept on re-render by design and the error names the
field.

### ux-1: no submenu arrow on 7.0

- Versions: 7.0 (6.0 and 6.1 alike). Severity: minor.
- Fix: the entry carries core's `span.icon-only` with `sprite_icon('angle-right',
  rtl: true)` after `a.submenu` when `sprite_icon` exists (6.0 and later);
  5.1 is unchanged (core draws the arrow by CSS there). The markup fixture
  `wizard_entry` has a 5.1 variant.

Resolution: fixed in this commit.

### ux-7: hints left of the indented control

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: the runtime marks the hint of a dependent control (`.depending-child`)
  with `dcf-hint--child`, and the stylesheet gives it the indent of the
  control (`margin-inline-start: 20px`), on the issue form, in bulk edit and
  in the wizard.

Resolution: fixed in this commit.

### ux-8: 'is invalid' for a kept disallowed value

Resolution: not fixed: the owner decision UD-10 keeps the core behaviour and
its 'is invalid' message for a kept disallowed value; a dedicated message is
an owner option. The claim that the Germany case cannot be saved is wrong:
the walkthrough saved issues with a blank required Postal Zone under Germany
on both versions.

### ux-9: the privacy-safe refusal has no next step

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: both texts (after the parent field name, and the general one) end
  with 'Keep the current value(s), or ask someone who can see all fields to
  make this change' in en, de, fr and nl; still no field name.

Resolution: fixed in this commit.

### ux-10: a required field whose parent value allows nothing

- Versions: 5.1 and 7.0. Severity: minor.
- Verified first: the walkthrough saved issues with a blank required Postal
  Zone under Germany on both versions (issue-new step 'two-level chain with
  Germany (no City) saves without City': 5.1 issue #37, 7.0 issue #35, City
  and Postal Zone blank), as UD-10 says.
- Fix: the hint of a field whose row label carries core's required marker
  reads 'No values are available for the selected %{parent}, so this
  required field stays empty and the form can still be saved.' (new key
  `text_dcf_hint_no_options_required`, JS `noOptionsRequired`); optional
  fields keep their text.

Resolution: fixed in this commit.

### ux-11: a default replaces a posted blank after a refused save

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: core puts its error box (`div#errorExplanation`, error_messages_for)
  inside the form of a page shown again after a refused save. On such a
  form the first pass of the runtime keeps a blank dependent field of a new
  record instead of applying the per-parent default; a fresh form keeps
  applying defaults, and a parent change on the shown-again form applies the
  default of the new parent value.

Resolution: fixed in this commit.

### ux-12: the wizard load error gives no way out

- Versions: 5.1 and 7.0. Severity: nit.
- Fix: 'The wizard could not be loaded. Click the entry again to try again.'
  (en, de, fr, nl, and the English fallbacks of both scripts).

Resolution: fixed in this commit.

## Evidence

All runs on PostgreSQL with the prepared checkouts of `.codex` (logs in
`$DCF_WORK_DIR/logs`) and, for the browser, the walkthrough servers b51
(Redmine 5.1) and b70 (Redmine 7.0) with the plugin copied from the working
tree and the data set seeded again.

- Reproduction at `84d3d68` (admin-1): the walkthrough scenario
  `permissions` failed on both versions in step
  'hard-rule-permission-holder-without-visibility' ('HARD RULE: ... contains
  ["Secret Code","Clearance"] ... fields/9 (HTTP 200) contains ["Secret
  Code","Zulu-7731",...]').
- Red first, against the unchanged production code (`84d3d68` with the new
  and changed tests): rspec 7.0 `7.0-rspec-subset-20261105-145201`, `62
  examples, 16 failures`, and on an unchanged copy of `84d3d68`
  `7.0-rspec-subset-20261105-145332`, `16 examples, 14 failures`, every
  failure the expected one (for example admin-1 'expected ... not to include
  Secret-...' on the Settings tab and 200 instead of 404 on the pages,
  issue-1 'got: ["#41214: Sub-07ce29 is invalid", "#41214: Other-52d7ce is
  invalid", ...]', ux-3 'Translation missing: en.label_dcf_audit_action_...',
  ux-6 'got: "(List (depending))"', ux-14 'got: ["p", ...]', ux-1 no
  span.icon-only after a.submenu); the two examples that passed were the
  administrator case and the hidden parent of a visible child, fixed by the
  full review commit. JS: `node --test test/js/runtime_walkthrough.test.js`
  `tests 5, pass 1, fail 4` (ux-7, ux-10 twice, ux-11) and `node --test
  test/js/dcf_dependency_editor.test.js` `tests 65, pass 64, fail 1` (ux-4).
- After the change: `.codex/test_matrix.sh --suite rspec --suite js --suite
  lint`: `version=5.1 exit=0 suite=rspec exit=0 2858 examples, 0 failures
  suite=js exit=0 # pass 583 # fail 0`, the same on 6.0, 6.1 and 7.0 (seeds
  29804, 11285, 47489, 13626; logs `5.1-rspec-20261105-162324`,
  `6.0-rspec-20261105-163342`, `6.1-rspec-20261105-164626`,
  `7.0-rspec-20261105-165833`), `lint exit=0 SYNTAX PASS COMPAT PASS
  RATCHET PASS files=176 base_offenses=129 head_offenses=92 fixed=29`. A
  first matrix run found two expectations of the new spec that hard-coded
  the comma delimiter (Redmine 5.1 en has none) and three lint offenses in
  it; the spec was corrected and the whole matrix run again (the results
  above). The sha256 of the diff (this report left out) plus the status and
  the new files was the same before and after that run (`0c01a43e...`).
  `npm run check`: 'ok ES2017' for the six assets. System specs
  (`.codex/test_plugin.sh <v> --suite system`): 7.0 `29 examples, 0
  failures` (`7.0-system-20261105-171209`), 5.1 `29 examples, 0 failures`
  (`5.1-system-20261105-171345`). rspec grew from 2842 to 2858 examples, JS
  from 577 to 583 tests. The markup fixtures `wizard_entry` and
  `wizard_body` and the four head fixtures were written again on 7.0 and
  5.1 (`DCF_WRITE_JS_FIXTURES=1`, new 5.1 variant of `wizard_entry`) and
  compared on 6.0 and 6.1 (`69 examples, 0 failures`).
- Mutation checks (each file copied to the scratchpad, mutated, the
  matching spec run on 7.0 or the JS test run, the file restored from the
  copy and its sha256 checked, all restored): admin-1 controller without
  the visibility check `16 examples, 1 failure` ('answers 404 on its pages
  and on every update action'); relevant_fields without the user filter `1
  failure` ('is not listed on the settings tab'); audit page without the
  row filter `1 failure` ('keeps its audit rows off the project audit
  page'); service preamble without the check `1 failure` ('is refused by
  the services as well'); issue-1 lines per issue again `21 examples, 2
  failures`; ux-3 raw action `1 failure` and raw summary `1 failure`;
  admin-2 ceiling never recognised `1 failure`; ux-1 no arrow `1 example, 1
  failure`; ux-15 note also on an empty match `1 failure`; admin-4 handle
  cell always rendered `1 failure`; ux-5 raw count `1 failure`; ux-4 view
  always 'all' `tests 65, pass 64, fail 1`; ux-7 no hint class `tests 5,
  pass 4, fail 1`; ux-10 no required text `tests 5, pass 3, fail 2`; ux-11
  defaults on an errored form `tests 5, pass 4, fail 1`.
- Browser, after the change, on 5.1 and 7.0 (scripts and screenshots in the
  walkthrough scratch space, not in the repository): `permissions` `pass 6
  fail 0` on both (fields/9 and fields/10 and their dependency pages 404,
  no hidden name on the Settings tab, the overview and the audit page; the
  Country rename panel heading beside its icon, in the text color);
  `context-wizard` `pass 14 fail 0` (alert 'City is invalid: #61, #62
  Languages is invalid: #61, #62 Postal zone is invalid: #61, #62', the
  load error with its retry sentence, the arrow on the 7.0 entries, the
  hints under the indented selects, bold names); `issue-new` `pass 17 fail
  0` (the required Postal Zone under Germany with the new hint, the blank
  Postal Zone kept after 'Postal zone cannot be blank', an issue saved under
  Germany with City and Postal Zone blank); `privacy` `pass 28 fail 0` (the
  refusals with the next step on the edit form, REST, bulk edit and the
  wizard); `bulk-edit` `pass 11 fail 0`; `project-values` `pass 13 fail 0`
  (translated audit table, 'A list of values would take 275,014 bytes, but
  at most 275,004 bytes can be stored.', the ceiling refusal naming 64 KiB,
  'Part ... 25,000' on the Settings tab); `large-list` `pass 10 fail 0`
  (A123 opens on its 50 linked values, the two buttons on one line, the
  drag note not on an empty match, no empty handle column, subtitles
  without parentheses); `project-dependency` `pass 12 fail 0`.
- G9 (a `python3 -I` script): the Unreleased lines equal the section 3
  lines of 0.1.0 (99 each, no duplicate) and their order is the stable
  partition by group (15, 39, 29, 2, 3, 5, 1, 5); no internal id in the
  Unreleased section; every 0.1.0 PC row quote is an Unreleased line and
  every Unreleased line is quoted (PC-92 to PC-102 for the eleven new
  lines, PC-86 for the changed one); no en or em dash in README.md,
  CHANGELOG.md or the added lines. `locale_parity_spec` and `no_dash_spec`
  are green in the matrix.
- Logs: after the runs `log/test.log` of the four checkouts (5.1, 6.0, 6.1,
  7.0) under the work directory was truncated to 0 bytes. The walkthrough
  servers were stopped.
- Not done here: MariaDB, seeds beyond the matrix's random seeds, and the
  owner's own verification (the commit title says so).
