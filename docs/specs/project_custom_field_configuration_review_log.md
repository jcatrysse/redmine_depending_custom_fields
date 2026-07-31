# Phase 12 — Review Passes

Four adversarial review passes over the draft specs. Each lists findings and the
resulting changes already folded into the spec set.

## Review pass 1 — Senior Redmine Architect

Checks: 5.1/6.1 consistency; existing plugin architecture; permission
integration; settings-tab strategy; `alias_method`; no `to_prepare`;
lightweight.

Findings & resolutions:
- **F1.1** Tying the permission to a project module would break "admin always has
  access" on projects where the module is disabled (`Project#allows_to?` returns
  false for disabled modules even for admins). → **Resolved:** permission is
  **module-independent** (Permissions §3).
- **F1.2** Existing plugin uses `prepend` for its 4 patches; the brief forbids
  `prepend` for the settings-tab patch. → **Resolved:** new tab patch uses
  `alias_method`; existing `prepend` patches left untouched (Integration §1/§4).
- **F1.3** Risk of writing `format_store`/`possible_values` directly and
  desyncing the plugin's dependency cache. → **Resolved:** all writes go through
  the model's `save`/`save!` so existing `after_save`/`after_initialize` cache
  callbacks run (Data Model §2, Operations §0).
- **F1.4** `sprite_icon` only on 6.x. → **Resolved:** guard with `respond_to?`
  (UI §2, Integration §13, CHANGELOG precedent).
- **F1.5** Lightweight check: only one additive table, no module, reuse of core
  markup and existing JS. → **Accepted** as lightweight.

## Review pass 2 — Product Owner

Checks: business need solved; workflow understandable; cross-project clarity;
tracker/workflow excluded; practical for PMs.

Findings & resolutions:
- **F2.1** PMs need the *common* operations (values + dependency matrix) without
  admin involvement. → Confirmed in v1 scope (Feasibility §11).
- **F2.2** Cross-project surprise is the top product risk. → **Resolved:** scope
  badges + warning banner + impact panel + required confirmation
  (Functional §6, UI §3/§4).
- **F2.3** Trackers/workflows must be clearly excluded so PMs don't expect them.
  → Stated as non-goals NG2/NG3 and reinforced in UI "out of scope" (UI §10).
- **F2.4** Practicality: empty states and no-JS reorder make it usable on minimal
  setups. → Added (UI §9, Product §11).
  **— The no-JS reorder half is superseded by Amendment A2 below.**
- **F2.5 (new)** PMs should see *what changed* in their project → project-scoped
  audit view in the same tab (Audit §2/§8).

## Review pass 3 — Security Reviewer

Attempts: privilege escalation; bypass permission; direct URL; mass-assignment;
edit irrelevant field; change out-of-scope global settings; reach full API;
bypass audit.

Findings & resolutions:
- **F3.1** Direct URL / forged POST. → `find_project` + `authorize` +
  service re-check + CSRF; 403 (Security §12/§20).
- **F3.2** Mass-assignment via `custom_field[...]`. → services never use
  `safe_attributes=`; operation-specific strong params only (Security §14/§15,
  Operations §0). Test T-SEC-1..3/8.
- **F3.3** Editing a field not relevant to the project (global field present but
  unrelated). → server-side relevance assertion → 404 (Security §10, Operations
  §0). Test T-SEC-7/T-REL-6.
- **F3.4** Reaching the existing full API. → unchanged `require_admin`; new
  actions are not `accept_api_auth` (Security §13). Test T-SEC-5/6.
- **F3.5** Out-of-scope global settings (type/visibility/applicability). → never
  in params, never assigned; forbidden by construction (Security §5/§20).
- **F3.6** Bypassing audit. → audit in same transaction; failure rolls back
  (Audit §6, decision D-AUDITBLOCK). Test T-AUD-2/8.
- **F3.7 (new)** Public-project / non-member exposure. → permission
  `require: :member` blocks Anonymous/Non-member by construction (Permissions
  §4/§10). Test T-AUTH-6.
