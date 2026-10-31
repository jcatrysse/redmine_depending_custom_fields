# Changelog

## 0.0.1

* Initial release with Extended user custom field format.

## 0.0.2

* Add context menu support
* Improve performance of custom field queries
* Refactor internals for better consistency and naming
* Replace Minitest with RSpec
* Add full test coverage including API and integration specs
* Improve visibility filtering and admin restrictions in API
* General code cleanup and optimizations

## 0.0.3

* Handle depending fields via Redmine mail handler
* Invalid combinations submitted via API or email are rejected server-side
* Ensure OWASP compliance (add class name mapping to API controller)

## 0.0.4

* Improve Redmine 6.0 compatibility
* Make default values configurable with parent / child relations

## 0.0.5

* Add option to hide depending fields when no valid options are available
* Issue import recognizes extended user values by full name and id

## 0.0.6

* Resolve error on saving new issue

## 0.0.7

* Resolve missing values on API GET output
* Resolve incorrect fields on API GET output

## 0.0.8

* Reworked JavaScript to handle checkboxes.
* Optimize default values handling.

## 0.0.9

* Refactor table layout in formats

## 0.0.10

* Fix internal server error (500) when opening the edit page of a depending
  enumeration custom field on Redmine 5.x/contexts where `sprite_icon` is not
  available by falling back to a plain labelled link directly in the view.


## 0.0.11

* Fix: required depending child fields no longer block saves when the parent's
  current value maps to zero allowed child options.  The suppression now applies
  at the `CustomField` model level (via `CustomFieldPatch#validate_custom_value`)
  so the independent `is_required?` guard in `CustomField#validate_custom_value`
  is correctly bypassed.  A non-blank value submitted despite no options being
  available is still rejected as invalid.
* Add admin warning in the custom-field edit view when a required depending field
  has parent values that carry no allowed child options.

## 0.0.12

* Add **project-level custom field configuration**: a new project permission
  `manage_project_custom_field_configuration` lets delegated (non-admin) project
  members manage the *values*, *enumeration values* and *dependency mappings* of
  custom fields relevant to their project, from a **Project → Settings → Custom
  field configuration** tab. Supported formats: standard `list` / `enumeration`
  and the plugin's `depending_list` / `depending_enumeration` (dependency
  mappings only apply to the two depending formats).
* Cross-project impact is made explicit (scope badges, warning banners, an impact
  panel listing affected dependent fields, and a required confirmation checkbox).
* Renaming/removing a value cascades correctly: list renames rewrite `CustomValue`
  rows and `default_value`; renames/removals of a value used as a *parent key*
  cascade into every depending child; enumeration removal deactivates in-use
  values and destroys unused ones.
* Every change, and every rejected attempt, is written to a new append-only
  `dcf_config_audit_events` table inside the same transaction as the change.
  A project-scoped audit view lives in the settings tab; an admin-only global
  view is available at `/dcf_config_audit`.
* Admin kill-switch `manage_standard_custom_fields` (default on) can exclude
  standard `list`/`enumeration` fields from delegation. Optional
  `block_removal_when_used` setting hardens value removal.
