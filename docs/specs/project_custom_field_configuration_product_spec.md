# Phase 1 — Product Requirements Specification

Feature name: **Project-Level Custom Field Configuration**
Host plugin: `redmine_depending_custom_fields`

## 1. Problem statement

In Redmine, all custom field configuration (possible values, enumeration
values, dependency mappings, flags, applicability) lives under
**Administration → Custom fields** and requires the global `admin` flag.
There is no way to delegate *narrow*, *safe* custom-field maintenance to a
trusted project manager.

In practice, project managers frequently need to add/rename/remove the
**possible values** of list fields and maintain the **parent/child value
dependency mappings** introduced by this plugin (e.g. a "Component" →
"Sub-component" cascade). Today every such change forces a round-trip to a
Redmine administrator, which is slow and over-privileged.

We want to let **selected non-admin project users**, holding a new project
permission, manage the *relevant* custom field configuration from inside the
project they manage — without exposing the Redmine administration area or the
plugin's existing full configuration API.

## 2. Goals

- G1. Add a standard, project-level Redmine permission that delegates a
  **narrow** set of custom field configuration changes.
- G2. Surface the feature as a **Project → Settings → Custom field configuration**
  tab, with no separate admin configuration screen.
- G3. Let delegated users manage **possible values**, **enumeration values**,
  **value dependency mappings** and **default value dependency mappings** for
  custom fields that are **relevant to the current project**. Supported formats
  are **standard `list`**, **standard `enumeration`**, and the plugin's
  **`depending_list`** and **`depending_enumeration`** (dependency mappings apply
  only to the two depending formats).
- G4. Make cross-project impact **explicit** (a field shared with other projects
  must warn loudly before destructive edits).
- G5. Show **impact information**: project usage counts, per-value usage counts,
  dependency references.
- G6. **Audit** every change (and every rejected attempt), with a project-scoped
  view for managers and a global view for administrators.
- G7. Keep the feature **lightweight, maintainable, secure-by-default**, and
  compatible with Redmine **5.1** (mandatory) and **6.1** (where feasible).

## 3. Non-goals