- **F3.8 (new)** Project-name leakage via impact panel. → names filtered by
  `Project.visible`; counts otherwise (Feasibility §7, UI §4). Test T-USE-3.

## Review pass 4 — QA Engineer

Checks: edge cases; dependency-mapping risks; usage counts; cross-project
warnings; coverage; 5.1/6.1; failure modes.

Findings & resolutions:
- **F4.1** List rename must update `CustomValue` rows **and** dependency entries
  or data silently breaks. → Operations §B (D-RENAME-LIST); tests T-REN-1/2.
- **F4.2** Enumeration vs list must be treated differently (id vs string). →
  explicit throughout (Feasibility §3, Operations §B/§C/§E); tests T-REN-3,
  T-RM-4.
- **F4.3** Reorder integrity (missing/extra/dup). → permutation check
  (Operations §D); tests T-ORD-3/4/5.
- **F4.4** Concurrent edits overwrite. → optimistic state-hash (Data Model §6,
  Operations §0); test T-CONC-1.
- **F4.5** Usage-count performance on large installs. → lazy + capped +
  fallback (Functional §7, UI §4); test T-USE-5.
- **F4.6** Removing a value used by issues. → warn/confirm, never delete data;
  optional block setting (Operations §C); tests T-RM-1/2/3.
- **F4.7** 6.1 without a test harness. → documented manual smoke test
  (Test Plan T-CMP-2); never break 5.1.
- **F4.8 (new)** Audit table missing (migration skipped). → controller fails
  closed (Audit §10); test T-AUD-8.

## Net changes folded in

- Permission made module-independent + `require: :member`.
- `alias_method` settings-tab patch; no `to_prepare`.
- All writes via model `save`; cache preserved.
- Transactional audit incl. failure statuses; fail-closed when table missing.
- Cross-project warnings, confirmation gate, visible-name filtering.
- List vs enumeration handling separated; CustomValue rewrite on list rename.
- Optimistic concurrency; lazy/capped usage counts; no-JS reorder.
  **— The no-JS reorder item is superseded by Amendment A2 below.**
- Standard list/enum fields excluded by default (setting-gated for later).
  **— Superseded by the Amendment below.**

## Amendment A1 — Standard `list`/`enumeration` included in v1

Product direction changed: standard (non-plugin) `list` and `enumeration` custom
fields are now **in v1 scope** for value operations (add/rename/remove/reorder +
enumeration values). Resulting spec changes:

- **Supported set** is now `['list','enumeration','depending_list',
  'depending_enumeration']`, split into two capability classes: *value-only*
  (`list`, `enumeration`) and *value + dependency* (`depending_*`). Dependency
  operations F/G remain restricted to the two depending formats (they require a
  parent). (Feasibility §6, Operations §0/§F.)
- **Default flipped:** the gating setting is renamed `manage_standard_custom_fields`
  and defaults to **true** (delegation enabled); it is now an admin *kill-switch*
  to disable standard-format delegation, not an opt-in. (Feasibility §6,
  Integration §1.4.)
- **Services are family-shared:** `list`≡`depending_list` and
  `enumeration`≡`depending_enumeration` share one service body; only the
  dependency-rewrite step branches on the depending formats. (Operations §0/§B/§C.)
- **Security re-review (delta):** no new write surface; the existing relevance
  check + cross-project warning/confirmation gate are the controls. Standard
  fields are more often global, so the impact panel/confirmation simply does more
  work. The admin kill-switch is an extra containment lever. (Security §19.)
- **Tests added:** T-REL-7/8/9 (standard listed & editable by default; setting-off
  exclusion; no dependency action on standard), T-SET-1/2/3, value-op
  parameterization across all four formats, standard-list global-rename
  cross-project test. (Test Plan §3/§4/§11a.)
- **One concern flagged for implementation (not a blocker):** delegating standard
  `is_for_all` lists means a project manager can rewrite option lists used by
  *every* project. This is intended but high-impact; the confirmation gate and
  audit `affected_projects_count` must be especially prominent here, and sites
  that dislike it set `manage_standard_custom_fields = false`. See independent
  review (separate note) for the recommendation to consider a future
  "project-only fields" hardening setting.

