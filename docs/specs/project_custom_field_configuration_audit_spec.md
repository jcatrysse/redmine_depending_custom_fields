# Phase 6b — Audit Specification

## 1. Goals

- Project managers can see configuration changes **relevant to their project**.
- Administrators can inspect **all** changes.
- Every successful change is audited; auth/validation failures are audited.
- Audit failure must not allow an un-audited change (transactional).

## 2. Design decision — location of audit visibility

**Decision:**
- **Project-scoped view:** an `audit` action inside the **Project → Settings →
  Custom field configuration** tab, showing events where `project_id = @project`.
  Visible to permission holders + admins. (Keeps audit where the manager works;
  no extra config screen.)
- **Global view (admins only, read-only):** the same controller/action serves a
  global listing when `User.current.admin?` and a `scope=all` (or a dedicated
  admin route). This is a **view**, not configuration, so it does not violate
  "no separate admin configuration screen".

**Alternatives considered:**
- Global plugin settings page → rejected (settings pages are for config, and it
  is admin-only by nature; a log there is awkward).
- A separate plugin project subpage (own module/menu) → rejected (extra surface;
  the settings tab already exists).
- Model/table with project-filtered + global views → **chosen** (this is exactly
  the table-backed approach, surfaced in the settings tab + admin view).

**Trade-off:** reusing the settings tab keeps surface minimal but couples audit
to the same permission; acceptable because the permission already implies the
right to see what changed in that project.

## 3. Audit table — `dcf_config_audit_events`

| Column | Type | Null | Default | Reason |
|---|---|---|---|---|
| `id` | bigint PK | no | auto | identity |
| `project_id` | integer | yes | NULL | scope filtering; nullable for non-project events (reserved); soft ref (no FK cascade) so history survives project deletion |
| `custom_field_id` | integer | yes | NULL | which field; soft ref (survives field deletion) |
| `custom_field_name` | string(255) | yes | NULL | readable name snapshot (field may be deleted later) |
| `acting_user_id` | integer | yes | NULL | who; soft ref (survives user deletion) |
| `acting_user_name` | string(255) | yes | NULL | readable actor snapshot |
| `action` | string(64) | no | — | operation key (see §4) |
| `status` | string(32) | no | `'success'` | `success` / `validation_failed` / `forbidden` / `error` |
| `before_value` | text | yes | NULL | serialized **delta** (JSON) of the changed slice — the specific value(s) changed, not whole lists (independent-review fix #10) |
| `after_value` | text | yes | NULL | serialized **delta** (JSON) of the result; reorder stores a compact moved-item / truncated representation with a `truncated` flag |
| `changes_summary` | string(1000) | yes | NULL | human-readable one-line summary |
| `affected_projects_count` | integer | yes | NULL | blast radius (projects sharing the field) |
| `affected_values_count` | integer | yes | NULL | e.g. CustomValue rows touched/orphaned |
| `affected_child_field_ids` | text | yes | NULL | JSON array of depending child field ids touched by the parent-side cascade on rename/remove (independent-review fix #1); NULL/`[]` when none |
| `ip_address` | string(45) | yes | NULL | traceability (IPv6-safe length) |
| `user_agent` | string(512) | yes | NULL | traceability |
| `request_id` | string(64) | yes | NULL | correlate with Rails logs |
| `error_message` | text | yes | NULL | populated on `validation_failed`/`error`/`forbidden` |
| `created_at` | datetime | no | — | when (no `updated_at`; rows are immutable) |

### Indexes
- `index_dcf_audit_on_project_created (project_id, created_at)` — project view.
- `index_dcf_audit_on_cf_created (custom_field_id, created_at)` — per-field history.
- `index_dcf_audit_on_created (created_at)` — global view ordering.

### Validations (audit model)
- `action`, `status` present; `status` in the allowed enum set.
- No update/destroy through application code (append-only). Provide no edit UI.

## 4. Audit `action` values

| action | When |
|---|---|
| `add_value` | possible value / enumeration added |
| `rename_value` | value / enumeration renamed |
| `remove_value` | value / enumeration removed |
| `reorder_values` | order/position changed |
| `update_enumerations` | batched enumeration changes (if used) |
| `update_dependencies` | value dependency mapping changed |
| `update_default_dependencies` | default value dependencies changed |
| `cleanup_invalid_dependencies` | orphan mappings cleaned |
| `authorization_failed` | `authorize`/service permission check failed |
| `validation_failed` | input rejected by validation |
| `save_failed` | model save / transaction error |

## 5. What each event records

- Always: actor, project, field (+ name snapshot), action, status, timestamp,
  request metadata.
- `success`: `before_value` + `after_value` as a **compact delta**, not whole
  lists (independent-review fix #10 — a 300-value global list must not write its
  entire array on every edit). Examples: add → `{"added":"X","position":4}`;
  rename → `{"from":"X","to":"Y"}`; remove → `{"removed":"X"}`; reorder →
  `{"moved":"X","from":2,"to":7}` (or a truncated order with `"truncated":true`).
  Plus `changes_summary`, `affected_*` counts, and `affected_child_field_ids`
  when the parent-side cascade touched children.
- `validation_failed` / `save_failed` / `authorization_failed`:
  `error_message` + attempted input summary (sanitized; no secrets).

## 6. Transactional guarantee

The audit insert occurs **inside** the same DB transaction as the config change:

```
ActiveRecord::Base.transaction do
  apply_change!          # possible_values / enumerations / format_store via model.save!
  write_audit_event!     # insert dcf_config_audit_events row
end
```
If either fails, both roll back. → "audit failure blocks the change" (secure
default). Marked as **decision D-AUDITBLOCK** (accepted over the alternative of
best-effort audit).

> Failure-status audit rows (`forbidden`, `validation_failed`) are written in
> their **own** short transaction (the main change never happened), so they
> persist even though the operation was rejected.

## 7. Who can view audit logs

| Viewer | Scope |
|---|---|
| Admin | All events (global view) + any project view |
| Permission holder in project P | Events with `project_id = P` only |
| Others | None (403) |

## 8. Where audit logs are shown

- **Project view:** `Project → Settings → Custom field configuration → Audit`
  (project controller action `audit`, hard-scoped to `project_id = @project`).
  Visible to permission holders + admins.
- **Global view (admin-only):** a **dedicated admin-only controller + route**,
  `GET /dcf_config_audit` → `DcfConfigAuditController#index` with
  `before_action :require_admin` (independent-review fix #6). This is **not**
  the project permission and **not** a `scope=all` toggle on the project action
  (which a delegated user could attempt to forge); it is a separate surface that
  only admins can reach. Read-only table, paginated, filterable by
  field/action/date/project. See Integration Spec §3/§5.

## 9. Retention policy

- Default: retain indefinitely (append-only).
- Optional admin rake task to purge events older than N days (out of v1; the
  schema supports it via `created_at`).

## 10. Failure-mode summary

| Failure | Audited as | Change persisted? |
|---|---|---|
| Permission denied | `authorization_failed` (own txn) | No |
| Validation error | `validation_failed` (own txn) | No |
| Model save error | `save_failed` (own txn) | No |
| Audit insert error during success path | nothing usable; main txn rolls back | No |
| Audit table missing (migration not run) | controller fails closed with admin error | No |
