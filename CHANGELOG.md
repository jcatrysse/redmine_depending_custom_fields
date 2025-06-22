# Changelog

## 0.0.1

* Initial release with Extended user custom field format.
* Dependable list and Dependable key/value list custom field formats.
* Parent field must be from the same object type.
  * List fields may depend on regular lists or other dependable lists.
  * Key/value fields (enumerations) may depend on key/value lists or other dependable key/value lists.
* Added dependency matrix to configure allowed parent/child values.
* Child fields are disabled until a parent value is chosen and only allowed
  values are shown. Blank options remain available for deselection and all
  descendant fields update when parents are cleared.
* DOM observers limited to context menu containers with debounced initialization.

