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

A second 500 showed up next to redmine_custom_workflows once the first was
fixed (reported by the redmine_ai_triage session, reproduced here):

```
ActionView::Template::Error (undefined method `dcf_relevant_custom_fields' for #<#<Class:0x...>>)
plugins/redmine_depending_custom_fields/app/views/project_custom_field_configuration/_settings_tab.html.erb:1
app/views/projects/settings.html.erb:3
```

Bisected over custom_workflows, contacts_helpdesk, checklists and tags:
custom_workflows alone triggers it. Admin and manager got 500; a user without
the dcf permission got 200, since the partial is not rendered for them.

## Cause

`ProjectsHelper#project_settings_tabs` is patched by several plugins. agile and
contacts prepend; dcf used `alias_method`. Plugins load alphabetically, so the
prepends come first. `alias_method :project_settings_tabs_without_dcf,
:project_settings_tabs` then resolves to agile's prepended method, not core's.
Core's method is lost, and the copied method's `super` runs from ProjectsHelper
itself, where nothing is above it: NoMethodError. The other order (alias
first, prepend after) happens to work, so whether the page breaks depends on
plugin names. On a class (redmine_itil_priority's `IssueQuery` patch next to
agile) the same mix recursed instead (SystemStackError in
`redmine:load_default_data`); that one is fixed in itil_priority 0aa2d54.

The second one: custom_workflows calls `ProjectsController.helper` in its
init, so `ProjectsController::HelperMethods` already includes ProjectsHelper
before dcf loads. dcf included its helper into ProjectsHelper; in the running
app `ProjectsHelper.ancestors` then lists it but `ProjectsController._helpers`
does not (checked with `rails runner` in production mode). Plain Ruby 3.3
propagates such an include in every order tried, so the exact mechanism inside
this chain is not pinned down; the fact is measured. The old alias_method code
had the same include; its own 500 came first and hid this one.

## Fix

`lib/redmine_depending_custom_fields/patches/projects_helper_patch.rb`: the
module defines `project_settings_tabs` calling `super` and is prepended to
ProjectsHelper; the dcf_* helpers are included into ProjectsHelper and, since
961cfca, also registered with `ProjectsController.helper`, which does not depend
on load order.
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
| 961cfca, dcf alone | **269 examples, 0 failures** | 14, 14 failures |
| 961cfca, with the four above plus custom_workflows 0d78541, contacts_helpdesk fba2b08, checklists 60cb538, tags 54630cd | 269, 3 failures | 14, 14 failures |

- The helper fix: with all nine plugins, the patch and request specs fail 8
  examples on 845ba82 (the 2 new helper examples, T-AUTH-1/2, T-UI-6, the
  empty overview, and 2 contacts-fixture ones), 2 on 961cfca.
- New `spec/patches/projects_helper_patch_spec.rb`, 9 examples (10 since 961cfca): on the old code
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
`./.codex/e2e.sh`, with all nine plugins at the heads listed above (the first
run, before 961cfca, had the five: same numbers):

- smoke: 19 screenshots, 0 problems
- core flows: 6 screenshots, 0 problems
- `test/e2e/project_settings_tab.mjs`: 9 screenshots, 0 problems. admin and
  manager see the tab (next to Sprints, Contacts, Deals, ITIL priority, Digest
  Rules) and open it and a field; editor (every permission but this one) gets
  the settings without the tab and 403 on the configuration URL; outsider 403
  on both.
- `docs/e2e/before/`: the same scenario on the old code, HTTP 500 for admin,
  manager and editor.
- `docs/e2e/before-custom-workflows/`: the scenario on 845ba82 with the nine
  plugins, HTTP 500 for admin and manager.
- Not tested: context_menu_actions (not reachable from this session).

Every screenshot was looked at. Seen on the way, not changed (older than this
branch): `/depending_custom_fields/options` is shadowed by the JSON
`depending_custom_fields/:id` route (the wizard JS does not use it).

## Review

- Own adversarial pass over the diff: the "reverse order recurses" claim was
  wrong for a module (checked in plain Ruby 3.3: NoMethodError; alias first and
  prepend after works) and is corrected in bd0b3c3. Ruby 3.x everywhere (CI
  5.1/6.0/7.0 use 3.2/3.3/3.4), so a prepend onto ProjectsHelper reaches
  helper modules that already include it; the dcf_* helper include behaves as
  before. The spec prepends onto throwaway modules only, so it leaves
  ProjectsHelper as it found it.
- `./.codex/openai_review.sh fa0adaf` (gpt-5, 14 files): no findings,
  `docs/reviews/openai-2026-10-07-bd0b3c3.md`.
- Not run in this session: Redmine 5.1 and 6.1 (GEOxyz runs 7.0); the
  workflows for them are there, manual only.

## Production

1. Deploy dcf at 961cfca or later (845ba82 still fails next to
   redmine_custom_workflows), together with redmine_itil_priority ≥ 0aa2d54 and
   redmine_mail_digest ≥ 87d79f2: each of the old versions breaks the page on
   its own next to agile/contacts.
2. No migration, no setting. Restart Redmine.
3. Before the restart, check the other plugins:
   `grep -rn "alias_method.*project_settings_tabs" plugins/` must print
   nothing. A plugin that still aliases a method that others prepend breaks the
   page the same way.
4. After: open Project → Settings as admin and as a project manager.
