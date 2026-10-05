# Large lists: decision register
> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 to 9. Owner area: delivery (cross-area). Work packages: all. Decisions: UD-01 to UD-34.

## Purpose

This register lists the decisions the owner must confirm, each with a recommendation. It also records where the plan deviates from the default decisions D1 to D10 it started from, and the design decisions each area took. Section 4 groups the open decisions by the release they block, so the owner only has to answer what the next release needs.

## Contents

1. Owner decisions UD-01 to UD-34
2. Deviations from the default decisions D1 to D10
3. Area design decisions
4. Which decisions block which release

## 1. Owner decisions

| UD | Status | First release | Work packages | Question |
|---|---|---|---|---|
| UD-01 | Resolved | 0.0.16 | WP-07, WP-14, WP-20, WP-32 | (Owner: one release, see detail) Release structure and deprecation targets: ship in four releases (0.0.16 foundation and hotfixes, 0.1.0 (M1) server rules and storage safety, 0.1.0 (M2) issue-form runtime, 0.1.0 (M3) editors and project pages) instead of one 0.1.0 (M1) as assumed by the area designs? |
| UD-02 | Resolved | 0.0.16 | WP-03 | Ship two hotfixes in the legacy code in 0.0.16 (remove delete_matched; fix the #bulk-edit-form selector) before the rewrite? |
| UD-03 | Resolved | 0.0.16 | WP-07, WP-20 | When does the separately tracked wizard-save security fix (SD-01) ship? |
| UD-04 | Open | 0.1.0 (M1) | WP-09, WP-17 | D1 per value: while the parent is unchanged, tolerate every value already stored and validate only newly added values (deviation from the whole-set wording of D1)? |
| UD-05 | Open | 0.1.0 (M1) | WP-09, WP-17 | Accept an untouched stored child when its parent field is not available on the record (for example not enabled for the tracker)? |
| UD-06 | Open | 0.1.0 (M1) | WP-09, WP-16 | Judge issue copies (single, bulk, project copy) against the source issue so unchanged legacy combinations are copied? |
| UD-07 | Open | 0.1.0 (M1) | WP-09 | Never reject an unchanged dependent field that the current user cannot edit when its parent changes? |
| UD-08 | Open | 0.1.0 (M1) | WP-10, WP-16 | Fields in or below a stored cycle: treat them as unconstrained on server and client until fixed, and run the cycle check only when a persisted field's parent id changes (D9 refinement)? |
| UD-09 | Open | 0.1.0 (M2) | WP-17, WP-20 | Bulk edit and wizard (deviation from D2): keep '(No change)' visible and selectable on descendants when a concrete parent is chosen, preselect the per-parent default with a hint, and force '(none)' only for parent '(none)' or a parent value without links? |
| UD-10 | Open | 0.1.0 (M2) | WP-17, WP-19 | Offer a marked '(none)' option for REQUIRED managed children in bulk edit and the wizard, enabled only while the parent selection allows no value? |
| UD-11 | Open | 0.1.0 (M2) | WP-18, WP-20 | Open every wizard field, including the root, on '(No change)' (deviation from D4 'otherwise unchanged')? |
| UD-12 | Open | 0.1.0 (M2) | WP-17 | Apply per-parent defaults at page load only to new records (always on parent changes)? |
| UD-13 | Open | 0.1.0 (M2) | WP-18 | Context menu size: keep the wizard template inline (with a 512 KB S1 budget asserted by spec) rather than loading the wizard body lazily? |
| UD-14 | Open | 0.1.0 (M2) | WP-15, WP-18 | Delete MappingBuilder, ParentMenuBuilder and the after_custom_field_save dispatch outright (D5) instead of uncached deprecated shims? |
| UD-15 | Open | 0.1.0 (M3) | WP-22 | Keep the admin safe attributes value_dependencies and default_value_dependencies permanently (deviation from D5's one-minor-version window)? |
| UD-16 | Open | 0.1.0 (M3) | WP-25, WP-27 | Editors require JavaScript (admin: mapping unchanged on save without JS; project: Save disabled) and the admin form switches to multipart/form-data while the editor is active? |
| UD-17 | Open | 0.1.0 (M3) | WP-22, WP-25, WP-27 | Keep the admin lost-update guard with the conflict panel (use mine, keep current, export mine) and defer a three-way merge? |
| UD-18 | Open | 0.1.0 (M3) | WP-26 | Spreadsheet formula protection on CSV export? |
| UD-19 | Open | 0.1.0 (M3) | WP-26 | Enumeration import matches by name only (D7) in this release? |
| UD-20 | Open | 0.1.0 (M3) | WP-25 | Editor page sizes: 100 parent sections and 200 child rows per 'Show more'? |
| UD-21 | Open | 0.1.0 (M3) | WP-28 | Values page: paginate only above 500 values; drag-and-drop only for unfiltered lists of at most 500 values? |
| UD-22 | Open | 0.1.0 (M3) | WP-31 | Project storage ceiling (SP-03): plugin setting project_storage_ceiling_kib default 2,048, minimum 64, applied to all project-page writes, never blocking writes that do not grow a field; plus a 255-character cap for list values added or renamed in project settings? |
| UD-23 | Open | 0.1.0 (M3) | WP-27, WP-29 | Shared/global fields: no server-side confirmation panel for dependency saves (including replace imports) and sort; only the scope banner and a JS confirm for sort? |
| UD-24 | Open | 0.1.0 (M3) | WP-29 | Sort inactive enumerations together with active ones (not pushed to the end)? |
| UD-25 | Open | 0.1.0 (M1) | WP-11 | Apply the MySQL size validation also to core List and Key/Value list fields? |
| UD-26 | Open | 0.1.0 (M1) | WP-13 | Default type for widen_core_columns? |
| UD-27 | Open | 0.1.0 (M1) | WP-13 | MySQL testing: add an optional manual (workflow_dispatch only) MariaDB workflow in addition to the :mysql-tagged specs and the documented local recipe? |
| UD-28 | Open | 0.1.0 (M1) | WP-11 | Show the storage usage line at 90 percent of the column limit on the core admin custom field form (view_custom_fields_form_upper_box hook) and project pages? |
| UD-29 | Resolved | 0.0.16 | WP-01 | Approve the committed .rubocop.yml overlay (TargetRubyVersion 2.7, TargetRailsVersion 6.1, Rails/HttpStatusNameConsistency disabled) as the ratchet configuration (deviation from raw core config in D10)? |
| UD-30 | Resolved | 0.0.16 | WP-01, WP-17 | Approve devDependencies jquery 3.7.1 and acorn ~8.18.0 in addition to jsdom ~29.1.1 (D10 named only jsdom)? |
| UD-31 | Resolved | 0.0.16 | WP-01 | rspec-61.yml: clone source and Ruby version? |
| UD-32 | Resolved | 0.0.16 | WP-01, WP-07 | May Claude dispatch the manual workflows? |
| UD-33 | Resolved | 0.0.16 | WP-01 | One-time local prerequisite: may the PostgreSQL role redmine/redmine with CREATEDB be created on developer machines (the scripts never do it themselves)? |
| UD-34 | Resolved | 0.0.16 | WP-01, WP-07 | Keep requires_redmine 5.0 while testing only 5.1 to 7.0, documenting Ruby 2.7 or newer? |

### UD-01

**Status: Resolved by the owner (deviates from the recommendation).** The owner chose one release for the renewal instead of four. Applied as: 0.0.16 stays a small patch release with WP-01, WP-02, WP-03 and WP-07, because UD-02 asks for the hotfixes right away; the separate SD-01 pull request lands before it (UD-03). Every other work package ships together in one release 0.1.0, built in three internal milestones: M1 (WP-04 to WP-06, WP-08 to WP-14), M2 (WP-15 to WP-20), M3 (WP-21 to WP-32). WP-14 and WP-20 become milestone checkpoints with a full evidence run but no version bump and no tag; WP-32 tags 0.1.0. Work packages stay small pull requests. Deprecations: deprecated in 0.1.0, kept throughout 0.1.x, removable no earlier than 0.2.0.

**Question.** Release structure and deprecation targets: ship in four releases (0.0.16 foundation and hotfixes, 0.1.0 (M1) server rules and storage safety, 0.1.0 (M2) issue-form runtime, 0.1.0 (M3) editors and project pages) instead of one 0.1.0 (M1) as assumed by the area designs?

**Recommendation.** Four releases. Deprecations: JS shims and CustomFieldVisibility deprecated in 0.1.0 (removable no earlier than 0.2.0); project nested params deprecated in 0.1.0 (removable no earlier than 0.2.0).

**Alternatives.** One 0.1.0 (M1) containing everything (designs' version targets 'removed no earlier than 0.2.0' unchanged), or 0.1.0 (M1) + 0.1.0 (M2) only.

**Impact.** Smaller, reviewable release units; each minor bump marks one class of behaviour change. CHANGELOG version targets in WP-20 and WP-32 follow this choice.

**Work packages.** WP-07, WP-14, WP-20, WP-32

### UD-02

**Status: Resolved by the owner (recommendation accepted).** Both hotfixes ship in 0.0.16 (WP-03).

**Question.** Ship two hotfixes in the legacy code in 0.0.16 (remove delete_matched; fix the #bulk-edit-form selector) before the rewrite?

**Recommendation.** Yes. Both are one-line edits; jsdom harness evidence shows the selector fix only removes the empty-array post of untouched multi children (planning scratch space, design/delivery).

**Alternatives.** Wait for 0.1.0 (M2), leaving MemCacheStore saves failing and bulk edit wiping multi-value children until then.

**Impact.** WP-03; users get the data-loss and crash fixes months earlier.

**Work packages.** WP-03

### UD-03

**Status: Resolved by the owner (recommendation accepted).** The wizard-save security fix is its own small pull request outside the plan, merged before 0.0.16 is tagged. Only the minimal fix (write only fields the user may edit); the journal and notification hardening stays SD-02.

**Question.** When does the separately tracked wizard-save security fix (SD-01) ship?

**Recommendation.** As its own PR merged before tagging 0.0.16; hard deadline: no 0.1.0 (M2) tag without it.

**Alternatives.** Together with 0.1.0 (M2) (point 1 touches the same controller), or later.

**Impact.** Closes a privilege issue (writing read-only and role-hidden fields) as early as possible; independent of all WPs.

**Work packages.** WP-07, WP-20

### UD-04

**Question.** D1 per value: while the parent is unchanged, tolerate every value already stored and validate only newly added values (deviation from the whole-set wording of D1)?

**Recommendation.** Per value (matches core ListFormat's value_was idiom).

**Alternatives.** Whole-set D1: any edit of a multi-value child that holds a legacy value is rejected.

**Impact.** WP-09 server rule and WP-17 client rule; with whole-set D1 users cannot add an allowed value next to a legacy one.

**Work packages.** WP-09, WP-17

### UD-05

**Question.** Accept an untouched stored child when its parent field is not available on the record (for example not enabled for the tracker)?

**Recommendation.** Accept (counts as an unchanged parent).

**Alternatives.** Keep forcing it blank as today (one-line switch in DependencyRules.dependency_check).

**Impact.** WP-09; affects tracker changes and the client 'parent unavailable' state in WP-17.

**Work packages.** WP-09, WP-17

### UD-06

**Question.** Judge issue copies (single, bulk, project copy) against the source issue so unchanged legacy combinations are copied?

**Recommendation.** Yes (fixes project copy silently skipping issues); data-dcf-stored carries the copy baseline so the browser behaves the same.

**Alternatives.** Keep new records strict (project copy keeps dropping those issues).

**Impact.** WP-09 and WP-16; relies on core's @copied_from ivar, pinned by a spec on all versions.

**Work packages.** WP-09, WP-16

### UD-07

**Question.** Never reject an unchanged dependent field that the current user cannot edit when its parent changes?

**Recommendation.** Yes.

**Alternatives.** Keep rejecting; the parent then stays effectively uneditable for that role.

**Impact.** WP-09.

**Work packages.** WP-09

### UD-08

**Question.** Fields in or below a stored cycle: treat them as unconstrained on server and client until fixed, and run the cycle check only when a persisted field's parent id changes (D9 refinement)?

**Recommendation.** Yes to both.

**Alternatives.** Keep validating cycle members per mapping (client must then filter them too); run the check whenever a parent is present (blocks unrelated saves of stored-cycle members).

**Impact.** WP-10 validation and the WP-16 emission rule (no parent attributes on cycle members).

**Work packages.** WP-10, WP-16

### UD-09

**Question.** Bulk edit and wizard (deviation from D2): keep '(No change)' visible and selectable on descendants when a concrete parent is chosen, preselect the per-parent default with a hint, and force '(none)' only for parent '(none)' or a parent value without links?

**Recommendation.** Revised D2. Concrete reason: the literal D2 clears still-valid values on every selected issue (setting Country on 50 issues would wipe City where it is still valid), which breaks existing users.

**Alternatives.** Literal D2 / README promise: hide '(No change)' and force default or '(none)'.

**Impact.** WP-17 runtime, WP-20 README rewrite, PC-28.

**Work packages.** WP-17, WP-20

### UD-10

**Question.** Offer a marked '(none)' option for REQUIRED managed children in bulk edit and the wizard, enabled only while the parent selection allows no value?

**Recommendation.** Adopt (server still rejects blank per issue when options exist).

**Alternatives.** Keep core behaviour and document that clear-on-(none) does not apply to required children.

**Impact.** WP-19; without it parent '(none)' leaves required descendants stale and every issue fails.

**Work packages.** WP-17, WP-19

### UD-11

**Question.** Open every wizard field, including the root, on '(No change)' (deviation from D4 'otherwise unchanged')?

**Recommendation.** Yes. Today Save without touching anything writes the root default onto every selected issue.

**Alternatives.** Keep the root default preselected.

**Impact.** WP-18 helper change and PC-29.

**Work packages.** WP-18, WP-20

### UD-12

**Question.** Apply per-parent defaults at page load only to new records (always on parent changes)?

**Recommendation.** Yes; existing records are no longer filled with values the user never chose.

**Alternatives.** Keep filling empty children of existing records at load (today).

**Impact.** WP-17, PC-24.

**Work packages.** WP-17

### UD-13

**Question.** Context menu size: keep the wizard template inline (with a 512 KB S1 budget asserted by spec) rather than loading the wizard body lazily?

**Recommendation.** Inline (D4 unchanged).

**Alternatives.** New edit_issues-gated GET that loads the wizard body when the submenu opens.

**Impact.** WP-18 spec; the lazy variant would add an endpoint and a WP.

**Work packages.** WP-18

### UD-14

**Question.** Delete MappingBuilder, ParentMenuBuilder and the after_custom_field_save dispatch outright (D5) instead of uncached deprecated shims?

**Recommendation.** Delete with CHANGELOG notes (nothing in or outside the plugin uses them).

**Alternatives.** Uncached shims kept throughout 0.1.x.

**Impact.** WP-15 and WP-18.

**Work packages.** WP-15, WP-18

### UD-15

**Question.** Keep the admin safe attributes value_dependencies and default_value_dependencies permanently (deviation from D5's one-minor-version window)?

**Recommendation.** Permanent; only the nested HTML form params stop being rendered.

**Alternatives.** Remove after one minor version.

**Impact.** jc-redmine_extended_api writes custom fields through safe_attributes= and would silently drop mappings with a 200 if removed.

**Work packages.** WP-22

### UD-16

**Question.** Editors require JavaScript (admin: mapping unchanged on save without JS; project: Save disabled) and the admin form switches to multipart/form-data while the editor is active?

**Recommendation.** Yes to both; multipart raises the reachable mapping size from about 2.5 MB to the 4 MiB cap.

**Alternatives.** Keep a no-JS matrix fallback (brings back page weight and Rack limits); keep the admin form urlencoded with a 3.9 MB pre-check.

**Impact.** WP-25 and WP-27.

**Work packages.** WP-25, WP-27

### UD-17

**Question.** Keep the admin lost-update guard with the conflict panel (use mine, keep current, export mine) and defer a three-way merge?

**Recommendation.** Yes; three-way merge needs a client delta in the payload and is a follow-up.

**Alternatives.** No guard (silent overwrite of concurrent project-level, cascade or API changes).

**Impact.** WP-22 and WP-25; same panel on the project 409 in WP-27.

**Work packages.** WP-22, WP-25, WP-27

### UD-18

**Question.** Spreadsheet formula protection on CSV export?

**Recommendation.** Opt-in checkbox, default off, with the symmetric import option (round-trip fidelity by default, warning in help text).

**Alternatives.** Default on; or no protection, warning only.

**Impact.** WP-26.

**Work packages.** WP-26

### UD-19

**Question.** Enumeration import matches by name only (D7) in this release?

**Recommendation.** Yes; ambiguous names reported. No '#<id>' cell syntax yet.

**Alternatives.** Also accept '#<id>' cells for lossless round trips with duplicate names.

**Impact.** WP-26.

**Work packages.** WP-26

### UD-20

**Question.** Editor page sizes: 100 parent sections and 200 child rows per 'Show more'?

**Recommendation.** Yes (measured 146-194 ms initial render for 5,000 parents in jsdom).

**Alternatives.** Other page sizes or windowed virtualization.

**Impact.** WP-25.

**Work packages.** WP-25

### UD-21

**Question.** Values page: paginate only above 500 values; drag-and-drop only for unfiltered lists of at most 500 values?

**Recommendation.** Yes; every list of 500 or fewer keeps today's UX.

**Alternatives.** Always paginate at per_page (25), removing drag for lists above 25.

**Impact.** WP-28.

**Work packages.** WP-28

### UD-22

**Question.** Project storage ceiling (SP-03): plugin setting project_storage_ceiling_kib default 2,048, minimum 64, applied to all project-page writes, never blocking writes that do not grow a field; plus a 255-character cap for list values added or renamed in project settings?

**Recommendation.** Yes, as a setting.

**Alternatives.** Constant instead of a setting; no ceiling (non-admins can grow fields without limit on PostgreSQL/SQLite); no length cap.

**Impact.** WP-31; new refusal path on PostgreSQL/SQLite for project managers.

**Work packages.** WP-31

### UD-23

**Question.** Shared/global fields: no server-side confirmation panel for dependency saves (including replace imports) and sort; only the scope banner and a JS confirm for sort?

**Recommendation.** Yes; removing links destroys no stored data and the audit delta records it.

**Alternatives.** Server confirm panel for replace imports and sort on shared fields.

**Impact.** WP-27 and WP-29.

**Work packages.** WP-27, WP-29

### UD-24

**Question.** Sort inactive enumerations together with active ones (not pushed to the end)?

**Recommendation.** Together.

**Alternatives.** Inactive last.

**Impact.** WP-29.

**Work packages.** WP-29

### UD-25

**Question.** Apply the MySQL size validation also to core List and Key/Value list fields?

**Recommendation.** Yes; the plugin writes them through its project services and API, and a 5,000-value core list fails today.

**Alternatives.** Depending formats only.

**Impact.** WP-11 GUARDED_FORMATS; upgrade note.

**Work packages.** WP-11

### UD-26

**Question.** Default type for widen_core_columns?

**Recommendation.** MEDIUMTEXT (6x the largest realistic case, keeps validation meaningful), TYPE=longtext available.

**Alternatives.** LONGTEXT by default (mirrors core's limit: 16.megabytes pattern).

**Impact.** WP-13.

**Work packages.** WP-13

### UD-27

**Question.** MySQL testing: add an optional manual (workflow_dispatch only) MariaDB workflow in addition to the :mysql-tagged specs and the documented local recipe?

**Recommendation.** Yes, manual-only for 5.1 and 7.0, because storage safety otherwise relies on stubs in CI.

**Alternatives.** Local recipe and :mysql specs only.

**Impact.** WP-13; one extra workflow file guarded by ci_workflows_spec.

**Work packages.** WP-13

### UD-28

**Question.** Show the storage usage line at 90 percent of the column limit on the core admin custom field form (view_custom_fields_form_upper_box hook) and project pages?

**Recommendation.** Yes (Should priority, rescues all errors).

**Alternatives.** Only the hard validation error.

**Impact.** WP-11.

**Work packages.** WP-11

### UD-29

**Status: Resolved by the owner (recommendation accepted).** RuboCop with the core 7.0 rules, set to Ruby 2.7 and Rails 6.1; only new offenses count.

**Question.** Approve the committed .rubocop.yml overlay (TargetRubyVersion 2.7, TargetRailsVersion 6.1, Rails/HttpStatusNameConsistency disabled) as the ratchet configuration (deviation from raw core config in D10)?

**Recommendation.** Yes; the raw config suggests :unprocessable_content (ArgumentError on Rack 2.2), params.expect, anonymous forwarding and Array#intersect?.

**Alternatives.** Raw core 7.0 config.

**Impact.** WP-01.

**Work packages.** WP-01

### UD-30

**Status: Resolved by the owner (recommendation accepted).** devDependencies jsdom ~29.1.1, jquery 3.7.1 and acorn ~8.18.0 in a private package.json.

**Question.** Approve devDependencies jquery 3.7.1 and acorn ~8.18.0 in addition to jsdom ~29.1.1 (D10 named only jsdom)?

**Recommendation.** Yes (serialize parity and jQuery-trigger tests; ES2017 gate).

**Alternatives.** jsdom only, without the language gate and real-jQuery tests.

**Impact.** WP-01, WP-17.

**Work packages.** WP-01, WP-17

### UD-31

**Status: Resolved by the owner (recommendation accepted).** rspec-61.yml clones upstream redmine/redmine 6.1-stable with Ruby 3.3.9.

**Question.** rspec-61.yml: clone source and Ruby version?

**Recommendation.** Upstream redmine/redmine 6.1-stable with Ruby 3.3.9 (the jcatrysse fork's 6.1-stable lags upstream).

**Alternatives.** The fork; Ruby 3.4.5.

**Impact.** WP-01.

**Work packages.** WP-01

### UD-32

**Status: Resolved by the owner.** The owner stated that CI runs only manually, or when Claude deliberately starts it. Claude may therefore dispatch the manual workflows deliberately, for example to obtain version-matrix evidence it cannot produce locally or before tagging a release. Conditions: only after the local gates pass; at most once per workflow per commit SHA unless a fix was pushed; never editing workflow triggers; every dispatch is reported (workflow, SHA, run URL, result). Automatic triggers are never added.

**Question.** May Claude dispatch the manual workflows?

**Recommendation.** Resolved by the owner: Claude may deliberately dispatch the manual (workflow_dispatch-only) workflows after the local gates pass, at most once per workflow per SHA unless a fix was pushed, never editing triggers, always reporting workflow, SHA, run URL and result; CI never gets automatic triggers.

**Alternatives.** Never dispatch.

**Impact.** G10 evidence comes from local runs, plus any deliberate manual dispatch reported per quality protocol section 10.

**Work packages.** WP-01, WP-07

### UD-33

**Status: Resolved by the owner (recommendation accepted).** Fixed local PostgreSQL role redmine/redmine with CREATEDB, documented in the README; the scripts never create it and exit with a clear hint when it is missing.

**Question.** One-time local prerequisite: may the PostgreSQL role redmine/redmine with CREATEDB be created on developer machines (the scripts never do it themselves)?

**Recommendation.** Yes, documented in README Development.

**Alternatives.** Each developer configures DCF_DB_* variables.

**Impact.** WP-01 scripts exit 5 with a hint when the DB is unreachable.

**Work packages.** WP-01

### UD-34

**Status: Resolved by the owner (recommendation accepted).** requires_redmine stays at 5.0; Ruby 2.7 or newer is documented; 5.0 is not actively tested.

**Question.** Keep requires_redmine 5.0 while testing only 5.1 to 7.0, documenting Ruby 2.7 or newer?

**Recommendation.** Yes (owner constraint); the Ruby 2.7 / Rails 6.1 syntax gate protects 5.0 compatibility at the syntax level.

**Alternatives.** Raise requires_redmine to 5.1.

**Impact.** WP-01 overlay and WP-07 README.

**Work packages.** WP-01, WP-07

## 2. Deviations from the default decisions

The area designs started from ten default decisions. This table shows where the final plan follows them, refines them or deviates from them, and why.

| Default | Original wording (short) | Final plan | Reason |
|---|---|---|---|
| D1 | Accept a child and parent combination when neither changed; JS keeps a stored disallowed value | Refined: tolerance per value (UD-04); a parent that is not available counts as unchanged (UD-05); copies are judged against the source (UD-06); a non-editable child never blocks a parent change (UD-07) | The whole-set wording would block adding an allowed value next to a legacy one; project copy silently skipped issues |
| D2 | Bulk edit: hide '(no change)' on descendants when a parent gets a value, force default or '(none)' | Deviates: '(no change)' stays available, the per-parent default is preselected with a hint, '(none)' is forced only for parent '(none)' or a parent value without links (UD-09); required children get a marked '(none)' (UD-10) | The literal D2 clears still-valid values on every selected issue (setting Country on 50 issues would wipe City where it is still valid) |
| D3 | hide_when_disabled keeps its key; hides the field while the parent offers no options | Follows, never in bulk edit and never while a stored non-matching value is shown | |
| D4 | Context menu without cache, per selection; wizard otherwise unchanged | Refined: wizard opens on '(no change)' (UD-11); wizard body stays inline with a size budget (UD-13); wizard save security is SD-01 | Saving the wizard untouched used to write the root default onto every selected issue |
| D5 | Keep JS shims one minor version; drop globals; MappingBuilder uncached or removed; legacy nested params one minor version | Refined: MappingBuilder, ParentMenuBuilder and the after_save dispatch are deleted (UD-14); admin safe attributes are permanent (UD-15); deprecation targets per UD-01 | No users of the builders found; removing the safe attributes would silently break jc-redmine_extended_api |
| D6 | Admin transport prunes unknown keys except inactive enumerations | Follows; pruning only on the JSON path | |
| D7 | Two-column import, separator auto, merge or replace, preview, all or nothing | Follows; enumerations matched by name only (UD-19); optional spreadsheet formula protection, default off (UD-18) | |
| D8 | Values page search and pagination, sort service, page-scoped enumeration batch | Refined: paginate only above 500 values, drag-and-drop for unfiltered lists up to 500 (UD-21); inactive enumerations sorted with the others (UD-24) | Lists of 500 or fewer keep today's UX |
| D9 | Cycle validation whenever a parent is present | Refined: only when a persisted field's parent id changes; stored cycle members are unconstrained until fixed (UD-08) | Avoids blocking unrelated saves of fields that are already in a stored cycle |
| D10 | Tooling: jsdom, opt-in system specs, manual 6.1 and JS workflows, .codex scripts, parity spec, RuboCop ratchet, delete test/spec | Refined: RuboCop overlay for Ruby 2.7 / Rails 6.1 (UD-29); devDependencies jquery and acorn added (UD-30); rspec-61 from upstream with Ruby 3.3.9 (UD-31); dispatch policy resolved (UD-32) | The raw core 7.0 config suggests constructs that break on Rack 2.2 and Ruby 2.7 |

## 3. Area design decisions

### server (large_lists_server_design.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| S1 | One shared module RedmineDependingCustomFields::DependingFormatMethods, INCLUDED in both format classes. It holds normalized_store_pairs, storage_preview(custom_field, store), before_custom_field_save, possible_values_options, validate_custom_value, validate_custom_field, value_from_keyword, edit_tag and bulk_edit_tag. Class bodies keep add, form_partial, label and query_filter_values, plus the enum possible_custom_value_options override. The module assigns no instance variables. | Include puts the module between the class and the core format, so super works. add is a private class method. Format objects are process-wide singletons, so any ivar would leak between requests (SP-16). | Prepended module (super would hit the class). Common superclass (impossible: two different core superclasses). |
| S2 | The central module DependencyRules (module_function) holds: Set-based allowed sets; ParentState with a baseline; per-value dependency_check; effective_parent_id; carries?; lookup_records; copy baseline; editable_by?; value_keys and value_options ([key, label, active] tuples); mapping_problems; prune_mapping (admin JSON transport only); the cycle helpers on FieldIndex. Memoization only on CustomField records via CustomFieldPatch#dcf_memo. | One rule set for validation, rendering, project services and the editor. Set lookups. Record-scoped memo needs no invalidation and is thread-safe. | Extend FieldRelevance (autoloaded, project-specific). CurrentAttributes (global state). |
| S3 | Canonical client contract owned by the server area (section 2). Context form/bulk. data-dcf-field and data-dcf-context on every depending field. data-dcf-parent, map, defaults and hide only on managed fields (effective parent that is valid, acyclic and visible to the user). data-dcf-parent-values in form context. Unpruned sanitized map with integer enumeration ids. Radio sentinel. Marked required-none option in bulk. | One owner ends the server/frontend drift (R1, QA-01, UX-02, BC-01). Parent-values gated identically to the map leak nothing beyond what the user can see (SP-04, SP-05) and are much smaller than an allowed set. Omission on cycles and invalid chains matches unconstrained server validation, so client and server agree. An unpruned map gives exact parity with server validation. | data-dcf-allowed (larger, same information under the same gate). Emitting on cycles (client would deadlock both members blank). Pruned map (client stricter than the server for stale parent values). |
| S4 | Single head hook specification: meta name=dcf-i18n (flat object with the 10 keys of ClientConfig::I18N), then the one UMD depending_custom_fields.js, context_menu_wizard.js and the CSS. Editor assets only for CustomFieldsController and ProjectCustomFieldConfigurationController, compared by class name, and only through the hook. | Matches the frontend runtime and wizard readers (R2) and quality G8. One inclusion path avoids double loading (BC-13). No DB access in the hook. | Nested i18n payload under another meta name (revision 1; no reader). content_for in project views for editor assets (double include). |
| S5 | Effective parent = exists, same type, family format, not self, and the ancestor chain is acyclic. It is used by validation, ClientData and SelectionGraph alike. Fields without one (dangling, invalid, cycle members, chains reaching a cycle) are unconstrained everywhere. | Client and server must agree. A stored cycle otherwise leaves both members blank with no options. Stored cycles are now refused at save, so only legacy data and races are affected, and the admin warning shows them. | Keep validating cycle members per mapping (client and server disagree; unusable UI). |
| S6 | D1 is per value: while the parent is unchanged, values already in the baseline are tolerated and only new values must be allowed. Parent changed means strict. A parent not available on the object counts as unchanged. | It matches core's own idiom (values - value_was - possible_values) and the frontend legacy behaviour (R14, QA-06, BC-06). Verified on 5.1 and 7.0: add, remove and reorder are accepted, a new bad value is rejected. | Whole-set comparison (revision 1; blocks multi edits). The client drops legacy values on any child edit (silent data loss). |
| S7 | For new records that are issue copies (copy? true), the baseline is the source issue's stored child and parent values, read through @copied_from. | Copies of legacy combinations are rejected today, and project copy silently skips them (QA-07). Verified: copy unchanged is valid, a changed child or parent is strict. Core has no reader, so the ivar access is pinned by a spec on all 4 versions. | A new-record flag to the client, keeping the server strict (keeps the project-copy data loss). |
| S8 | The dependency rule never rejects an unchanged child that the current user cannot edit (editable_custom_field_values), even when the parent changed. It is evaluated only on the failure path. | Such errors cannot be fixed by that user (QA-08). Core filters assignment of non-editable values but still validates them. | Keep rejecting with a clearer message (parent remains effectively uneditable for that role). |
| S9 | FieldIndex is the single topology helper. It reads parent ids from raw YAML with an anchored regex (deserialization fallback), is built from loaded read-only records (0 queries) or from a raw select_all, and loads missing ids lazily in one batched query. DependencyRules::Graph and the competing limits proposal are dropped. | R18 and SP-08. A regex extraction costs 0.041 ms against a 16.6 ms YAML parse per S1 row. raw before_type_cast leaves the attribute undeserialized (probe_rev). | Parse each field's format_store per hop (YAML cost). find_by per hop (query per hop). |
| S10 | Parents are resolved from customized.custom_field_values or from the selection's available fields first. carries? short-circuits objects that cannot hold the field's type (a Project in context menus). Query assertions use invariance only. | R16: 0 queries when parents are loaded (verified, 5 children, 0 queries). The context menu no longer parses hidden children's stores. The Project-object shortcut is invisible because core destructures 2 elements. | find_by per child (O(fields) queries). Absolute query counts (version-sensitive). |
| S11 | The storage guard is owned by the limits area (validate :dcf_validate_storage_limits in Patches::CustomFieldValidationPatch, dcf_storage_too_large). The server provides a sanitize-only normalized_store_pairs shared by before_save and storage_preview(custom_field, store) (called as format.storage_preview(record, record.format_store)), including parent normalization. D6 pruning stays exclusively in the admin JSON transport. | R5 and UX-04: one owner, one key. BC-02: before_save must not rewrite stored mappings on API, extended-API or cascade saves. Preview bytes equal stored bytes. | Server-owned StorageLimits (revision 1, conflicting API). Pruning in before_save (silent data changes). |
| S12 | CustomFieldPatch.prepended registers no callbacks. All new CustomField callbacks live in the one Patches::CustomFieldValidationPatch, prepended after CustomFieldPatch (WP-11; WP-22 adds the transport callbacks). The two stand-in-based validation specs are rewritten DB-backed in the same commit. | Stand-in classes define only after_save; registering more there broke 14 examples (limits V11). DependencyRules needs real custom_field_values. | Stub DependencyRules.find_parent and keep the stand-ins (cannot express parent_state). |
| S13 | Required managed depending children in bulk_edit_tag get a '(none)' __none__ option marked data-dcf-required-none='1'. It is reimplemented only for that case, using core's body; the client enables it only while no value is allowed. | Makes D2 'parent (none) clears descendants' possible for required children (R6, FD-22) without letting the client choose it as a fallback when options exist. The server still rejects blank per issue when options exist. | Reject FD-22 and document the limitation (required children keep stale values and fail per issue). |
| S14 | Radio blank sentinel: hidden input name=tag_name value='' with no id and data-dcf-blank='1', placed before span.check_box_group for managed single-value check_box children in form context. | A required radio child otherwise posts nothing and keeps a stale value. Last-wins parsing is verified on Rack 2.2, AP 7.2 and AP 8.1. With no id the label-for scan is unchanged. Core always renders the stored value as a radio (value_was appended), so no stored value is cleared by accident. | JS-injected sentinel (fails without JS; a mirror under another name). |
| S15 | Cycle validation runs only on persisted fields whose normalized parent id changed versus attribute_in_database. The candidate is resolved like before_save. The ancestor walk goes through FieldIndex.load. Error [:parent_custom_field_id, :dcf_circular_dependency]. Concurrent creation race accepted. | D9 kept (silent nil for unresolvable ids). Does not block reorder, cascades or unrelated API saves of stored-cycle members. Store dirty helpers are unreliable (F1). | Validate whenever a parent is present (blocks unrelated saves). |
| S16 | The parent select uses parent_candidates (same type and family, minus self and descendants, always keeping the current parent). The cycle warning uses the sprite_icon guard and comma-joined names. | Excluding a stored parent would silently drop it. The icon renders on 7.0, where .icon-warning styles only svg (UX-10). | Strict exclusion. No warning. |
| S17 | One fixture mechanism: generated markup fixtures (spec/frontend/markup_fixtures_spec.rb); fixture records get explicit ids from the quality per-kind ranges (CustomField 9_100_001+ ...) via dcf_fixture_record, with the normalizer, the sequence-bump self check and two seeds (compat section 2.4 row Fixture ids). The JSON contract fixture is deleted. Rules cases are shared through test/js/fixtures/rules_cases.json. | R13, QA-01: both sides break together, and ids from sequences cannot leak into fixtures (E23: the fixed ranges stay stable while sequences drift). | A full DB-id replacement table (server revision 2; kind-aware rewriting, collision-prone). Two parallel fixtures (drift). |
| S18 | ClientData fails open: any exception logs a warning and the field renders without data-dcf-* attributes (and without a sentinel). | BC-12: an unexpected legacy store shape must not break issue, project, user or version forms. Server validation still applies. | Let exceptions propagate (one bad field breaks the whole form). |
| S19 | Context menu: early return when @options_by_custom_field is blank. ParentDetector visibility uses core visible_by?, fails closed and is memoized per [cf, project, tracker]. Declared response-size budget for S1. CustomFieldVisibility deprecated and unused. | SP-08, SP-10: fail-open visibility could expose fields in the wizard. The memo removes repeated per-issue checks. | Keep rescue NoMethodError => true (fail open). |
| S20 | value_options returns ordered Ruby tuples [key, label, active]; the one compact wire shape ({key}, label only when it differs, active:false only when inactive) is produced only by DependencyEditorConfig.wire_values. Order is list order or enumeration [position, id], inactive included. | R7: one shape for the values endpoint, both presenters and the JS, covered by a contract fixture. Compact for large lists. | Full triples on the wire (doubles bytes for lists). Per-consumer shapes (revision 1 drift). |
| S21 | value_dependencies and default_value_dependencies stay permanent CustomField safe attributes. Only the nested HTML form params are deprecated (not rendered, still accepted). | BC-04: jc-redmine_extended_api writes through safe_attributes=, and removal would silently drop mappings with a 200. | Remove them after one minor version (silent breakage). |
| S22 | No rollback-only cache delete is kept in code. A documented downgrade step deletes the stale key. | Point 1 explicitly requires removing the Rails.cache mapping and its after_save invalidation (BC-07 code change rejected). The documented one-line command covers the downgrade risk. | Keep a plain Rails.cache.delete in after_commit through 0.1.x (contradicts the owner's point 1). |
| S23 | Keep query_filter_values asymmetric (list: all; enum: restricted by the query project's parent value). Enum tolerates a nil query. Delete QueryCustomFieldColumnPatch (verified no-op). | Characterized behaviour, not part of the 9 points. The patch has no effect on any target version. | Unify semantics (behaviour change). |
| S24 | Server-owned locale keys: field_parent_custom_field (same text as the form label), warning_dcf_parent_cycle, activerecord.errors.messages.dcf_circular_dependency (phrased to follow the label). field_value_dependencies is owned by limits with the 'Dependency mapping' wording. The hook hint keys are owned by frontend. | R19, UX-15, UX-03, R11: one owner and one text per key. Error messages read correctly after their label in all four languages. | 'Parent field' label (mismatch with 'Depends on'). |

### frontend (large_lists_frontend_design.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| FD-1 | Fold the pure rules and the DOM runtime into ONE UMD file, assets/javascripts/depending_custom_fields.js (same name as today). Under CommonJS the rules are module.exports; in a browser the runtime starts and exposes window.DependingCustomFields, with rules at .rules. No new asset and no new global. | It removes the 'rules file missing, runtime inert' failure mode and the head-hook disagreement (R2, BC-01). The script list stays as today, which helps upgrades and stale caches. Node tests still require the pure rules without a DOM (proto2: 31 pass). | Two files (rules first). Rejected: an extra asset, a load-order coupling, and the server hook had already omitted it once. |
| FD-2 | Keep the static includes on every base-layout page. The head hook emits <meta name="dcf-i18n"> with a flat object of the 10 ClientConfig::I18N keys first, then depending_custom_fields.js, context_menu_wizard.js and the CSS. ClientConfig::I18N lists the 10 frontend JS keys mapped to text_dcf_hint_*, text_dcf_live_message and error_save_failed. label_dcf_hint_* is deleted. | Depending fields arrive by AJAX on pages whose head is never re-rendered. The flat object is what the runtime and the wizard read, the meta tag is CSP friendly, and there is one owner of the key list. | Nested meta name="redmine-depending-custom-fields" payload (frontend revision 2; superseded by the consolidated contract). Per-field i18n attributes (repeated bytes). |
| FD-3 | Canonical contract C1 (section 3), implemented by the server and agreed text. - Attributes data-dcf-field/parent/context (form/bulk)/kind/multiple/parent-name/map/defaults/hide/parent-values/parent-label/stored. - Emitted only on an active child: parent exists, is not itself, and is visible to the user (fail closed) in both contexts. - Stored cycles, self-parents and dangling parents get no parent attributes (UD-08). - The map is sanitized, not pruned; enumeration ids are numbers. | One table removes the server/frontend drift (R1, QA-01, UX-02, BC-01). The visibility gate stops leaking role-restricted parent data and the parent option names in the map (SP-04), and keeps today's behaviour, where an invisible parent leaves the child unfiltered. Unpruned maps equal exactly what validation reads. | data-dcf-allowed without a gate (leaks). Gating only parent-values (map keys still leak). Pruned maps (client and server disagree on stored parent values outside the list). |
| FD-4 | Parent not on the form (workflow read-only, not available for the tracker): filter by data-dcf-parent-values (current parent keys, [] when blank or unavailable). Hints use data-dcf-parent-label. Invisible parents produce no attributes at all. | It matches server validation for read-only and unavailable parents without exposing hidden data. A single map stays the source of truth (parent keys instead of a duplicated allowed list). | Server-computed allowed set (duplicates the map, larger, same privacy once gated). Leave unfiltered (users pick values the server rejects). |
| FD-5 | data-dcf-stored = {"child": value_was keys, "parent": parent value_was keys}, emitted for persisted records (value_was) and for issue copies (copy-source baseline, UD-06). It drives D1 legacy eligibility and acts as the new-record flag. | Only genuinely stored values (for issue copies, the copy source's values, which the server uses as the same baseline) can be legacy, so new records and values posted on a failed save are never shown as 'kept' when the server would reject them (R15, QA-20b). value_was is captured before assignment (core acts_as_customizable:96/98), so it is the database value even after re-renders. | Treat every disallowed value at load as legacy (previous design; breaks copies). A separate new-record flag (two attributes for one concept). |
| FD-6 | D1 per value on both sides. Client: eligible = stored.child minus allowed when the parent control is absent or its values equal stored.parent. Server: with an unchanged parent (unavailable counts as unchanged), values contained in value_was are exempt and new values must be allowed. Memory may hold legacy values; they are re-filtered on restore, so A to B to A restores the stored legacy value. | Whole-set leniency rejects any edit of a multi child that holds a legacy value (R14). The per-value rule matches core ListFormat's value_was idiom. Restoring on return to the stored parent fixes the silent loss in UX-07 and QA-20a. | Client drops legacy values on any child edit (surprising loss). Whole-set D1 as written (breaks multi edits). |
| FD-7 | Per-parent defaults are applied at load only to new records (no data-dcf-stored), and always on parent changes. On AJAX re-renders, memory beats defaults. | Filling defaults into existing records writes values the user never chose, under their name in the journal (UX-14), which contradicts D1's spirit. | Keep filling defaults on existing records (today's behaviour E1). |
| FD-8 | Never disable the child control. Disallowed options and choice inputs are hidden and disabled; selected options are deselected before being disabled. Choice labels are hidden with the hidden attribute plus a mandatory CSS override, because core .check_box_group label {display:block} beats [hidden]. | Point 2: enabled controls are always submitted, so the mirror inputs go away. The CSS override was found in core-7.0 application.css:1414-1421 and core-5.1 :950-957. | Remove options from the DOM (breaks legacy display and overlays). Inline styles (the runtime would own presentation). |
| FD-9 | Server deliverables are adopted explicitly: (a) a blank sentinel hidden input (id nil, data-dcf-blank) before span.check_box_group for single radio active children; (b) bulk_edit_tag offers __none__ for required active children (FD-22 adopted). Both come with request specs. | Without (a) a required radio child can never be cleared (harness G1/G2). Without (b) parent '(none)' cannot clear required descendants, and every issue fails 'invalid' (U2). Last-wins parsing is verified on Rack 2.2.24, AP 7.2.4 and AP 8.1.4. The no-options bypass accepts the clear. | A JS-injected sentinel (a mirror again, fails without JS). Document the limitation for required children. |
| FD-10 | D2 revised for bulk edit and the wizard. For a concrete parent, '(no change)' stays visible and enabled. The child becomes the remembered pick, a carried pick, or the per-parent default (with a hint and the dcf-auto-applied class), else stays on '(no change)'. It is forced to '(none)' only for parent '(none)' or a parent value without links. Parent '(no change)' restores the pre-cascade value. | Concrete reason D2 breaks existing users: hiding '(no change)' and forcing '(none)' clears valid values on every selected issue (BC-05, UX-08). Today single children stay on '(no change)' (A1) and are validated per issue. Defaults were already applied today (A'), and now they are visible and reversible. | D2 as written (data loss). '(no change)' preselected even when a default exists (drops the documented default behaviour). |
| FD-11 | Wizard fields, including the root, open on '(no change)' (render_custom_field passes nil). Fields are wrapped in an implicit <label>, and the action comes from the named route. | Today Save without touching anything writes the root default onto all selected issues (QA-09). The controller skips blank values, so nothing is written unless chosen. The implicit label gives an accessible name without colliding ids (UX-13). | Keep the default preselection (D4 literal), which causes unintended writes. |
| FD-12 | Hints name the parent (DOM label of the present parent, else data-dcf-parent-label) and the offending values, with generic fallbacks. Each hint has a JS-generated id tied by aria-describedby while visible. There is no per-hint role=status; one debounced page-level polite live region announces user-initiated changes. | 'Parent field' is admin jargon, and the parent often sits in the other column (UX-05). An id on a JS-created hint is safe: the label-for scan only sees server markup, and replaceIssueFormWith copies only form values (UX-06). | Generic texts without names (previous design). role=status per hint (noisy and unreliable). |
| FD-13 | D3: hide only the field's own <p>, in edit context only, while allowed is empty (parent blank, unavailable, or a value without links) and no legacy value is selected. Un-hide only what the runtime hid. | This matches D3. It never hides a submitted stored value and never hides in bulk. | Hide closest container (can hide unrelated content). |
| FD-14 | One native delegated change listener, plus a jQuery delegate that handles only isTrigger events. Own events are tracked in a WeakSet. change is dispatched only when values changed, and dcf:updated for every evaluation that was not a no-op. BFS cascade with a visited set; depth-ordered init. | Points 3 and 5. It handles select2 triggers without double processing (verified) and terminates on stored cycles. | Per-element listeners and always-fired change events (today). |
| FD-15 | The MutationObserver initialises matching added roots directly inside its callback (a microtask after the inserting task). There is no debounce, and requestSetup alone keeps a 25 ms debounce. | It removes the window in which re-rendered fields are unfiltered and could be submitted (QA-15, QA-20b). One task's mutations arrive in one callback, so coalescing is preserved for replaceIssueFormWith and #content replacement. | A 25 ms debounce (previous design). |
| FD-16 | Memory is a WeakMap keyed by the scope element, then prefix/fieldId, then the parent key. It is written at initial evaluation, on parent-driven changes (edit) and on every user or third-party child change. Bulk memory holds only the initial state and user picks. | Fixes E3 (latest pick restored). It survives updateIssueFrom and needs no dataset bookkeeping. | dataset JSON or sessionStorage. |
| FD-17 | Compatibility: setup(root) and requestSetup(root) are deprecated in 0.1.0, kept throughout 0.1.x, removable no earlier than 0.2.0. DependingCustomFieldData and ContextMenuWizardConfig are removed. A load guard prevents double binding. | D5, with the explicit version targets that BC-14 asks for. No external users were found. | 'At least one minor version' without targets. |
| FD-18 | context_menu_wizard.js: - resolve the form action with new URL against location and refuse cross-origin or missing actions; - init the cloned wizard synchronously; - show a localized alert on non-JSON errors and catch the rejection; - narrow the observer to childList filtered on li.cf-parent. | Removes the last global and adds defense in depth for the CSRF token (SP-15). Removes the delayed unfiltered state and the body-wide style observer. | Post to any action read from the DOM. |
| FD-19 | ES2017 for all plugin JS, enforced by an acorn parse in npm run check. No CSS.escape. | Matches browsers supported by Redmine 5.0+. jsdom lacks CSS.escape. The prototype passes the acorn gate. | ES2020. |
| FD-20 | Tests use one fixture mechanism: real request rendering in all four rspec workflows, explicit record ids in a reserved range, a shared Nokogiri normalizer (placeholders, JSON-aware) and a savepoint self-check that sequence shifts do not change the output. Every required contract case gets a jsdom outcome test. jsdom ~29.1.1 plus jquery 3.7.1, a spec-compliant entries helper, opt-in system specs for the CSS and browser-only behaviour. | Fixes the fixtures depending on sequences under random order (R13) and the two parallel contract fixtures (QA-01). jsdom FormData is wrong for disabled options. jsdom cannot evaluate the [hidden] overrides. | Helper-only rendering (misses workflow and visibility paths). Hand-written fixtures. |

### editor (large_lists_editor_design.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| AD-1 | One transport per page: admin uses the virtual attribute `custom_field[dependencies_json]` (safe attribute `dependencies_json`) and the project page uses `dependencies_json`. Both carry the versioned v1 object {version, source, import, base, value_dependencies, default_value_dependencies}. Storage stays a Hash in format_store. | A single param removes the 4096-param cap, the bracket corruption and the id collisions, and links and defaults travel atomically. `source` and `import` satisfy D7 auditing without nested `meta`. | Two JSON fields; nested params with a sentinel; a fetch JSON body (needs a JSON route and CSRF plumbing); a nested `meta` object (rejected for one strict schema). |
| AD-2 | Semantics: absent, nil or blank means unchanged on admin and is an error on the project page (via parse!); `{}` clears. The admin editor posts '' until dirty. The project editor always posts its payload. | Saving for unrelated reasons never rewrites or prunes the mapping. A JS failure on the project page fails closed instead of clearing. | Always post the full state (re-prunes on every save, doubles page weight); disabling the input instead of blanking it. |
| AD-3 | The writer only stores the raw value. A before_validation callback decodes (memoized per raw String object), applies the base check, prunes and assigns. A separate validate adds errors on :value_dependencies. An after_save resets the virtual attribute. All new CustomField callbacks live in the one Patches::CustomFieldValidationPatch, prepended after CustomFieldPatch (WP-11; WP-22 adds the transport callbacks). | Attribute order inside safe_attributes= is arbitrary, and by before_validation all attributes are final. The JSON wins over legacy nested params. StorageLimits and the cycle check measure the final mapping. A separate module keeps the stand-in classes in spec/patches/custom_field_required_validation_spec.rb (lines 32, 60, 252, 285) working. Limits V11 measured 14 failures otherwise. after_save prevents re-application on a second save. | Apply in the writer (order dependent); register the callbacks in CustomFieldPatch.prepended (breaks 14 examples); rewrite that spec DB-backed in the same commit (larger change). |
| AD-4 | Invalid payloads fail closed. The DB stays unchanged, only the error code and byte count are logged, and submitted input is never echoed. Errors map per entry point: too_large maps to a size message (dcf_dependencies_too_large_to_send / error_dcf_dependencies_too_large_to_send); everything else maps to the 'could not be read' message. | This follows the fail-closed convention. A size problem gets a size message, never a misleading 'reload' message (UX-01). Not echoing input removes error loops and the SP-11 injection path. | Ignore bad payloads silently; fall back to legacy params; echo the raw value. |
| AD-5 | D6 pruning runs only on the admin JSON path, through the single implementation DependencyRules.prune_mapping(vd, dd, parent_keys:, child_keys:, multiple:). Parent keys are pruned only when a valid parent resolves; inactive enumerations count as known; defaults are kept only when linked and shaped by multiple?; order is deterministic. before_custom_field_save and storage_preview stay sanitize-only. The project page keeps strict validation. | This matches D6 and gives canonical stored data, while API, extended-API, cascade and untouched saves never rewrite mappings (BC-02). One implementation avoids drift between duplicates (R18). | Prune in before_save, as the limits area proposed (silently rewrites mappings on unrelated saves); strict rejection on the admin form. |
| AD-6 | Admin lost-update guard: the payload carries `base`, the digest of the stored mapping at render. A mismatch with attribute_in_database('format_store') refuses the save with dcf_stale_dependencies, applies nothing, and re-renders the current version together with the user's version (conflict panel AD-20). | Long-lived edits (large imports) would otherwise silently overwrite concurrent audited project-level changes, cascades or API writes. The digest covers only the mapping, so unrelated field edits never trigger it. | No guard; BaseService.state_hash (includes values the same form edits); a silent 'overwrite anyway'. |
| AD-7 | Live parent change fetches values from an admin-only route, GET /dcf_dependency_editor/values?custom_field_id=&type=&kind=. It is format-less and session-authenticated, and returns the canonical wire format. | Core ignores the session on .json requests. The prefix cannot be shadowed by depending_custom_fields/:id. The endpoint enforces type and family. | Embed all candidate parents' values (unbounded); extend ContextMenuWizardController (different authorization model). |
| AD-8 | Exactly one partial (depending_custom_fields/_dependency_editor) and one presenter (DependencyEditorConfig.for_admin / for_project) serve both pages. Configuration and i18n travel in data-dcf-editor-* attributes. The hidden input always renders blank, and initial state always comes from data-dcf-editor-mapping plus data-dcf-editor-dirty. | This removes the incompatible project DOM, the project presenter and the undefined dcf_editor_i18n helper (R4, QA-03, UX-01). An untouched project page is not dirty, so beforeunload does not fire. Core sets include_all_helpers = false, which rules out helpers. | A helper through a core controller patch; separate project markup (two contracts); using a pre-filled hidden input as initial state (dirty heuristics). |
| AD-9 | Scalable UI: details/summary per parent value; bodies built on open and removed on close; 100 sections and 200 rows per 'Show more'; parent filter plus 'only parent values without links'; per-section filter plus views (all, linked, not linked here, not linked anywhere); check and uncheck act on all matches. | Measured 146-194 ms initial render for 5,000 parents in jsdom, about 100 closed nodes. Native details provides keyboard support and expanded state. | Windowed virtualization; an inverted child-to-parents table; keeping the matrix. |
| AD-10 | The per-parent default is a select inside each section: '(no default)' plus the linked children, or a multi-select plus Clear for multiple fields. The summary shows the default while the section is closed. | This mirrors today's UX and needs no named radios. | Per-row radios (need names); per-row exclusive checkboxes (poor accessibility). |
| AD-11 | Client state is a superset built from Map/Set, never from plain objects keyed by user values. Output dictionaries are null-prototype objects filled through defineProperty. Serialization intersects with the current lists. | Transient textarea edits never lose links. Values named __proto__ survive; this was verified as a bug in revision 1 and fixed in rev/proto2 (30/30 tests). | Prune the state on every list change; plain objects (drop __proto__). |
| AD-12 | Import and export run client-side in a pure UMD model with node tests. The parser is lenient RFC 4180 with auto separator detection. Limits: 10,000,000 characters and 200,000 records. The skipped header is shown with its cells. Matching order is exact, then exact NFC, then a unique case-insensitive NFC match. Add-missing rejects values that contain line breaks. Apply is all-or-nothing, blocked when the resulting payload would exceed the server cap, and supports merge or replace plus undo. | Implements D7 without Rack limits on the import text, using the same code on both pages, and closes QA-11 and SP-13. | A server preview endpoint (multipart upload, new authorization surface); a third column for defaults. |
| AD-13 | File import decodes strict UTF-8, then falls back to general_csv_encoding or windows-1252 and reports the fallback. Export is UTF-8 with BOM and CRLF, using the locale separator by default. An opt-in, default-off 'protect formulas' export prefixes ' to cells starting with = + - @ TAB CR; the matching import option reverses exactly that. | Covers Excel's non-UTF-8 CSV and keeps core parity and round-trip fidelity by default, while giving cautious admins protection (SP-14). The reverse rule never corrupts values that do not begin with ' followed by a formula character. | Always neutralize (breaks round trip); never offer protection; export ISO-8859-1 with a library. |
| AD-14 | 'Add missing child values' (admin, list children only) appends trimmed, NFC-normalized unknown children to the textarea on apply, fires input/change, and can be undone. | Implements point 8 without a server round trip. Core strips values exactly as the importer trims, so link keys match and are not pruned. | Server-side value creation; offering it on the project page. |
| AD-15 | Editor assets are added only by the head hook (server ClientConfig.editor_page? / editor_asset_tags, in the order model JS, editor JS, CSS) on CustomFieldsController and ProjectCustomFieldConfigurationController pages. Project views must not add them through content_for. A MutationObserver initializes editors inserted later. | A single inclusion path avoids double loading (BC-13) and works with the /new AJAX re-render. | content_for in project views (lost on AJAX, doubles includes); loading on every page. |
| AD-16 | A capture-phase change listener on document for #custom_field_field_format asks for confirmation when the editor is dirty. On cancel it stops propagation and restores the format. On confirm, or when not dirty, it empties the payload before core's jQuery handler serializes the form. | Prevents silent loss of edits (UX-11) and a 414 on large payloads. Capture on document runs before the element-bound jQuery handler. | Silent emptying (revision 1); accepting the 414 risk. |
| AD-17 | The core default_value control is always rendered inside p[data-dcf-default-value-row] and is hidden live while a parent is selected. | Removes the 'typed default silently set to nil' surprise. The server rule is unchanged. | Keep the render-time-only condition. |
| AD-18 | One payload parser for both entry points: DependencyPayload.parse (nil or Result) and parse! (raises Invalid, blank is an error). The schema is strict: unknown keys including meta are rejected, nulls/booleans/floats are rejected, create_additions is false. Both paths share MAX_BYTES 4 MiB and max_nesting 3, a two-stage string-aware pre-scan rejects digit runs of 20 or more before JSON.parse, and Integers are accepted only when positive with bit_length <= 63. | Resolves R3, QA-02, BC-03 and SP-02 (one schema and API) and SP-01 (a 1,000,000-digit literal is rejected in under 1 ms instead of costing 5.7 s; the worst-case 4 MiB parse takes 0.41-0.61 s). Verified in rev/dependency_payload_test.rb on Ruby 3.2.6 and 3.3.6. | Two parsers (the earlier editor and project designs); a 16 MB cap (multiplies DoS cost); a non string-aware regex (false positives on values containing long digit runs). |
| AD-19 | After successful init the admin editor sets form.enctype = 'multipart/form-data'. Before submit it blocks with an i18n message when the payload exceeds 4 MiB or when the estimated body, for the encoding actually in use, exceeds the Rack limit minus a margin. The same check runs on the multipart project form. | Urlencoding inflates JSON 1.5-1.8x, so a 3 MB JSON already fails urlencoded (QueryLimitError) but passes multipart on rack 2.2.24 and 3.2.7 (rev/rack_admin_probe.rb). An over-limit urlencoded PUT is otherwise a silent 404 (critic A1, QA-10). The multipart non-file buffer is 16 MiB and the part limit is 4096. | Keep urlencoded with only a ~3.9 MB pre-check (ceiling far below the parser cap); a fetch JSON submit (breaks the core form). |
| AD-20 | Conflict panel on an admin stale save and on a project 409. The editor shows the current version (fresh base or state_hash) and offers 'Use my version' (deliberate overwrite against the fresh base), 'Keep the current version' and 'Export my version (CSV)', with counts of links present in only one version. | The user's work is never lost, the recovery no longer depends on import-by-name, and admin and project behave identically (UX-09). | A three-way 're-apply my changes' merge (needs the base mapping or a client delta in the payload; deferred as a user decision); revision 1's 'export, reload, import' message. |
| AD-21 | One value wire format: {key} plus label only when it differs from key, plus active:false only when inactive. It is produced by DependencyEditorConfig.wire_values from DependencyRules.value_options tuples and used by the endpoint and both presenter modes, and the JS decodes it with documented defaults. | Resolves the three-shape conflict (R7) with the compact shape, saving about 200 KB at 5,570 list values, and is pinned by a contract spec. | Always emit all three keys (heavier); server tuples on the wire (less self-describing). |
| AD-22 | One shared JS fixture mechanism, spec/support/dcf_js_fixtures.rb: fixture records get explicit ids from the quality per-kind ranges (CustomField 9_100_001+ ...) via dcf_fixture_record, with the normalizer, the sequence-bump self check and two seeds (compat section 2.4 row Fixture ids); the ID_BASE 1,900,000,000 scheme of editor revision 2 is superseded. Tokens and state hashes are scrubbed, and fixtures are written or compared through DCF_WRITE_JS_FIXTURES. The fixture spec renders each scenario twice with sequences advanced in between. | PostgreSQL sequences are not rolled back and random order changes them, so DB-derived ids must not reach fixtures (R13). The same mechanism serves the frontend markup fixtures and the payload fixtures (R1, QA-01). | Placeholder substitution of numbers (fragile); resetting sequences (affects other specs). |
| AD-23 | The project page renders Save disabled with data-dcf-editor-submit, and the editor enables it only after successful init. Bad data attributes leave the editor inert, with an error notice and nothing written. | No-JS users can no longer trigger a misleading no-op 'saved' flash or a 'reload' message (UX-01). Fail closed on corrupt bootstrap data (QA-24). | Pre-fill the hidden input so that a no-JS save is a no-op (project revision 1); fail open with an empty state (would clear the mapping). |
| AD-24 | The admin nested safe attributes value_dependencies and default_value_dependencies stay permanently. Only the project nested params are deprecated (deprecated in 0.1.0, accepted throughout 0.1.x, removable no earlier than 0.2.0). | Concrete reason to deviate from D5: jc-redmine_extended_api writes custom fields through safe_attributes= (custom_fields_controller_patch.rb assign_filtered_attributes); removing them would silently drop its clients' mappings. | Remove after one minor version (breaks that plugin). |

### project (large_lists_project_design.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| P-D1 | edit_dependencies posts one hidden field, dependencies_json, plus state_hash, in a multipart PATCH form. The value is decoded inside DependencyMappingService with the shared DependencyPayload.parse (editor-owned, schema v1). Every bad input is therefore an audited 422. A present-but-blank value is an error and never clears. When the key is absent, the service falls back to the legacy nested params (deprecated in 0.1.0, accepted throughout 0.1.x, removable no earlier than 0.2.0). JSON wins when both are posted. | Decoding in the BaseService subclass satisfies 'bad input is audited'. Multipart keeps PATCH beyond the 4 MB urlencoded limit (rack_probe.out). One parser and one schema remove the R3/QA-02/BC-03 divergence. | Parse in the controller (not audited). Urlencoded form (about 4 MB ceiling minus escaping bloat). A project-only parser with a meta wrapper (revision 1; conflicts with the admin path). |
| P-D2 | The editor's initial state comes from data-dcf-editor-mapping. The hidden input is always blank (GET and every re-render); a parsed ok posted payload is rendered in data-dcf-editor-mapping with data-dcf-editor-dirty="1" (gap 1). The Save button carries data-dcf-editor-submit and is enabled after init. | A server pre-fill no longer counts as a dirty echo, so there is no spurious beforeunload (R4). Without working JS nothing can be posted, so a no-op never reports success and nobody is told to reload (UX-01). Rendering the parsed posted payload as the dirty initial state keeps the user's work after a 422. | Pre-fill the hidden input with the canonical mapping (revision 1; conflicts with the editor's always-blank hidden input). Treat blank as unchanged (ambiguous; the admin path uses that semantic, the project path must fail closed). |
| P-D3 | Project validation stays strict: unknown parent keys, unknown child values and defaults outside the links give 422 error_invalid_dependency. Lookups use Hash#key?. All offenders are aggregated into the audit summary, with at most 5 labels per kind cut at 40 characters, and the flash stays generic. On the JSON path defaults are shaped by multiple? (a single [x] becomes x, and several values on a single field are an offender). | Preserves the tested project contract (T-DEP-2/3/5) and removes the O(n*m) cost. Shaping matches what the editor serializes. | Silent pruning as on the admin form (hides tampering at the non-admin surface). |
| P-D4 | update_dependencies writes a compact v2 delta. Samples are bounded by count (20 per list) and by encoded bytes (4,000 per list, measured with ActiveSupport::JSON), labels are cut at 80 characters, and each default entry keeps 3 labels. The digest key is mapping_sha256. The limits AuditPayload cap (16,384 B, marker payload_sha256) is the backstop and is never reached by this delta. | Measured worst case 12,028 B on AS 6.1 and 8.1 (proto2/delta_worst.out), so the delta digest is never overwritten by a shrink (R10). The key names cannot collide with the marker. | Count-only caps (worst case 19 KB plus, which the shrink would then mangle). A 60 KB project cap (revision 1; conflicts with limits). |
| P-D5 | The values page paginates only above UNPAGINATED_MAX = 500 values. per_page comes from core per_page_option, capped at 500. Drag-and-drop is offered only when the list is unfiltered and unpaginated. | Every list of 500 values or fewer keeps today's UX. All forms stay under 4,096 params. | Always paginate at per_page (removes drag from lists of 26 values or more by default). |
| P-D6 | Search is server-side GET q. q is folded with ValueCollation (the same tables as the editor fold, asserted by a shared fixture), split into tokens, and a row matches when its key contains every token. An empty token set means unfiltered. The filter uses core fieldset markup and has a filtered empty state. | Ruby and JS parity is verified (collation.out), which fixes the QA-17 'lodz' mismatch and the combining-mark-only query. The markup is consistent with core filters (UX-12). | \p{Mn}-based folding (diverges from the JS). SQL LIKE (adapter-dependent; list values live in YAML). |
| P-D7 | New action sort_values: PATCH .../values/sort, direction asc/desc, audited as 'sort_values' with before and after order_sha256. The sort is stable, and inactive enumerations are sorted together with active ones. Lists are saved through save_field!; enumerations are updated with a chunked CASE update of changed rows only. There is no server confirmation panel; a JS data-confirm is used. | Large lists need ordering without posting a full permutation. The order digest makes the previous order attestable (SP-12). update_all is safe because no update callbacks exist in 5.1 to 7.0. | Reuse the reorder audit action. One UPDATE per row. Move-to-position (out of scope). |
| P-D8 | update_enumerations gains an opt-in batch_scope=page. It takes a non-empty subset of the field's ids, ignores positions, and checks duplicates on the merged state. state_hash is checked as in full mode. The form carries a leave-unsaved guard. Full mode is unchanged and unknown scopes are rejected. | Pagination cannot satisfy the full id-set contract. An explicit mode keeps T-ACT-21. The guard prevents silent loss of page edits on pagination (UX-12). | Accept subsets in full mode (weakens tamper detection). |
| P-D9 | reorder_values keeps its ordered_values[] array contract and gains order_sha256 in its audit. | Its only UI consumer (drag) is bounded at 500 values; sort_values covers large lists. | A JSON variant (a second contract with no consumer). |
| P-D10 | Storage enforcement uses the limits area's model validation and RecordInvalid mapping only, with no project pre-check. BaseService#save_field! sets the non-persisted record.dcf_storage_ceiling to ProjectStoragePolicy.ceiling_bytes. The plugin setting project_storage_ceiling_kib defaults to 2,048 and has a minimum of 64. StorageLimits.effective_limit then uses min(column limit, max(ceiling, persisted bytes)). New list values from project services are capped at 255 characters. | One mechanism, one error path and one set of keys (R5, UX-04). It closes the stored DoS by non-admins on PostgreSQL and SQLite (SP-03) without blocking edits of fields an admin already made large. The admin form, API and import are untouched. | A project pre-check guard (revision 1; duplicates the model validation). A ceiling for every path (restricts trusted admins). A constant instead of a setting (no override). |
| P-D11 | Editor JS and CSS are loaded only by the head hook (ClientConfig.editor_page? includes this controller). Project views include only dcf_config.css, plus dcf_value_reorder.js when sortable and dcf_values_page.js in page mode. | Nothing is loaded twice (R2, R4, BC-13). The per-view assets are not in the hook. | content_for for the editor assets too (double load next to the hook). |
| P-D12 | edit_dependencies shows the global/shared banner based on the child field's scope. It shows text_dcf_parent_missing for a dangling parent and text_dcf_parent_not_available for a non-relevant parent, without an editor. Banners and the confirm panel use dcf_flash_box, which prepends notice_icon on 6.0+. | The mapping is stored on the child. The specific empty states replace the misleading 'No values yet.' The icon fills core's reserved padding on 7.0 (UX-10). | Parent-scope banner. A 404 on GET. |
| P-D13 | There are no server import or export endpoints at project level. Import is applied client-side and saved by the normal Save. source and import travel at the top level of the payload (schema v1). They are documented as client-reported, informational metadata. | Follows D7. The server-computed delta and digest are authoritative (SP-12). | A server import action with preview. |
| P-D14 | Dependency saves on shared or global fields keep no confirmation panel; the banner is shown instead. | Unchanged behaviour. Removing links destroys no stored data, and the delta records the change. | A confirm panel for replace imports on shared fields. |
| P-D15 | UsageCalculator.page_usage uses 2 grouped queries per page plus one load of the child records found through the limits FieldIndex. Counts are exact. | Uses one topology helper (R18) and is query-invariant in page size (R16). | Per-row capped counts. |
| P-D16 | Without JavaScript the dependency page shows text_dcf_editor_noscript and the Save button stays disabled. No legacy matrix is rendered. | A second renderer would bring back the page-weight and Rack problems. A disabled Save prevents misleading outcomes. | A noscript matrix below a threshold. |
| P-D17 | On 409 the page re-renders the fresh DB state and passes the posted mapping as conflict: to DependencyEditorConfig.for_project (data-dcf-editor-conflict-mapping); the shared conflict panel offers Use my version, Keep the current version and Export my version (CSV). Nothing is applied automatically. | Concurrent edits on shared fields are likely, and an applied import of thousands of rows must not be lost (QA-18). | Discard the posted state (revision 1). Auto-merge (unsafe). |
| P-D18 | The payload is parsed once per request. DependencyMappingService exposes parsed_payload, and the controller reuses it on 422. On 409 the service raised in the preamble before parsing, so the controller parses exactly once, after authorization, to build the conflict state. | Halves the cost of the largest inputs (SP-17) and keeps parsing behind authorization. | Re-parse in the controller on every error (revision 1). |
| P-D19 | translate_error(error_or_key) (one parameter; callers holding an OperationError call translate_error(e)) HTML-escapes every interpolation value before l(). It is used for every flash of this controller. Payload content never goes into a flash. | Redmine renders flash with html_safe in 5.1 to 7.0 (SP-06). | Escape at each call site (easy to forget). |
| P-D20 | prepare_dependencies reloads @field before computing state_hash and rendering, for every error re-render and for GET. | The service mutates the controller's instance before save!, so a re-render from that instance would make every corrected resubmit a 409 (R9). | Compute the hash from a fresh find (equivalent, but leaves the mutated instance in use for rendering). |

### limits (large_lists_limits_design.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| L1 | Register every new CustomField callback in one new module, Patches::CustomFieldValidationPatch, prepended to CustomField in init.rb after CustomFieldPatch. It holds before_validation :dcf_apply_dependencies_json and validate :dcf_validate_dependencies_json (method bodies owned by the editor area) plus validate :dcf_validate_storage_limits (this area). CustomFieldPatch.prepended registers nothing new. | Registering inside CustomFieldPatch.prepended broke 14 existing examples. Their stand-in class (spec/patches/custom_field_required_validation_spec.rb:31-33, prepend at :60) has no callback API (V11). Symbol callbacks are deduplicated when init.rb loads twice (V12). Every before_validation runs before every validate, so the storage check always measures the decoded and pruned mapping. | Registration inside CustomFieldPatch.prepended, as in server S13 and editor 2.3: breaks specs. A DB-backed rewrite of the stand-in spec in the same commit: possible, but it couples unrelated work. Validating in the formats' validate_custom_field: no error details or interpolation, and core list is missed. |
| L2 | Measure exact bytes with CustomField.type_for_attribute(col).serialize(preview). The format_store preview comes from storage_preview(custom_field, store), called as format.storage_preview(record, record.format_store), which shares ONE sanitize-only normalizer (normalized_store_pairs) with before_custom_field_save. D6 pruning is never part of it. | type.serialize is the write path, so the result is exact (V4: 61,062 = 61,062; V5 boundary). A shared normalizer keeps preview and write byte-identical, including parent id normalization. Keeping pruning out of before_save preserves today's API, extended-API and cascade semantics (R8/BC-02). Core list and enumeration have a no-op before_custom_field_save, so their raw store is exact. | Pruning in the normalizer (silently rewrites mappings on every save path). Measuring the raw store (10 bytes off). Estimating with sum(bytesize+3) (inexact when YAML quotes values). |
| L3 | column_limit(column, model = CustomField) = columns_hash[col].limit, with a 65,535 fallback when the column is :text, the limit is nil and Redmine::Database.mysql? is true. A nil limit means no check. | Verified 65535 / 16777215 / 4294967295 on Rails 6.1 and 8.1 (V1). This signature is the one the server and editor designs already call, so one seam serves all callers. | column_limit(model, column) (the revision 1 signature, conflicting). Hard-coding 65,535 (wrong after widening). Querying information_schema on every save. |
| L4 | Check a column only when new_record? // will_save_change_to_attribute?(column). | Unrelated edits never fail (V5), and the extra cost is only paid on real changes. | Always check (blocks unrelated edits of legacy oversized rows). |
| L5 | Guard list, enumeration, depending_list and depending_enumeration; nothing else. | These are the formats the plugin writes through. A 5,000-value core list parent is 77 KB and fails today. | Depending formats only. Every format (would reach into other plugins). |
| L6 | One model error: :dcf_storage_too_large under activerecord.errors.messages, with locale-delimited %{size}/%{limit} and integer bytes/max_bytes/column in errors.details. The label key field_value_dependencies is owned by this area with the wording 'Dependency mapping / Abhängigkeitszuordnung / Mappage des dépendances / Afhankelijkheidskoppeling'. | This gives grammatical full messages in all four locales and matches existing plugin copy (notice_dependencies_saved). 'Value dependencies is too large' is ungrammatical everywhere (UX-03). The details let services rebuild the violation without parsing text. | Server dcf_too_large with %{bytes} (dropped). :base errors (no field label). |
| L7 | One service mapping in BaseService. A RecordInvalid carrying a storage violation becomes OperationError :error_dcf_values_too_large or :error_dcf_mapping_too_large, with summary (for audit) and interpolations {field, size, limit}. ActiveRecord::ValueTooLong becomes :error_dcf_value_too_long with a summary of class, column identifier, field id and byte counts, and never the DB message. OperationError gets the consolidated kwargs summary:, interpolations: and payload:. | The model validation already covers all four formats, so a project pre-check would duplicate the work and could produce two errors or two audit rows (QA-04). An exception raised inside a rescue clause is not caught by its siblings, so each rejected call writes exactly one failure row. SP-09 requires no SQL in error_message, because project managers can read it. | Project guard_storage!/save_field! pre-check (dropped). Generic :error_save_failed (unhelpful). |
| L8 | One audit cap, AuditPayload (16,384 bytes per before/after), used by AuditRecorder. Output under the cap is byte-identical to ActiveSupport::JSON.encode. Above the cap, values shrink deterministically while top-level scalars are kept, with marker keys payload_truncated, payload_bytes and payload_sha256. Ids are capped at 1,000 and error_message at 4,000 chars. No audit table migration. | An audit insert inside the change transaction can then never overflow TEXT. The marker names cannot collide with the project delta's own sha256 and truncated (R10). Keeping top-level scalars preserves counts and digests. Verified on ActiveSupport 6.1 and 8.1 (V19). | Project 60,000-byte cap with marker {v, truncated, bytes, sha256} (collides, bigger rows). Migration 002 widening the audit columns (unbounded, needs a table copy). |
| L9 | Project delta caps: CAP 20, DEFAULTS_PER_PARENT_CAP 3, labels cut by JSON-encoded bytes to LABEL_MAX_BYTES 80, then '...'. | A character cap cannot bound bytes, because '<' encodes as < (6 bytes). The measured worst case over 5 adversarial label classes is 13,603 B, under 16,384, so update_dependencies rows are never shrunk (V19). | LABEL_CAP 120 chars and 5 defaults (the worst case exceeds 16 KB). LABEL_CAP 80 chars (still unbounded in bytes). |
| L10 | Rake tasks: report_sizes (StorageReport, the one report implementation: read-only, raw select_all, CORRUPT/SUSPECT, load_ms, table or CSV, FAIL_ABOVE) and widen_core_columns (MySQL only, dry run by default, CONFIRM=1, a single ALTER built from information_schema, idempotent, never narrows, guarded REVERT=1 in strict mode). The widener validates charset and collation names against /\A[A-Za-z0-9_]+\z/ and warns when max_allowed_packet is below 16 MB. | Verified end to end on MariaDB (V9) and with a fake connection (V21). Identifier validation closes the raw interpolation gap (SP-19). Nothing ever alters core tables automatically. | Server StorageLimits.report (dropped). Rails change_column. A migration (forbidden). |
| L11 | The default widening type is MEDIUMTEXT; TYPE=longtext is available. | MEDIUMTEXT is 6 times the largest realistic case. The 4 MiB transport cap maps to about 6.4 MB of YAML, below 16 MB, so validation stays a meaningful backstop. | LONGTEXT by default (user decision). |
| L12 | Issue-form payload: defer to the server-owned canonical attribute table. data-dcf-map is sanitized but not pruned, enumeration child ids are JSON integers when canonical, and data-dcf-defaults appears only when non-empty. This area withdraws its revision 1 'pruned map' claim. | There must be one contract with one owner (R1/QA-01/BC-01). An unpruned map is needed so a stored legacy parent value still maps (D1). Its size is bounded by the stored YAML: under about 95 KB on MySQL TEXT. | A pruned map (breaks D1 legacy parents). Option-index encoding (fragile). |
| L13 | One topology helper: RedmineDependingCustomFields::FieldIndex. It reads raw format_store with an anchored regex and falls back to deserializing. Server names: FieldIndex.load, FieldIndex.new(records:), parent_id, children_ids (sorted by position, id), descendant_ids, ancestor_ids. DependencyRules::Graph and the per-hop find_parent walk are removed, and DependencyRules ancestor/descendant/in_cycle?/parent_candidates/children_of and UsageCalculator.page_usage take an index. | Regex extraction takes 0.04 ms vs 16.6 ms of YAML parse per S1 row (V14). One query replaces the per-hop lookups. Never used on issue pages or the context menu, so G6 gates are untouched (R16, R18). | Server Graph (parses each field's YAML). Both helpers side by side (duplication). |
| L14 | Memoize only on CustomField instances (keyed by the raw input they derive from, including the raw dependencies_json String for the parsed payload) and on per-operation objects. Never on format singletons, Rails.cache, CurrentAttributes or process-level caches. | Format objects are process-wide singletons (core field_format.rb:24-25,64). Per-operation memoization needs no invalidation. | CurrentAttributes. A digest-keyed process cache. |
| L15 | One generator: the arithmetic DcfLargeList (quality owner) pinned at 233acf899217e962 (names(5570, tricky_every: 97)) and 466b240daca61be9 (partition), JS twin, spec/quality/dcf_large_list_spec.rb; this area adds the byte helpers (STRESSORS/with_stressors, BRAZIL_SIZES/partition_sizes, element_bytes, yaml_list_bytes, values_of_yaml_bytes). | There must be one generator with one set of pinned hashes (R12); the arithmetic one has proven Ruby and JS parity (quality E17). Exact byte targets come from ASCII padding on top of any generator (V20: 16 / 1,000 / 65,535 / 65,536 / 200,000 exact on Ruby 3.2 and 3.3). | The mulberry32 generator pinned at 0634a624422f2f06 (limits revision 2; dropped, see Q9). The revision 1 base-60 generator (conflicting hash and signature). |
| L16 | Test the MySQL path on PostgreSQL CI by stubbing StorageLimits.column_limit (bytes vs bytes-1), with :mysql-tagged specs that run only on MySQL, and a verified manual MariaDB recipe. There is no MySQL CI job by default. Editor fixtures stub column_limit to nil, and storage-base becomes a placeholder. | CI stays manual-only and unchanged. Fixtures stay identical on PostgreSQL and MariaDB and independent of DB sequences (R13). | A workflow_dispatch MariaDB job (user decision). |
| L17 | One storage UX: a server usage line (stored bytes, text_dcf_storage_usage) at 90% of the limit on the admin form via the view_custom_fields_form_upper_box hook and on project pages via a helper, with an admin-only README line (text_dcf_storage_admin_help). One client estimate warning (text_dcf_storage_estimate) uses the same 90% threshold (data-dcf-editor-storage-warn) and the attributes data-dcf-editor-storage-limit, -storage-base and -values-limit. Units are delimited bytes everywhere. | Removes the two competing hints with different units and thresholds (R20/UX-04). Project managers never get a README reference. | Editor KB-based 90% hint plus limits 80% bytes hint (inconsistent). |
| L18 | translate_error(error_or_key) HTML-escapes every interpolation value with ERB::Util.html_escape before l(), and flash messages never carry payload content. | Redmine renders flash with v.html_safe (core-5.1 application_helper.rb:487, core-7.0 :527) and l() does not escape, so an interpolated field name would be stored XSS (SP-06). | Escaping at each call site (error-prone). No field name in the flash (less helpful). |

### quality (large_lists_quality_protocol.md)

| Id | Decision | Rationale | Alternatives |
|---|---|---|---|
| Q1 | Twelve gates: the owner's G1-G6 made measurable, plus G7 Backward compatibility/upgrade, G8 I18n, G9 Docs/CHANGELOG/version, G10 Version matrix, G11 CI policy and tooling hygiene, G12 Data integrity and storage limits. Each gate has a fixed evidence format and an applicability matrix per WP. G1 additionally requires contract conformance: every canonical contract row has a generated fixture case and a consuming jsdom test. | The owner's constraints map one-to-one onto checkable gates. The review showed that integration can break while both sides stay green, so contract conformance is part of correctness. | Fold G7-G12 into G1/G2 (less visible). A single checklist gate (not measurable). |
| Q2 | PASS only from observed output: command, exit code, summary line, log path, plugin_worktree_sha with dirty=0, redmine_sha and ruby from the DCF SUMMARY block. Stale evidence is rerun; NOT RUN is never DONE. | Owner's rule; the scripts print one summary block per run so evidence cannot be confused across versions. | CI links only (manual, costly). Prose claims (rejected by the owner). |
| Q3 | The .codex scripts are redmine_clone.sh, test_setup.sh, test_plugin.sh (as the owner's prompt names them) plus test_matrix.sh, rubocop_ratchet.sh, lib/common.sh and lib/rubocop_ratchet.rb, with shared exit codes, a work dir outside the repo, rsync --delete copies and a DB reset per setup. test_plugin.sh gains --write-fixtures, which points DCF_JS_FIXTURE_DIR at the repo so regenerated fixtures are not lost in the rsynced copy. | The chain mirrors run_baseline.sh and CI and was verified on all four versions (E1). Fixtures generated inside the Redmine checkout copy would be overwritten by the next sync, hence the explicit repo target. | Symlink the plugin (differs from CI). Write fixtures into the copy and copy back by hand (error prone). |
| Q4 | Deviation from D10 (explicit): the ratchet uses core 7.0's config with plugins un-excluded through a committed plugin .rubocop.yml overlay (TargetRubyVersion 2.7, TargetRailsVersion 6.1, Rails/HttpStatusNameConsistency disabled), with a dynamic merge-base and per-file per-cop counts. | The raw config suggests :unprocessable_content (ArgumentError on Rack 2.2, verified), params.expect, anonymous block forwarding and Array#intersect?. Core's own run never reads the overlay (E5). | Raw core config (unsafe hints). Static allowlist JSON (goes stale). |
| Q5 | Ruby 2.7 compatibility is enforced by RuboCop's 2.7 parser on all Ruby files plus a compat grep on added lines. The grep now also flags javascript_tag (inline scripts) and the en/em dash characters in code, assets, tests, docs, README and CHANGELOG additions. | No Ruby 2.7 binary is available; the parser catches syntax, the grep catches runtime-only APIs. E25 showed the current inline script uses javascript_tag, so a '<script' grep alone misses it; the owner forbids en/em dashes. | Install Ruby 2.7 (heavy). Rely on the 5.1 run (CI uses Ruby 3.2). |
| Q6 | Deviation from D10: devDependencies are jsdom ~29.1.1 plus jquery 3.7.1 and acorn ~8.18.0; npm run check parses every shipped asset as ES2017. | jquery 3.7.1 is core 6.1/7.0's version, needed for serialize parity and jQuery-trigger tests; acorn enforces the ES2017 level chosen by the frontend (E15). | ESLint (heavier). No language-level gate. |
| Q7 | System specs are opt-in (DCF_SYSTEM_SPECS=1) with core's capybara + selenium headless Chrome, Selenium Manager by default, DOM-state option assertions and a.logout login checks. The scenario list adds the project editor (Save disabled until init, no false beforeunload) and the admin URL-encoded size pre-check. | Verified on 5.1 and 7.0 (E8-E10). The new scenarios cover browser-only behaviour from the editor and project reviews. | Cuprite (plugin Gemfile change leaks into every bundle). Always-on system specs (slow, flaky). |
| Q8 | Characterization first for points 1-6, committed alone and shown green on the base matrix; refactor commits flip only listed assertions; mutation checks now include the D1 per-value exemption, the payload integer pre-scan, the visibility gate on data-dcf-parent-values and flash escaping. | Several behaviours had no spec; the new guards are the ones the review identified as security or data-loss critical. | Rewrite specs during the refactor (regressions invisible). |
| Q9 | REVISED: ONE large-list generator, the limits area's arithmetic algorithm (no PRNG) with tricky-value injection, in spec/support/dcf_large_list.rb, plus a JS twin test/js/support/large_list.js. sizes() uses a naive left fold. One Ruby spec (spec/quality/dcf_large_list_spec.rb) and one JS test pin names(5570, tricky_every: 97) at 233acf899217e962 and the partition at 466b240daca61be9. The mulberry32 generator is dropped. | Verified byte-identical on Ruby 3.2.6, 3.3.6 and Node 22.22.0 (E17). The limits algorithm already provides exact YAML byte targets and tricky values, so jsdom and editor tests now see YAML/CSV stressors at scale. Ruby Array#sum uses Kahan-Babuska summation, which JS lacks, hence the explicit fold. | Keep mulberry32 (no tricky values, breaks the limits builders). Two generators (pinned hashes conflict on one file). |
| Q10 | REVISED: performance assertions use only invariance (small vs large input) or differential (plugin path minus stubbed path) query and YAML counts through shared helpers; no absolute counts anywhere. Parents are resolved from customized.available_custom_fields first, find_by only for parents not available on the record. Wall clock only for pure computations with 10x headroom, plus opt-in :perf specs. | E22: resolving 5 distinct parents (one role-restricted) from loaded objects costs 0 queries on 5.1 and 7.0, find_by costs 5 or 6, so the original 1 vs 5 gate was unreachable with the server lookup and reachable with resolution from loaded objects. Absolute counts are version-sensitive. | Define the gate as O(distinct parents) (weaker, hides a cheap fix). Absolute counts (flaky across versions). |
| Q11 | rails_helper: random order with the seed printed; drop the second init.rb load; reset I18n.locale after each example; dedicated tracker/status builders; tag exclusions for :mysql (unless MySQL) and :perf (unless DCF_PERF_SPECS=1); system opt-in. | Verified green on 3 seeds and on 4 versions without the double load (E11, E12); the tags are needed by the limits specs. | Defined order (hides leaks). Keep the double load (duplicate callbacks). |
| Q12 | Lint runs once per matrix and in rspec-70.yml behind a lint input (fetch-depth 0, base_ref input); JS tests and core stylelint run in js-tests.yml; all workflows workflow_dispatch only with permissions: contents: read. | Lint is version independent and needs the 7.0 bundle; stylelint needs only core's config. | Separate lint workflow (duplicate setup). |
| Q13 | Claude may deliberately dispatch the manual workflows after local gates PASS (UD-32, resolved), at most once per workflow per SHA unless a fix was pushed, never editing triggers, reporting workflow, SHA (headSha), inputs, run URL and conclusion; a spec guards manual-only triggers. | Owner constraint that CI stays manual-only. | Free dispatch (against intent). No dispatch at all (loses optional CI evidence). |
| Q14 | REVISED: the locale parity spec also fails on duplicate mapping keys at any depth inside one file (Psych.parse_stream tree walk), resolves every value of every I18N constant map in all four locales with raise: true, scans symbol literals and dcf_* error symbols as 'used keys', enforces plural subkeys, the per-locale quote convention, no en/em dashes, and a reviewed English-leftover allowlist including the new identical-by-design values. | E24: YAML keeps the last duplicate silently, so the original flattened-set comparison could not see cross-area collisions; keys referenced only from constant maps escaped the l()/t() regex scan. | YAML.load comparison only (blind to duplicates). Manual review only. |
| Q15 | WP-01 rewrites the 7 endless defs; WP-02 deletes test/spec/** and test/test_helper.rb, removes the 17 en/em dashes from README and CHANGELOG, switches label_default_value to field_default_value and amends test plan section 8. WP-04 rewrites custom_field_required_validation_spec.rb DB-backed. | The files are never run and broken; endless defs fail the 2.7 gate; the dash rule needs a clean starting point (E27); the stand-in classes of that spec broke 14 examples when a callback was registered in CustomFieldPatch (limits V11). | Port the broken specs (already covered). Keep the stand-ins and only avoid them (fragility stays). |
| Q16 | New code and specs use numeric 422; Rack status deprecation warnings stay at or below the baseline 11 per run on 6.x/7.0. | Works on Rack 2.2 and 3.x without warnings (E3, E19). | :unprocessable_entity (warnings grow). :unprocessable_content (breaks 5.1). |
| Q17 | NEW: the quality design carries a canonical cross-area contract section (ownership register, issue-form attributes, head hook, payload and editor, storage/audit/topology, D1 per value, locale registry). Each shared artifact has one owner area, one shape and one test source; gates test only these definitions, and changing one requires changing that section first. | The review found the same contracts specified twice with incompatible shapes (attributes, meta tag, payload parser, editor DOM, value options, storage API, audit cap, locale keys, generator). A gate cannot be measurable against two definitions. | Leave contracts to each area (drift, as found). A separate contract document outside the plan (one more place to drift). |
| Q18 | NEW: issue-form contract choices: data-dcf-context form/bulk; data-dcf-parent-values gated by parent.visible_by? replaces data-dcf-allowed; attributes emitted only when effective_parent_id resolves (valid, acyclic, not self, visible); stored cycles and self-parents excluded (UD-08); data-dcf-map sanitized but not pruned; enumeration ids as numbers; id-less radio sentinel; FD-22 left to the owner with both outcomes tested; JS-generated hint ids with aria-describedby and one page-level live region. | form matches new and edit records and the frontend prototype (E26); the gate prevents leaking role-restricted parent values (SP-04); omitting attributes on cycles keeps the client consistent with server validation, which treats cycle members as unconstrained (UD-08); an unpruned map is exactly what validation uses; a JS-generated id is safe because replaceIssueFormWith copies only control values and the label scan covers only server markup. | data-dcf-allowed without a gate (leak). Attributes on cycles (client would deadlock both members blank while the server leaves them unconstrained). Pruned map (legacy parent values stop mapping on the client only). |
| Q19 | NEW: single head hook: meta name=dcf-i18n (flat object with the 10 keys of ClientConfig::I18N), then the one UMD depending_custom_fields.js, context_menu_wizard.js and the CSS; editor assets come only from the head hook for the two editor controllers. | One UMD file removes the 'rules file missing, runtime inert' failure mode (FD-1); the only non-i18n config (basePath) is replaced by the form action, so a nested config object is empty; a single asset owner avoids double loading and the T-ASSET contradiction. | Server's nested meta and label_dcf_hint_* keys (frontend and wizard read the flat one). content_for for editor assets (lost on the /new AJAX re-render). |
| Q20 | NEW: one DependencyPayload: strict schema with top-level version/source/base/value_dependencies/default_value_dependencies/import, unknown keys rejected, parse returns nil or a Result and never raises, 4 MiB and max_nesting 3 on both paths, numeric-token pre-scan and 63-bit integer limit before to_s, no null/bool/float, create_additions false, too_large mapped to size messages, parse memoized once per request; payload golden files written by the real JS serializer and posted by Ruby request specs to both pages. | The two parser prototypes were mutually incompatible (meta vs top-level source, raise vs Result, 4 vs 16 MiB) and both accepted huge integers (SP-01: 1M digits cost 5.7 s with the GVL held). Golden files make either side's drift fail. | Keep two parsers (one page always breaks). 16 MiB cap (higher per-request cost for non-admins with no realistic need). |
| Q21 | NEW: contract fixtures are deterministic by construction: fixture records get explicit ids in disjoint high ranges, a normalizer scrubs tokens, state hashes and asset digests, a guard fails on any id-bearing number outside the ranges, a sequence-bump self check renders twice inside savepoints, and G2 runs the fixture specs under two seeds. | E23: fixed ids stay identical while sequence ids drift between renders on 5.1 and 7.0, and the sequence never reaches the fixed range on PostgreSQL. Normalizing only custom field ids left enumeration and project ids sequence-dependent (R13). | Placeholder replacement by creation order (kind-aware rewriting, collision-prone). Seed-only checks (catch drift late, not deterministic). |
| Q22 | NEW: storage, audit and topology are owned by limits: all new CustomField callbacks in one separate CustomFieldValidationPatch module; StorageLimits.column_limit(column, model = CustomField); one model error key dcf_storage_too_large; one RecordInvalid mapping in BaseService (no pre-check guard); sanitized ValueTooLong audit rows; escaped flash interpolations; AuditPayload 16 KB with payload_sha256 marker; FieldIndex as the only topology helper and StorageReport as the only report; pruning only in the admin JSON transport. | Four incompatible storage designs existed and registering callbacks in CustomFieldPatch broke 14 examples (V11); flash is rendered html_safe (SP-06); the limits sha256 marker overwrote the project delta's digest (R10); normalization-time pruning would rewrite mappings on unrelated API and plugin saves (BC-02). | Server's StorageLimits API and registration (breaks specs). Project pre-check plus limits mapping (two mappings, two keys). |
| Q23 | NEW: D1 leniency is per value (values contained in value_was are exempt while the parent is unchanged), tested from one shared case table by the Ruby rules and the JS rules. | With the whole-set rule, adding an allowed value to a multi child that holds a legacy value always failed validation, although the client keeps legacy values selectable; core's ListFormat already uses the per-value idiom. | Client drops legacy values on any child edit (silent data loss on every edit). |
| Q24 | NEW: an upgrade-notes register UN-01..UN-45 lists every change a 0.0.15 user can notice with its CHANGELOG section and owning WP; G9 checks the entries each WP touches and the release WP checks all. Version targets: four releases (UD-01); JS shims and CustomFieldVisibility deprecated in 0.1.0, removable no earlier than 0.2.0; project nested params deprecated in 0.1.0, removable no earlier than 0.2.0; admin nested safe attributes kept permanently. | No area design collected all user-visible changes and several had no compatibility row (BC-14). Admin safe attributes are used by other plugins (E28), which is a concrete reason to deviate from D5's one-minor-version window on the admin side. | Per-WP CHANGELOG lines without a register (items fall through). Remove admin nested params after one minor (breaks jc-redmine_extended_api writes). |
| Q25 | NEW: the wizard save authorization bypass is tracked as a separate SECURITY defect (out of the 9 points per D4) scheduled no later than the release that ships point 1, with a CHANGELOG Security entry; WP-15 pins that the endpoint still requires login, visibility and editability. | The controller assigns custom_field_values directly, bypassing core's editable filter (SP-07); point 1 touches this controller and route, so the release must not ship without a plan for it. | Leave it as 'hardening' (understates a privilege issue). Fold it into point 1 (contradicts D4). |

## 4. Which decisions block which release

Release structure after UD-01 (resolved): 0.0.16 (patch release) and one release 0.1.0 with milestones M1, M2 and M3.

- **0.0.16**: all needed decisions are resolved (UD-01, UD-02, UD-03, UD-29, UD-30, UD-31, UD-32, UD-33, UD-34).
- **0.1.0, milestone M1**: UD-04, UD-05, UD-06, UD-07, UD-08, UD-25, UD-26, UD-27, UD-28 (open).
- **0.1.0, milestone M2**: UD-09, UD-10, UD-11, UD-12, UD-13, UD-14 (open).
- **0.1.0, milestone M3**: UD-15, UD-16, UD-17, UD-18, UD-19, UD-20, UD-21, UD-22, UD-23, UD-24 (open).

The open decisions only need an answer before the milestone that implements them starts.
