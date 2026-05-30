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
* Every change — and every rejected attempt — is written to a new append-only
  `dcf_config_audit_events` table inside the same transaction as the change.
  A project-scoped audit view lives in the settings tab; an admin-only global
  view is available at `/dcf_config_audit`.
* Admin kill-switch `manage_standard_custom_fields` (default on) can exclude
  standard `list`/`enumeration` fields from delegation. Optional
  `block_removal_when_used` setting hardens value removal.
* Adds one additive migration (the plugin's first). The settings-tab is added via
  `alias_method` (no `prepend`, no `Rails.configuration.to_prepare`). The existing
  admin-only API is untouched.