* Adds one additive migration (the plugin's first). The settings-tab is added via
  `alias_method` (no `prepend`, no `Rails.configuration.to_prepare`). The existing
  admin-only API is untouched.

## 0.0.13

* **Redmine 7.0 compatibility.** Fix a `LoadError`/`NameError` on boot under
  Redmine 7.0 (Rails 8.1 / Zeitwerk). The plugin's patch files used
  `require_dependency '<app class>'`, a classic-autoloader idiom that no longer
  resolves for controllers under Zeitwerk. These are removed; the target classes
  are now autoloaded by referencing their constants, which continues to work on
  Redmine 5.x and 6.x.
* Adapt to Redmine 7.0's split of `ContextMenusController#issues` into the
  namespaced `ContextMenus::IssuesController#index`. `init.rb` prepends onto
  whichever controller the running version provides, and the context-menu filter
  now recognises both routings.
* Add a GitHub Actions workflow running the plugin specs against Redmine 7.0.

## 0.0.14

* **Fix `AssociationNotFoundError` on the project custom-field configuration
  tab (GitHub #13).** `FieldRelevance.relevant_fields` preloaded `:projects`
  and `:enumerations` from the `CustomField` STI base while the result set
  mixed `IssueCustomField` and `ProjectCustomField` records. Since `:projects`
  is a habtm defined only on `IssueCustomField`, the Rails 7 preloader (Redmine
  6+), which groups records by concrete class and requires the association on
  each, raised `Association named 'projects' was not found on
  ProjectCustomField`, producing a 500 on the settings tab. The two field types
  are now queried separately so `:projects` is preloaded only where it exists,
  keeping the N+1 optimisation intact.

## 0.0.15

* Drag-and-drop value ordering on the project custom-field configuration
  page
* Edit key-value (enumeration) values the way Redmine's own Administration
  screen does.

## 0.0.16

* **Security:** the context-menu wizard now writes only the custom fields the
  current user may edit on each issue, like Redmine's own bulk edit. Before,
  a user allowed to edit an issue could also change fields that are read-only
  for their role by workflow, or hidden for their role, by posting those field
  ids to `/depending_custom_fields/save`. Values for such fields are now
  ignored (the save still answers HTTP 200). As in core, a workflow read-only
  rule also applies to administrators when every role that follows the
  workflow has it. Known limitation: the wizard can still show a field that is
  read-only for the user; its value is not saved.
* **Security:** CSV issue import of `User (extended)` fields now writes only
  the fields the importing user may edit, the same filter Redmine applies to
  every other custom field of the import. Before, a user allowed to import
  issues could set such fields that are hidden for their role or read-only by
  workflow by mapping them in the import settings.
* **Security:** the unused context-menu wizard endpoint
  `/depending_custom_fields/options` is removed. Through a non-JSON extension
  (for example `.html`) any logged-in user could read the names and values of
  depending fields and their parent fields for any issue id, including issues
  they are not allowed to see.
  No part of the plugin called it; the wizard only posts to
  `/depending_custom_fields/save`, which is unchanged.
* Fixed: saving a depending field no longer fails with an internal error (and
  a rolled back save) on MemCacheStore or other cache stores without
  `delete_matched`.
* Fixed: bulk edit of issues and time entries no longer clears untouched
  multi-value dependent fields on every selected record.
* Fixed: the per-parent default table of the admin custom field form shows
  "Default value" instead of a missing translation.
* Removed: the unused and broken `test/spec` suite (it was never run by CI or
  rake).
* Development: `.codex` scripts that reproduce the CI steps locally, a lint
  gate (Ruby 2.7 syntax, compatibility check on added lines, RuboCop ratchet),
  JavaScript tests with `node --test` and jsdom, specs in random order, opt-in
  browser specs (`DCF_SYSTEM_SPECS=1`), locale parity and no-dash checks, and
  manual workflows for Redmine 6.1 and JavaScript.
* Upgrade notes: Ruby 2.7 or newer is required. Redmine 5.0 stays declared but
  is not tested; 5.1, 6.0, 6.1 and 7.0 are tested.

## Unreleased (0.1.0)

* Removed: QueryCustomFieldColumnPatch (it had no effect on any supported Redmine version).
* Added: Choosing the field itself or one of its dependent fields as 'Depends on' is refused (form error, HTTP 422 in the APIs).
* Added: The admin form warns about fields that are part of an existing circular dependency; such fields are treated as independent until the cycle is fixed.
* Added: Size validation against MySQL/MariaDB TEXT limits for List, Key/Value list and both depending formats; nothing is truncated anymore.
* Added: Rake tasks redmine:depending_custom_fields:report_sizes and redmine:depending_custom_fields:widen_core_columns (opt-in, dry run by default, CONFIRM=1 to apply).
* Added: A database storage usage line on the custom field form and project pages at 90 percent of the column limit.
* Changed: Stored values that no longer fit the parent are accepted on save until the parent changes; other values of a multi-value field can still be added or removed.
* Changed: Issue copies (single copy, bulk copy, project copy) keep such values when copied unchanged; project copy no longer skips those issues.
* Changed: On issues and projects, a parent field change is now refused while a dependent field that you cannot edit (read-only by workflow or hidden for your role) holds a value the new parent value does not allow (HTTP 422 in the REST API). A dependent field you can see reports is invalid; for one you cannot see, the error is shown on the parent field without naming it (or as a general error when you cannot see the parent field either or its value did not change). Time entries and other objects already refused such changes.
* Changed: The 'Depends on' select no longer offers the field's own dependent fields.
* Changed: Audit before/after values above 16 KB are stored shrunk with payload_truncated, payload_bytes and payload_sha256 of the full value.
* Fixed: Key/Value list (depending): a disallowed new value gives one error instead of two, and the edit form no longer shows the stored value twice.
* Fixed: On MySQL/MariaDB, a value list or dependency mapping that is too large gives a clear validation error (HTTP 422 in the APIs, audited error in project settings) instead of an internal error or silent truncation.
* Fixed: A large mapping save on widened MySQL columns no longer rolls back because its audit row overflowed.
* Fixed: Error messages in project settings no longer interpret HTML in field names.
* API: The response shape is unchanged. New HTTP 422 reasons: circular parent and MySQL oversize; on core issue and project updates, a parent change blocked by a dependent field you cannot edit (WP-09b).
* Upgrade notes: On issues and projects a parent change is now refused while a dependent field you cannot edit holds a value the new parent value does not allow; this also applies to bulk edit, the context-menu wizard, email and REST updates. A new issue, a new project or a copy gets the default value of a dependent field you cannot edit, and so does an issue moved to a tracker or project where that field was not available; the save is refused when the parent value does not allow that default, and a project copy skips such an issue. Ask someone who may edit that field to change or clear it first, or an administrator to fix a default value the parent value does not allow.
* Upgrade notes: On MySQL servers running without strict mode, saves that used to be truncated silently are now refused. Core List and Key/Value list fields are checked too. The plugin never alters core tables; widening is an explicit rake task and running Redmine processes keep the old limit until restarted. Run report_sizes once after upgrading: fields reported CORRUPT or SUSPECT were truncated earlier and need their values restored from a backup.
* Changed: Dependent fields are never disabled. Disallowed options are hidden and disabled, and a hint under the field names the parent field.
* Changed: In bulk edit and the context-menu wizard, choosing a parent value keeps '(No change)' available on dependent fields; a per-parent default is preselected with a visible hint; a dependent field is cleared automatically only when the parent is '(none)' or its value allows nothing. Setting the parent back to '(No change)' restores the previous choice.
* Changed: The context-menu wizard opens every field on '(No change)'; saving without choosing changes nothing (it used to write the root field's default).
* Changed: Per-parent defaults are filled in on new records and when the parent changes; they are no longer filled into empty fields of existing records when the form opens.
* Changed: Dependent fields whose parent is read-only on the form or not available for the tracker are filtered by the stored parent value and may be hidden when 'Hide when no valid options' is set.
* Changed: Dependent fields whose parent you cannot see are no longer filtered in the browser and the page no longer contains that parent's mapping; the server still validates them.
* Changed: 'Hide when no valid options' hides the field with its label while the parent offers no options, only on single-record forms, never while a stored non-matching value is shown and never in bulk edit.
* Changed: The context menu hides only dependent fields available for the selected issues and their parents; parents of unavailable fields come back with their full list; fields whose parent was deleted or that are part of a circular configuration show as plain lists.
* Changed: Context-menu responses include dependency data for the wizard fields and can be larger for very big mappings.
* Changed: The change event fires only when a value really changes; listen to the new dcf:updated event for option changes (see README Integration).
* Changed: Fields rendered without Redmine's custom field helpers are no longer filtered in the browser (see README Integration); the server still validates them.
* Changed: Without JavaScript, Key/Value list (depending) fields show all active values; the server still rejects invalid combinations.
* Changed: A required dependent field that is part of or below a circular configuration, depends on itself or depends on a field of another type or format now needs a value like any required field, also in the REST API, email and imports (up to 0.0.16 a blank value was accepted while the stored parent allowed nothing for it).
* Changed: A blank required radio-style dependent field whose parent value offers options now needs a value on every save of the issue form, also when only a note is added, as a required drop-down already does.
* Fixed: Stored values that do not match an unchanged parent stay selected, marked and saved instead of being removed silently on the next save; switching the parent back restores them.
* Fixed: Required radio-style dependent fields can be cleared.
* Fixed: No more browser errors with circular configurations.
* Fixed: The wizard reports server errors and stays open.
* Fixed: The dependency mapping is no longer embedded in every page, including the login page.
* Fixed: The context-menu wizard offers only fields you may edit on every selected issue; a field that is read-only for you on one of them is no longer shown (its value was not saved), and neither are the dependent fields below it.
* Added: In bulk edit and the wizard, required dependent fields offer '(none)' while the parent selection allows no value.
* Added: Hints are announced to screen readers.
* Deprecated: DependingCustomFields.setup and requestSetup (aliases of DependingCustomFields.init) and CustomFieldVisibility; kept at least throughout 0.1.x, removable no earlier than 0.2.0.
* Removed: window.DependingCustomFieldData, window.ContextMenuWizardConfig, MappingBuilder, ParentMenuBuilder, the after_custom_field_save dispatch, data-depending-* attributes, depending_cf_N ids, the hidden mirror inputs and the data-field-id attribute.
* Upgrade notes: Restart Redmine. If automatic plugin asset mirroring (5.1) or redmine_detect_update (6.x/7.0) is disabled or assets are baked into an image, run rake redmine:plugins:assets (5.1) or rake assets:precompile (6.x/7.0). Reload open browser tabs. The cache key depending_custom_fields/mapping is no longer used; before downgrading to an earlier version on a persistent cache store, run bin/rails runner -e production "Rails.cache.delete('depending_custom_fields/mapping')" once.
* Added: The value you last picked for each parent value comes back when you switch the parent back, also after the form refreshes.
* Added: A dependency editor replaces the checkbox matrix on the admin custom field form and on the project dependency page: collapsible sections per parent value, search, check or uncheck all shown, filters for values without links, counters, per-parent defaults inside each section and inactive values shown and kept.
* Added: CSV import of links (paste or file, preview with per-line errors, merge or replace, undo) and CSV export from the editor, with optional spreadsheet formula protection; 'Add missing child values' for List (depending) fields on the admin form.
* Added: A save is refused when someone else changed the dependency mapping after the page was opened; the editor then shows the current version and your version (use, keep or export yours).
* Added: Search on the project values page for fields with more than 25 values, and pagination for fields with more than 500 values.
* Changed: The admin form sends the dependency mapping as one field (custom_field[dependencies_json]) and is submitted as multipart/form-data while the editor is active.
* Changed: Saving the admin form without touching the dependencies leaves the stored mapping unchanged.
* Changed: Changing the parent field in the admin form removes links that do not match the new parent's values.
* Changed: The default value field stays visible until a parent field is chosen.
* Changed: Editor saves store defaults as one value for single-value fields and as a list for multi-value fields and normalize the order; API GET output can change after an editor save. The JSON API itself is unchanged.
* Changed: The dependency editors need JavaScript. Without it the admin form keeps the mapping unchanged and the project page disables Save.
* Changed: Links to values that no longer exist are reported by the editor and removed at the next editor save; project audit rows count them.
* Changed: Project dependency audit rows store a compact summary (counts, samples, SHA-256 of the mapping); sort and reorder audit rows store the SHA-256 of the order. The source and import details are reported by the browser and are informational.
* Changed: Drag-and-drop ordering is offered only for unfiltered lists with at most 500 values; redirects keep the search and the page; 'Show usage' reports exact counts.
* Fixed: Unticking every link clears the mapping; parent values containing [ or ] and mappings with more than about 4,000 links can be saved (admin form and project settings).
* Fixed: Links to inactive Key/Value list entries are kept on admin saves.
* Fixed: Correcting a failed dependency save in project settings and saving again no longer reports a conflict.
* Deprecated: Posting value_dependencies / default_value_dependencies as nested params to the project dependency page; send dependencies_json (accepted throughout 0.1.x, removed no earlier than 0.2.0). The admin safe attributes value_dependencies and default_value_dependencies remain permanently.
* Removed: Partials custom_fields/formats/_dependencies_matrix and _default_dependencies, CSS classes .dependencies-matrix*, .dependencies-defaults* and .dcf-dependencies-matrix, locale key text_dependency_matrix_help.
* Upgrade notes: Links dropped by earlier versions (inactive Key/Value entries) cannot be restored. Links stored under parent values containing [ or ] were saved under corrupted keys by earlier versions; the editor lists them as orphans and they must be re-linked once. Copied Key/Value list (depending) fields keep links to the source field's entries (no remap); they show as orphans and are removed at the first editor save. Reverse proxies may limit request bodies (nginx client_max_body_size is 1 MB by default): raise it for very large mappings. On PostgreSQL and SQLite, changes from project settings are limited by the new storage setting; the administration and the API are not. Restart Redmine after upgrading (new asset files).
* Changed: The project dependency page shows the global/shared field warning, and a notice instead of the editor when the parent field is not available in the project or no longer exists.
* Changed: The admin form asks for confirmation before a format change that would discard unsaved dependency edits, warns before leaving with unsaved edits, and now places the dependency editor after 'Hide when no valid options' and the edit style.
