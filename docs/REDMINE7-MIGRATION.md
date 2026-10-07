# Redmine 7 migration: Project → Settings HTTP 500

Branch `redmine70-migration`, 2026-10-07. Redmine 7.0-stable-GEOxyz (8067e23),
Rails 8.1, Ruby 3.3.6, PostgreSQL 16.15.

## Problem

With the GEOxyz plugins installed, Project → Settings answered HTTP 500 for
every user allowed to open it (admin, manager, any member with a settings
permission). Production log of the old code:

```
Completed 500 Internal Server Error in 17ms
ActionView::Template::Error (super: no superclass method `project_settings_tabs' for an instance of #<Class:0x...>)
plugins/redmine_contacts/lib/redmine_contacts/patches/projects_helper_patch.rb:26:in `project_settings_tabs'
plugins/redmine_depending_custom_fields/lib/redmine_depending_custom_fields/patches/projects_helper_patch.rb:17:in `project_settings_tabs'
plugins/redmine_agile/lib/redmine_agile/patches/projects_helper_patch.rb:26:in `project_settings_tabs'
app/views/projects/settings.html.erb:3
```

Which combination it takes (old dcf, production server, admin / manager /
reporter):

| plugins next to dcf | result |
|---|---|
| itil_priority (4e47d26), mail_digest (0542bea), agile, contacts | 500 / 500 / 403 |
| agile, contacts | 500 / 500 / 403 |
| agile | 500 / 500 / 403 |
| mail_digest, itil_priority (both alias_method, no prepend) | 200 / 200 / 403, tab present |

So dcf plus **redmine_agile alone** is enough. mail_digest 0542bea had the same
bug on its own (500 with the fixed dcf too, trace through
`project_settings_tabs_with_issue_digest`); fixed upstream in 87d79f2.

## Cause

`ProjectsHelper#project_settings_tabs` is patched by several plugins. agile and
contacts prepend; dcf used `alias_method`. Plugins load alphabetically, so the
prepends come first. `alias_method :project_settings_tabs_without_dcf,
:project_settings_tabs` then resolves to agile's prepended method, not core's.
Core's method is lost, and the copied method's `super` runs from ProjectsHelper
itself, where nothing is above it: NoMethodError. The reverse order recurses.

## Fix

`lib/redmine_depending_custom_fields/patches/projects_helper_patch.rb`: the
module defines `project_settings_tabs` calling `super` and is prepended to
ProjectsHelper; the dcf_* helpers are still included into ProjectsHelper.
Same behaviour (tab only with `:manage_project_custom_field_configuration`,
admins always), works in any load order, and a second prepend is a no-op. The
plugin's other four patches (CustomField, QueryCustomFieldColumn,
ContextMenus::IssuesController, IssueImport) already prepend, and none of the
other four plugins patch those methods; nothing else changed. The specs that
required `alias_method` (Integration §1/§4, UI §1, Product §8/§14, specs
README, agent plan, T-INT-4) now state the new rule and why; review log
Amendment A5.

## Tests

Plugin suite, `spec/` and `test/spec/` (rspec), Redmine 7.0-stable-GEOxyz,
PostgreSQL 16:

| run | spec/ | test/spec/ |
|---|---|---|
| old code (fa0adaf), dcf alone | 259 examples, 0 failures | 14, 14 failures |
| fix, dcf alone | **268 examples, 0 failures** | 14, 14 failures |
| fix, with itil_priority 0aa2d54, mail_digest 87d79f2, agile 8c1d6c9, contacts 634f00f | 268, 3 failures | 14, 14 failures |

- New `spec/patches/projects_helper_patch_spec.rb`, 9 examples: on the old code
  4 fail (prepend structure; chaining through another plugin's prepend loaded
  before and after; applied twice), the 5 behaviour examples pass on both.
- `test/spec/`: the 14 failures are the same on the old code and unrelated
  (stale specs: `session:` keyword on request specs, unqualified
  `ParentDetector`). CI never ran this directory. Left as they are.
- The 3 failures with all plugins come from redmine_contacts: its top-menu `if:`
  proc calls `User#roles`, which needs the builtin GroupNonMember row. The
  plugin's `spec/fixtures/users.yml` replaces the users table, so the test
  database has no builtin groups (a real database has them since migration
  20140920094058; the e2e database has 2). The same 3 examples pass with
  contacts removed. Test-harness artefact, not a production problem.

## End to end (browser)

`./.codex/start_server.sh` (production mode, PostgreSQL) and
`./.codex/e2e.sh`, with all five plugins at the heads listed above:

- smoke: 19 screenshots, 0 problems
- core flows: 6 screenshots, 0 problems
- `test/e2e/project_settings_tab.mjs`: 9 screenshots, 0 problems. admin and
  manager see the tab (next to Sprints, Contacts, Deals, ITIL priority, Digest
  Rules) and open it and a field; editor (every permission but this one) gets
  the settings without the tab and 403 on the configuration URL; outsider 403
  on both.
- `docs/e2e/before/`: the same scenario on the old code, HTTP 500 for admin,
  manager and editor.

Every screenshot was looked at. Seen on the way, not changed (older than this
branch): `/depending_custom_fields/options` is shadowed by the JSON
`depending_custom_fields/:id` route (the wizard JS does not use it).

## Production

1. Deploy dcf together with redmine_itil_priority ≥ 0aa2d54 and
   redmine_mail_digest ≥ 87d79f2: each of the old versions breaks the page on
   its own next to agile/contacts.
2. No migration, no setting. Restart Redmine.
3. Before the restart, check the other plugins:
   `grep -rn "alias_method.*project_settings_tabs" plugins/` must print
   nothing. A plugin that still aliases a method that others prepend breaks the
   page the same way.
4. After: open Project → Settings as admin and as a project manager.
