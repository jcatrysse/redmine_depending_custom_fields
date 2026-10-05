# Frontend runtime design, revision 2: points 1 (client), 2, 3, 4, 5 (client)
> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 (client side), 2, 3, 4, 5 (client side). Owner area: frontend (issue-form runtime, context-menu wizard script, plugin CSS, runtime locale keys, client contract C1 jointly with the server area). Work packages: WP-16, WP-17, WP-18, WP-19, WP-20 (primary, release 0.1.0 (M2)); WP-15 (named wizard save route and form action, 0.1.0 (M2)); WP-01 (JS toolchain), WP-03 (legacy bulk hotfix that pre-ships row B1m) all 0.0.16, and WP-04 (legacy jsdom characterization, 0.1.0 (M1)); WP-05 (`DependencyRules.parent_of`, `effective_parent_id`, shared rules case table, 0.1.0 (M1)), WP-09 and WP-10 (server D1 per value, copies, effective parent, 0.1.0 (M1)) for the server requirements of section 14. Decisions: UD-01, UD-02, UD-03, UD-04, UD-05, UD-06, UD-08, UD-09, UD-10, UD-11, UD-12, UD-13, UD-30, UD-32.

Scope:
- Replace `assets/javascripts/depending_custom_fields.js` with one UMD file. The file holds the pure rules and the DOM runtime, and is driven by per-field data attributes.
- Remove every global the current JS and `context_menu_wizard.js` depend on.
- Publish the canonical client contract (C1) that the server, limits and quality areas must use verbatim.

The plugin is read-only for this design. The scratchpad root (`$S`) is `<planning scratch space, not part of the repository>`.

## 0. What changed in this revision

Each item names the review issues it answers. Section 0.1 lists every deliberate deviation from the default decisions.

1. **One canonical contract C1 (section 3).**
   - It replaces both the server design's section 4 table and the previous frontend table.
   - The context vocabulary is `form|bulk` (binding, `large_lists_compatibility.md` section 2.4; this revision originally used `edit|bulk`). Wherever this document says "edit context" or `ctx == edit`, it means `data-dcf-context="form"`, emitted by `edit_tag` for new and persisted records alike.
   - A child is "active" only when it has an effective parent: `DependencyRules.effective_parent_id(cf)` returns a parent that exists, has the same type and family, is not itself, has an acyclic ancestor chain, and is visible to the current user (gap 2). Only active children get parent attributes. This closes the leak of role-restricted parent data (SP-04) and the map leak for invisible parents.
   - Stored cycle members get no parent attributes (UD-08, gap 2): server validation treats them as unconstrained, so the client leaves them unfiltered too. The client still guards against cycles with its visited set.
   - The map is sanitized but not pruned, so it is exactly what server validation reads.
   - `data-dcf-allowed` is dropped. `data-dcf-parent-values`, `data-dcf-parent-label` and `data-dcf-stored` are added.
   - Issues: R1, QA-01, UX-02, BC-01, SP-04.
2. **One head hook and one meta tag.**
   - Meta name `dcf-i18n`, payload a flat JSON object of the 10 runtime keys (binding, compat section 2.4; this revision originally proposed `redmine-depending-custom-fields` with a nested `{"i18n":{...}}` payload), locale keys `text_dcf_hint_*`. The `label_dcf_hint_*` keys are deleted.
   - The rules module is folded into `depending_custom_fields.js`. The script list is therefore unchanged from today, and the "rules file missing, runtime inert" failure mode no longer exists.
   - Issues: R2, BC-01, R11.
3. **D1 per value on both sides.**
   - Legacy is defined only by the server D1 baseline. `data-dcf-stored` carries it: child and parent `value_was` for persisted records, and the copy source's stored child and parent values for issue copies (UD-06, compat section 2.4 "Legacy marker").
   - Issue copies with `data-dcf-stored` keep a legacy value under the unchanged parent: it stays enabled, marked and posted, and the server, which judges copies against the source, accepts it (gap 6, row F6b-a).
   - Plain new records (no `data-dcf-stored`) drop disallowed values, as today (row F6b-b).
   - A value posted on a failed save that is not stored is never shown as legacy.
   - Parent A to B to A restores the stored legacy value.
   - Issues: R14, R15, QA-20, UX-07.
4. **Defaults at load are applied only to new records without a baseline, that is without `data-dcf-stored` (UX-14, UD-12).**
5. **Bulk edit and the wizard (D2 revised).**
   - "(no change)" stays visible and selectable for a concrete parent.
   - Per-parent defaults are still applied, with a visible hint.
   - A child is forced to "(none)" only when nothing can be valid: the parent is "(none)", or the parent value has no links.
   - The wizard root opens on "(no change)".
   - Decisions: UD-09 (bulk semantics), UD-10 (required "(none)"), UD-11 (wizard root).
   - Issues: UX-08, BC-05, QA-09.
6. **Server deliverables are now explicit server work items with specs (R6, QA-12):** the blank sentinel for single radio children, and `__none__` for required depending children in bulk (FD-22, adopted).
7. **Hints (UX-05, UX-06).**
   - Hints name the parent field and the offending values, with generic fallbacks.
   - Each hint has a JS-generated id tied to the control with `aria-describedby`.
   - `role=status` is no longer set per hint. One debounced page-level polite live region is used instead.
8. **MutationObserver.** Added markup is initialised inside the observer callback, which runs as a microtask. All mutations delivered in one callback are coalesced and the added roots are initialised synchronously in that callback; there is no timer debounce. There is no 25 ms window of unfiltered fields after AJAX re-renders (QA-15, QA-20b). This is a deliberate deviation from the wording of point 3 ("filtered, debounced MutationObserver"), recorded as a contract row in `large_lists_compatibility.md` section 3 (gap 13, section 5.11).
9. **Fixtures (R13, QA-01).** One fixture mechanism: real request rendering, explicit record ids, a shared normalizer and a self-check. Every required contract case has a jsdom outcome test.
10. **Wizard.** Same-origin check before posting (SP-15). Wizard labels wrap their selects, and hint width is capped (UX-13).
11. **CSS fix found while revising.** Core `.check_box_group label { display: block }` overrides the UA `[hidden]` rule. A plugin rule is therefore mandatory to hide disallowed choices (section 8).
12. **CHANGELOG and README.** Full list of the frontend changes users will notice, with explicit version targets (BC-08, BC-09, BC-14). Release targets follow UD-01: every frontend runtime item of this document ships in 0.1.0 (M2) (WP-15 to WP-20).

### 0.1 Deviations from the default decisions, with the concrete reason

| Default | Deviation | Concrete reason |
|---|---|---|
| D1 (whole-set "neither child nor parent changed") | Per value (UD-04): while the parent is unchanged, values contained in the child's `value_was` (or, for issue copies, the copy source's values, UD-06) are exempt and only newly added values must be allowed | With the whole-set rule, adding an allowed value to a multi child that holds a legacy value posts `[legacy, new]` and is always rejected (R14). Per value matches core `ListFormat#validate_custom_value` (`values - Array.wrap(value_was) - possible_values`, core-7.0 `lib/redmine/field_format.rb`). |
| D2 ("(no change)" hidden on descendants; child becomes default, else "(none)") | UD-09 (required children: UD-10). "(no change)" stays visible and enabled. The child becomes the per-parent default when one exists (shown with a hint), otherwise it stays on "(no change)". It is forced to "(none)" only for parent "(none)" or a parent value without links. | Example: setting Country=Belgium on 50 issues where some already hold City=Ghent would clear City on all of them. Today single children stay on "(no change)" (harness A1 posts `''`, which core bulk update skips), so this would be new data loss (BC-05, UX-08). |
| D4 ("wizard behaviour otherwise unchanged") | The wizard root opens on "(no change)" instead of `cf.default_value` (UD-11) | Today Save without touching anything writes the root default onto every selected issue (`app/helpers/context_menu_wizard_helper.rb:11`). Any cascade would make that worse (QA-09). The controller already skips blanks (`app/controllers/context_menu_wizard_controller.rb:49-62`), so "(no change)" posts nothing. |
| D5 ("at least one minor version") | Explicit targets (UD-01): the shims are deprecated in 0.1.0, kept throughout 0.1.x, and removable no earlier than 0.2.0 (together with the project nested params, which are deprecated in 0.1.0 and removable no earlier than 0.2.0) | BC-14 asks for explicit targets. `init.rb:14` is 0.0.15; per UD-01 the work ships in four releases, and this document's runtime ships in 0.1.0 (M2) (WP-15 to WP-20). |
| D10 (jsdom only) | Add `jquery 3.7.1` as a devDependency (same as quality Q6; acorn ~8.18.0 for the ES2017 gate; UD-30) | Needed to test `updateIssueFrom` serialize parity and jQuery-triggered (select2) changes against real jQuery. |
| Point 3 wording ("filtered, debounced MutationObserver") | Filtered, and coalesced per observer callback: all mutations of one callback are handled together and the added roots are initialised synchronously in that callback; no timer debounce (FD-15, gap 13) | A timer debounce leaves an unfiltered window after an AJAX re-render in which stale disallowed values can be submitted (QA-15, QA-20b). One task's mutations already arrive in one callback, so `replaceIssueFormWith` and `#content` replacement are still initialised once. Recorded in `large_lists_compatibility.md` section 3; implemented and tested in WP-17. |

### 0.2 Consolidation amendments (binding)

These amendments come from the consolidated plan and override older wording elsewhere in this document. Sources: `large_lists_compatibility.md` sections 2.4 and 3, `large_lists_work_packages.md` WP-15 to WP-20, critic gaps 2, 6 and 13.