## Review pass 5 — Independent analyst/programmer (post-amendment)

A fresh adversarial re-read after the standard-format amendment. 15 findings,
all integrated into the specs (no code). Severity P0 = data/mapping corruption,
P1 = Redmine-API correctness, P2 = hardening/quality.

| # | Sev | Finding | Resolution (spec) |
|---|-----|---------|-------------------|
| 1 | P0 | **Parent-side cascade missing** — child `value_dependencies` are keyed by the *parent's* values; renaming/removing a value of any field used as a parent (incl. standard lists, now in scope) silently orphans children | Operations §parent-relationships + §B/§C cascade step; Functional §10/§11; audit `affected_child_field_ids`; tests T-CAS-1..5 |
| 2 | P0 | **Dep-ref count computed on wrong side** — under-reports parent-key usage | Functional §8 dual-side count; Feasibility §5; UsageCalculator (Agent 4); T-USE-4 |
| 3 | P0 | **Field `default_value` not updated** on rename/remove | Operations §B/§C; Functional §10/§11; T-DEF-1/2 |
| 4 | P1 | **`read:` is per-permission, not per-action**, and a non-read perm hides the tab on archived projects even for admins | Permissions §4/§9 → `read: true` + controller `require_active_project`; Integration §1.1; T-AUTH-7/9 |
| 5 | P1 | **Settings-tab rendering model ambiguous** (inline vs link) | Integration §4 decision: overview inline via helper, actions on dedicated controller redirect back, detail screens full pages; T-UI-7 |
| 6 | P1 | **Global admin audit had no route/auth** | Integration §3/§5 admin-only `DcfConfigAuditController` + route; Audit §8; T-SEC-9; Agent 3 |
| 7 | P1 | **ProjectCustomField relevance wrong** — not per-project scoped | Feasibility §2.2/§2.3 → always relevant, badge always Global |
| 8 | P1 | **Plugin-setting boolean read is string/tri-state** (`!= false` bug) | Integration §1.4 + Operations §0 exact `ActiveModel::Type::Boolean` rule, centralized in FieldRelevance |
| 9 | P2 | **Enum removal should deactivate, not destroy, when in use** | Operations §C decision D-ENUM-DEACTIVATE; Functional §11; T-ENU-1/2 |
| 10 | P2 | **Audit before/after bloat** on large global lists | Audit table + §5 compact-delta; data model; T-AUD note |
| 11 | P2 | **Setting name under-describes scope** (also gates enums) | Renamed `manage_standard_list_fields` → `manage_standard_custom_fields` everywhere |
| 12 | P2 | **Bulk `update_all` skips journals** — state it | Operations §B note D-NO-JOURNAL |
| 13 | P2 | **Overview N+1** on scope/value counts | Feasibility §5 mitigation; Integration §6 helper; T-USE-6 |
| 14 | P2 | **Core List/Enum label keys differ by version** | UI §3 derive label from field-format registry; T-UI-6 |
| 15 | P2 | **No Capybara stack** — don't assume system specs | Test Plan §8 request-spec note |

**Open recommendation (not implemented):** consider a future
`restrict_to_project_only_fields` hardening setting for sites that want to forbid
delegated edits of `is_for_all`/global fields entirely. Logged as a non-blocking
idea; the current confirmation gate + audit + `manage_standard_custom_fields`
kill-switch are deemed sufficient for v1.

## Amendment A2 — Reorder is drag-only (Redmine core parity)

Product direction changed after the feature shipped in a first form. The values
screen originally offered **both** a drag handle and per-row **Move up / Move
down** buttons, the latter mandated by UI §9 as a no-JS and keyboard fallback
(review finding F2.4). Feedback on the running screen: the two controls together
make each row noisy, and Redmine itself does not work that way.

Source check across every supported version (5.1, 6.0, 6.1, 7.0-stable):

