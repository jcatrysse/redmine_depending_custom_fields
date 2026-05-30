# Phase 10 — Test Plan

The repo ships **both** RSpec (`spec/`, `spec/rails_helper.rb`) and Redmine
test-unit (`test/`, `test/test_helper.rb`). New tests should follow the existing
**RSpec** convention (majority of suites) and reuse
`spec/support/custom_field_factory.rb`. Security/permission integration may also
use request specs (`spec/requests`).

## 1. Test levels & mapping

| Level | Targets |
|---|---|
| Model | `ConfigAuditEvent` (validations, append-only, enum status) |
| Service | each operation service (A–G), `FieldRelevance`, `UsageCalculator`, `AuditRecorder` |
| Controller / request | authorization, routing, params filtering, flash/redirects |
| Helper | scope badge, visible-name filtering, icon guard |
| View / system | tab visibility, forms render, no-JS reorder; matrix screen |
| Security | bypass attempts, mass-assignment, cross-project, API isolation |
| Audit | event written per success/failure; transactional rollback |
| Compatibility | runs on 5.1 (mandatory) and 6.1 (if harness available) |

## 2. Permission / authorization tests

- T-AUTH-1 Admin sees the settings tab in any project.
- T-AUTH-2 User with permission sees the tab in that project.
- T-AUTH-3 User without permission does **not** see the tab.
- T-AUTH-4 No-permission direct GET/POST to each action → 403.
- T-AUTH-5 Permission in project A → action on project B → 403.
- T-AUTH-6 Non-member on public project → 403 (permission `require: :member`).
- T-AUTH-7 Archived project (permission is `read: true`): `index`/`show`/`audit`
  remain reachable for an actor who retains access (incl. admin); every write
  action returns **403 `error_project_archived`** via `require_active_project`.
