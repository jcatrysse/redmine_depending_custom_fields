# Phase 2 — Feasibility Analysis

Scope: only **custom field configuration used by projects**. Conclusions are
based on the existing plugin (inspected) and Redmine 5.1/6.1 internals.

## 1. Existing plugin facts (confirmed by inspection)

| Fact | Evidence |
|---|---|
| Plugin requires Redmine ≥ 5.0, tested on 5.1 | `init.rb`, `README.md` |
| Three formats registered: `extended_user`, `depending_list`, `depending_enumeration` | `lib/redmine_depending_custom_fields.rb` |
| Plugin formats identified by constants `FIELD_FORMAT_DEPENDING_LIST` and `FIELD_FORMAT_DEPENDING_ENUMERATION` (no `managed_formats` helper exists — the code uses these two constants inline) | `lib/redmine_depending_custom_fields.rb`, format classes |
| `depending_list` extends `Redmine::FieldFormat::List`; `depending_enumeration` extends `Redmine::FieldFormat::EnumerationFormat` | format classes |
| `value_dependencies` / `default_value_dependencies` are virtual attrs persisted into the custom field **`format_store`** via `after_save`, loaded `after_initialize` | `patches/custom_field_patch.rb` |
| Global `CustomField.safe_attributes(... value_dependencies, default_value_dependencies, parent_custom_field_id, hide_when_disabled ...)` | `init.rb` |
| Existing API (`DependingCustomFieldsApiController`) is **admin-only** (`before_action :require_admin`) with a `PERMITTED_SCALAR` whitelist | controller |
| Routes are **global** JSON, not project-scoped | `config/routes.rb` |
| Patches currently use `prepend` (4 of them) | `init.rb` |
| **No `db/migrate`** — the plugin has zero migrations today | repo |
| No project permission, no project module, no project-settings tab, no `Rails.configuration.to_prepare` exist today | `init.rb` |
| RSpec (`spec/`) **and** Redmine test-unit (`test/`) harnesses both present | repo |

## 2. How Redmine determines fields "used by a project"

### 2.1 Issue custom fields
`IssueCustomField` is linked to projects through:
- `is_for_all = true` → available in **every** project (global), **or**
- `custom_fields_projects` join (`CustomField#projects`) → project-scoped, **and**
- `custom_fields_trackers` join (`CustomField#trackers`) → restricts which
  trackers expose it.

Redmine exposes helpers:
- `Project#all_issue_custom_fields` → `IssueCustomField.sorted` filtered to
  `is_for_all` plus the project's associated issue custom fields (union). This is
  the canonical "issue custom fields available in this project" set.
- A field is *effectively* shown on an issue only if its tracker is enabled for
  the project, but for **configuration relevance** `all_issue_custom_fields`
  is the correct, stable basis.