- There is **no `reorder_links` helper** — it does not exist in any of them.
- `reorder_handle` is the **single** reorder affordance, used in all six
  reorderable core views: `custom_fields/_index`, `enumerations/index`,
  `trackers/index`, `issue_statuses/index`, `roles/index`,
  `projects/settings/_boards`.
- No `move_higher` / `move_lower` / `:highest` / `:lowest` UI anywhere.
- The rule `table.list td.reorder` still sits in core's stylesheet but is
  referenced by **no core view** — leftover CSS from the era when Redmine did
  have up/down links, since removed. Core deliberately dropped this pattern.

Decision: the up/down buttons are removed; the drag handle is the only reorder
control, matching core exactly.

Accepted cost, recorded deliberately: as in core, reordering now requires
JavaScript and a pointer. There is no keyboard or no-JS path to reorder. Every
other value operation (add, rename, remove, default value) remains a plain form
submit and still works without JavaScript, and the handle is hidden until the
sortable initialises so a no-JS client is never shown a dead control. Revisit
only if core introduces a keyboard-accessible handle.

Resulting spec changes:

- **UI §4** — "drag or up/down Reorder controls" → a drag Reorder handle.
- **UI §9** — retitled *Accessibility / no-JS behaviour*; the no-JS reorder
  requirement is replaced by this parity decision and its cost.
- **Test Plan §1/§8** — the "View / system" row and the harness note no longer
  rest on a no-JS reorder path; T-UI-2 is reframed as the endpoint contract that
  the sortable submits; **T-ORD-13** added to guard that the buttons do not
  return; **T-CMP-4** added for the manual drag smoke test.
- **Agent Plan, Agent 6** — the "no-JS reorder" scope item is marked superseded.
- Locale keys `label_dcf_move_up` / `label_dcf_move_down` deleted from en, nl,
  fr and de as no code references them any more.

## Amendment A3 — Enumeration values can be activated / deactivated

The values screen showed the `active` flag of an enumeration value as a
read-only "Yes" / "No", so the only way to switch a value off was to go to
Administration — exactly the round trip this feature exists to remove. The flag
is now editable, with core's own control (Operations Spec §I, UI Spec §4).

Adversarial findings raised while implementing, and how each is resolved:

- **F-A3.1** A dedicated operation, or the `active` checkbox folded into the
  existing rename form (core saves name + position + active with one button)?
  → Folding them in would file a deactivation in the audit trail as
  `rename_value`, which is unacceptable for an audit-first feature. Resolved
  as a **separate operation** in a **separate inline form**, which is also the
  pattern this screen already uses: one operation per editable cell.
- **F-A3.2** Reactivating a value whose name was meanwhile taken by an active
  value would create two active values with the same name — a state Add (§A)
  and Rename (§B) both refuse to produce. Core has no such validation, but
  inheriting that gap here would let the toggle bypass the plugin's own rule.
  → **Resolved:** reactivation is rejected with `error_value_duplicate`
  (T-ACT-6).
- **F-A3.3** Deactivating the value that is the field's `default_value` leaves
  the default pointing at an option no picker offers — and the values screen's
  own default picker lists active values only, so the stale default is
  invisible there and cannot be corrected by inspection. → **Resolved:** the
  default is cleared as part of the operation and named in the audit summary
  (T-ACT-5). `default_value_dependencies` are deliberately **not** pruned: the
  project-level matrix lists all enumerations, so those entries stay visible
  and editable, and pruning them would not survive a reactivation.
- **F-A3.4** Should deactivation prune parent keys from depending children, as
  Remove (§C) does? → **No.** Remove is terminal; deactivation is a reversible
  visibility flag, and pruning would silently discard mappings that ticking the
  box again cannot restore (T-ACT-7). The asymmetry — remove-then-reactivate is
  not a round trip — is recorded in Operations §I.
- **F-A3.5** Should a shared/global field require the confirmation panel before
  a value is switched off? → **No.** The panel guards changes that destroy or
  rewrite data; deactivation destroys nothing and is undone by ticking the box.
  The scope badge and warning banner already state the blast radius.
