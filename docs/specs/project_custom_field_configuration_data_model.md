# Phase 6a — Data Model Specification

## 1. Principle

Authorization is handled entirely by the Redmine **project permission**; the
feature stores **no per-project configuration**. The only persistent storage
this feature *adds* is the **audit table** (see Audit Spec). All custom field
configuration continues to live where Redmine/the plugin already store it.

## 2. Existing storage reused (no new tables)

| Concept | Storage | Owner |
|---|---|---|
| List possible values (`list`, `depending_list`) | Serialized YAML array in `custom_fields.possible_values` | Redmine core |
| Enumeration values (`enumeration`, `depending_enumeration`) | `custom_field_enumerations` rows (`id`, `custom_field_id`, `name`, `position`, `active`) | Redmine core |
| Existing issue values | `custom_values` (`customized_type`, `customized_id`, `custom_field_id`, `value`) | Redmine core |
| `value_dependencies`, `default_value_dependencies` | Custom field **`format_store`** (no table) | this plugin |
| Parent/child link | `custom_fields.format_store` `parent_custom_field_id` (+ plugin attrs) | this plugin |
| Field ↔ project | `custom_fields_projects` join / `is_for_all` | Redmine core |
| Field ↔ tracker | `custom_fields_trackers` join | Redmine core |

**No migration is needed for configuration.** Writes must go through the
`CustomField` model's normal `save` so the plugin's dependency sanitizer and
cache callbacks run (do not write `format_store` or `possible_values` columns
directly via SQL).

## 3. `CustomValue.value` semantics (critical)

- **List/depending_list:** `value` = the option **string**. Renaming an option
  requires rewriting matching `custom_values.value`.
- **Enumeration/depending_enumeration:** `value` = the `CustomFieldEnumeration`
  **id** (string). Renaming a `name` does **not** touch `custom_values`.

## 4. New table — audit events

One additive table (the plugin's first migration). Full field-by-field spec is in
the Audit Spec; summarized here for the data-model view:

`dcf_config_audit_events` — append-only log of configuration operations, with
`project_id`, `custom_field_id`, `acting_user_id`, `action`, `status`,
`before_value`, `after_value` (compact **deltas**, not whole lists),
`changes_summary`, `affected_projects_count`, `affected_values_count`,
`affected_child_field_ids` (parent-side cascade targets), request metadata,
`error_message`, `created_at`.

Table-name prefix `dcf_` is chosen to avoid collisions with other plugins in this
multi-plugin environment.

## 5. Referential considerations

- `project_id` / `custom_field_id` / `acting_user_id` are **soft references**
  (no FK with cascade) so audit history survives deletion of a project, field or
  user. Store the human-readable name in `changes_summary`/`before_value` for
  post-deletion readability.
- Nullable `project_id` is allowed for events not tied to a single project
  (none expected in v1, but reserved).

## 6. Optimistic concurrency token

No new column needed. The controller computes a hash of the field's current
value-set / dependency state and submits it as a hidden form field; the service
compares before writing (stale → 409/422). This avoids schema changes.

## 7. Indexing (audit table)

See Audit Spec §indexes. At minimum: `(project_id, created_at)` and
`(custom_field_id, created_at)`.

## 8. What is explicitly NOT stored

- No per-project "which fields are manageable" table (relevance is derived).
- No permission/role mapping table (Redmine roles do this).
- No copy of possible values/enumerations/dependencies (single source of truth
  remains the custom field).
- No new table for the standard-format kill-switch: `manage_standard_custom_fields`
  is a single boolean stored in Redmine's existing plugin-settings store
  (`Setting.plugin_redmine_depending_custom_fields`), not a feature table.