- T-AUTH-8 Service re-check rejects even if controller is bypassed (unit-level).
- T-AUTH-9 Admin on an **archived** project still sees the tab and overview
  (regression guard for the `read: true` decision — independent-review fix #4).

## 3. Relevance / listing tests

- T-REL-1 Overview lists only supported-format fields relevant to the project
  (the four: `list`, `enumeration`, `depending_list`, `depending_enumeration`).
- T-REL-2 Global (`is_for_all`) field appears with **Global** badge.
- T-REL-3 Field shared by >1 project shows **Shared** badge + count.
- T-REL-4 Project-only field shows **Project** badge.
- T-REL-5 Truly unsupported-format field (e.g. `bool`, `string`, `user`) is
  absent; direct edit → 422 `error_format_unsupported`.
- T-REL-6 Field not relevant to project → 404 on edit.
- T-REL-7 Standard `list`/`enumeration` are listed **and editable by default**
  (setting on); the "Edit dependencies" action is **absent** for them.
- T-REL-8 With `manage_standard_custom_fields` **off**: standard `list`/
  `enumeration` are not listed and direct edit → 422; plugin depending formats
  remain editable.
- T-REL-9 Dependency action/route on a standard `list`/`enumeration` → 422
  `error_format_unsupported` (no parent / not a depending format).

## 4. Operation tests

> Each value-operation test (Add/Rename/Remove/Reorder) is parameterized across
> **all four families' representatives**: standard `list`, standard
> `enumeration`, `depending_list`, `depending_enumeration`. The shared service
> body must behave identically except for the dependency-rewrite step (present
> only for the two depending formats).

Add: T-ADD-1 works (each format); T-ADD-2 blank → 422; T-ADD-3 duplicate → 422;
T-ADD-4 insert at position.
Rename: T-REN-1 list/standard-list rename rewrites `possible_values` **and**
`CustomValue` rows; T-REN-2 `depending_list` rename **also** rewrites dependency
keys/child entries, standard `list` rename leaves no dependency store (no-op);
T-REN-3 enumeration/standard-enumeration rename changes only `name`, leaves
`CustomValue` intact; T-REN-4 rename to duplicate → 422; T-REN-5 cross-project
rename requires confirm; T-REN-6 standard `list` rename on a global field rewrites
CustomValue across all projects (cross-project confirm enforced).
Remove: T-RM-1 `depending_list` remove prunes dependency refs and does **not**
delete `CustomValue`; T-RM-1b standard `list` remove leaves `CustomValue`
orphaned, no dependency store touched; T-RM-2 remove used value warns/requires
confirm; T-RM-3 with `block_removal_when_used` → 422; T-RM-4 enumeration/
standard-enumeration remove deactivates/destroys (+ prunes id refs only for
`depending_enumeration`).
Reorder: T-ORD-1 works (list order); T-ORD-2 enumeration positions;
T-ORD-3 missing value → 422; T-ORD-4 extra value → 422; T-ORD-5 duplicate → 422.
Dependencies: T-DEP-1 valid mapping saves; T-DEP-2 unknown child → 422;
T-DEP-3 wrong/unknown parent key → 422; T-DEP-4 orphan prevented;
T-DEP-5 default dependency must be an allowed child; T-DEP-6 matrix uses existing
`MappingBuilder`/`Sanitizer`.
Concurrency: T-CONC-1 stale state-hash → 409/422.

Parent-side cascade (independent-review fixes #1/#2):
- T-CAS-1 Renaming a value of a **standard `list`** that is used as a **parent
  key** in a `depending_list` child rewrites that child's `value_dependencies`
  **and** `default_value_dependencies` keys in the same transaction.
- T-CAS-2 Renaming a value of a `depending_list` parent cascades to all its
  depending children.
- T-CAS-3 Removing a parent value prunes that key from every depending child.
- T-CAS-4 Renaming an **enumeration** parent value does **not** touch child keys
  (id-stable); removing/deactivating it **does** prune the id key from children.
- T-CAS-5 `affected_child_field_ids` is recorded in the audit event and surfaced
  in the impact panel before confirmation.

`default_value` integrity (independent-review fix #3):
- T-DEF-1 Renaming a value that equals the field's `default_value` rewrites
  `default_value`.
- T-DEF-2 Removing a value that equals `default_value` clears it.

Enumeration removal semantics (independent-review fix #9):
- T-ENU-1 Removing an **in-use** enumeration value **deactivates** it
  (`active=false`); existing `CustomValue` ids still resolve to the name.
- T-ENU-2 Removing an **unused** enumeration value hard-destroys it.

## 5. Impact / usage tests

- T-USE-1 per-value usage count (current project) correct.
- T-USE-2 cross-project usage count correct.
- T-USE-3 project names shown only for visible projects; others summarized.
- T-USE-4 dependency-reference count correct on **both** sides (own-side child
  refs + parent-side refs across child fields).
- T-USE-5 usage query cap/fallback triggers gracefully on large datasets.
- T-USE-6 Overview avoids N+1: a single `Project.active.count` reused for
  `is_for_all` rows; `projects` preloaded; no per-value/cross-project usage query
  on overview render (assert query count bound).

## 6. Security tests (explicit bypass attempts)

- T-SEC-1 POST with `field_format`/`type` → ignored; field unchanged.
- T-SEC-2 POST with `visible`/`role_ids` → ignored.
- T-SEC-3 POST with `tracker_ids`/`project_ids`/`is_for_all`/`is_required` →
  ignored.
- T-SEC-4 No route/action can create or delete a custom field.
- T-SEC-5 Existing `DependingCustomFieldsApiController` still `require_admin`
  (non-admin → 401/403).
- T-SEC-6 New actions reject token/API auth (no `accept_api_auth`); CSRF enforced.
- T-SEC-7 Edit attempt on irrelevant field → 404 (no info leak).
- T-SEC-8 No `safe_attributes=` invoked by services (collaboration/spy or
  behavioural check: only intended attributes change).
- T-SEC-9 Global audit route `GET /dcf_config_audit` requires admin: non-admin
  (even a permission holder) → 403; admin → 200 (independent-review fix #6).
- T-SEC-10 Standard-format edit while `manage_standard_custom_fields` is **off**
  → 422, even for a permission holder (setting kill-switch is server-enforced).

## 7. Audit tests

- T-AUD-1 Each successful op writes exactly one event with correct
  action/before/after/counts.
- T-AUD-2 Audit row written in same transaction (forced audit failure → change
  rolled back; no `possible_values` change persisted).
- T-AUD-3 Authorization failure → `authorization_failed` event (own txn).
- T-AUD-4 Validation failure → `validation_failed` event.
- T-AUD-5 Project view shows only `project_id = P` events for a delegated user.
- T-AUD-6 Admin global view shows all; non-admin cannot access global scope.
- T-AUD-7 Audit rows are append-only (no update/destroy path).
- T-AUD-8 Missing audit table → controller fails closed (admin-facing error),
  no change applied.

## 8. View / request tests

> **Harness note (independent-review fix #15):** the repo has no Capybara/system
> stack (only `spec/` request/model/lib specs + a `test/` unit harness). Write
> these as **request specs** (assert rendered HTML / redirects / status), **not**
> Capybara system specs, unless Agent 9 confirms and adds a system-test stack.
> No test may depend on a JS driver; the no-JS reorder path makes this possible.

- T-UI-1 Tab renders for authorized users (request spec asserts the tab link in
  `projects/settings`).
- T-UI-2 Reorder works without JS (up/down form submit → redirect + new order).
- T-UI-3 Destructive action shows confirm; cross-project shows required checkbox
  (assert the confirm markup / required field in the rendered HTML).
- T-UI-4 Matrix screen renders for depending fields with a parent only; absent
  for standard `list`/`enumeration`.
- T-UI-5 Empty states render (no fields; no values; no audit events).
- T-UI-6 All visible strings resolve via I18n (no missing-translation markers in
  en); Format column derives label from the field-format registry (fix #14).
- T-UI-7 Overview renders inline inside the settings tab via the helper (no
  dependence on dedicated-controller ivars — fix #5).

## 9. I18n / routing / integration

- T-INT-1 `rake routes` includes new project-scoped HTML routes; old routes
  intact.
- T-INT-2 Permission appears in role screen with translated label.
- T-INT-3 Plugin loads with no `Rails.configuration.to_prepare`.
- T-INT-4 Settings-tab patch uses `alias_method` (grep/loadcheck) and tab
  appears.

## 10. Compatibility tests

- T-CMP-1 Full suite green on Redmine **5.1** (mandatory gate).
- T-CMP-2 Suite green on Redmine **6.1** if a 6.1 test harness is available;
  otherwise a documented manual smoke test (tab loads, add/rename/remove/reorder,
  matrix save, audit view) on 6.1.
- T-CMP-3 Icon helper guarded (`respond_to?(:sprite_icon)`) — render test on both.

## 11. Fixtures / factories

- Reuse `spec/support/custom_field_factory.rb` and `spec/fixtures/users.yml`.
- Add factories/fixtures for: a `depending_list` issue CF (global), a
  project-only `depending_list`, a `depending_enumeration` with a parent,
  **a standard `list` issue CF (global)**, **a standard `enumeration` issue CF**,
  **a standard `list` project CF**, projects A/B, roles with and without the
  permission, members.

## 11a. Setting tests

- T-SET-1 Default of `manage_standard_custom_fields` is **true**.
- T-SET-2 Toggling it off removes standard fields from the overview and blocks
  their edit routes (422), without affecting depending formats.
- T-SET-3 Setting is admin-only (it is a plugin setting under Administration).

## 12. Coverage gate

- Every service operation (A–G) has success + each documented failure path.
- Every security answer in the Security Model §20 has at least one test.
- Every audit action value has at least one test.
