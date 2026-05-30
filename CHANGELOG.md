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