| Topic | Binding rule | Sections touched |
|---|---|---|
| Release | All frontend runtime items ship in 0.1.0 (M2) (WP-15 to WP-20, UD-01). Prerequisites: the JS toolchain in 0.0.16 (WP-01), legacy characterization and `DependencyRules` in 0.1.0 (M1) (WP-04, WP-05), server D1 per value, copies and effective parent in 0.1.0 (M1) (WP-09, WP-10). JS shims deprecated in 0.1.0, removable no earlier than 0.2.0. | 0.1, 5.1, 9, 10, 13 |
| Context vocabulary | `data-dcf-context` is `form` or `bulk`; the client reads missing or unknown values as `form`. | 3.3, 3.7, 5.3, 5.4 |
| Emission predicate (gap 2) | Client emission relies on `DependencyRules.effective_parent_id(cf)`: valid (exists, same type and family, not self), acyclic and visible to the user (fail closed). `DependencyRules.parent_of(cf)` (WP-05) is the memoized raw lookup it builds on: it returns the parent record, or nil for blank, dangling, wrong type or family, or self. Stored cycle members and chains reaching a cycle get no parent attributes (UD-08). | 3.2, 12.1, 14 |
| Legacy marker (gap 6) | `data-dcf-stored` = server D1 baseline: `value_was` for persisted records, copy source values for issue copies (UD-06), absent for other new records. Row F6b is split into F6b-a (copy, kept) and F6b-b (plain new record, dropped). | 3.3, 5.4, 6, 9, 12.1 |
| MutationObserver (gap 13) | Coalesced per callback, synchronous init of added roots, no timer debounce; jsdom test: one `replaceIssueFormWith` insertion causes exactly one `init` per root. Recorded in compat section 3. | 0, 0.1, 5.11, 12.1 |
| Meta tag | `<meta name="dcf-i18n">` with a flat object of the 10 keys of `ClientConfig::I18N`. | 0, 3.6, 7 |
| Required "(none)" in bulk | `bulk_edit_tag` adds `<option value="__none__" data-dcf-required-none="1">` for required managed children; the runtime enables it only while the parent selection allows no value (UD-10, WP-19). | 3.4, 5.5 |
| Shared rules cases | `test/js/fixtures/shared/rules_cases.json` (WP-05; `spec/fixtures` is the DB fixture directory). | 4, 13, 14 |
| Fixture ids | Fixed per-kind id ranges from WP-02 plus the normalizer, the sequence-bump self check and two seeds (`--seed 1`, `--seed 4242`); support file `spec/support/dcf_js_fixtures.rb` (WP-16). | 2, 12.1 |
| Locale texts | Key names and owners stay here; the texts live only in `large_lists_i18n_registry.md`. | 3.6 |

## 1. Evidence

**Revised prototype (not plugin code):** `$S/design/frontend/proto2/depending_custom_fields.js` (single UMD file), `support.js`, `rules.test.js`, `runtime.test.js`.
- Run `NODE_PATH=$S/design/probe/node_modules node --test rules.test.js runtime.test.js` in that directory: 31 pass, 0 fail, 0 skipped (Node 22.22.0, jsdom 29.1.1, jQuery 3.7.1 loaded).
- acorn `ecmaVersion: 2017` parses the file.
- The 25,000-option, 5,000-key decide plus filter takes 29 ms, including map normalization.

**Previous probes, still valid:** `$S/design/frontend/p1_copy.js`, `p2_formdata.js`, `p3_params.rb`.
1. jsdom 29 `FormData` includes a selected disabled option, so tests use a spec-compliant entry list.
2. `CSS.escape` is missing in jsdom.
3. A native change reaches jQuery handlers with `isTrigger` undefined. `jQuery.trigger('change')` does not reach native listeners.
4. Duplicate scalar params are last-wins on Rack 2.2.24, actionpack 7.2.4 with rack 3.2.7, and actionpack 8.1.4. `x=&x=r1` gives `"r1"`.
5. Core `em.info {display:block}` beats `[hidden]`. Cited at core-7.0 `app/assets/stylesheets/application.css:1463` and core-5.1 `public/stylesheets/application.css:989`.

**New core facts used in this revision:**
- **Choice labels.** `.check_box_group label { ... display: block; }` also beats `[hidden]` (core-7.0 `application.css:1414-1421`, core-5.1 `application.css:950-957`). Section 8 adds the override.
- **`value_was`.** It is captured when `custom_field_values` is built, before any assignment: `x.value_was = x.value.dup if x.value` (core-7.0 `lib/plugins/acts_as_customizable/lib/acts_as_customizable.rb:98`, core-5.1 `:96`). So on persisted records `value_was` is the database value, even after a failed save or the `updateIssueFrom` re-render.
- **Copies.** `Issue#copy_from` assigns values into a new record (core-7.0 `app/models/issue.rb:322-324`). A new record has no `value_was`. This revision therefore made `data-dcf-stored` persisted-only; the consolidated plan instead emits the copy source's stored values as the baseline for issue copies, read through core's `@copied_from` (server S7, UD-06, WP-09 and WP-16), so client and server judge copies the same way (gap 6).
- **AJAX value copy.** `replaceIssueFormWith` copies into the detached replacement, by element id, only values that changed while the AJAX request was in flight (`valuebeforeupdate`, core-7.0 `app/assets/javascripts/application-legacy.js:713-737`, core-5.1 `public/javascripts/application.js:620`). The copy happens before the replacement is inserted, so the observer's initial evaluation sees the copied value.
- **Label `for`.** `custom_field_tag_with_label` sets `for=` only when the tag contains exactly one ` id="..."` (core-7.0 `app/helpers/custom_fields_helper.rb:122-131`). The sentinel has no id, so this is unchanged.
- **Bulk label markup.** Bulk edit renders `<p><label>Name</label> <select>` (core-7.0 `app/views/issues/bulk_edit.html.erb:198-200`). The runtime reads parent names from the DOM there.
- **`(none)` in bulk.** Core bulk `List#bulk_edit_tag` omits `__none__` for required fields (core-7.0 `lib/redmine/field_format.rb:612-616`).
- **Visibility check.** `IssueCustomField#visible_by?` is `super || roles.intersect?(user.roles_for_project(project))` and `CustomField#visible_by?` is `visible? || user.admin?` (core-7.0 `app/models/issue_custom_field.rb:31-33`, `app/models/custom_field.rb:75-77`). It short-circuits for fields visible to all.
- **Core labels used in hint texts.** `label_no_change_option`: en "(No change)", de "(Keine Änderung)", fr "(Pas de changement)", nl "(Geen wijziging)" (core-7.0 locales).
- **Asset cache busting.**
  - 5.1 adds `?asset_id` mtime parameters, cached per process in production (core-5.1 `config/initializers/10-patches.rb:167-178`).
  - 5.1 mirrors plugin assets on startup unless `mirror_plugins_assets_on_startup` is false (core-5.1 `config/initializers/30-redmine.rb:24`).
  - 6.0 and 7.0 precompile on boot when `redmine_detect_update` is on (core-7.0 `config/initializers/30-redmine.rb:130`, `config/environments/production.rb:98`; core-6.0 `config/initializers/10-patches.rb:125`).

## 2. Files

| File | Change |
|---|---|
| `assets/javascripts/depending_custom_fields.js` | REWRITTEN. Same file name. One UMD IIFE: under CommonJS it exports the pure rules (`module.exports`); in a browser it starts the DOM runtime and exposes `window.DependingCustomFields`, with the rules at `window.DependingCustomFields.rules`. No other global. |
| `assets/javascripts/context_menu_wizard.js` | EDITED (section 7) |
| `assets/stylesheets/depending_custom_fields.css` | EDITED (section 8) |
| `lib/redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook.rb`, `client_config.rb`, `client_data.rb`, the shared format module, `app/helpers/context_menu_wizard_helper.rb`, `app/views/depending_custom_fields/_context_menu_wizard.html.erb` | Server area implements C1 (sections 3 and 14) |
| `config/locales/{en,de,fr,nl}.yml` | 9 new keys (section 3.6); `error_save_failed` is reused |
| `package.json`, `package-lock.json`, `.gitignore` | NEW (section 12) |
| `test/js/**` | NEW node and jsdom tests, generated fixtures (section 12) |
| `spec/frontend/markup_fixtures_spec.rb`, `spec/support/dcf_js_fixtures.rb` (WP-16) | NEW: the single fixture mechanism (section 12). |

Removed from the current `depending_custom_fields.js` (points 1 to 4):
- the `window.DependingCustomFieldData` reader;
- `collectRelevantFieldIds`, the per-key DOM scans, `findCheckboxGroup`, `findFieldElement`, `getContextRoot`, `ensureElementId` (`depending_cf_N` ids);
- the whole mirror family: `ensureHiddenContainer`, `removeOldHiddenInputs`, `appendHidden`, `syncBulkInputs`, `syncInlineInputs`, `syncRegularInputs`, `syncHiddenInputs`, plus the `select[data-field-id]` loop;
- the `#inline_edit_form` branch and the `#context-menu li` hiding;
- all `data-depending-*`, `data-value-map`, `data-last-parent-key`, `data-initialized`, `data-change-listener` and `data-sync-hidden-input-listener` bookkeeping;
- per-element listeners, `ajaxComplete`, `observeContextMenu`, and the never-attached body observer.

Language level: ES2017. No `?.`, no `??`, no object spread, no `CSS.escape`. Enforced by the acorn gate (quality Q6).

## 3. Canonical client contract C1

### 3.1 Ownership

- C1 is the single contract. The server area implements it and owns the Ruby side (`ClientData`, `ClientConfig`, the format overrides). The text below is agreed and replaces the server design's section 4 table, its `ClientConfig::I18N` values, and `spec/fixtures/dcf_client_contract.json`. Where the revised designs still disagreed (context vocabulary, emission on cycles, legacy marker, meta tag name), `large_lists_compatibility.md` section 2.4 is binding and the text below follows it (section 0.2).
- Changes need both the server and frontend reviewers.
- There is one fixture mechanism (section 12.1): markup rendered by real requests in all four rspec workflows is written to `test/js/fixtures/markup/*.html` and consumed by the jsdom suites.
- `ClientData` unit specs assert the attribute Hash against this table directly, without a second JSON fixture.

### 3.2 Emission predicate: active child

Parent attributes and the sentinel are emitted only on an active child. Client emission relies on `DependencyRules.effective_parent_id(cf)` (gap 2; WP-05 API, used by `ClientData` in WP-16). A field in a depending format is active when the effective parent resolves, that is when all of these hold for `parent = DependencyRules.parent_of(cf)`:
- `parent` is not nil. `parent_of(cf)` (WP-05) is the memoized raw lookup: it returns the parent record, or nil for a blank, dangling, wrong-type or wrong-family id, or for a self-parent, so rendering and validation agree. A dangling id or a self-parent gives no parent attributes (the every-field attributes are still emitted);
- the ancestor chain of `cf` is acyclic: members of a stored cycle and fields whose chain reaches a cycle have no effective parent (UD-08);
- the parent is visible to `User.current`:
  - form context: `parent.visible_by?(customized.try(:project), User.current)`;
  - bulk: `objects.map(&:project).uniq.all? { |p| parent.visible_by?(p, User.current) }`, or `parent.visible_by?(nil, User.current)` without objects;
  - any exception is rescued and counts as not visible, so the check fails closed.

