# Redmine Depending Custom Fields

**ATTENTION: ALPHA STAGE**

This plugin provides depending / cascading custom field formats for Redmine that can be toggled via the plugin settings. Two new field formats (*List (dependable)* and *Key/Value list (dependable)*) are introduced in addition to the *Extended user* field format with options for group-based filtering and visibility of active, registered or inactive users.

## Features

1. `User` custom field
   - Filter users by Redmine groups
   - Optionally exclude administrators
   - Choose to display active, registered and/or inactive users
   - Users are listed under headers for active, registered and inactive status in filters
2. `Depending` or `Cascading` custom fields
   - Both for `lists` as `key/value` pairs
   - New formats `List (dependable)` and `Key/Value list (dependable)` allow defining parent/child relationships
   - Parent lists can depend on other lists or dependable lists of the same object type
   - Key/value lists can depend on enumerations or dependable key/value lists of the same object type
   - `Parent` and `Child` relationships between fields
   - Relation between `Parent` and `Child` values is configurable in a matrix
   - Child fields include a blank option to deselect and are disabled until a
     parent value is chosen. Descendant fields update automatically when parents
     are cleared and only show the allowed options
   - Works on all objects that support custom fields such as issues, projects,
     time entries, versions and users
3. `Bulk edit`
   - New custom field types can be used when editing multiple issues at once
   - Allowed values are calculated across all selected issues so only valid options remain available
   - Javascript behaviour ensures only allowed values are selectable when parent fields change
   - "None" can be chosen to clear a value while bulk editing
   - Selecting "None" for a parent field automatically clears all of its
     dependent fields
   - Choosing a value for a parent field hides the "No change" option on all of
     its descendants so invalid values can't be kept

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run `bundle install` if required and migrate plugins with:
   `bundle exec rake redmine:plugins`.
3. Copy plugin assets:
   `bundle exec rake redmine:plugins:assets`.
4. Restart Redmine.

## Compatibility

The plugin is tested with Redmine **5.1** and should work with later versions.

## Development

Tests can be run using:

```bash
bundle exec rake test
```

## API

The plugin exposes a JSON API to read and modify the configuration of list,
enumeration and dependable custom fields. Each endpoint returns all attributes
you normally configure in the Redmine GUI, such as name, description, required
flag, visibility, trackers and projects as well as the dependency mapping.
The following endpoints are available:

- `GET /dependable_custom_fields` – list supported custom fields.
- `GET /dependable_custom_fields/:id` – show a single custom field with its
  dependencies.
- `POST /dependable_custom_fields` – create a new custom field.
- `PUT /dependable_custom_fields/:id` – update an existing custom field.
- `DELETE /dependable_custom_fields/:id` – remove a custom field.

Responses contain the custom field attributes listed above including
`parent_custom_field_id`, the possible values and the mapping of allowed child
values per parent option. Parameters use the same types as in Redmine:

- booleans for flags like `is_required`, `is_filter`, `searchable`, `multiple`,
  `is_for_all` and `visible` (set `visible` to `false` and provide `role_ids`
  to restrict visibility to specific roles)
- arrays of integers for `tracker_ids`, `project_ids` and `role_ids`
- arrays of strings for `possible_values`
- hashes for `value_dependencies`
- enumeration definitions in the `enumerations` array when using enumeration
  fields

### Example usage

List all configured fields:

```bash
curl -H "X-Redmine-API-Key: <TOKEN>" \
  https://redmine.example.com/dependable_custom_fields.json
```

Create a new dependable list field linked to a parent field with id `5`:

```bash
curl -X POST -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "name": "Subtype",
      "type": "IssueCustomField",
      "field_format": "dependable_list",
      "possible_values": ["Minor", "Major"],
      "is_required": true,
      "is_filter": true,
      "searchable": true,
      "visible": true,
      "multiple": false,
      "default_value": "Minor",
      "url_pattern": "https://tracker.example.com/%value%",
      "edit_tag_style": "select",
      "tracker_ids": [1,2],
      "project_ids": [3],
      "role_ids": [4,5],
      "parent_custom_field_id": 5,
      "value_dependencies": {"1": ["Minor"], "2": ["Major"]}
    }
  }' \
  https://redmine.example.com/dependable_custom_fields.json
```

Update dependencies for an existing field:

```bash
curl -X PUT -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "tracker_ids": [1],
      "value_dependencies": {"1": ["Bug", "Feature"]}
    }
  }' \
  https://redmine.example.com/dependable_custom_fields/7.json
```

### Dependable enumeration example

Fetch a dependable enumeration field:

```bash
curl -H "X-Redmine-API-Key: <TOKEN>" \
  https://redmine.example.com/dependable_custom_fields/9.json
```

Create a new dependable enumeration field that depends on a parent field with id `8`.
Enumeration values are passed using the `enumerations` array. Each item can
include a `name` and `position` and will be created for the field. When updating
existing values, include their `id` and optionally `_destroy: true` to remove
them. In this example the field is visible only to the specified roles because
`visible` is set to `false`.

```bash
curl -X POST -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "name": "Detailed activity",
      "type": "TimeEntryCustomField",
      "field_format": "dependable_enumeration",
      "enumerations": [
        {"name": "Research", "position": 1},
        {"name": "Testing", "position": 2}
      ],
      "is_required": true,
      "is_filter": true,
      "searchable": true,
      "visible": false,
      "multiple": false,
      "default_value": 1,
      "tracker_ids": [1],
      "project_ids": [3],
      "role_ids": [4,5],
      "parent_custom_field_id": 8,
      "value_dependencies": {"1": ["2"]}
    }
  }' \
  https://redmine.example.com/dependable_custom_fields.json
```

Update the dependencies of that enumeration field:

```bash
curl -X PUT -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "enumerations": [
        {"id": 1, "name": "Research", "position": 1},
        {"name": "Implementation", "position": 2},
        {"id": 2, "_destroy": true}
      ],
      "value_dependencies": {"1": ["2"]}
    }
  }' \
  https://redmine.example.com/dependable_custom_fields/9.json
```

## License

This plugin is released under the GNU GPL v3.

