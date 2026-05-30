# Phase 7 — UI / UX Specification

The UI must feel like **Redmine**, not a SPA. Reuse Redmine's existing markup,
CSS classes, helpers and patterns. Avoid new JavaScript except where the plugin
already uses it (the dependency matrix already ships JS for cascading selects;
reuse that style for the matrix editor only).

## 1. Location & entry point

`Project → Settings` gains a tab **Custom field configuration**
(`label_project_custom_field_configuration`). Added by patching
`ProjectsHelper#project_settings_tabs` with **`alias_method`** (see Integration
Spec). The tab is included only when
`User.current.allowed_to?(:manage_project_custom_field_configuration, @project)`.
**Do not** use `prepend`. **Do not** add `Rails.configuration.to_prepare` to
`init.rb`.

Visibility audience: admins (always) + permission holders. Menu hiding is UX
only — never the security boundary (server enforces).

## 2. Redmine patterns to reuse

- Settings tabs (`render_tabs`) — match core `projects/settings`.
- `<div class="box">`, `<table class="list">`, `<p class="buttons">`.
- Flash: `flash[:notice]`, `flash[:error]`, `flash[:warning]`.
- Errors: Redmine `error_messages_for` / `errorExplanation` block.
- Context/contextual links: `<div class="contextual">`.
- Warnings: `<div class="flash warning">` / `<p class="warning icon icon-warning">`.
- Pagination: Redmine `pagination` helper for audit.
- Icons: **guard with `respond_to?(:sprite_icon)`** (Redmine 6 sprites) and fall
  back to classic `icon-*` CSS classes for 5.1 (existing plugin convention; see
  CHANGELOG "guard sprite_icon for Redmine 5.x").
- All strings via I18n (`l(...)`).

## 3. Screen 1 — Overview (action `index`)

`<div class="box">` with a `<table class="list">`:

| Column | Content |
|---|---|
| Name | field name (link to Manage) |
| Format | format label — **prefer `cf.format.label` / the field-format registry label** (works for every format incl. standard), rather than hard-coding `l(:label_list)` etc. *(independent-review fix #14: the exact core label keys for List/Enumeration differ between 5.1 and 6.1; deriving the label from the registered field format avoids missing-translation markers.)* Plugin formats already expose `label_depending_list` / `label_depending_enumeration`. |
| Scope | badge: **Global** / **Shared** / **Project** |
| Projects | usage count (number; lazy/omitted if global = "all") |
| Values | value count |
| Shared? | warning icon when Global/Shared |
| Actions | "Manage values" (all supported formats); "Edit dependencies" (only depending formats with a parent) |

The overview includes all four supported formats (`list`, `enumeration`,
`depending_list`, `depending_enumeration`) relevant to the project. Standard
`list`/`enumeration` rows show only "Manage values"; the dependency action is
absent for them. When the admin setting `manage_standard_custom_fields` is off,
standard rows are not listed.

- Empty state: `<p class="nodata">` "No manageable custom fields are enabled for
  this project."
- Contextual link to the **Audit** sub-view.
- No links into Administration.

## 4. Screen 2 — Field values edit (action `show`)

Header: field name + format. Warning banner when Global/Shared:
`<div class="flash warning">` "This field is used by other projects. Changes
affect them too."

Sections:
1. **Impact summary box** (lazy): projects using the field (count; names if
   visible to viewer, else "+N other projects"); total values.
2. **Possible values table** (`table.list`):
   | Value | Usage (this project) | Usage (other projects) | Dependency refs | Actions |
   - Inline **Rename** (text field + Save), **Remove** (with confirm), drag or
     up/down **Reorder** controls.
   - Usage columns lazy-loaded or shown behind a "Show usage" toggle to avoid
     heavy queries on render.
3. **Add value** form: text input + optional position + Add button.
4. For Remove/Rename when impact > 0: a confirmation panel with a required
   checkbox ("I understand this affects other projects / existing data") before
   the destructive submit is enabled.

Buttons: `<p class="buttons">` Save / Cancel (Cancel returns to overview).

### Enumeration variant
Same layout, but rows are `CustomFieldEnumeration` records; Rename is safe
(id-stable) — the warning notes that rename does not affect stored issue values,
while Remove deactivates/destroys and warns about historical references.

## 5. Screen 3 — Dependency mapping (action `edit_dependencies`)

Only for fields with a `parent_custom_field_id`.
- Reuse the existing **dependencies matrix** look (`_dependencies_matrix`
  partial style) — rows = parent values, columns = child values, checkboxes.
- A **Default** selector per parent row (single-select among that row's allowed
  children) drives `default_value_dependencies`.
- Help text: `text_dependency_matrix_help` (existing key).
- Warning banner when the field or its parent is Global/Shared.
- Flag invalid/orphan cells; offer "Clean up invalid mappings" (audited).
- Buttons: Save / Cancel.
- Reuse the existing matrix JavaScript only; add no new framework.

## 6. Screen 4 — Audit log (action `audit`)

`<table class="list">`:

| When | Actor | Field | Action | Status | Summary |
|---|---|---|---|---|---|

- Project view: events for `@project`. Admin global view: add a **Project**
  column and a `scope=all` toggle (admin only).
- Paginated (Redmine `pagination`). Optional filters: field, action, date range.
- Status rendered with color cues (success/neutral, failed/red) using existing
  CSS classes.
- Read-only; no edit/delete controls.

## 7. Flash & validation messaging

- Success: `flash[:notice]` with the operation key (e.g. `notice_value_added`).
- Validation: re-render the screen with `error_messages_for`-style block; map to
  keys: `error_value_blank`, `error_value_duplicate`, `error_reorder_mismatch`,
  `error_invalid_dependency`, `error_value_in_use`, `error_format_unsupported`,
  `error_project_archived`, `error_field_not_found`, `error_stale_edit`.
- Cross-project: `flash[:warning]` style banner persists on the edit screen.

## 8. I18n keys to add (en, then de/fr/nl with English fallback)

Labels: `label_project_custom_field_configuration`,
`label_custom_field_values`, `label_custom_field_dependencies`,
`label_custom_field_config_audit`, `label_scope_global`, `label_scope_shared`,
`label_scope_project`, `label_usage_this_project`, `label_usage_other_projects`,
`label_dependency_references`, `label_add_value`, `label_rename_value`,
`label_remove_value`, `label_reorder_values`, `label_show_usage`,
`label_affected_projects`.
Permission: `permission_manage_project_custom_field_configuration`.
Notices: `notice_value_added/renamed/removed`, `notice_values_reordered`,
`notice_dependencies_saved`.
Errors: as listed in §7.
Warnings: `text_shared_field_warning`, `text_global_field_warning`,
`text_confirm_cross_project_change`.

## 9. Accessibility / no-JS fallback

- Reorder must also work without drag-and-drop (up/down buttons submit a form),
  so the feature degrades gracefully and is testable without a JS driver.
- All destructive actions are real form submissions (POST) with confirm dialogs
  using Redmine's `data: { confirm: ... }` pattern.

## 10. Out-of-scope UI

- No field create/delete buttons.
- No type/visibility/required/tracker/project applicability controls.
- No links into Administration or the admin API.