- **F-A3.6** A new controller action is unreachable until it is listed in
  `Redmine::AccessControl.map`; `authorize` fails closed with 403 otherwise.
  Caught by the request specs before review. → **Resolved:** `set_value_active`
  added to the permission's action list in `init.rb`.
- **F-A3.7** The state-hash digest already covers `active`, so a hash captured
  before a toggle is stale afterwards — a second tab cannot silently re-toggle
  (T-ACT-9). No change needed; locked in by a test.
- **F-A3.8** Core renders a visible `l(:field_active)` label next to each
  checkbox because its values are a flat `<ul>`. Here the table header already
  carries that word. → Label dropped, string kept as `title`/`aria-label` so the
  checkbox still has an accessible name (UI §4).

Pre-existing behaviour noticed but deliberately **not** changed here: the
project-level dependency matrix lists inactive enumerations as tickable child
values (the controller's `value_options` does not filter on `active`, unlike the
admin matrix partial, which goes through `possible_values_options`). Hiding them
would silently drop existing mappings on the next save, so it needs its own
change with its own migration story.

### A3 red-team pass — measured, not argued

Every claim in Amendment A3 was re-checked against a running Redmine (5.1, 6.0,
6.1, 7.0 on sqlite) rather than reasoned about. What the probes showed:

- The first round of probes was **vacuous**: the custom field was never linked
  to the tracker, so `Issue#available_custom_fields` ignored it and nothing was
  stored. "Existing values survive" had until then only been asserted at the
  `CustomValue`-row level, never through `Issue` validation. `dcf_real_issue`
  was added to the spec helpers to close that gap, and T-ACT-17/18/19 now
  exercise the real path.
- **Confirmed:** an issue holding a deactivated value re-saves cleanly, keeps
  the value, and still casts to its name — core's
  `RecordList#possible_custom_value_options` re-adds `value_was` for the record
  that holds it. A **new** issue is refused ("is not included in the list").
- **Confirmed:** an issue already on a deactivated **parent** value re-saves and
  its child field keeps exactly its previous options — this only holds because
  §I does not prune. Pruning would have left that issue with no allowed child.
- **No stale-cache path.** `depending_custom_fields/mapping` holds only
  `parent_id` / `map` / `defaults` / `hide_when_disabled`, all id-keyed and read
  from the `CustomField` row, so an enumeration toggle cannot stale it. (The
  `dcf/*` namespace is deleted in two places and written nowhere — dead, and
  unrelated.)
- **Page weight**, measured on 6.1: +840 bytes per row (per-row `<form>` +
  `_method` + three hidden inputs + submit, plus a CSRF token in production).
  10 values: 28.3 KB → 36.7 KB. 200 values: 351 KB → 520 KB (+48% on a page that
  was already heavy). Irrelevant at the value counts this screen is built for;
  the cheaper shape would be core's single `update_each` form for the whole
  table, which this screen's one-form-per-cell design rules out.

Residual risk accepted, **not** introduced here: deactivating the last active
value of a **required** field blocks issue creation wherever the field applies
("cannot be blank", measured). Delete already reached the same state — with a
confirmation panel in front of it — so the toggle lowers the friction rather
than opening a new hole. A warning when a field is left with zero active values
would cover both operations and is the natural follow-up.

## Amendment A4 — The enumeration table follows core's submit model

Raised by the maintainer against Amendment A3: *"wel een beetje vreemd met een
save knop per lijn… ik denk dat Redmine de move en de save niet live doet maar
met een algemene save knop?"* Correct on both counts, and A3 was wrong to claim
core parity for the whole control.

**What core actually does.** There are **two** patterns, verified in 6.1 source:

1. `reorder_handle` + `$.fn.positionedItems` (`application-legacy.js`) — used by
   trackers, issue statuses, roles, enumerations, custom_fields index: a drop
   fires an immediate AJAX `PUT` of that one item's new position. No Save button.
