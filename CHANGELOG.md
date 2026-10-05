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

## 0.0.16 (unreleased)

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
