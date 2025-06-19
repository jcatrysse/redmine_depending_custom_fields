# Redmine Depending Custom Fields

This plugin provides depending / cascading custom field formats for Redmine that can be toggled via the plugin settings. Version `0.0.2` introduces two new field formats (*List (dependable)* and *Key/Value list (dependable)*) in addition to the *Extended user* field format with options for group-based filtering and visibility of active, registered or inactive users.

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

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run `bundle install` if required and migrate plugins with:
   `bundle exec rake redmine:plugins`.
3. Restart Redmine.

## Compatibility

The plugin is tested with Redmine **5.1** and should work with later versions.

## Development

Tests can be run using:

```bash
bundle exec rake test
```

## License

This plugin is released under the GNU GPL v3.