2. `custom_field_enumerations#index` — **the screen this feature copies**: the
   whole list is one `form_tag(..., method: 'put')`; per row a hidden `position`,
   a name field, a hidden `active=0` + checkbox, and a `delete_link`; **one**
   `submit_tag(l(:button_save))` at the bottom. Its sortable's `update` handler
   only rewrites `input.position` and submits nothing.

A3 copied core's *control* (checkbox + hidden `0`) but not its *submit model*,
and A2 had already borrowed pattern 1 for both families. The screen ended up with
a per-row rename Save, a live-submitting drag, and a second per-row Save for
Active — three interaction models where core has one per screen.

**Resolution.** The enumeration table now uses pattern 2 in full: one form, one
Save, staged positions, `PATCH …/enumerations` → `UpdateEnumerationsService`
(Operations §E, which had reserved `update_enumerations` for exactly this and was
marked "optional"). The list family keeps pattern 1 — core has no table UI for
plain string values to copy, and a field is only ever one family, so a user never
sees both models at once.

Consequences accepted:

- **A2 is revised, not reversed.** "One drag = one operation = one audit event"
  still holds for the list family. For the enumeration table one *Save* is the
  unit instead, which is strictly closer to core.
- **Audit granularity is coarser by design**: one `update_enumerations` event per
  Save rather than separate `rename_value` / `reorder_values` / activation
  events. The information is preserved in the delta — renamed / activated /
  deactivated name lists (capped at 20 with a `(+N more)` tail) plus a
  `reordered` flag — and the summary reads e.g. `Saved 3 enumeration value(s):
  renamed 1, deactivated 1, reordered`.
- `set_value_active` (the A3 route, action, service and its two locale keys) is
  **removed** rather than left alongside: a nested form is impossible, so keeping
  it would mean two ways to write the same flag with only one reachable. Its
  semantics moved into §E and its tests with them.
- Delete becomes a `delete_link`, because forms cannot nest — core's own choice
  here. Its impact panel and confirmation are unchanged. Pending unsaved edits
  are lost if Delete is clicked first, exactly as in core.
- §B (`rename_value`) and §D (`reorder_values`) still accept enumeration params
  because the list family shares those endpoints; the project screen simply no
  longer routes enumeration edits through them.

New guards the batch shape required, both tested:

- **F-A4.1** The duplicate check must look at the **resulting** state, not the
  stored one — one Save can rename row 1 onto row 2's name, or reactivate a row
  whose name a sibling now holds. A per-row check would have missed both.
- **F-A4.2** The submitted id set must equal the field's exactly, so a partial or
  tampered payload is refused whole instead of applied in part (T-ACT-21). A real
  concurrent add/delete is already caught by the state hash.
- **F-A4.3** Atomicity now matters in a way it did not for single-row operations:
  a blank name, a duplicate, or a name the model rejects must leave *every* row
  untouched. Validated before the write loop, with the transaction covering the
  rest (T-ACT-22).

Measured side effects, on 6.1: the A3 findings F3 (page weight) and F4 (two
identical Save buttons per row) are gone, and the page is now **lighter than
before this feature existed** — one form replaces N. 10 values: 28.3 KB baseline
→ 36.7 KB with per-row Saves → **25.5 KB**. 200 values: 351 KB → 520 KB →
**293 KB**. The old duplicate DOM ids in the enumeration table
(`id="enumeration_id"` etc. repeated per row) disappear too, since the inputs are
now name-indexed and carry no ids.

Two smaller cleanups the new shape allowed:

- The `.dcf-values td.dcf-active { white-space: nowrap }` rule added by A3 existed
  only to keep a per-row Save next to its checkbox. Removed with the button.
- `_confirm_panel` re-emits the pending params as hidden fields and handled only
  scalars and arrays. A nested hash — the batch payload's shape — would have been
  serialised into a single `value="{...}"` field. No confirmable operation submits
  one (§E needs no panel), but the panel now skips hashes so a future confirmable
  batch operation fails loudly on the id-set check instead of silently
  re-submitting a mangled payload.