- NG1. Editing custom field *values* on issues/objects (already covered by core
  Redmine and the plugin's context-menu wizard).
- NG2. Tracker management. **Out of scope.**
- NG3. Workflow management. **Out of scope.**
- NG4. Creating or deleting custom fields.
- NG5. Changing custom field **type/format**, **visibility/role restriction**,
  **required flag**, **tracker applicability**, or **project applicability**
  through this feature (see Feasibility §operation classification).
- NG6. A separate admin configuration screen for this feature.
- NG7. Exposing the existing `DependingCustomFieldsApiController` to non-admins.
- NG8. Custom fields of object types other than **issue** and **project**
  custom fields in v1 (time entry / version / user custom fields are deferred).
- NG9. A SPA / heavy client-side framework.

## 4. Target users & personas

| Persona | Description | Access |
|---|---|---|
| **Administrator** | Redmine global admin | Always sees and uses the tab in **every** project; can view all audit records. |
| **Project Manager (delegated)** | Member of a project holding `manage_project_custom_field_configuration` | Sees and uses the tab in **that** project only; manages relevant fields; warned on shared fields; sees project-scoped audit. |
| **Project Member (no permission)** | Ordinary member | Never sees the tab; cannot reach the routes; gets 403. |
| **Auditor / Security reviewer** | Needs traceability | Reads audit records (project-scoped if delegated; global if admin). |

## 5. Main use cases

1. Maintain the option list of a project-relevant list custom field.
2. Maintain enumeration values of a depending-enumeration field.
3. Maintain the parent→child value dependency matrix.
4. Maintain per-parent default values (default value dependencies).
5. Understand impact before a destructive change (usage counts, sharing).
6. Review what was changed, by whom, and when.

## 6. Expected user flows (high level)

### 6.1 Open the tab
Project → Settings → **Custom field configuration** → overview list of relevant
fields with sharing badges and counts.

### 6.2 Edit values
Pick a field → values screen → add / rename / remove / reorder. Destructive
actions show an impact panel and require explicit confirmation when the value is
in use or the field is shared.

### 6.3 Edit dependency mapping
Pick a depending field with a parent → matrix screen → tick allowed child values
per parent value → save. Default value per parent set on the same screen.

### 6.4 Review audit
Audit sub-view lists recent changes for the current project.

Detailed flows: see Functional Spec (Phase 3) and Operations Spec (Phase 8).

## 7. Permission model overview

- One new project permission: `manage_project_custom_field_configuration`
  (see Permissions Spec for naming rationale and alternatives).
- **Module-independent** so administrators always have access in any project
  (Redmine grants module-independent permissions to admins unconditionally).
- `require: :member` so it can never be granted to *Non member* / *Anonymous*.
- Admin bypass is automatic via `User#allowed_to?`.
- Enforcement is **at the controller** (`authorize`) and **re-checked in the
  service layer** per field (relevance + format allow-list). Menu visibility is
  **never** the security boundary.

## 8. Project settings integration

- A new tab appears in `Project → Settings` for admins and permission holders.
- Implemented by patching `ProjectsHelper#project_settings_tabs` via
  **`alias_method`** (see Integration Spec). The tab entry itself is filtered by
  `User.current.allowed_to?(:manage_project_custom_field_configuration, @project)`.
- No global Administration screen is added for configuration. (An optional,
  admin-only **read-only** global audit view is allowed; it is not configuration.)

## 9. Acceptance criteria

- AC1. Admin sees the tab in every project's settings.
- AC2. A user with the permission in project A sees the tab in project A.
- AC3. A user without the permission does not see the tab and receives **403**
  on direct URL access to any action.
- AC4. A user with the permission in project A receives **403** for project B.
- AC5. The overview lists only custom fields **relevant to the project** and in
  a **supported format** — `list`, `enumeration`, `depending_list`,
  `depending_enumeration` (see Feasibility §6). The dependency-mapping screen is
  offered only for fields that have a parent (the two depending formats).
  Standard-format delegation is included unless an admin disables it via the
  `manage_standard_custom_fields` setting.
- AC6. Fields shared beyond the current project show a clear **shared** warning
  and a project-usage count.
- AC7. Each possible value shows a usage count and a dependency-reference count.
- AC8. Add value: appends/normalizes, rejects blank/duplicate.
- AC9. Rename value: updates possible values **and** dependent references **and**
  existing `CustomValue` records (for string-keyed list fields) atomically;
  rejects blank/duplicate; warns on cross-project impact.
- AC10. Remove value: warns/blocks per rules; never silently deletes issue data.
- AC11. Reorder: accepts only a permutation of the exact current value set.
- AC12. Dependency mapping update validates parent/child relationship and value
  existence; rejects orphan mappings.
- AC13. No request can change field type, visibility, required flag, tracker or
  project applicability, nor create/delete a field (mass-assignment safe).
- AC14. Every successful change writes exactly one audit event in the same
  transaction; an audit write failure rolls back the change.
- AC15. All user-facing strings are I18n keys (en + existing de/fr/nl updated at
  least with English fallback).
- AC16. Routes, permission, translations validate; existing admin API behaviour
  is unchanged.
- AC17. Specs pass on Redmine 5.1; the feature does not crash on 6.1.

## 10. Error cases

| Case | Expected behaviour |
|---|---|
| Direct URL access without permission | 403 (Redmine `:forbidden`) |
| Field not relevant to project | 404/403 (treated as not found in this project's scope) |
| Field in unsupported format | 422 / not offered in UI |
| Blank value added | 422, field error, no change |
| Duplicate value added/renamed-to | 422, field error, no change |
| Reorder list mismatch (missing/extra) | 422, no change |
| Invalid dependency mapping (unknown value / wrong parent) | 422, no change |
| Disallowed param submitted (e.g. `field_format`, `visible`) | Ignored (strong params); attempt may be audited |
| Concurrent stale edit | Optimistic check on value-set hash → 409/422 with reload prompt |
| Audit write fails | Whole transaction rolls back; user sees error flash |
| Project archived | Read-only (or 403 on write) — see Functional Spec |
| Permission revoked mid-session | Next request → 403 |

## 11. Empty states

- Project with no relevant fields: friendly empty panel explaining that no
  manageable custom fields are enabled for this project, with a hint to ask an
  administrator. (No links into Administration.)
- Field with no possible values: empty value table with "Add value".
- Field with no parent: dependency matrix tab hidden / disabled with note.
- No audit events yet: "No configuration changes recorded for this project."

## 12. Security requirements (summary; full model in Phase 4)

- Deny-by-default; never rely on menu hiding.
- Controller authorize + service re-check on every action.
- Operation-specific parameters only; no `custom_field` blanket mass assignment.
- Field relevance + format allow-list enforced server-side.
- Existing admin-only API remains admin-only.
- Cross-project changes require explicit confirmation.
- Audit-on-failure for authorization and validation failures (configurable but
  on by default for auth failures).

## 13. Audit requirements (summary; full spec in Phase 6/audit)

- One audit event per successful change; rejected auth attempts audited.
- Project managers see events scoped to their project; admins see all.
- Audit is written transactionally with the change.

## 14. Redmine 5.1 compatibility requirements

- No API/Rails/Zeitwerk feature unavailable in Redmine 5.1 (Rails 6.1).
- Use `require_relative` loading like the rest of the plugin.
- Guard icon helpers (`sprite_icon`) with `respond_to?` (already a plugin
  convention) — 5.1 has no sprite icons.
- Use `alias_method` for the settings-tab patch (not `prepend`).
- Do **not** add `Rails.configuration.to_prepare` to `init.rb`.

## 15. Redmine 6.1 compatibility considerations

- Verify `project_settings_tabs`, `format_store`, `CustomFieldEnumeration`,
  permission registration, and strong-params behaviour on 6.1.
- Where the icon/markup helpers differ, branch on `respond_to?`.
- Differences must be documented and must not break 5.1 (see Integration Spec).

## 16. Operational requirements

- Zero-downtime install: the only schema change is **one additive migration**
  (audit table). No changes to core tables.
- No new runtime dependencies / gems.
- Feature degrades safely: if the audit table is missing (migration not run),
  the controller must fail closed with a clear admin-facing error rather than
  silently skipping audit.
- Logging: audit table is the source of truth; standard Rails logs supplement.
