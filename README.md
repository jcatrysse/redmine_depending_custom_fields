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
   - Fields can optionally be hidden when they have no valid options to choose
     from
   - Works on all objects that support custom fields such as issues, projects,
     time entries, versions and users
3. `Bulk edit`
   - New custom field types can be used when editing multiple issues at once
   - Allowed values are calculated across all selected issues so only valid options remain available
   - Javascript behaviour ensures only allowed values are selectable when parent fields change
   - The server rejects a new value the parent value does not allow, also via
     API or email; a value already stored is accepted while its parent value
     is unchanged (see [Validation](#validation))
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
issue once you click **Save**, except in the fields you may not edit on that
issue (read-only by workflow or hidden for your role): their values are
ignored, as in Redmine's bulk edit. Each issue is saved on its own. An issue
that cannot be saved, for example because a dependent field you cannot edit
holds a value the new parent value does not allow, keeps its values; the
other issues are saved and the wizard shows the error messages.

## Validation

The server checks every saved value of a dependent field against the values
its parent value allows: on the forms of issues, projects and other objects,
in bulk edit, in the context menu wizard, through the REST API, by email, in
CSV imports and on copies. A value the parent value does not allow is refused
with "is invalid" (HTTP 422 in the REST API), except in the cases below.

### Stored values

A value that was saved earlier and that the parent value no longer allows,
for example after the dependency mapping changed, is accepted on save while
the parent value is unchanged. The values of a multi-value parent are
compared regardless of their order.

- Each value counts on its own: other values of a multi-value field can still
  be added or removed, but every newly added value must be allowed.
- Once the parent value changes, every value must be allowed.
- Only values saved on the record count. A new record that is no copy has
  none, so it is checked strictly; a copy is checked against its source (see
  [Copies](#copies)). The default value a field gets when a tracker or
  project change makes it available is checked strictly too.

This applies to the REST API, email, bulk edit (fields left on "(No change)"
and updates of other attributes), the context menu wizard and copies. The
forms in the browser (the issue form, including the copy form, project
settings, time entries and others) still remove such a value when they open,
if the parent field is on the form. Saving such a form clears the value, or
is refused for a required field.

### Copies

A copy is checked against the issue it was copied from. Values the source
holds are kept when they are copied unchanged and the parent value is the
same as on the source; a changed parent value or an added value is checked
strictly. Bulk copy, project copy and a copy made through the REST API
(`copy_from`) keep such values, and a project copy no longer skips those
issues. A field you cannot edit gets its default value on a copy instead
(see [Dependent fields you cannot edit](#dependent-fields-you-cannot-edit)).
The copy form in the browser is the issue form, so it clears such values (see
above).

### Unavailable parent, missing parent and cycles

- When the parent field is not available on the record (not enabled for its
  tracker or project), a dependent field you can edit must be empty when the
  custom field values are saved; a value gives "is invalid", as before. For a
  dependent field you cannot edit, see the next section.
- A field whose parent field no longer exists is not checked, as before.
- Fields that are part of a stored circular dependency, or whose chain of
  parents reaches one, are not checked on the server until the cycle is
  fixed, and a "Depends on" change that would create a cycle is refused. See
  [Circular dependencies](#circular-dependencies).

### Dependent fields you cannot edit

On issues and projects Redmine checks only the custom fields the user may
edit. The plugin also checks the dependent fields you cannot edit (read-only
by workflow or hidden for your role), with the same rule for stored values:

- A parent change is refused while such a field holds a value the new parent
  value does not allow. This applies to the issue form, the project settings
  form, bulk edit, the context menu wizard, email and REST updates (HTTP 422).
- A field you can see reports "is invalid" under its name. A field you cannot
  see is never named: the error is shown on the parent field, for example
  "Hardware cannot be changed because a dependent field you cannot see has a
  value that does not match the new value", or as the general message "This
  change cannot be saved because a dependent field you cannot see has a value
  that the change does not allow." when you cannot see the parent field either
  or its value did not change.
- A new issue, a new project or a copy gets the default value of a dependent
  field you cannot edit, and so does an issue moved to a tracker or project
  where that field was not available. The save is refused when the parent
  value does not allow that default (for a copy, unless the source issue
  holds that value under the same parent value), and a project copy skips
  such an issue. This is not the stored-value case above: a value the source
  issue holds in a field you can edit is kept by a project copy.
- While the parent field is not available on an issue, a dependent field you
  cannot edit keeps its stored value: edits on the form, in bulk edit, in the
  wizard, by email (notes-only replies included) or through REST, and tracker
  or project moves that make the parent unavailable, still save. A default
  value the field gets on a new issue, a copy or a move is still checked.
- The forms in the browser (the issue form, including the copy form, the
  project settings form and others) clear an editable dependent field whose
  stored value its parent value does not allow, if the parent field is on the
  form (see [Stored values](#stored-values)). So the form save is refused
  when a field you cannot edit depends on that cleared field and holds a
  value.

To get such a save through, ask someone who may edit that field to change or
clear it first, or an administrator to fix a default value the parent value
does not allow.

On time entries, versions and other objects the plugin adds no such check:
Redmine itself validates every custom field value there, so such a parent
change was already refused. Redmine's error there names the dependent field,
also one that is hidden for your role.

## Circular dependencies

A depending field cannot depend on itself or on one of its own dependent
fields. Saving such a "Depends on" choice is refused with a form error, or
with HTTP 422 in the JSON API; the "Depends on" select does not offer these
fields, except the current parent of a field that is already part of a
cycle (see below). The check runs only when the parent of an existing field
changes, so other saves of a field (reordering, mappings, renames) keep
working.

Two administrators who save A depends on B and B depends on A at the same
moment can still create a cycle, because each save checks the other field's
old setting. This race is accepted. A cycle can also come from data saved
before this check existed. The guards:

- the server treats fields that are part of a cycle, or whose chain of parents
  reaches one, as independent (no dependency check) until the cycle is fixed;
- the admin form of a field that is part of a cycle shows a warning naming
  the fields of the cycle; choosing another "Depends on" field breaks it;
- every walk along the parents on the server keeps a list of the fields it
  has visited and stops after 1,000 fields, so a cycle never loops there. The
  issue-form script of this version has no such guard and still filters the
  members of a cycle by their mappings: on a form with a stored cycle it can
  loop and raise script errors in the browser, so fix the cycle with the help
  of the warning.

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run `bundle install` if required and migrate plugins with:
   `bundle exec rake redmine:plugins`.
3. Copy plugin assets:
   `bundle exec rake redmine:plugins:assets`.
4. Restart Redmine.

## Compatibility

* Tested with Redmine **5.1, 6.0, 6.1 and 7.0** on PostgreSQL; 5.1 and 7.0
  also on MariaDB 10.11 (manual run, see
  [MySQL / MariaDB and large lists](#mysql--mariadb-and-large-lists)).
* `requires_redmine` stays at **5.0**: the code is kept compatible with Ruby 2.7
  and Rails 6.1, but Redmine 5.0 itself is not tested.
* Ruby **2.7 or newer** is required.

## MySQL / MariaDB and large lists

### Storage

Redmine stores the possible values of a custom field
(`custom_fields.possible_values`) and its format settings, including this
plugin's dependency mapping (`custom_fields.format_store`), as YAML in two
`TEXT` columns. On MySQL and MariaDB a `TEXT` column holds at most 65,535
bytes. PostgreSQL and SQLite have no such limit.

### Approximate ceilings

For values of about 12 characters, a `TEXT` column holds about:

- 4,250 list values;
- 3,750 links (allowed child values, counted over all parent values) for a
  List (depending) field;
- 5,000 links for a Key/Value list (depending) field.

These numbers are a guide only: the plugin measures the exact bytes a save
would write.

### When a list or mapping is too large

The save is refused with a validation error that names the field and the
sizes, for example "Possible values is too large to store (85,869 bytes, the
database allows at most 65,535 bytes)". This holds for the administration
form, the JSON APIs (HTTP 422) and the project settings pages, where the
refused attempt is audited. Nothing is ever truncated. Core List and
Key/Value list fields are checked too. From 90 percent of the limit the
administration form and the project pages show how much of the column a
field uses.

Before this version MySQL either answered with an internal error or, on a
server without strict mode, silently cut the data, which could leave a field
unreadable.

A field whose stored YAML is not what Rails writes, and whose Rails version
of it is over the limit, refuses every save, a rename included. An example is
a list that MariaDB stored one byte over `TEXT` without its final newline.
Widening the columns (below) is the way out.

### Check the sizes

```bash
bundle exec rake redmine:depending_custom_fields:report_sizes RAILS_ENV=production
```

The task only reads. It lists every List, Key/Value list, List (depending)
and Key/Value list (depending) field with these columns:

- `value_count`: the number of values (rows for Key/Value lists);
- `parents` and `links`: the parent values of the dependency mapping, and the
  allowed child values over all of them;
- `pv_bytes` and `pv_pct`: the bytes stored in `possible_values` and their
  percent of the column limit (`n/a` without a limit);
- `fs_bytes` and `fs_pct`: the same for `format_store`;
- `load_ms`: the time to read both columns, which Redmine pays on every
  request that loads the field;
- `status`: one of
  - `ok`;
  - `WARN`: a column is at or above `WARN_AT` percent of its limit;
  - `OVER`: a column is above its limit;
  - `SUSPECT`: a column does not end with the newline YAML always writes, or
    is exactly at the limit, so it was probably cut by a server without strict
    mode;
  - `CORRUPT`: a column cannot be read, or the value list has a missing
    (null) entry;
  - `n/a (no column limit)`: PostgreSQL and SQLite.

On MySQL and MariaDB the report starts with the session `sql_mode` and
whether it is strict (without strict mode oversized values are silently
truncated), `max_allowed_packet`, and the type and limit of both columns.

Options:

- `FORMAT=csv`: CSV instead of the table (a header line and one line per
  field, without the server lines);
- `ALL=1`: every field format, not only the four above;
- `WARN_AT=90`: the percent for `WARN` (default 90);
- `FAIL_ABOVE=<percent>`: exit with status 1 when a column of any field
  reaches that percent of its limit, for monitoring.

`CORRUPT` and `SUSPECT` fields were probably truncated in the past, and a
`CORRUPT` field may not open in the administration form: restore their values
from a backup (widen the columns first when they do not fit). Run
`report_sizes` again before a Redmine upgrade.

### Widen the columns (optional)

1. Back up the database.
2. Dry run: it prints the plan and the exact SQL and changes nothing:
   `bundle exec rake redmine:depending_custom_fields:widen_core_columns RAILS_ENV=production`
3. Apply: the same command with `CONFIRM=1`.
4. Restart Redmine. Running processes keep the old limit until they restart
   (regenerate `db/schema_cache.yml` too if you use one).

- The columns become `MEDIUMTEXT` (16,777,215 bytes); `TYPE=longtext` gives
  `LONGTEXT`.
- One `ALTER TABLE` statement changes both columns and keeps their character
  set, collation, nullability and comment. It runs with a strict `sql_mode`.
- The task is idempotent and never narrows a column. It refuses, with exit
  status 1 and without any change, a column of an unexpected type, with a
  default value or with an unusual character set or collation name.
- It changes a core table. The plugin never does this by itself: no
  migration, install or upgrade step calls it.
- Check `max_allowed_packet`: a value larger than it cannot be written,
  whatever the column type. The task prints it and warns below 16 MB.
- On Galera clusters, run it in a maintenance window.
- On PostgreSQL and SQLite it prints that there is nothing to do.

### Revert and uninstall

Uninstalling the plugin does not revert the widening; the wider columns are
harmless. To go back to `TEXT`:

1. Back up the database and stop Redmine (or block writes). Running processes
   accept values up to the wider size until they restart, and `TEXT` cannot
   hold them.
2. Dry run:
   `bundle exec rake redmine:depending_custom_fields:widen_core_columns REVERT=1 RAILS_ENV=production`
3. Apply: the same command with `REVERT=1 CONFIRM=1`.
4. Regenerate `db/schema_cache.yml` if you use one, then start Redmine.

The revert is refused while any row holds more than 65,535 bytes; it runs
with a strict `sql_mode` and keeps the collation. Redmine 5.1 to 7.0 contain
no migration that changes these columns.

### Very large lists

Prefer Key/Value list (depending) for very large lists: its values are rows of
their own, the mapping stores their ids, and the data sent to the issue form
is about 2.7 times smaller.

### Tests on MySQL / MariaDB (development)

The specs tagged `:mysql` run only on MySQL or MariaDB. A local run, for
example with MariaDB 10.11 in Docker:

```bash
docker run --rm -d --name dcf-mariadb -p 3307:3306 \
  -e MARIADB_ROOT_PASSWORD=root -e MARIADB_USER=redmine -e MARIADB_PASSWORD=redmine mariadb:10.11
# wait until the first start (user and password setup) has finished
until docker exec dcf-mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; do sleep 1; done
docker exec dcf-mariadb mariadb -uroot -proot -e "GRANT ALL ON *.* TO 'redmine'@'%'"
# in the Redmine checkout (plugin in plugins/redmine_depending_custom_fields):
cat > config/database.yml <<'YML'
test:
  adapter: mysql2
  database: redmine_dcf_test
  host: 127.0.0.1
  port: 3307
  username: redmine
  password: redmine
  encoding: utf8mb4
  variables:
    tx_isolation: "READ-COMMITTED"
YML
rm -f db/schema.rb
bundle install
RAILS_ENV=test bundle exec rake db:drop db:create db:migrate redmine:plugins:migrate
RAILS_ENV=test bundle exec rspec plugins/redmine_depending_custom_fields/spec
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:report_sizes
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns CONFIRM=1
RAILS_ENV=test bundle exec rake redmine:depending_custom_fields:widen_core_columns REVERT=1 CONFIRM=1
```

- Use `host: 127.0.0.1`: with `localhost` the mysql2 adapter uses the Unix
  socket.
- MariaDB before 11.1 knows only `tx_isolation`; MySQL 8 and MariaDB 11.1 or
  later need `transaction_isolation` instead.
- Remove a `db/schema.rb` dumped by PostgreSQL: MySQL cannot load its
  expression indexes.
- On `TEXT` columns one example is reported as pending: it saves a list of
  5,570 values (81,239 bytes) and needs widened columns.

With the `.codex` scripts, `.codex/test_setup.sh 7.0 --db mysql` writes the
same `database.yml` and migrates (defaults 127.0.0.1:3307, user and password
`redmine`, database `dcf_mysql_70`; `DCF_DB_HOST`, `DCF_DB_PORT`,
`DCF_DB_USER`, `DCF_DB_PASSWORD` and `DCF_DB_NAME` override them; it picks
`tx_isolation` or `transaction_isolation` from the server version). The
checkout follows the adapter (`database.yml`, `Gemfile.lock`), so give it its
own `DCF_WORK_DIR`; the script refuses a checkout prepared for PostgreSQL and
never creates users. Then run `.codex/test_plugin.sh 7.0 --suite rspec` with
the same `DCF_WORK_DIR`. The optional manual workflow
`.github/workflows/rspec-mysql.yml` (started by hand only) runs this recipe
for Redmine 5.1 and 7.0 on MariaDB 10.11.

## Development

Plugin specs run inside a Redmine checkout:

```bash
RAILS_ENV=test bundle exec rspec plugins/redmine_depending_custom_fields/spec
```

The `.codex` scripts reproduce the CI steps locally on a fresh Redmine checkout
(they need PostgreSQL with a role `redmine`/`redmine` that may create databases;
the scripts never create roles themselves):

```bash
.codex/redmine_clone.sh 7.0          # shallow clone of 7.0-stable
.codex/test_setup.sh 7.0             # gems, database.yml, migrations
.codex/test_plugin.sh 7.0            # rspec, JavaScript tests and the lint gate
.codex/test_matrix.sh --setup --suite rspec --suite lint   # 5.1, 6.0, 6.1 and 7.0
```

* Specs run in random order; the seed is printed, rerun a failure with
  `--seed <n>`.
* Browser specs (`spec/system`) are opt-in: `DCF_SYSTEM_SPECS=1` (headless
  Chrome). Leave `CHROME_BIN` unset so Selenium Manager picks a matching
  Chrome and chromedriver; set it only together with a matching driver.
* JavaScript tests use Node 22: `npm ci && npm run check && npm test`.
* Lint gate: `.codex/rubocop_ratchet.sh` (Ruby 2.7 syntax, compatibility check
  on added lines, no new RuboCop offenses in changed files).
* The GitHub workflows are manual only (`workflow_dispatch`).
* MySQL / MariaDB runs: see
  [MySQL / MariaDB and large lists](#mysql--mariadb-and-large-lists).

## API

The plugin exposes a JSON API to read and modify the configuration of list,
enumeration and depending custom fields. Each endpoint returns all attributes
you normally configure in the Redmine GUI, such as name, description, required
flag, visibility, trackers and projects as well as the dependency mapping.
The following endpoints are available:

- `GET /depending_custom_fields`: list supported custom fields.
- `GET /depending_custom_fields/:id`: show a single custom field with its
  dependencies.
- `POST /depending_custom_fields`: create a new custom field.
- `PUT /depending_custom_fields/:id`: update an existing custom field.
- `DELETE /depending_custom_fields/:id`: remove a custom field.

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

An update that sets `parent_custom_field_id` to the field itself or to one of
its dependent fields is refused with HTTP 422 and `{"errors": [...]}` (see
[Circular dependencies](#circular-dependencies)). An id that names no field of
the same type and family is stored as `null`, as before.

### Errors

Routes, authentication (administrators only), parameters and the response
shape are unchanged. A refused create or update answers HTTP 422 with
`{"errors": [...]}` holding the full messages, like any other validation
error. Reasons added in this version:

- a circular parent, as described above;
- on MySQL and MariaDB, possible values or a dependency mapping that the
  database column cannot hold, for example
  `{"errors": ["Dependency mapping is too large to store (70,204 bytes, the database allows at most 65,535 bytes)"]}`.
  Nothing is written, and a create with `enumerations` is rolled back. This
  holds for List, Key/Value list and both depending formats; PostgreSQL and
  SQLite have no such limit. The section
  [MySQL / MariaDB and large lists](#mysql--mariadb-and-large-lists) has the
  details.

Redmine's own REST API for issues and projects (not the plugin's
`/depending_custom_fields` endpoints) keeps its response shape too, HTTP 422
with `{"errors": [...]}`. The rules of [Validation](#validation) give it
these reasons:

- `PUT /issues/:id.json` and `PUT /projects/:id.json` are refused when the
  parent value changes while a dependent field you cannot edit (read-only by
  workflow or hidden for your role) holds a value the new parent value does
  not allow. A field you can see reports "is invalid" under its name; a field
  you cannot see is never named: the message is on the parent field, or it is
  the general message "This change cannot be saved because a dependent field
  you cannot see has a value that the change does not allow."
- `POST /issues.json`, a copy with
  `POST /projects/:id/issues.json?copy_from=<id>` and `POST /projects.json`
  give a dependent field you cannot edit its default value, and so does a
  `PUT /issues/:id.json` whose new `tracker_id` or `project_id` makes such a
  field available. The request is refused when the parent value does not
  allow that default; a copy is judged against its source, so a default the
  source issue holds is accepted while the parent value is the same as on
  the source.
- Fewer refusals: an update that sends the stored custom field values
  unchanged, or changes only another custom field, for example
  `PUT /issues/:id.json` with `custom_fields` holding the stored values, is no
  longer refused because a stored value no longer fits its parent value. A
  newly added value the parent value does not allow still answers 422, and
  for Key/Value list (depending) it gives one "is invalid" instead of two
  errors.

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
      "type": "IssueCustomField",
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

A new value the parent value does not allow is rejected just like when using
the API, and a value already stored is accepted while its parent value is
unchanged (see [Validation](#validation)).


## Project-level custom field configuration

By default, all custom field configuration lives under **Administration → Custom
fields** and requires the global `admin` flag. This plugin adds a way to delegate
a **narrow, safe** subset of that work to trusted project members.

### Permission

Grant the project permission **"Manage custom fields"**
(`manage_project_custom_field_configuration`) to a role
(Administration → Roles and permissions). The permission is module-independent,
so administrators always have access in every project, and it can never be
assigned to the *Non member* / *Anonymous* roles. Members holding it gain a
**Project → Settings → Custom field configuration** tab.

### What can be managed

For custom fields **relevant to the current project** (issue custom fields in the
project plus all project custom fields) in a supported format:

* **Standard `list`** and **standard `enumeration`**: values and the field's
  default value.
* **`depending_list`** and **`depending_enumeration`**: values **plus** the
  parent/child dependency matrix. Fields without a parent expose a plain default
  value; child fields configure per-parent default values in the matrix.

Add, rename, remove and reorder values; manage enumeration values; set the
field's default value; and edit the dependency matrix. Values are reordered by
dragging the handle to the target position: the same drag handle, and the same
single control, that Redmine itself uses for enumeration values in
Administration. Key/value (enumeration) values are edited exactly as
Administration edits them: the table is one form with a single **Save** that
applies renames, reordering and the **Active** checkbox together. Unticking
Active hides the value from every picker without deleting anything, and ticking
it again brings the value back. For `multiple` fields the
per-parent default selectors allow choosing several values. The feature
**cannot** create or delete fields, or change a field's type, visibility,
required flag, tracker or project applicability.

### Safety

* Renaming a list value rewrites existing issue values, the field default, the
  field's own dependency entries and the parent keys of every dependent field,
  all in one transaction. Removing a value never deletes issue data (list values
  are left orphaned; in-use enumeration values are deactivated rather than
  destroyed).
* Deactivating an enumeration value is reversible and destroys nothing: stored
  issue values keep resolving to the (inactive) name and the dependency matrix is
  left untouched, so reactivating restores the previous behaviour, including for
  issues already sitting on a deactivated parent value. The only thing it changes
  besides the flag is the field's default value, which is cleared if it pointed
  at the value being deactivated.
* Editing a field shared with, or global to, other projects is allowed but
  surfaced with scope badges, a warning banner, an impact panel and a required
  confirmation checkbox.
* Every change, and every rejected attempt, is recorded in an append-only
  audit log, written in the same transaction as the change. Project managers see
  the audit for their project in the settings tab; administrators can view the
  global log at `/dcf_config_audit`.

### Settings

Two plugin settings (Administration → Plugins → Configure):

* **Allow managing standard list / key-value fields** (`manage_standard_custom_fields`,
  default **on**): turn off to restrict delegation to the plugin's depending
  formats only.
* **Block removing values that are still in use** (`block_removal_when_used`,
  default off): hardens value removal.

### Migration

The feature adds the plugin's first migration (the `dcf_config_audit_events`
audit table). Run `rake redmine:plugins:migrate` after upgrading. If the table
is missing the feature fails closed rather than applying un-audited changes.

> Note on archived vs. closed projects: in Redmine, **closed** projects are
> read-only (the tab and audit remain viewable; write actions are blocked),
> while **archived** projects are inaccessible at the core level.


## Thank you

Many thanks to ChatGPT for helping to create this plugin.

## License

This plugin is released under the GNU GPL v3.