An inactive child renders as a plain list. Server validation is unchanged, so the server remains the safety net. Today a role-invisible parent is never in the DOM, so its child is already unfiltered (harness T). Omitting the attributes keeps that behaviour and stops leaking the parent's option names through the map. `data-dcf-field`, `data-dcf-context`, `data-dcf-kind` and `data-dcf-multiple` are emitted on every depending field (WP-16); they carry no parent data and the runtime ignores fields without `data-dcf-parent`.

Members of a stored cycle are NOT active (consolidated rule, compat section 2.4, UD-08; this revision originally emitted attributes on them). Server validation treats them as unconstrained until the cycle is fixed, so filtering them in the browser would make the client stricter than the server and could leave both members blank. The client's visited set still guarantees termination for any cycle that reaches the DOM (for example markup rendered during a race with a cycle-creating save).

### 3.3 Attribute table

Rails JSON-encodes Hash and Array data values and HTML-escapes them. The caller's `options[:data]` is merged, never replaced: core passes Stimulus data only for full-text fields (core-7.0 `custom_fields_helper.rb:80-101,133-150`). Attributes go on the `<select>` (drop-down, always in bulk) or on `span.check_box_group` (check_box style).

| Attribute | Value | Presence | Read by the runtime |
|---|---|---|---|
| `data-dcf-field` | child id, e.g. `7` | every depending field (WP-16) | yes |
| `data-dcf-parent` | effective parent id, e.g. `5`. The discovery selector is `[data-dcf-parent]` | active child | yes |
| `data-dcf-context` | `form` (from `edit_tag`, new and persisted records) or `bulk` (from `bulk_edit_tag`: issue and time-entry bulk edit, context-menu wizard) | every depending field (WP-16) | yes; missing or unknown means `form` |
| `data-dcf-kind` | `list` or `enumeration` | every depending field (WP-16) | no (informational for CSS and integrators) |
| `data-dcf-multiple` | `1` | every depending field with `multiple?` (WP-16) | no (the runtime reads `select.multiple` or the input types) |
| `data-dcf-parent-name` | `<prefix>[custom_field_values][<parent id>]` | active child when `tag_name =~ /\A(.+)\[custom_field_values\]\[\d+\](\[\])?\z/` | yes. Without it the name is derived from the child's own name; an unparseable name means the field is ignored. |
| `data-dcf-map` | JSON object: `Sanitizer.sanitize_dependencies(cf.value_dependencies)`, NOT pruned. Keys are strings. List child values are strings; enumeration child ids are JSON numbers when they match `/\A[1-9]\d*\z/`, otherwise strings. | active child; `{}` when empty | yes. Absent or invalid JSON means unfiltered; `{}` means no value is allowed. |
| `data-dcf-defaults` | JSON object, parent key to child value or array, same number rule | active child with non-empty sanitized defaults | yes |
| `data-dcf-hide` | `1` | active child with `hide_when_disabled` true (both contexts) | yes in form context; ignored in `bulk` (D3) |
| `data-dcf-parent-values` | JSON array of the parent's CURRENT keys on the record (strings); `[]` when blank or when the parent is not available on the record (`ParentState.available == false`) | form context, active child, `customized.respond_to?(:custom_field_values)` | only when the parent control is absent from the scope (workflow read-only, not available for the tracker) |
| `data-dcf-parent-label` | `parent.name` (plain text) | same as `data-dcf-parent-values` | only for hints when the parent control is absent |
| `data-dcf-stored` | JSON `{"child":[<baseline child keys>],"parent":[<baseline parent keys>]}` from the server D1 baseline: `DependencyRules.child_baseline(custom_value)` (child) and `ParentState#baseline` (parent) for persisted records, the copy source's stored child and parent values for issue copies (UD-06). `parent` is `[]` when blank or unavailable; `child` is `[]` when empty. | form context, active child, and `customized.persisted?` or an issue copy (`copy?` with a source, server S7). Absent for every other new record. | yes: D1 legacy eligibility and the "no baseline" flag for defaults at load |

The client compares every key and value as `String(x)`. Unknown keys and values without an option are ignored.

Why the map is not pruned:
- server validation reads exactly `Sanitizer.sanitize_dependencies`;
- a stored parent value that is no longer in the parent list (core keeps `value_was` options) must still map;
- the admin editor's D6 save prunes, so stored maps converge anyway.

This supersedes limits L11 on pruning; L11's integer enumeration ids stay. It is also consistent with BC-02: `before_save` stays sanitize-only, so the form mirrors stored data exactly.

### 3.4 Server-rendered helpers for point 2

1. **Blank sentinel.** For an active child in form context with `!multiple?` and `edit_tag_style == 'check_box'` (radio buttons), `edit_tag` returns `view.hidden_field_tag(tag_name, '', id: nil, data: { dcf_blank: 1 })` immediately BEFORE `span.check_box_group`.
   - With no radio checked, the field posts `''`. A checked radio comes later and wins (last-wins, probe 4).
   - With `id: nil` the label-for scan is unchanged: the radios already render without ids.
   - Without JS nothing regresses: the server always checks the current value, and a blank required radio already stores blank.
   - This amends server guarantee 1 to: "adds attributes, and for single radio children one id-less hidden input".
2. **`__none__` for required children in bulk (FD-22, adopted; UD-10, WP-19).** `bulk_edit_tag` of an active child offers `[l(:label_none), '__none__']` even when `is_required?`. Core drops that option for required fields (core-7.0 `field_format.rb:615`).
   - Consolidated form (server S13, WP-19): for required active children only, the option is rendered as `<option value="__none__" data-dcf-required-none="1">` right after "(no change)"; non-required output stays core's `List#bulk_edit_tag` plus the data attributes.
   - The runtime enables a `data-dcf-required-none` option only while the parent selection allows no value (parent "(none)", or a parent value without links), so it is never chosen as a fallback while options exist.
   - Without it, D2's "parent (none) clears descendants" is impossible for required children: every selected issue would fail with "invalid".
   - When the parent maps to nothing, the existing `CustomFieldPatch` no-options bypass accepts the clear.
   - When the parent maps to options, core reports "cannot be blank" per issue.

### 3.5 Wizard markup (server renders)

- `<form class="cf-wizard-form" action="<%= depending_custom_fields_save_path %>" method="post">`. The path stays `/depending_custom_fields/save`; the route name `depending_custom_fields_save` is added in WP-15 (0.1.0 (M2)).
- `render_custom_field(cf, issues)` passes `nil` as the value for every field, so all wizard fields, including the root, open on "(no change)" (deviation from D4, section 0.1, UD-11, WP-18). The `data-field-id` injection is dropped.
- Each field is `<div class="cf-wizard-field"><label class="cf-wizard-label"><span class="field-description" title="...">Name</span> SELECT</label></div>`. An implicit label gives the select an accessible name without ids (UX-13; ids collide with the issue form on the issue page). WP-18 also marks the wrapper with `data-dcf-wizard-field` (not a C1 name and not starting with `data-dcf-parent`).

### 3.6 Head hook, meta tag and i18n keys

Head hook output, in this order. jQuery is already loaded by `javascript_heads` (core-7.0 `app/views/layouts/base.html.erb:13,17`).

```erb
<meta name="dcf-i18n" content="{&quot;selectParent&quot;:&quot;...&quot;, ...}">
<script src=".../plugin_assets/redmine_depending_custom_fields/javascripts/depending_custom_fields.js"></script>
<script src=".../context_menu_wizard.js"></script>
<link rel="stylesheet" href=".../depending_custom_fields.css">
<!-- plus the editor assets on CustomFieldsController and ProjectCustomFieldConfigurationController only (editor area) -->
```

