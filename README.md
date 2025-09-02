# Redmine Depending Custom Fields

**ATTENTION: ALPHA STAGE**

This plugin provides depending / cascading custom field formats for Redmine. Two new field formats (*List (depending)* and *Key/Value list (depending)*) are introduced in addition to the *Extended user* field format with options for group-based filtering and visibility of active, registered or inactive users.

## Features

1. `User` custom field
   - Filter users by Redmine groups
   - Optionally exclude administrators
   - Choose to display active, registered and/or inactive users
   - Users are listed under headers for active, registered and inactive status in filters
   - Issue import recognizes extended user values by full name and id
2. `Depending` or `Cascading` custom fields
   - Both for `lists` as `key/value` pairs
   - New formats `List (depending)` and `Key/Value list (depending)` allow defining parent/child relationships
   - Parent lists can depend on other lists or depending lists of the same object type
   - Key/value lists can depend on enumerations or depending key/value lists of the same object type
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
   - Invalid combinations submitted via API or email are rejected server-side
   - "None" can be chosen to clear a value while bulk editing
   - Selecting "None" for a parent field automatically clears all of its
     dependent fields
   - Choosing a value for a parent field hides the "No change" option on all of
     its descendants so invalid values can't be kept

## Context menu wizard

Open the context menu on an issue list (right-click or the menu button) to
access the wizard. Users who have the **Edit issues** permission will see a menu
entry for each parent custom field that is valid for all selected issues.
Choosing one of these entries expands the menu in place and shows cascading
select boxes with a save button. Child fields are hidden from the normal menu so
dependencies cannot be broken. The selected value is stored for every chosen
issue once you click **Save**.

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
RAILS_ENV=test bundle exec rspec plugins/redmine_depending_custom_fields/spec
```

## API

The plugin exposes a JSON API to read and modify the configuration of list,
enumeration and depending custom fields. Each endpoint returns all attributes
you normally configure in the Redmine GUI, such as name, description, required
flag, visibility, trackers and projects as well as the dependency mapping.
The following endpoints are available:

- `GET /depending_custom_fields` – list supported custom fields.
- `GET /depending_custom_fields/:id` – show a single custom field with its
  dependencies.
- `POST /depending_custom_fields` – create a new custom field.
- `PUT /depending_custom_fields/:id` – update an existing custom field.
- `DELETE /depending_custom_fields/:id` – remove a custom field.

Responses contain the custom field attributes listed above including
`parent_custom_field_id`, the possible values and the mapping of allowed child
values per parent option. Parameters use the same types as in Redmine:

- booleans for flags like `is_required`, `is_filter`, `searchable`, `multiple`,
  `is_for_all` and `visible` (set `visible` to `false` and provide `role_ids`
  to restrict visibility to specific roles)
- arrays of integers for `tracker_ids`, `project_ids` and `role_ids`
- arrays of strings for `possible_values`
- `default_value` when no `parent_custom_field_id` is set
- hashes for `value_dependencies` and `default_value_dependencies`
- enumeration definitions in the `enumerations` array when using enumeration
  fields

### Example usage

List all configured fields:

```bash
curl -H "X-Redmine-API-Key: <TOKEN>" \
  https://redmine.example.com/depending_custom_fields.json
```

Create a depending list field without a parent:

```bash
curl -X POST -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "name": "Severity",
      "type": "IssueCustomField",
      "field_format": "depending_list",
      "possible_values": ["Minor", "Major"],
      "default_value": "Minor"
    }
  }' \
  https://redmine.example.com/depending_custom_fields.json
```

When a parent field is configured, defaults can be specified per parent value using `default_value_dependencies`:

Create a new depending list field linked to a parent field with id `5`:

```bash
curl -X POST -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "name": "Subtype",
      "type": "IssueCustomField",
      "field_format": "depending_list",
      "possible_values": ["Minor", "Major"],
      "is_required": true,
      "is_filter": true,
      "searchable": true,
      "visible": true,
      "multiple": false,
      "url_pattern": "https://tracker.example.com/%value%",
      "edit_tag_style": "select",
      "tracker_ids": [1,2],
      "project_ids": [3],
      "role_ids": [4,5],
      "parent_custom_field_id": 5,
      "value_dependencies": {"1": ["Minor"], "2": ["Major"]},
      "default_value_dependencies": {"1": "Minor", "2": "Major"}
    }
  }' \
  https://redmine.example.com/depending_custom_fields.json
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
  https://redmine.example.com/depending_custom_fields/7.json
```

Update dependencies and add a value (Critical)

```bash
curl -X PUT -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <TOKEN>" \
  -d '{
    "custom_field": {
      "possible_values": ["Minor", "Major", "Critical"],
      "value_dependencies": {
        "Parent value 1": ["Minor"],
        "Parent value 2": ["Major"]
      }
    }
  }' \
  https://redmine.example.com/depending_custom_fields/7.json
```

### Depending enumeration example

Fetch a depending enumeration field:

```bash
curl -H "X-Redmine-API-Key: <TOKEN>" \
  https://redmine.example.com/depending_custom_fields/9.json
```

Create a new depending enumeration field that depends on a parent field with id `8`.
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
      "field_format": "depending_enumeration",
      "enumerations": [
        {"name": "Research", "position": 1},
        {"name": "Testing", "position": 2}
      ],
      "is_required": true,
      "is_filter": true,
      "searchable": true,
      "visible": false,
      "multiple": false,
      "tracker_ids": [1],
      "project_ids": [3],
      "role_ids": [4,5],
      "parent_custom_field_id": 8,
      "value_dependencies": {"1": ["2"]},
      "default_value_dependencies": {"1": 2}
    }
  }' \
  https://redmine.example.com/depending_custom_fields.json
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
  https://redmine.example.com/depending_custom_fields/9.json
```
## Using depending fields via incoming email

Example snippet showing a parent and child custom field:

```
Parent Field: Hardware
Child Field: Keyboard
```

Invalid combinations are rejected just like when using the API.


## Thank you

Many thanks to ChatGPT for helping to create this plugin.

## License

This plugin is released under the GNU GPL v3.

