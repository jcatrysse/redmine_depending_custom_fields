# Phase 4 — Security Model Specification

Security is a first-class requirement. The model is **deny-by-default**, defense
in depth, and never relies on menu hiding.

## 1. Threat model overview

The feature deliberately grants a non-admin the ability to mutate *shared and
global* custom field configuration. The risk is that a delegated user (or an
attacker who compromises one) escalates from "manage option lists of fields
relevant to my project" into "modify arbitrary global custom field properties,
read other projects' data, or reach the Redmine administration area".

## 2. Trust boundaries

- **Browser ↔ Rails controller**: all input untrusted; strong params + CSRF.
- **Controller ↔ Service**: service does not trust the controller's authorization
  alone; re-checks permission, relevance and format.
- **Service ↔ CustomField model**: only specific attributes/associations mutated;
  no blanket mass assignment.
- **This feature ↔ existing admin API**: hard separation; the admin API is not
  reused or relaxed.

## 3. Assets to protect

- Integrity of custom field configuration (values, enumerations, dependencies).
- Integrity of issue/object data (`CustomValue` rows).
- Confidentiality of other projects' names/membership.
- The admin boundary (global `admin` capabilities, Administration screens, full
  config API).
- Audit trail integrity.

## 4. Actors

- Administrator (full trust).
- Delegated project manager (partial trust, scoped to a project + operations).
- Ordinary member / non-member / anonymous (untrusted for this feature).
- External attacker (forged requests, parameter tampering).

## 5. Abuse cases & mitigations

| Abuse case | Mitigation |
|---|---|
| Forge `field_format`/`type` in params | Not read by the service (operation-specific params only); strong params drop it; attempt auditable. |
| Forge `visible`/`role_ids` | Same — never assigned. |
| Forge `tracker_ids`/`project_ids`/`is_for_all`/`is_required` | Same — never assigned. |
| Edit a field not relevant to the project | Service asserts relevance; otherwise 404/403. |
| Edit a supported field via project B where user has no perm | `authorize` on `@project` (B) fails → 403. |
| Reach Administration / CustomFieldsController | Those routes still require `admin`; this feature adds no bridge. |
| Reach the existing full config API | Still `before_action :require_admin`; unchanged. |
| Delete/create a field | No route/action exposed; impossible. |
| Mass orphan issue data via remove | Remove never deletes `CustomValue` rows; warn+confirm; optional block-when-used. |
| Enumerate other projects via counts | Counts only; names filtered by visibility. |
| Bypass audit | Audit is in the same transaction; failure rolls back the change. |
| CSRF | Rails `protect_from_forgery` (HTML); no `accept_api_auth` on these actions. |
| Stale/concurrent overwrite | Optimistic value-set hash check. |

## 6. Privilege escalation analysis

The only new capability is the scoped operation set on relevant supported
fields. There is **no path** from the new controller to: changing field type,
visibility, applicability, required flag; creating/deleting fields; the admin API;
or Administration. Editing a *global* field is an intended, warned, audited
capability — equivalent to a deliberate admin action but limited to value/dep
surface.

## 7. Deny-by-default model

- No route is anonymous-accessible.
- `require: :member` prevents granting the permission to Non member/Anonymous.
- Every action runs `authorize`.
- Unsupported formats and irrelevant fields are rejected server-side.
- Unknown/extra params are ignored, never assigned.

## 8. Project permission enforcement

- Controller: `before_action :find_project, :authorize`.
- `authorize` maps `{controller, action}` to the permission via Redmine
  `AccessControl`; admins pass automatically.
- Service: `User.current.allowed_to?(:manage_project_custom_field_configuration,
  project)` re-checked before mutation.

## 9. Administrator override model

- Admins bypass the permission check (Redmine built-in).
- Admins can view the optional global audit (read-only). No new admin config UI.

## 10. Project field relevance model

A mutation is allowed only if the field passes the relevance check
(Feasibility §2.3) for the **current** project. This prevents using a project
where you have the permission to edit a field that merely *exists* globally but
is not actually relevant to that project — narrowing blast radius and aligning
capability with intent.

## 11. Shared custom field risk

- Editing a Shared/Global field is permitted but gated by explicit cross-project
  warnings and a confirmation checkbox when impact > 0.
- Audit records `affected_projects_count` and `affected_values_count` so the
  blast radius of each change is reconstructable.

## 12. Direct URL access protection