- `ClientConfig::META_NAME = 'dcf-i18n'` (binding, compat section 2.4; this revision originally proposed `'redmine-depending-custom-fields'` with a nested payload).
- `ClientConfig.payload` is the flat Hash `I18N.transform_values { |k| ::I18n.t(k) }` (JS key to translated text), built per request in the current locale. The hook writes it with `tag.meta(name: META_NAME, content: payload.to_json)` (Ruby 2.7 syntax, no hash shorthand; gap 15, WP-18).
- `ClientConfig::I18N` is the single i18n map of the meta tag (gap 5). There is no `I18N_KEYS` constant; the WP-02 parity spec iterates `ClientConfig::I18N` (and the editor's `DependencyEditorConfig::I18N`), and WP-18 adds an example proving its map is checked.
- The hook does no DB or cache access, so it cannot fail a page. It stays on every base-layout page: depending fields arrive by AJAX on pages whose head is never re-rendered (`replaceIssueFormWith`, `bulk_edit.js.erb`, context menus, wizard templates).

`ClientConfig::I18N` (frontend owns the list; the server emits exactly this):

| JS key | locale key |
|---|---|
| `selectParent` | `text_dcf_hint_select_parent` |
| `noOptions` | `text_dcf_hint_no_options` |
| `noOptionsGeneric` | `text_dcf_hint_no_options_generic` |
| `legacy` | `text_dcf_hint_legacy` |
| `legacyLocked` | `text_dcf_hint_legacy_locked` |
| `legacyGeneric` | `text_dcf_hint_legacy_generic` |
| `bulkDefault` | `text_dcf_hint_bulk_default` |
| `bulkCleared` | `text_dcf_hint_bulk_cleared` |
| `liveMessage` | `text_dcf_live_message` |
| `saveFailed` | `error_save_failed` (exists in all four locales, `config/locales/en.yml:76`) |

New locale keys. They are flat, with key parity across de/en/fr/nl. Values that start with `%{` or contain `: ` are double-quoted in YAML. `%{values}` is a comma-joined list of option labels: at most 3, then `, ...`. The colon-list phrasing avoids plural forms. Interpolation variables: `%{parent}` in all hint keys that name the parent, `%{values}` in the three `text_dcf_hint_legacy*` keys, `%{field}` and `%{message}` in `text_dcf_live_message`. The en, de, fr and nl texts have a single source of truth, `large_lists_i18n_registry.md`; this document keeps only the key names and owners. All nine keys are added in WP-18 (0.1.0 (M2)); `error_save_failed` already exists and is reused.

| key | owner WP | en, de, fr, nl texts |
|---|---|---|
| `text_dcf_hint_select_parent` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_no_options` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_no_options_generic` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_legacy` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_legacy_locked` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_legacy_generic` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_bulk_default` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_hint_bulk_cleared` | WP-18 | see large_lists_i18n_registry.md |
| `text_dcf_live_message` | WP-18 | see large_lists_i18n_registry.md |

Notes:
- The parenthesised labels match core `label_no_change_option` in each locale.
- The WP-02 parity allowlist must list `text_dcf_live_message` for de and nl (identical to en by design, gap 10).
- The runtime has the English texts built in as fallbacks for a missing or invalid meta tag.

### 3.7 Example (list child, edit form, persisted record, stored legacy value)

```html
<p><label for="issue_custom_field_values_7">City</label>
<select name="issue[custom_field_values][7]" id="issue_custom_field_values_7" class="depending_list_cf cf_7"
  data-dcf-field="7" data-dcf-parent="5" data-dcf-context="form" data-dcf-kind="list"
  data-dcf-parent-name="issue[custom_field_values][5]"
  data-dcf-map="{&quot;A&quot;:[&quot;a1&quot;,&quot;a2&quot;],&quot;B&quot;:[&quot;b1&quot;]}"
  data-dcf-parent-values="[&quot;A&quot;]" data-dcf-parent-label="Country"
  data-dcf-stored="{&quot;child&quot;:[&quot;b1&quot;],&quot;parent&quot;:[&quot;A&quot;]}">...</select></p>
```

## 4. Rules (pure part, `window.DependingCustomFields.rules` / `module.exports`)

```
NONE='__none__', BLANK='', NOCHANGE_KEY, VERSION
parseFieldName(name)        -> {prefix, fieldId, multiple} | null   (greedy prefix: 'issues[7]' works)
parseJSON(raw)              -> {ok, value}; never throws
normalizeMap(obj)           -> Map<string, Set<string>> | null (null: absent or invalid, so unfiltered)
normalizeDefaults(obj)      -> Map<string, string[]>
normalizeList(arr)          -> string[] | null
normalizeStored(obj)        -> {child: string[], parent: string[] | null} | null
allowedFor(map, parentVals) -> Set (union)
parentKey(values)           -> JSON of sorted unique values (memory key); sameSet(a, b)
parentState(ctx, present, raw, staticValues) -> {kind, values, key}
legacyEligible(input, allowed) -> Set   (section 5.4)
defaultsFor(defaults, parentVals, allowed) -> ordered unique defaults
decide(input)               -> {values, legacy, eligible, filter, state, hint, auto, hideField, rememberKey}
optionEnabled(filter, value), orderByDepth(nodes) (cycle-safe), interpolate(text, vars)
```

- All membership tests use `Set`.
- Shared parity cases with the Ruby `DependencyRules` (allowed set, defaults, per-value exemption) live in `test/js/fixtures/shared/rules_cases.json` (binding path, compat section 2.4; this revision originally proposed `spec/fixtures/dcf_rules_cases.json`, which is the DB fixture directory). WP-05 creates it with allowed-set and default rows, WP-09 adds the D1 rows. Both the node tests (`test/js/rules_cases.test.js`, WP-17) and the server-area Ruby spec read it.

## 5. Runtime (`window.DependingCustomFields`)

### 5.1 Lifecycle and public API

**Load guard.** If `window.DependingCustomFields.__runtime` is already set (the script was included twice), the second copy returns.

**`start()` runs once,** on `DOMContentLoaded` or immediately when the document is already parsed:
1. adds one native `change` listener on `document`;
2. when `window.jQuery` exists, adds `jQuery(document).on('change.dcf', 'select, input', h)`, where `h` handles only `e.isTrigger` events, so native events are never processed twice;
3. starts one `MutationObserver` on `document.body` (falling back to `documentElement`) with `{childList: true, subtree: true}`;
4. calls `init(document)`.

**API:**

| Member | Behaviour |
|---|---|
| `init(root)` | Synchronous and idempotent. |
| `setup(root)` | Deprecated alias of `init`. |
| `requestSetup(root)` | Deprecated, 25 ms debounced `init`. |
| `rules` | The pure rules module. |
| `t(key, vars)` | i18n lookup. |
| `__runtime`, `VERSION` | Markers. |

`setup` and `requestSetup` are deprecated in 0.1.0 (the release that ships this runtime, WP-17 and WP-18), stay throughout 0.1.x, and are removable no earlier than 0.2.0 (UD-01; compat section 2.3).

**Dropped globals:** `window.DependingCustomFieldData` and `window.ContextMenuWizardConfig`.

### 5.2 Discovery, scope, parent lookup (point 4)

- **Children.** Only `root.querySelectorAll('[data-dcf-parent]')`, plus `root` itself. Nothing else is scanned. A child whose `data-dcf-parent` equals its own `data-dcf-field` is ignored.
- **Control.** The element that carries the attributes: a `<select>` or a `span.check_box_group`. Its name is `select.name` or the first `input[name]` of the group.
- **Scope.** `ctl.closest('form') || ctl.closest('.cf-wizard') || document`. This separates the issue form from a wizard on the issue page, and the time-entry block by prefix.
- **Parent control.** Inside the scope, non-hidden `select` or `input` elements whose name equals `data-dcf-parent-name` or that name plus `[]`. The runtime quotes the attribute values itself. The parent is resolved on every evaluation and never cached.
- **Parent label (for hints).**
  1. The parent control is present: in the closest `p` or `.cf-wizard-field`, take the first `label` or `.field-description` that is not inside `.check_box_group`. Clone it, remove form controls, `.required` and hints, and use the trimmed text. Reading the label of a control that is on the page leaks nothing.
  2. Otherwise use `data-dcf-parent-label`.
  3. Otherwise use the generic texts.

### 5.3 Parent state

| ctx | parent control | kind | allowed |
|---|---|---|---|
| form | present, concrete value(s) | `values` | union of the map |
| form | present, blank | `empty` | empty set |
| form | absent, `data-dcf-parent-values` present | `static` (values = that list) | union of the map (empty for `[]`) |
| form | absent, no `data-dcf-parent-values` | `unfiltered` | none |
| bulk | concrete value(s); a mixed `['__none__','A']` counts as concrete | `values` | union |
| bulk | `__none__` only | `none` | empty |
| bulk | `''` (no change), nothing selected, or absent (not common to the selection) | `unfiltered` | none |
| any | `data-dcf-map` absent or invalid | `unfiltered` | none |

- `sig = kind + '|' + key`.
- An evaluation whose `sig` is unchanged is a no-op. That makes `init` idempotent and cascades cheap.
- `parentChanged` means: the control already has a state and `sig` differs from the stored one.

### 5.4 Edit-form decision (points 2 and 5 client, D1 per value)

**Legacy eligibility.** It needs a server D1 baseline (`data-dcf-stored`: a persisted record, or an issue copy with the copy-source baseline, UD-06) AND a parent the server will see as unchanged:

```
eligible = {}  unless ctx == form && data-dcf-stored present && allowed != null
unchanged = kind == static                                  (parent not on the form: it cannot be changed)
         || sameSet(parentValues, stored.parent)            (parent on the form, back on its stored value)
eligible = unchanged ? stored.child minus allowed : {}
usable(v) = (allowed has v || eligible has v) && an option with value v exists
```

**Decision:**

```
initial evaluation (first time this DOM element is seen):
  values = current concrete values filtered by usable          (disallowed values outside the baseline are dropped: plain new records,
                                                                values posted on a failed save, values copied by replaceIssueFormWith;
                                                                a copy keeps the copy-source legacy values under the unchanged parent)
  if the child was empty: memory[key] filtered by usable, if present (AJAX re-render)
                          else per-parent defaults ONLY when there is no baseline (no data-dcf-stored: a plain new record) and kind == values
parent changed:
  memory[key] filtered by usable (ignored if it filtered a non-empty pick down to nothing)
  else if sameSet(parentValues, stored.parent): stored.child filtered by usable        (return to the stored state)
  else carry still-allowed current values when the previous parent values were empty or a subset of the new ones
       (multi child: plus defaults of newly added parent values)
  else per-parent defaults
values: only values with an option; single child -> first; empty single -> '' (the (none) radio for check_box style;
        the sentinel posts '' for a required radio)
legacy = selected values that are eligible
state/hint: legacy -> 'legacy'; kind empty -> 'waiting'; allowed empty -> 'empty'; else 'ok'
hideField = data-dcf-hide && allowed empty && legacy empty   (D3)
rememberKey = key (initial and parent changed; also on every user or third-party change of the child)
```

**Consequences:**
- **Notes-only save keeps the stored legacy value.** It stays selected, enabled and posted unchanged; server D1 per value accepts it (harness I fixed).
- **Return to the stored parent.** A to B drops the legacy value. B back to A restores it, with its marking and hint (UX-07, QA-20a).
- **Multi child with a legacy value.** Adding an allowed value posts `[legacy, new]`. The server exempts the value in `value_was` and validates `new` (R14).
- **Issue copies (gap 6, row F6b-a).** `data-dcf-stored` carries the copy source's stored child and parent values. While the parent is unchanged, a legacy value copied from the source stays selected, enabled, marked (`dcf-legacy-option`, `data-dcf-state="legacy"`, legacy hint) and posted; the server judges the copy against the source (UD-06, server S7, WP-09) and accepts it. Changing the parent makes the copy strict, as for persisted records. Because a copy has a baseline, an empty child of a copy is not filled with the per-parent default at load (it stays as copied).
- **Plain new records (row F6b-b).** Without `data-dcf-stored`, a disallowed value is dropped at load, as today (R15). The page cannot claim a value is "kept" when the server would reject it.
- **Failed-save re-render.** A posted disallowed value that is not stored is dropped (QA-20b). After a failed save where the parent changed, stored values are not eligible until the parent returns to its stored value.
- **Defaults at load (UX-14, UD-12).** An existing record with an empty child is no longer filled with the per-parent default at load. Defaults still apply on new records without a baseline and on every parent change.

### 5.5 Bulk and wizard decision (D2 revised)

| Parent | Child options | Child value |
|---|---|---|
| `unfiltered` ("(no change)", nothing selected, not common) | all enabled | Initial: as rendered. On return from a cascade: the pre-cascade value (`memory[NOCHANGE]`). |
| concrete value(s) with links | allowed values, `''` "(no change)" and `__none__` enabled; others hidden and disabled | Initial: current filtered by `allowed + '' + __none__`. On parent change: user pick remembered for this parent key; else carried concrete value picked under "(no change)"; else per-parent default (`auto`, hint `bulkDefault`, class `dcf-auto-applied`); else `''` "(no change)" for single, nothing selected for multi. |
| `none`, or concrete value(s) whose links are empty | only `__none__` enabled (`''` enabled only when no `__none__` option exists) | `__none__` (hint `bulkCleared`); without a `__none__` option: `''` with hint `empty` |

Notes:
- Required children (UD-10, WP-19): their `__none__` option carries `data-dcf-required-none="1"` and is enabled only in the last row (parent `none`, or concrete values without links). In the "with links" row it stays hidden and disabled, so a required child is never cleared while options exist.
- The auto hint disappears when the user changes the child.
- Bulk memory holds only the initial state and user picks.
- `data-dcf-hide` is ignored in bulk (D3).
- There is no legacy concept in bulk; the server validates per issue.

Grandchild cascades follow naturally:
- a child left on "(no change)" leaves its own children unfiltered;
- a child set to a default filters its children by that default.

### 5.6 Apply (point 2: never disable the child control)

**Select:**
- For each option: `enabled = optionEnabled(filter, v) || target has v`.
- A selected option is deselected before it is disabled.
- `disabled` and the `hidden` attribute are written only when they differ.
- When enabling, a server-rendered inline `display:none` is cleared, for tolerance of older enumeration markup. The runtime never writes inline styles itself.
- Class `dcf-legacy-option` marks eligible options.
- Multi: `selected = target has v`. Single: select the target option, else the enabled `''` option. `select.value` is never assigned a missing value.
- The `<select>` is never disabled. Core's hidden `''` input after a multi select is never touched.

**Check-box group:**
- Each radio or checkbox input gets `disabled = !enabled`.
- Its wrapping label gets the `hidden` attribute, made effective by the CSS in section 8 against core's `display:block`.
- `checked = target has v`.

### 5.7 Hints and accessibility

- **Element.** One `em.info.dcf-hint` per control, created lazily. Its id is generated by JS (`dcf-hint-<n>`, page-unique counter). It carries no `role` and no `data-dcf-*`. It is appended to `ctl.closest('p, .cf-wizard-field')` or inserted after the control.
- **Why a JS id is safe.** It is never part of server markup, so `custom_field_tag_with_label`'s single-id scan is unaffected. `replaceIssueFormWith` copies only input, textarea and select values (core-7.0 `application-legacy.js:727-737`).
- **`aria-describedby`.** While the hint is visible, its id is added to the select, or to every choice input of a group. Other tokens are preserved. The id is removed when the hint is hidden, because a description that references a hidden element is still announced.
- **Texts (from the meta tag, interpolated, set with `textContent` only):**

  | Situation | Text |
  |---|---|
  | `waiting` | `selectParent` |
  | `empty` with the parent on the form | `noOptions` |
  | `empty` with the parent absent | `noOptionsGeneric` |
  | `legacy` with the parent on the form | `legacy` |
  | `legacy` with the parent absent but labelled | `legacyLocked` |
  | `legacy` without any parent label | `legacyGeneric` |
  | bulk default applied | `bulkDefault` |
  | bulk cleared | `bulkCleared` |

  Class `dcf-hint--legacy` marks the legacy hint.
- **Live region.** One page-level `div.hidden-for-sighted.dcf-live[role=status][aria-live=polite]`, created lazily. The class exists in core 5.1 (`application.css:1871`) and 7.0 (`:2631`). It is updated only after a user-initiated cascade, debounced 400 ms, with `liveMessage` (`"%{field}: %{message}"`) for each dependent whose hint newly appeared or changed. Nothing is announced during `init`.
- **Machine-readable state.** `data-dcf-state` on the control is one of `ok | waiting | empty | legacy | none | unfiltered`. It is read-only output for CSS, other plugins and system specs. Class `depending-child` is still added at the first evaluation.

### 5.8 D3 hide

- Only in form context and only the field's own `ctl.closest('p')`, and only when that `<p>` holds no control of another field.
- Hiding adds class `dcf-hidden` and the `hidden` attribute. Un-hiding removes only what the runtime added.
- The `<p>` is never hidden while a legacy value is selected.
- Allowed is empty when the parent is blank or not available, so `hide_when_disabled` hides the field (label included) exactly while the current parent selection offers no options.

### 5.9 Cascade, cycles, events (points 3 and 5)

- **Change handling.** `onNativeChange` ignores the runtime's own events (a `WeakSet`). For any other change it records the user's pick when the target belongs to a child, then cascades from that field.
- **Cascade.** A BFS over dependents in the same scope and with the same prefix, with a visited `Set`. Each control is evaluated at most once per cascade, so stored cycles terminate (fixes harness C, D, S).
- **`init`.** Evaluates controls per scope in `orderByDepth` order, parents first and cycle-safe.
- **Dispatch, in evaluation order:** a native bubbling `change` only when the selected values actually changed, then `CustomEvent('dcf:updated', {bubbles: true, detail: {fieldId, state, values, changed}})` for every evaluation that was not a no-op.
- **jQuery.** The runtime never calls `jQuery.trigger('change')`. Third-party listeners that re-dispatch change are processed normally.

### 5.10 Memory

- Shape: `WeakMap<scope element, Map<prefix|fieldId, Map<parentKey, values[]>>>`, for the lifetime of the page.
- It survives `updateIssueFrom`, because `#issue-form` persists and only `#all_attributes` is replaced. It is fresh for each wizard opening and each bulk refresh.
- Edit memory may contain legacy values. They are re-filtered by `usable` on restore, so they come back only under the stored parent.
- Nothing is persisted: no dataset, no storage.

### 5.11 MutationObserver

- For added element nodes that match `[data-dcf-parent]` or contain one, the callback calls `init(node)` directly inside the callback (a microtask at the end of the inserting task).
- It skips nodes that are disconnected or contained in another added root.
- Records of one task arrive in one callback, so a `replaceIssueFormWith` or `#content` replacement is initialised once, before the next task. There is no unfiltered window.
- **Coalescing instead of a timer debounce (gap 13, FD-15).** All mutation records delivered in one callback are coalesced: the callback first collects the distinct added roots (deduplicated, nested roots dropped), then calls `init` once per remaining root, synchronously, before returning. No `setTimeout` debounce is used. `requestSetup` alone keeps its 25 ms debounce, for backward compatibility.
- **Why this deviates from point 3.** Point 3 asks for a "filtered, debounced MutationObserver". The observer is filtered (only roots that contain `[data-dcf-parent]`) but not timer-debounced: a timer debounce leaves a window after an AJAX re-render in which re-rendered fields are unfiltered and stale disallowed values can be submitted (QA-15, QA-20b). The coalescing per callback gives the same "one pass per burst" effect as a debounce for `replaceIssueFormWith` and `#content` replacement. This deviation is recorded as a contract row ("MutationObserver (gap 13)") in `large_lists_compatibility.md` section 3 and in section 0.1 of this document; WP-17 implements it.
- **Test (WP-17, `test/js/runtime_ajax.test.js`).** A jsdom test performs one `replaceIssueFormWith` insertion (with jQuery 3.7.1) of a fragment holding several roots and nested children, and asserts exactly one `init` per root (a spy on `init`), no `init` for nested roots, and filtered options before the next task (no timer is pending after the callback).
- The runtime's own DOM additions (the hint `em`, the live region) carry no `data-dcf-parent`. `<template>` content is inert.
- There is no `ajaxComplete` dependency.

### 5.12 Overlays

- **select2-like overlays changing the parent.** They use `jQuery.trigger('change')`; the jQuery delegate routes it to the same handler.
- **Runtime value changes.** They dispatch a native `change`, which reaches jQuery handlers, so overlays redraw.
- **Option-state changes.** select2 re-reads `<option disabled>` on open; disabled options appear greyed, and `hidden` is ignored. Other overlays hook `dcf:updated`, documented in the README Integration section.

## 6. AJAX and lifecycle flows

- **`updateIssueFrom`** (tracker, status or project change):
  - `$('#issue-form').serialize()` carries exactly what a submit carries: no control is disabled and no disabled option stays selected. A prototype test proves serialize equals the spec entry list.
  - The server re-renders `#all_attributes`, with `data-dcf-stored` from the database `value_was`.
  - `replaceIssueFormWith` copies in-flight user changes by id into the detached replacement.
  - The observer callback initialises the new markup before the next task, once per added root (coalesced, no timer debounce, section 5.11). Values not usable under the stored rules are dropped; stored values under an unchanged parent stay as legacy; memory survives.
- **Tracker change that removes the parent.** The child is re-rendered with `data-dcf-parent-values="[]"` and `stored.parent: []`.
  - kind is `static` and eligible is `stored.child`, so the child is kept, marked and posted unchanged.
  - Server D1 counts an unavailable parent as unchanged and accepts it.
  - Switching back to the old tracker: the parent is rendered with its database value, which equals the stored parent, so filtering is restored with the legacy value intact.
- **Failed save re-render:** see 5.4.
- **Issue copy** (`GET /issues/:id/copy`, gap 6): new record with `data-dcf-stored` = the copy source's stored child and parent values (UD-06). Under the unchanged parent a legacy value copied from the source stays enabled, marked and posted, and the server accepts it (row F6b-a). A plain new record without `data-dcf-stored` drops disallowed values (row F6b-b).
- **Bulk refresh** (`updateBulkEditFrom` replaces `#content`): the observer initialises the new form with the posted values; memory starts fresh.

## 7. context_menu_wizard.js (global-dependent parts only; other wizard behaviour unchanged except 3.5; WP-18, 0.1.0 (M2))

1. **`submitForm(form)`:**
   - `url = new URL(form.getAttribute('action') || '', window.location.href)`.
   - If the action is missing or `url.origin !== window.location.origin`, alert `saveFailed` and do not post (SP-15).
   - The body is unchanged (`URLSearchParams(new FormData(form))` with the form's `authenticity_token`).
   - Non-2xx with a JSON body: alert `errors.join('\n')`. A non-JSON body (403/422 HTML, 500): alert `saveFailed + ' (' + status + ')'`.
   - The rejection is caught in `onSubmit`; the wizard stays open on error.
2. **`openWizard`:** after cloning the template, call `window.DependingCustomFields.init(container)` synchronously. The observer pass that follows is a no-op.
3. **i18n:** parse `meta[name="dcf-i18n"]` itself (flat object, key `saveFailed`; compat section 2.4), with the English fallback "The change could not be saved.".
4. **Observer hygiene:** replace the body-wide `{attributes: true, attributeFilter: ['style']}` observer with a `childList` subtree observer filtered on added `li.cf-parent`. Create `#cf-wizard-container` lazily.

Out of scope, tracked separately (D4):
- **Wizard save authorization (SP-07, SECURITY; tracked as SD-01, UD-03).** `ContextMenuWizardController#save` assigns `custom_field_values` without the editable filter. Recommended as its own PR merged before tagging 0.0.16; hard deadline: no 0.1.0 (M2) tag (the release that ships point 1) without it, with a CHANGELOG Security entry (WP-07, WP-20).
- Journal and `@can[:edit]` hardening.
- The time-entry context menu.

## 8. CSS (`assets/stylesheets/depending_custom_fields.css`; WP-18, 0.1.0 (M2))

```css
.depending-child { margin-left: 20px; }                                        /* unchanged */
em.info.dcf-hint[hidden] { display: none; }                                    /* core em.info display:block beats [hidden] */
.check_box_group label[hidden] { display: none; }                              /* core .check_box_group label display:block beats [hidden] */
em.info.dcf-hint.dcf-hint--legacy { color: #9a5b00; }
p.dcf-hidden { display: none !important; }                                     /* themes may set p display */
select[data-dcf-state="legacy"], .check_box_group[data-dcf-state="legacy"] { outline: 1px dashed #c98a00; outline-offset: 1px; }
select.dcf-auto-applied { outline: 1px dashed #3e5b76; outline-offset: 1px; }
option.dcf-legacy-option, label.dcf-legacy-option { font-style: italic; }
.cf-wizard em.dcf-hint { display: block; max-width: 260px; white-space: normal; }
.cf-wizard .cf-wizard-label { display: flex; flex-direction: column; font-weight: normal; }
```

- Remove the dead rules: `.cf-wizard-spinner`, `@keyframes cf-spin`, `#context-menu.cf-has-wizard ul.cf-wizard`.
- The admin and matrix rules belong to the editor area.
- Every `[hidden]` override is covered by a system spec, because jsdom does not compute the cascade.

## 9. Behaviour table (before = 0.0.15 code with harness ids; after = this design with prototype test ids)

Class: P = preserved, F = bug fix, C = intentional change, N = new.

Release: every "after" column ships in 0.1.0 (M2) (WP-16 to WP-19; rows F10 and B3r need WP-19). Exception: the untouched multi-value bulk data loss (rows B1m and B7 for multi children) is already fixed in the legacy script in 0.0.16 by the WP-03 hotfix (UD-02); the 0.1.0 (M2) runtime keeps that outcome. Rows F6 and F6d depend on the server D1 per value from 0.1.0 (M1) (WP-09, UD-04); in 0.1.0 (M1) the legacy script still drops such values on the issue form.

| id | scenario | before | after | class |
|---|---|---|---|---|
| F1 | form, parent blank | child select disabled, mirror posts '' (E0) | control enabled, concrete options hidden and disabled, '' selected, hint "Select a value for Country first." tied by aria-describedby | C (point 2), same submission |
| F2 | parent set to A | filter; value = stored combo, else default, else ''; change always fired | same filter; value = memory, else stored state (on return), else carry, else default, else ''; change only when the value changed | P + F |
| F3 | user picks a1 under A, then A to B to A | restores the value captured at the last parent change (E3) | restores a1 | F |
| F4 | parent cleared, chain | children disabled and cleared, change on every level (N2) | cleared and enabled, hints, change only where the value changed | P outcome, F events |
| F5 | stored allowed child | kept, change fired at setup (F) | kept, no event | F |
| F6 | persisted, stored b1 under stored A (legacy) | dropped at load; a notes-only save clears it (I) | kept selected, enabled and marked; hint names b1 and Country; posted unchanged; server D1 per value accepts | F (D1) |
| F6a | F6 then A to B to A | n/a | b1 dropped under B, restored and marked under A | F (UX-07) |
| F6b-a | issue copy (`data-dcf-stored` = copy source baseline, UD-06) with a legacy value under the unchanged parent | dropped at load; the server rejected the copy and project copy skipped the issue | kept, enabled, marked and posted; the server judges the copy against the source and accepts it | F (UD-06, gap 6) |
| F6b-b | plain new record without `data-dcf-stored`, disallowed value | dropped at load | dropped at load (no baseline) | P (R15) |
| F6c | failed-save re-render with a posted, non-stored disallowed value | dropped | dropped | P (QA-20b) |
| F6d | multi child with legacy b1, user adds a1 | n/a (dropped at load) | posts b1 and a1; server exempts b1 (in value_was) and validates a1 | F (R14) |
| F7 | multi select cleared | mirror posts name[]=, core hidden removed, values posted twice (L) | core hidden '' posts name[]=; each value posted once | P outcome |
| F8 | multi checkbox child | all inputs disabled (P1, P2) | only disallowed inputs disabled, their labels hidden (CSS override) | C |
| F9 | single radio, not required, parent changes | nothing posted, stale value rejected (G1) | "(none)" radio checked, posts '' | F |
| F10 | single radio, required | nothing posted, stale, invalid (G1/G2) | all unchecked, sentinel posts '' | F (server sentinel) |
| F11 | chain | event-driven | explicit BFS cascade, depth-ordered init | P |
| F12 | multi parent | union, defaults of added parents merged | same | P |
| F13 | parent read-only by workflow (visible) | child unfiltered (T) | filtered by data-dcf-parent-values; stored disallowed value kept with the "not editable here" hint | C |
| F13b | parent not available for the tracker | child unfiltered, but the server forced blank on save | generic "No values are available for this field."; stored value kept (server: unavailable counts as unchanged); hide_when_disabled may hide it when no legacy value | C |
| F14 | parent invisible to the role | unfiltered, mapping leaked globally | unfiltered, no data-dcf attributes at all | P + F (privacy) |
| F15 | updateIssueFrom | ajaxComplete plus 100 ms rescan; serialize relied on the mirror; memory lost | serialize carries enabled controls; re-init in the observer microtask, exactly one init per added root (coalesced, no timer debounce, gap 13); memory kept; copied values classified by stored data | P + F |
| F16 | hide_when_disabled, form | p hidden while no options; forced visible otherwise | own p hidden while no options and no legacy value; only un-hides what it hid | P + F |
| F17 | time-entry fields inside the issue form | prefix-aware | prefix-aware | P |
| F18 | project, user, my account, register, version, group, document, enumeration, time entry forms | as issue form | as issue form | P |
| F19 | inline-edit forms built with core edit_tag and nested prefix issues[7] | regex did not match | works | N |
| F19b | third-party select_tag without data attributes | filtered by DOM id or name scan | not filtered in the browser; server still validates | C (BC-08) |
| F19c | #inline_edit_form empty multi select | scalar '' | core name[]= | C |
| F20 | existing record, empty child, parent set | default filled at load and saved on the next save (E1) | left empty; defaults apply on new records and on parent changes | C (UX-14) |
| B1 | bulk, parent (no change), single child untouched | posts '' (A0) | posts '' | P |
| B1m | bulk, multi child untouched | posts name[]= and clears it on every issue (B) | posts nothing | F (data loss) |
| B1r | bulk, required multi child | disabled, posts name[]= (B2) | enabled, posts nothing | F |
| B2 | bulk parent to A, no default | "(no change)" hidden but still selected, child unchanged (A1) | "(no change)" selected, visible and enabled; disallowed values hidden; server validates per issue | P outcome, F UI (deviates from README line 37) |
| B2d | bulk parent to A, default a1 | a1 (A') | a1 with the "Set to the default..." hint; "(no change)" still available | P + N |
| B2e | bulk parent value with no links | child unchanged, server invalid per issue | child "(none)" with the "Cleared because..." hint | C |
| B2g | bulk grandchild | stays on visible "(no change)" (Q1) | unfiltered while its parent is "(no change)"; filtered with default or "(no change)" when its parent got a default | F |
| B3 | bulk parent "(none)" | child disabled, mirror posts __none__ (A2, Q2) | child __none__, "(no change)" disabled, cascades | P outcome |
| B3r | bulk parent "(none)", required child | stale value, invalid (U2) | __none__ offered (FD-22); cleared; accepted by the no-options bypass | F |
| B4 | bulk parent back to "(no change)" | forced value kept | child restored to its pre-cascade value and unfiltered | C |
| B5 | bulk pick under "(no change)", then parent A | n/a | pick kept when allowed | N |
| B6 | bulk hide_when_disabled | hidden while the parent is "(no change)" (M) | never hidden in bulk | F (D3) |
| B7 | time-entry bulk edit | same bugs | same as B1..B6 | F |
| B8 | bulk refresh | ajaxComplete rescan | observer re-init; posted values kept | P |
| B9 | bulk parent not common | unfiltered | unfiltered | P |
| W1 | wizard open | root preselected to its default, 100 ms delayed setup, Save writes the default (J) | root and every field on "(no change)"; synchronous init; Save without a choice writes nothing | C (deviation D4, QA-09) |
| W2 | wizard parent "(none)" | children disabled plus mirror; parent posted twice (J, K) | children __none__; every field posted once | F |
| W3 | wizard submit URL | basePath global, TypeError without it | form action from the named route plus a same-origin check | C |
| W4 | wizard error with a non-JSON body | silent, unhandled rejection | localized alert, wizard stays open | F |
| W5 | wizard next to the issue form | document-wide lookup | scoped to the wizard form | F |
| W6 | wizard labels | span next to the select, no accessible name | implicit label wraps span and select | F (UX-13) |
| X1 | change events | always fired (F, N0) | only on a value change; dcf:updated always | F |
| X2 | stored cycle or self-parent | RangeError (C, D, S) | terminates; self-parents and stored-cycle members get no parent attributes and stay unfiltered, matching unconstrained server validation (UD-08, gap 2); the visited set still guards any cycle that reaches the DOM | F |
| X3 | discovery | every mapping key scanned | only [data-dcf-parent] | C (point 4) |
| X4 | select2 jQuery-triggered change | missed | handled | F |
| X6 | context-menu observer | never attached | childList-only, filtered | F |
| X7 | setup / requestSetup | rescan with the global mapping | thin wrappers, deprecated in 0.1.0, kept throughout 0.1.x, removable no earlier than 0.2.0 | P (deprecated) |
| X8 | globals DependingCustomFieldData, ContextMenuWizardConfig | inline script on every page | removed | C |
| X9 | anonymous pages | full mapping inline | only the i18n meta | F |
| X10 | hints for assistive technology | none | aria-describedby plus one polite live region | N |

## 10. CHANGELOG, README, version targets (frontend lines; release 0.1.0 (M2))

All lines below belong to the 0.1.0 (M2) CHANGELOG (WP-20) unless marked otherwise. The canonical wording of every CHANGELOG line is in `large_lists_work_packages.md` section 3 and `large_lists_compatibility.md` section 4 (PC-22 to PC-44); the lines here are the frontend's source list.

**Fixed:**
- Bulk edit no longer clears untouched multi-value depending fields. (Already released in 0.0.16 by the WP-03 legacy hotfix, UD-02; the 0.1.0 (M2) runtime keeps it.)
- Required radio-style children can be cleared.
- Stored values that no longer match an unchanged parent are kept and accepted instead of being silently removed on save (also when only other values of a multi-value field change). The server accepts them since 0.1.0 (M1) (WP-09, UD-04); from 0.1.0 (M2) the issue form keeps them too, also on issue copies (UD-06).
- No more event recursion with cyclic configurations.
- The wizard reports server errors and stays open.
- Switching the parent back restores the child value you picked, including a stored value.
- The value you last picked for each parent value comes back when you switch the parent back, also after the form refreshes. (Added, WP-17, gap 11.)
- Choosing "(none)" for a parent in bulk edit or the wizard now also clears required dependent fields (UD-10, WP-19).

**Changed (Upgrade notes):**
1. Dependent fields are never disabled. Disallowed options are hidden and disabled, and a hint under the field explains why, naming the parent field.
2. (UD-09) In bulk edit and the context-menu wizard, choosing a parent value keeps "(No change)" available on dependent fields. A per-parent default is preselected with a visible hint. A dependent field is cleared automatically only when the parent is "(none)" or its value allows nothing. The README promise that "(No change)" is hidden is withdrawn; invalid kept values are reported per issue by the server.
3. (UD-11) The context-menu wizard opens every field on "(No change)". Saving without choosing changes nothing (it used to write the root field's default).
4. (UD-12) Per-parent defaults are filled in on new records and when the parent changes. They are no longer filled into empty fields of existing records when the form opens.
5. Dependent fields whose parent is read-only on the form, or not available for the tracker, are now filtered by the stored parent value, and may be hidden when "Hide when no valid options" is set.
6. "Hide when no valid options" applies only to single-record forms, never in bulk edit, and never while a stored non-matching value is shown.
7. The `change` event fires only when a value changes. Listen to `dcf:updated` for option changes.
8. Fields rendered without Redmine's custom field helpers (custom `select_tag` in third-party views) are no longer filtered in the browser. See README Integration; the server still validates.
9. Without JavaScript, Key/Value list (depending) fields show all active values. The server still rejects invalid combinations.
10. (UD-13) Context-menu responses carry dependency data for the wizard fields and can be larger for very big mappings.
11. Fields that are part of a circular configuration (stored cycle) show as plain lists in the browser, as the server treats them as unconstrained until the cycle is fixed (UD-08).

**Removed:**
- `window.DependingCustomFieldData` and `window.ContextMenuWizardConfig`.
- The `data-depending-*`, `data-value-map` and `depending_cf_N` ids.
- The hidden mirror inputs.

**Deprecated (0.1.0 (M2)):** `DependingCustomFields.setup` and `requestSetup` (aliases of `DependingCustomFields.init`). Kept throughout 0.1.x, removable no earlier than 0.2.0 (UD-01). `CustomFieldVisibility` is deprecated in the same release with the same targets (server area, WP-15).

**Upgrade:**
- Restart Redmine.
- If `mirror_plugins_assets_on_startup` (5.1) or `config.assets.redmine_detect_update` (6.x/7.0) is disabled, or assets are baked into an image, run `rake redmine:plugins:assets` (5.1) or `rake assets:precompile` (6.x/7.0).
- Reload open browser tabs: an old cached script with the new pages leaves fields unfiltered until reload.

**Security (tracked separately as SD-01, UD-03):** the wizard save writes only fields the user may edit (SP-07). Decided (UD-03): its own pull request, merged before the 0.0.16 tag.

**README:**
- Rewrite lines 22-24 (disabled until a parent value is chosen), 31 and 36-37 (bulk "(No change)").
- New "Integration" section:
  - supported render paths: `custom_field_tag`, `format.edit_tag`, `format.bulk_edit_tag`;
  - the C1 attribute table, for integrators who render their own markup;
  - `data-dcf-state`, `dcf:updated`, the overlay hook example;
  - `DependingCustomFields.init(root)`.

## 11. Edge cases

- A parent hidden by its own hide_when_disabled has a blank value, so the child is "waiting" (and hidden too if it has `data-dcf-hide`).
- Duplicate forms on one page: scoped per form. Wizard on the issue page: tested.
- Radio or checkbox parents: changes come from the inputs, matched by name.
- Map keys containing `[`, `]`, quotes or `||`: JSON in the attribute; memory keys are JSON.
- Enumeration ids as numbers or strings: coerced with `String()`.
- A value with no option (pruned, or a legacy value core appended): never selected by the runtime; kept when it is selected and eligible.
- Server pre-hidden options (`hidden` plus inline style from older markup): reset when enabled.
- A detached root passed to `requestSetup`: skipped.
- Script loaded before `<body>`: the observer falls back to `documentElement`.
- A multi bulk child with `__none__` plus values: left as is; core resolves it (core-7.0 `app/controllers/application_controller.rb:450-472`).
- A third party disables the control: not re-enabled.
- Hint labels with markup characters: `textContent` only.
- The parent label cannot be resolved: generic texts.
- The meta tag is missing or invalid: English fallbacks.

## 12. Test plan

### 12.1 Single fixture mechanism (R13, QA-01)

**`spec/frontend/markup_fixtures_spec.rb` (runs in the 5.1, 6.0, 6.1 and 7.0 workflows):**
- It renders scenarios through real requests:
  - `GET /issues/:id/edit` and `GET /issues/new` (extract `#all_attributes`);
  - `GET /issues/:id/copy`;
  - `GET /issues/bulk_edit?ids[]=` and time-entry bulk edit (extract the custom field paragraphs);
  - `POST /issues/context_menu` (extract the wizard template);
  - `GET /projects/:id/settings` and `GET /users/:id/edit` as admin.
- It writes `test/js/fixtures/markup/<scenario>.html`.
- **Deterministic ids.** Every record the scenario creates (custom fields, enumerations, project, issue, tracker, status, role, member) is created with an explicit id in the fixed per-kind id ranges from WP-02 (binding, compat section 2.4; this revision originally proposed one reserved range 91000-91999). The fixture spec runs under two seeds (`--seed 1` and `--seed 4242`) and must compare clean under both (WP-16). `spec/support/dcf_js_fixtures.rb` (WP-16, shared with the editor fixtures) does the rest: it scrubs authenticity tokens, state hashes, asset digests and timestamps; it keeps the fixed-range ids verbatim (no placeholders, compat section 2.4 "Fixture ids"); it fails on any id-bearing number outside the fixed ranges (a leaked sequence id).
- **Self-check.** Each scenario is rendered twice inside savepoints, with throwaway rows created between the renders to shift auto-increment and sequences, and the two normalized outputs must be identical. This proves independence from sequences in random order.
- `DCF_WRITE_JS_FIXTURES=1` rewrites the fixtures. A divergence on any version fails CI.
- The node fixture loader reads the committed files unchanged.

**Required scenarios:**
- edit, new record, single;
- edit, persisted, single with a legacy value;
- edit, persisted, multi with a legacy value;
- edit, required;
- radio, and required radio (with the sentinel);
- checkbox multi;
- enumeration (integer ids);
- chain of three;
- parent read-only by workflow (`data-dcf-parent-values` present, parent absent);
- parent role-invisible (only the every-field attributes `data-dcf-field`, `data-dcf-context`, `data-dcf-kind`, `data-dcf-multiple`; no parent attributes, no `data-dcf-parent-values`);
- parent not available for the tracker (`data-dcf-parent-values="[]"`);
- stored cycle (no parent attributes on either member, UD-08, gap 2);
- dangling parent and self-parent (only the every-field attributes);
- issue copy with a legacy value under the unchanged parent (`data-dcf-stored` = copy source baseline, UD-06, gap 6);
- plain new record with a disallowed value (no `data-dcf-stored`);
- inactive values (QA-21, WP-16): a stored inactive child id, a stored inactive parent value, a per-parent default on an inactive id, and inactive ids in `data-dcf-map` without a matching option;
- issue plus time_entry prefixes;
- project form, user form;
- bulk single, bulk multi, bulk required (with `__none__`), bulk chain, time-entry bulk;
- wizard template (root on "(no change)", implicit labels, named-route action).

`test/js/contract_fixtures.test.js` asserts the filtering outcome for each scenario on the generated markup (expected `data-dcf-state`, enabled options and the spec-compliant entry list, WP-17).
- **Copy expectation (gap 6, updated).** For the issue-copy scenario the test expects the legacy value to stay selected and enabled, marked (`dcf-legacy-option`, `data-dcf-state="legacy"`, legacy hint) and present in the entry list (row F6b-a); a request spec in the server area confirms that posting it creates the copy (UD-06, WP-09). For the plain new-record scenario it expects the disallowed value to be dropped and absent from the entry list (row F6b-b). The earlier expectation "issue copy: disallowed value dropped at load" is removed.
- **Observer expectation (gap 13).** `test/js/runtime_ajax.test.js` asserts that one `replaceIssueFormWith` insertion causes exactly one `init` per root and leaves no pending timer (section 5.11).

### 12.2 Tooling (D10 plus jquery)

The toolchain lands in WP-01 (0.0.16); the support helpers below are completed in WP-17 (0.1.0 (M2)).

- `package.json`: private, `"license": "SEE LICENSE IN LICENSE"`, `engines.node ">=22.13"`.
- devDependencies: `jsdom ~29.1.1`, `jquery 3.7.1`, `acorn ~8.18.0` (quality Q6; UD-30).
- Scripts: `check` (acorn ES2017 parse plus `node --check` of every `assets/javascripts/*.js`) and `test: node --test "test/js/**/*.test.js"`.
- `.gitignore`: `node_modules/`, `coverage/`.
- `js-tests.yml`: `workflow_dispatch` only; no automatic trigger is ever added. Dispatch policy (UD-32, resolved by the owner): Claude may deliberately dispatch this and the other manual workflows only after the local gates pass (`npm ci && npm run check && npm test`), at most once per workflow per commit SHA unless a fix was pushed, never editing workflow triggers, and always reporting the workflow, SHA, run URL and result.
- Helpers in `test/js/support/`:
  - `dom.js`: JSDOM with `runScripts: 'outside-only'`, optional jQuery, loads the asset, resolves after `DOMContentLoaded`;
  - `entries.js`: spec-compliant entry list;
  - `fixtures.js`, `fire.js`.

### 12.3 Order

1. Commit 1 adds `test/js/legacy_characterization.test.js`, pinning the current script for harness scenarios A0..U2. In the consolidated plan this is WP-04 (0.1.0 (M1)), pinned on the WP-03 hotfixed legacy script; WP-17 points it at the renamed `depending_custom_fields_legacy.js`.
2. The rewrite commit deletes it. In the consolidated plan the switch WP-18 (0.1.0 (M2)) deletes it, together with `test/js/legacy_bulk_hotfix.test.js`. The PR lists each flipped row id from section 9.

## 13. Implementation order

1. Tooling plus the legacy characterization.
2. Server C1 (server area):
   - visibility-gated attributes, `data-dcf-stored`, the sentinel, `__none__` for required children in bulk;
   - D1 per value;
   - the named wizard route, root on "(no change)", wizard labels;
   - head hook plus meta;
   - the fixture spec and normalizer.
3. Rules plus `rules.test.js` plus the shared `test/js/fixtures/shared/rules_cases.json`.
4. Runtime rewrite plus the jsdom suites; remove the legacy characterization.
5. `context_menu_wizard.js` plus wizard tests.
6. CSS, locales (parity), README, CHANGELOG.
7. Opt-in system specs.

Steps 2 to 5 ship in the same release, 0.1.0 (M2) (the server D1 per value and effective parent of step 2 ship earlier, in 0.1.0 (M1)): removing the global before the attributes exist would disable all dependency logic.

**Mapping to the canonical work packages (releases per UD-01):**

| Step | Work packages | Release |
|---|---|---|
| 1. Tooling plus legacy characterization | WP-01 (toolchain, `js-tests.yml`), WP-03 (legacy hotfixes), WP-04 (`legacy_characterization.test.js`) | 0.0.16 (WP-01, WP-03); 0.1.0 (M1) (WP-04) |
| 2. Server prerequisites | WP-05 (`DependencyRules`, `parent_of`, `effective_parent_id`, shared rules cases), 0.1.0 (M1); WP-09 (D1 per value, copy baseline), WP-10 (effective parent, cycle validation), 0.1.0 (M1) | 0.1.0 (M1) / 0.1.0 (M1) |
| 2. Server C1 emission | WP-15 (named wizard route, selection graph), WP-16 (per-field attributes incl. `data-dcf-stored`, fixture spec and normalizer, additive) | 0.1.0 (M2) |
| 3 and 4. Rules and runtime | WP-17 (UMD file shipped behind the renamed legacy script, jsdom suites) | 0.1.0 (M2) |
| 2, 5 and 6. Switch | WP-18 (head hook and `dcf-i18n` meta, globals and `Rails.cache` removed, wizard JS, CSS, locales, README Integration, opt-in system specs) | 0.1.0 (M2) |
| 2. Sentinel and required '(none)' | WP-19 | 0.1.0 (M2) |
| 6. Release | WP-20 (README rewrite, CHANGELOG 0.1.0 (M2), version) | 0.1.0 (M2) |

WP-18 changes server and JS in one PR, so no state without filtering exists on main.

## 14. Requirements on the server area (consolidated)

1. **C1 exactly as in section 3:**
   - the active-child predicate through `DependencyRules.effective_parent_id` (valid, acyclic, visible; gap 2), including the visibility gate with fail-closed rescue in both contexts;
   - the attribute names and JSON shapes;
   - the unpruned sanitized map;
   - `data-dcf-parent-values` and `data-dcf-parent-label` in form context;
   - `data-dcf-stored` = server D1 baseline: persisted records (`value_was`) and issue copies (copy source values, UD-06); absent for other new records (gap 6);
   - no parent attributes for dangling or self parents, nor for stored-cycle members and chains reaching a cycle (UD-08; consolidated rule, this revision originally emitted them on cycle members).
2. **`DependencyRules.parent_of(cf)` is part of the WP-05 API (gap 2):** memoized on the record, it returns the parent record, or nil for blank, dangling, wrong type or family, or self, so rendering and validation agree. Client emission does not use it directly: `ClientData` uses `effective_parent_id`, which builds on `parent_of` and adds the acyclic check (WP-16).
3. **D1 per value in `validate_custom_value`:**
   - when `parent_state` exists and `!state.changed?` (an unavailable parent counts as unchanged), values contained in the normalized `value_was` are exempt from the dependency check, and every other non-blank value must be allowed;
   - when the parent changed, every value must be allowed.
   - for issue copies the baseline is the copy source's stored child and parent values (UD-06, server S7), which is exactly what `data-dcf-stored` carries;
   - This replaces whole-set `legacy_combination?` (R14). The shared parity cases in `test/js/fixtures/shared/rules_cases.json` cover add, remove and reorder for multi children.
   - Delivered by WP-09 in 0.1.0 (M1) (UD-04, UD-05, UD-06).
4. **The blank sentinel** (3.4.1; WP-19, 0.1.0 (M2)), with specs: present only for single radio active children; no id; label `for` unchanged; request spec posting `x=&x=r1` (stored r1) and `x=` (cleared) on all four versions.
5. **`__none__` for required active children in `bulk_edit_tag`** (3.4.2; marked `data-dcf-required-none="1"`; WP-19, 0.1.0 (M2), UD-10), with request specs:
   - `bulk_update` with `__none__` on a required child whose parent maps to nothing is accepted through the no-options bypass;
   - with a parent that maps to options, it gives the per-issue "cannot be blank" failure.
6. **Wizard:** named route action (WP-15); `render_custom_field` with value `nil` (UD-11); implicit labels; request spec that Save without a choice changes nothing (WP-18).
7. **Head hook and `ClientConfig`** as in 3.6 (WP-18): `<meta name="dcf-i18n">` written with `tag.meta(name: META_NAME, content: payload.to_json)`. The hook spec renders the meta in all four locales and asserts that every `ClientConfig::I18N` value resolves without "translation missing".
8. **Drop** `spec/fixtures/dcf_client_contract.json` in favour of 12.1 (WP-16).

## 15. Positions on cross issues owned by other areas (recorded for the consolidated plan; no frontend runtime change)

- **Payload (R3, QA-02, BC-03, UX-01, SP-02, SP-17):**
  - one `DependencyPayload` owned by the editor area, with a strict schema: top-level `version`, `source`, `base` and an optional validated `import: {mode, rows}`;
  - unknown keys rejected; one 4 MiB cap for both paths; nesting 3;
  - one error API (Result);
  - Integers bounded before `to_s` (SP-01);
  - parse memoized per raw String.
  - The project page uses the same partial, presenter and `data-dcf-editor-*` attribute namespace. Failed-save re-render (consolidated rule, gap 1, compat section 3): the hidden input is always blank on both pages; the parsed ok payload is rendered in `data-dcf-editor-mapping` with `data-dcf-editor-dirty="1"`; there is no `data-dcf-editor-echo` and no `input_value`. The project page passes `posted: service.parsed_payload` to `DependencyEditorConfig.for_project` (WP-27). A server pre-fill without a failed save never starts dirty (R4). (This revision originally proposed an explicit `data-dcf-editor-echo="1"`; that is superseded.)
  - Editor markup must never use attribute names that start with `data-dcf-parent` or equal any C1 name, so the runtime selector and the C1 semantics cannot collide.
- **Storage messages (R5, UX-04, BC-13, R20):**
  - limits owns them;
  - the single `Patches::CustomFieldValidationPatch` (WP-11; compat section 2.4 row "CustomField callback registration"), no separate `CustomFieldStoragePatch`;
  - key `dcf_storage_too_large` with `%{size}`/`%{limit}`;
  - one normalizer shared by preview and `before_save`.
  - The editor's client estimate uses `data-dcf-editor-storage-limit`, `data-dcf-editor-storage-base` and `data-dcf-editor-values-limit`, and names the field `dependencies_json` everywhere. Consolidated rule (compat section 2.4): it warns at or above `data-dcf-editor-storage-warn` percent (90) of `data-dcf-editor-storage-limit` with the single key `text_dcf_storage_estimate`, and shows no warning without the attribute (owner WP-24; test `test/js/dependency_editor_storage.test.js` in WP-25). This revision's `text_dcf_storage_estimate_over` and "warn only above the limit" are superseded.
  - The issue-form runtime shows no storage UI.
- **Value options (R7):** consolidated rule (gap 3, compat sections 2.4 and 3): `DependencyRules.value_options` returns Ruby `[key, label, active]` tuples, consumed as `|key, label, active|`; the compact wire format for the endpoint, both presenters and the editor JS comes from `DependencyEditorConfig.wire_values` (WP-05, WP-24, WP-27, WP-28). Not used by the runtime.
- **Audit (R10, SP-09):** one `AuditPayload` (16 KB) with marker key `payload_sha256`, so the project delta's own `truncated` and `mapping_sha256` are never overwritten. `ValueTooLong` rows store only the class name, column and byte counts. Not frontend.
- **Locales (R11, QA-05, UX-03):**
  - frontend keys are final (3.6); the `label_dcf_hint_*` keys are removed from the server map;
  - `field_value_dependencies` uses the limits wording "Dependency mapping";
  - the parity spec adds a duplicate-key check per file (Psych handler) and resolution of every `I18N` constant map: it iterates `RedmineDependingCustomFields::ClientConfig::I18N` and `DependencyEditorConfig::I18N` when they are defined (gap 5, WP-02; WP-18 and WP-24 each add an example proving their map is checked);
  - the WP-02 allowlist gains `text_dcf_live_message` (de, nl) and the editor's identical-by-design values (gap 10);
  - texts for every key live in `large_lists_i18n_registry.md`.
- **Generator (R12):** adopt the arithmetic generator (exact YAML byte targets, Ruby-version independent) with a JS port for parity, and pin one hash. Consolidated owner (compat section 2.4): quality (rev 2 arithmetic, hash 233acf899217e962), with the JS twin. The frontend perf test uses the JS port.
- **Query gate (R16):** the C1 additions cost no queries beyond the memoized parent and `visible_by?`, which short-circuits for fields visible to all. The server resolves parents from `available_custom_fields` first. Quality's invariance assertions are the single style.
- **Topology and reporting (R18):** `FieldIndex` as the single topology helper, with the server names (`load`, `children_ids`; WP-05, compat section 2.4); `StorageReport` as the single report. Not used by the runtime.
- **Flash XSS (SP-06):** one escaping flash helper on the project pages. The runtime never writes HTML from values.
- **Icons (UX-10):** the runtime renders no flash or icon markup (hints are core-style `em.info`, the wizard uses `alert`). Partials use `sprite_icon` when available; editor JS prepends `createSVGIcon` when defined.
