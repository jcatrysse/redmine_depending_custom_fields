# Phase 5 — Permissions & Authorization Specification

## 1. Required direction (from brief)

- Add a standard project-level Redmine permission.
- Admins always have access (override).
- No separate admin configuration screen.

## 2. Permission name — evaluation & recommendation

| Candidate | Pros | Cons |
|---|---|---|
| `manage_project_custom_field_configuration` | Most explicit; matches "configuration" scope; verb_object Redmine style | Long |
| `manage_project_custom_fields` | Short | Implies create/delete of fields (it does not) → misleading |
| `manage_depending_custom_fields` | Plugin-specific | Hides that scope is project-level; not future-proof if standard fields added |
| `manage_project_field_values` | Communicates "values" | Understates dependency-mapping management |

**Recommendation:** `manage_project_custom_field_configuration`.
**Alternative:** `manage_project_custom_fields` (shorter) — rejected because it
implies field create/delete which is explicitly forbidden.
**Trade-off:** length vs. precision; precision wins for a security-sensitive,
deliberately narrow permission.

- I18n label key: `permission_manage_project_custom_field_configuration`
  = "Manage project custom field configuration" (en).

## 3. Project module dependency

**Decision: register the permission *without* a project module
(module-independent).**

Rationale: Redmine grants module-independent permissions to administrators
unconditionally and does not gate them behind `enabled_module_names`. This
guarantees requirement "admins always see/access the tab in every project"
without forcing admins to enable a module per project. Module-independent
permissions also appear in the role permission screen ungrouped (acceptable;
several core permissions do this).

**Alternative considered:** a dedicated project module
(`project_module :custom_field_configuration`). Pros: opt-in per project, tidy
grouping. Cons: breaks "admin always has access" unless the module is enabled in
every project (because `Project#allows_to?` returns false for disabled modules,
even for admins). **Rejected** for v1 on that basis.
**Trade-off:** module-independent = always-on availability + slightly less tidy
role UI grouping; documented as accepted.

## 4. Registration (init.rb) — shape only (no code in this task)

Registered via `Redmine::AccessControl.map` (NOT inside a `project_module`
block), mapping the new project-scoped controller's actions:

- permission: `:manage_project_custom_field_configuration`
- actions: all actions of `ProjectCustomFieldConfigurationController`
  (`index`, `show`, `add_value`, `rename_value`, `remove_value`,
  `reorder_values`, `edit_dependencies`, `update_dependencies`, `audit`).
- options: `require: :member` (never granted to Non member/Anonymous) **and**
  `read: true`.

> **Correction (independent review): `read:` is a property of the whole
> permission, not per action.** `Redmine::AccessControl.map.permission` takes a
> single `read:` flag for all the listed actions — you cannot mark `index`/`show`
> read and the write actions non-read within one permission. More importantly,
> `read:` controls **closed/archived-project** access: Redmine's
> `User#allowed_to?` returns `false` for a **non-read** permission whenever the
> project is not active (`@project.active? == false`) — *including for admins*.
> If we left the permission non-read, the tab and audit would vanish on archived
> projects even for admins, contradicting the archived-project requirement.
>
> **Decision:** declare the permission **`read: true`** (one flag, all actions),
> so the routes remain reachable on closed/archived projects, and enforce the
> read/write distinction **in the controller**: every write action calls a
> `require_active_project` guard that returns 403 `error_project_archived` when
> `!@project.active?`. This is the standard Redmine pattern and is the single
> source of truth for "read-only while archived".

> `require: :member` ensures the permission cannot be assigned to the built-in
> Non-member or Anonymous roles, closing the public-project hole by construction.

## 5. Routes requiring the permission

All routes under `/projects/:project_id/custom_field_configuration/...`
(see Integration Spec for the exact route table). Each maps to an action of the
new controller covered by the permission.

## 6. Controller-level authorization

```
before_action :find_project          # resolves @project from :project_id
before_action :authorize             # Redmine helper; checks {controller,action} on @project
```
- `authorize` uses `User.current.allowed_to?({controller:, action:}, @project)`;
  admins pass automatically.
- `find_project` 404s on unknown project; archived-project handling per
  Functional Spec §21.

## 7. Service-level authorization (defense in depth)

Each service object re-verifies:
1. `User.current.allowed_to?(:manage_project_custom_field_configuration, project)`.
2. The target field is **relevant** to `project` (Feasibility §2.3).
3. The field's `field_format` is in the supported set (`list`, `enumeration`,
   `depending_list`, `depending_enumeration`); standard `list`/`enumeration`
   additionally require the admin setting `manage_standard_custom_fields`;
   dependency operations additionally require a depending format with a parent.
Failure → raise a typed error mapped to 403/404/422 (and audited).

## 8. Admin override behaviour

- Admins satisfy `allowed_to?` for module-independent permissions in every
  project → see tab, pass `authorize`, pass service check.
- Admins additionally access the optional global audit (read-only).

## 9. Archived projects

- Because the permission is `read: true`, `find_project` + `authorize` succeed on
  archived projects for actors who retain access (incl. admins), so the
  **overview and audit remain viewable**.
- **All write actions** (`add_value`, `rename_value`, `remove_value`,
  `reorder_values`, `update_dependencies`) run a `require_active_project`
  `before_action` that returns **403 `error_project_archived`** when
  `!@project.active?`.
- This controller guard — not the `read:` flag — is the read/write boundary for
  archived projects.

## 10. Public projects

- The permission is `require: :member`, so anonymous/non-member users on a public
  project never receive it. Public visibility of the project does not expose the
  tab or routes.

## 11. Non-members

- No access (403). Membership in the project carrying the role/permission is
  required.

## 12. API access

- v1: **no** project API for this feature; actions are HTML + CSRF only and are
  **not** `accept_api_auth`.
- The existing admin-only API is untouched.
- Future: a read-only project API could reuse the same permission with explicit
  scoping (out of v1).

## 13. Authorization test obligations
See Test Plan §permission tests (admin sees tab; permission holder sees tab;
no-permission 403; cross-project 403; archived read-only; non-member 403).
