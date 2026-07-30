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