### 2.2 Project custom fields
`ProjectCustomField` applies to the **Project** object itself. **Correction
(independent-review fix #7):** unlike issue custom fields, project custom fields
are **not scoped per project** — `ProjectCustomField` has no per-project
`projects` association the way `IssueCustomField` does; every project custom
field effectively applies to **all** projects. Consequences:
- **Relevance** for a project CF = "defined and in a supported format" (it is
  relevant to every project).
- **Scope badge** for a project CF is therefore **always Global** — every edit is
  high-impact and the cross-project warning/confirmation always applies.
- The implementing agent must **verify the exact association surface**
  (`is_for_all`, `projects`) for `ProjectCustomField` on both 5.1 and 6.1 before
  coding, and must not assume the issue-CF scoping logic transfers.

### 2.3 Definition adopted for this feature (relevance model)
A custom field is **relevant to project P** for v1 iff **all**:
1. Its type is `IssueCustomField` or `ProjectCustomField`, **and**
2. For `IssueCustomField`: it is in `P.all_issue_custom_fields`
   (i.e. `is_for_all` or associated with P). For `ProjectCustomField`: it is
   always relevant (treated as Global; see §2.2), **and**
3. Its `field_format` is in the **supported set** (see §6), and — for standard
   `list`/`enumeration` — the `manage_standard_custom_fields` setting is enabled.

Time entry / version / user custom fields are **deferred** (NG8).

## 3. Storage of values per format

| Format | Possible values storage | `CustomValue.value` stores | Rename safety |
|---|---|---|---|
| `list`, `depending_list` (extends List) | Serialized YAML array in `custom_fields.possible_values` column | the **string** value | Renaming **breaks** stored values unless `CustomValue` rows are also rewritten |
| `enumeration`, `depending_enumeration` | `custom_field_enumerations` rows (`id`, `name`, `position`, `active`) | the enumeration **id** (as string) | Renaming the `name` is **safe** (id unchanged); deleting an enumeration orphans references |

This distinction is the single most important feasibility result: **list-format
renames are string-keyed and risky; enumeration renames are id-keyed and safe.**

## 4. Dependency mapping storage & desync risk

`value_dependencies` and `default_value_dependencies` are stored in the custom
field's **`format_store`** (no dedicated table). Shape (from README/API):
- `value_dependencies`: `{ "<parent_value_key>" => ["<child_value>", ...] }`
- `default_value_dependencies`: `{ "<parent_value_key>" => "<child_value>" }`

Keying:
- For `depending_list` children, child values are **strings** matching
  `possible_values`. Parent keys are the parent field's value keys
  (string for list parents, enumeration **id** for enumeration parents — README
  examples use both numeric ids and value strings).
- For `depending_enumeration` children, child values are enumeration **ids**.

Consequences:
- **Renaming a list value** that appears as a key or in a child list in
  `value_dependencies` / `default_value_dependencies` **silently breaks** the
  mapping unless those entries are rewritten in the same operation.
- **Removing a list value** must also prune it from all dependency entries
  (as a key and inside child arrays) to avoid orphan mappings.
- **Renaming an enumeration value** does not touch dependency keys (id-based).
- **Removing an enumeration value** requires pruning id references.

→ Operations Spec defines transactional rewrite of `format_store` alongside
`possible_values`/`CustomValue` changes.

> The plugin also maintains a dependency *cache* (see `spec/models/*cache*`).
> The implementing agent MUST invalidate/refresh that cache after writes by
> re-saving the custom field through its normal `save` path (the existing
> `after_save`/`after_initialize` hooks already maintain the cache). Do not write
> `format_store` behind the model's back.

## 5. Usage counts — feasibility

| Count | Query | Notes |
|---|---|---|
| Per-value usage (global) | `CustomValue.where(custom_field_id: cf.id, value: v).count` (list) | For enumeration, `value` is the id string. |
| Per-value usage in current project | Join `custom_values` → customized (e.g. `issues`) → `project_id = P` | Issue CF: `customized_type='Issue'`. Project CF: customized is the Project itself. |
| Cross-project usage | total minus current-project, or grouped by project | Computable; can be expensive on large installs → cache per request, cap, and lazy-load (see UI Spec). |
| Project-usage of a field | issue CF: `cf.is_for_all ? Project.active.count : cf.projects.count`; project CF: always all projects (treated Global, see §2.2) | For `is_for_all`, use a single cached `Project.active.count`, not a per-row query. |
| Dependency reference count for a value (own-side) | occurrences as child in this field's `value_dependencies` + `default_value_dependencies` | In-memory over `format_store`; depending formats only. |
| Dependency reference count for a value (parent-side) | occurrences as a **parent key** across `children_of(field)`'s stores | In-memory; applies to **all** supported formats, incl. standard lists used as parents (see §4 and Operations §B/§C). |

**All counts are feasible.** Performance mitigation (independent-review fix #13):
- **Overview** must avoid N+1: preload the `projects` association for listed
  fields, reuse one cached `Project.active.count` for all `is_for_all` rows, and
  derive value-count from already-loaded `possible_values`/enumerations. **Do not**
  run per-value or cross-project **usage** queries on the overview.
- **Value-edit screen** computes per-value usage lazily (or behind a "show usage"
  toggle), caps multiplexed `value IN (...)` queries, and shows a
  "usage unavailable (too large)" fallback past a configurable threshold rather
  than timing out.

## 6. Supported formats for v1

Operationally identical "list of options" semantics make these safe to manage.
**Standard `list` and `enumeration` are now included in v1** (per updated product
direction) alongside the two plugin formats.

| Format | v1 support | Reason |
|---|---|---|
| `depending_list` (plugin) | **Yes** | Core plugin domain; values + dependencies. |
| `depending_enumeration` (plugin) | **Yes** | Core plugin domain; enumeration + dependencies. |
| Standard `list` (`IssueCustomField`/`ProjectCustomField`) | **Yes (v1)** | Same `possible_values` storage as `depending_list`; string-keyed `CustomValue`. Managed for **values only** (no dependency matrix — standard lists have no parent/child). |
| Standard `enumeration` (`IssueCustomField`/`ProjectCustomField`) | **Yes (v1)** | Same `CustomFieldEnumeration` storage as `depending_enumeration`; id-keyed. Managed for **enumeration values only** (no dependency matrix). |
| `extended_user`, `user`, `bool`, `date`, `int`, `float`, `string`, `text`, `link`, `version`, `attachment` | **No** | No "possible values" list to manage, or out of domain. |

**Supported-format set (v1):**
`['list', 'enumeration', 'depending_list', 'depending_enumeration']`.

The set splits into two **capability classes**:

| Capability class | Formats | Manageable operations |
|---|---|---|
| **Value-only** | `list`, `enumeration` | A Add, B Rename, C Remove, D Reorder, E Enumeration values |
| **Value + dependency** | `depending_list`, `depending_enumeration` | the above **plus** F Dependency mapping, G Default value dependencies |

> Standard `list`/`enumeration` fields have **no** `parent_custom_field_id`, so
> the dependency-matrix screen (operations F/G) is **not offered** for them. A
> standard field that an admin later converts to a depending format gains the
> matrix automatically (relevance is derived from `field_format` at request time).

**Setting (kept, repurposed):** a plugin boolean setting
`manage_standard_custom_fields` (default **true** in v1) lets an administrator
**globally disable** delegation of standard (non-plugin) `list`/`enumeration`
fields if a site wants to restrict the feature to the plugin's own formats only.
This is an admin safety valve, not a per-project toggle. Marked as
**assumption A-FORMAT (revised)**.

### 6.1 Why standard formats are safe to include
- **Identical storage**: `list` ≡ `depending_list` for `possible_values`;
  `enumeration` ≡ `depending_enumeration` for `CustomFieldEnumeration`. The
  same add/rename/remove/reorder services work unchanged; only the
  dependency-matrix path is skipped.
- **No new write surface**: the same strong-params + no-`safe_attributes=`
  discipline applies.
- **Blast radius is the only delta**: standard `list`/`enumeration` fields are
  more commonly `is_for_all` (global) than the plugin's, so the cross-project
  warning/confirmation gate (already specified) does more work. No new mechanism
  is required — the existing Shared/Global badges and impact panel cover it.
- **Relevance still applies**: a standard field is offered only if it is in
  `Project#all_issue_custom_fields` / project-scoped for P (Feasibility §2.3),
  so a global field unrelated to the project is still not editable from a
  project where it is not actually used.

## 7. Cross-project name leakage

- Showing **counts** of projects is always safe.
- Showing **project names** must be filtered by `Project.visible(User.current)`
  (or `User.current.allowed_to?(:view_project, project)`/membership). Admins see
  all names. Delegated users see only names of projects they can see; the rest
  are summarised as "+N other project(s)". **Feasible and required.**

## 8. Can direct editing from project settings safely save *global* field changes?

Yes, **if and only if** the write path is constrained:
- Only `possible_values` (reordered/added/renamed/removed), enumeration rows,
  and `value_dependencies`/`default_value_dependencies` are mutated.
- No `safe_attributes=` blanket assignment from params; the service sets only the
  specific attributes/associations.
- The model is saved through its normal `save` (so validations, dependency
  sanitizer and cache callbacks run).
- The change to a shared/global field is surfaced with explicit cross-project
  warnings and confirmation.

This is acceptable: a delegated manager *intentionally* edits a shared field
after being warned — equivalent to what an admin would do, but scoped to the
allowed operations and audited.

## 9. Operations that must be blocked (too risky / out of domain)

- Changing `field_format`/`type` (data corruption).
- Changing `visible`/`role_ids` (information disclosure / privilege).
- Changing `is_required`, `tracker_ids`, `project_ids`, `is_for_all`
  (changes scope/validation across projects — outside delegation intent).
- Create/Delete custom field.
- Any tracker/workflow change.

## 10. Operation classification

Legend: **R** = Recommended for v1 · **P** = Possible but risky · **O** = Out of
scope for v1 · **D** = Strongly discouraged.

| Op | Operation | Class | Rationale / conditions |
|---|---|---|---|
| A | Add possible value | **R** | All four formats. Append/insert; reject blank/duplicate; audit. |
| B | Rename possible value | **R** | All four formats. List/standard-list: rewrite `possible_values` + `CustomValue` rows + (depending only) dependency entries, transactional, cross-project warning. Enumeration/standard-enumeration: rename `name` (id-safe). |
| C | Remove possible value | **R** | All four formats. Warn + confirm; prune dependency entries (depending only); do **not** auto-delete issue data (orphaned values flagged). Optionally block when used (config). |
| D | Reorder possible values | **R** | All four formats. List: reorder array; Enumeration: update `position`. Submitted set must equal current set exactly. |
| E | Manage enumeration values | **R** | `enumeration` + `depending_enumeration`. Via `CustomFieldEnumeration` (id/name/position/active); id-keyed, safe. |
| F | Manage dependency mapping | **R** | `depending_list` + `depending_enumeration` **only** (requires `parent_custom_field_id`). Validate parent/child + value existence; prevent orphans. |
| G | Manage default value dependencies | **R** | `depending_list` + `depending_enumeration` **only**. Same store as F; validate referenced values; safe. |
| H | Edit field name | **O** | Global rename; not needed for delegation intent. |
| I | Edit field description | **O** | Same. |
| J | Edit required flag | **O** | Changes validation across all projects. |
| K | Edit visibility / role_ids | **D** | Security/disclosure risk. |
| L | Edit tracker applicability | **O** | Out of domain (tracker-adjacent). |
| M | Edit project applicability | **D** | Could attach field to other projects → privilege/blast-radius. |
| N | Delete custom field | **O/D** | Forbidden for delegated users. |
| O | Create custom field | **O/D** | Forbidden for delegated users. |

## 11. v1 scope conclusion

**Included (R):**
- **Value operations** A Add, B Rename, C Remove, D Reorder, E Enumeration
  values — for **`list`**, **`enumeration`**, **`depending_list`** and
  **`depending_enumeration`** custom fields (`IssueCustomField` and
  `ProjectCustomField`) that are **relevant to the current project**.
- **Dependency operations** F Dependency mappings, G Default value dependencies —
  for **`depending_list`** and **`depending_enumeration`** only (they require a
  parent field).

**Excluded:** H–O (all field-attribute edits, create/delete), all non-issue/
non-project object types, trackers, workflows, and every field attribute outside
the value/dependency surface. Standard `list`/`enumeration` delegation can be
globally disabled by an admin via the `manage_standard_custom_fields` setting.

## 12. Open questions (non-blocking — defaults chosen)

- **OQ-1**: *(Resolved by updated product direction)* Standard `list`/
  `enumeration` fields **are in v1** (value operations only; no dependency
  matrix). Admin global kill-switch `manage_standard_custom_fields` (default
  **true**). See §6.
- **OQ-2**: Should removing an in-use value be **blocked** or **warn+confirm**? →
  **Default: warn + explicit confirm**, never auto-delete `CustomValue` rows;
  plugin setting `block_removal_when_used` (default **false**) can harden it.
- **OQ-3**: Exact parent-value key type when parent is an enumeration vs list —
  the implementing agent must mirror the existing `MappingBuilder`/`Sanitizer`
  keying exactly (README shows numeric ids for enum parents, strings for list
  parents). → Reuse existing helpers, do not reinvent.