- All actions require permission on the resolved `@project`.
- No action is reachable without passing `authorize`.
- 403 for unauthorized; 404 for irrelevant fields (no information leak about
  unrelated fields).

## 13. Existing API protection

- `DependingCustomFieldsApiController` is **not modified** and remains
  `require_admin` + `accept_api_auth`.
- The new controller does **not** call into the admin API, does not reuse its
  `PERMITTED_SCALAR`, and is **not** marked `accept_api_auth` in v1 (HTML-only,
  CSRF-protected). (A future read-only project API could be added separately
  with the same project permission, explicitly scoped — out of v1.)

## 14. Mass-assignment protection

- The service never calls `custom_field.safe_attributes = params[:custom_field]`.
- It sets only: `possible_values` (computed array), specific
  `CustomFieldEnumeration` records, and `value_dependencies` /
  `default_value_dependencies` (computed via existing builder/sanitizer).
- Note: `init.rb` currently registers `value_dependencies` /
  `default_value_dependencies` etc. as global `safe_attributes`. The new feature
  **must not** rely on `safe_attributes=`; it assigns the computed virtual
  attributes directly, so global safe-attribute registration is irrelevant to
  this path. (No change to the existing registration is required or recommended.)

## 15. Strong parameter strategy

Per operation, only:
- `add`: `value` (string), `position` (int, optional).
- `rename`: `old_value`/`enumeration_id`, `new_value`, `confirm` (bool).
- `remove`: `value`/`enumeration_id`, `confirm` (bool).
- `reorder`: `ordered_values` (array of existing identifiers).
- `dependencies`: `value_dependencies` (hash, sanitized), `default_value_dependencies` (hash, sanitized).
No other keys are permitted; nested `custom_field` blobs are rejected.

## 16. CSRF expectations

- HTML forms with Rails authenticity token; standard `protect_from_forgery`.
- No CSRF exemption; no token-auth on these actions in v1.

## 17. Audit log integrity

- Audit row written in the same transaction as the change → atomic.
- Audit rows are append-only; no UI to edit/delete them.
- Captured: actor, project, field, action, status, before/after, counts, IP,
  user agent, request id (see Audit Spec).
- Retention: keep indefinitely by default; optional admin purge task (out of v1).

## 18. Sensitive data handling

- Do not store other projects' names in audit `after_value` beyond counts unless
  the actor could already see them.
- IP/user-agent stored for traceability; treat as personal data per the
  installation's policy (documented; purge task optional).

## 19. Safe defaults

- Permission off for all roles until granted.
- Standard `list`/`enumeration` fields are **in scope by default** (value
  operations only) but can be globally disabled by an admin via
  `manage_standard_custom_fields`. The relevance check and cross-project
  warning/confirmation gate are the controlling safeguards — standard fields are
  more often global, so the impact panel and confirmation do more work, but no
  new mechanism is required.
- Remove never deletes issue data.
- Audit-on-auth-failure **on**.
- Confirmation required for any cross-project / in-use destructive change.

## 20. Explicit answers (required)

1. **Can a delegated user access Redmine Administration?** No. No route/menu
   change; Administration still requires `admin`.
2. **Can a delegated user access the normal `CustomFieldsController`?** No;
   it requires `admin`. Unchanged.
3. **Can a delegated user use the existing full depending CF create/update/delete
   API?** No; `DependingCustomFieldsApiController` remains `require_admin`.
4. **Can a delegated user change custom field type?** No (not in params; not
   assigned).
5. **Can a delegated user change visibility/role restriction?** No.
6. **Can a delegated user change tracker/project applicability?** No.
7. **Can a delegated user create or delete a custom field?** No (no such
   action/route).
8. **Can a delegated user manage a field not relevant to the current project?**
   No (server-side relevance check).
9. **Can a delegated user modify a global field used in other projects?** Yes,
   intentionally — but only the value/dependency surface, with explicit
   cross-project warning, confirmation, and full audit.
10. **How is the user warned about cross-project impact?** Scope badges, a
    warning banner, an impact panel with counts (+ visible names), and a required
    confirmation checkbox when impact > 0.
11. **What happens if audit logging fails?** The surrounding transaction rolls
    back; the change is not persisted; the user sees an error.
12. **How are direct POST attempts handled?** They must pass `find_project` +
    `authorize` + CSRF; unauthorized → 403; tampered params are dropped by strong
    params; irrelevant field → 404.
