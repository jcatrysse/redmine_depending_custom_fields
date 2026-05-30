# Phase 9 — Redmine Integration Specification

How the feature wires into the existing plugin and Redmine, with 5.1/6.1
compatibility. Mirrors existing plugin conventions.

## 1. `init.rb` changes (additive)

Add, after existing registrations (no removal of existing lines):

1. **Permission registration** (module-independent), e.g.:
   ```
   Redmine::AccessControl.map do |map|
     map.permission :manage_project_custom_field_configuration,
       { project_custom_field_configuration:
           %i[index show add_value rename_value remove_value
              reorder_values edit_dependencies update_dependencies audit] },
       require: :member,
       read:    true     # single flag for the whole permission (see Permissions §4)
   end
   ```
   `read: true` is **required** so the tab/overview/audit remain reachable on
   closed/archived projects (incl. for admins). The read/write boundary for
   archived projects is enforced in the controller via a `require_active_project`
   guard on the write actions — **not** via the `read:` flag (which is not
   per-action). See Permissions Spec §4/§9.

2. **New `require_relative`s** for the new patch + (optionally) eager files,
   following the existing `require_relative` style at the top of `init.rb`.

3. **Apply the ProjectsHelper patch via `alias_method`** (see §4) — **not**
   `prepend`.

4. **Plugin setting registration** in the `Redmine::Plugin.register` block, e.g.:
   ```
   settings default: { 'manage_standard_custom_fields' => true },
            partial: 'settings/dcf_project_config'
   ```
   - `manage_standard_custom_fields` (boolean, default **true**): when false,
     **standard `list` AND standard `enumeration`** fields are excluded from
     delegation; the two plugin depending formats are always in scope. (Renamed
     from `manage_standard_list_fields` — independent-review fix #11 — because it
     also gates standard *enumeration* fields, not only lists.)
   - **Read rule (independent-review fix #8) — exact, because plugin settings are
     strings (`'0'`/`'1'`), not booleans:**
     ```
     raw = Setting.plugin_redmine_depending_custom_fields['manage_standard_custom_fields']
     standard_enabled = raw.nil? ? true : ActiveModel::Type::Boolean.new.cast(raw)
     ```
     A missing key ⇒ enabled; `'0'`/unchecked ⇒ disabled. **Do not** use
     `!= false` (a string `'0'` is truthy and `'0' != false` is `true`, which
     would wrongly read a disabled setting as enabled). All agents use this rule
     verbatim; centralize it in `FieldRelevance`.
   - This is the **only** admin-facing screen the feature adds, and it is a
     plugin *settings* page (a checkbox), **not** a custom-field configuration
     screen — consistent with "no separate admin configuration screen for the
     configuration workflow".

**Constraints honored:**
- **No `Rails.configuration.to_prepare`** is added (existing convention; the
  plugin loads patches directly in `init.rb`).
- Existing `prepend` patches (CustomField, QueryCustomFieldColumn,
  ContextMenusController, IssueImport) are left as-is. The new **settings-tab**
  patch specifically uses `alias_method` per the environment's requirement.

## 2. Project module decision

**None.** The permission is module-independent (Permissions Spec §3) so admins
always have access. No `project_module` block is added.

## 3. Routes (`config/routes.rb`, additive)

Add project-scoped routes (keep existing global routes untouched):
```
RedmineApp::Application.routes.draw do
  resources :projects, only: [] do
    resource :custom_field_configuration,
             controller: 'project_custom_field_configuration',
             only: [:show] do
      # overview
      get  '',                 action: :index
      get  'fields/:field_id',          action: :show,             as: :field
      post 'fields/:field_id/values',           action: :add_value
      patch 'fields/:field_id/values/rename',   action: :rename_value
      delete 'fields/:field_id/values',         action: :remove_value
      patch 'fields/:field_id/values/reorder',  action: :reorder_values
      get  'fields/:field_id/dependencies',     action: :edit_dependencies
      patch 'fields/:field_id/dependencies',    action: :update_dependencies
      get  'audit',            action: :audit
    end
  end

  # Admin-only GLOBAL audit view (read-only). Separate controller with
  # before_action :require_admin (NOT the project permission). See Audit Spec §8.
  get 'dcf_config_audit', to: 'dcf_config_audit#index', as: :dcf_config_audit
end
```
> The exact route shape is a recommendation; the implementing agent may use a
> flat `match`-style block (consistent with the existing `routes.rb`) as long as
> every project action is scoped under `/projects/:project_id/...`, all actions
> are HTML (not `format: 'json'`), and the global audit route is admin-only.
> Validate with `bundle exec rake routes`.

> **Global audit (independent-review fix #6):** the global, cross-project audit
> view promised by the Audit Spec needs its **own admin-only route + controller**
> (`DcfConfigAuditController#index`, `before_action :require_admin`). It must NOT
> live under the project permission and must NOT be reachable by delegated users.
> The project-scoped `audit` action above only ever shows `project_id =
> @project` events.

## 4. Project settings tab patch — `alias_method` strategy

Patch `ProjectsHelper#project_settings_tabs` to append the new tab:

```
module RedmineDependingCustomFields
  module Patches
    module ProjectsHelperPatch
      def self.included(base)
        base.class_eval do
          alias_method :project_settings_tabs_without_dcf, :project_settings_tabs
          def project_settings_tabs
            tabs = project_settings_tabs_without_dcf
            if User.current.allowed_to?(:manage_project_custom_field_configuration, @project)
              tabs << {
                name:    'custom_field_configuration',
                action:  :manage_project_custom_field_configuration, # used by render_tabs visibility
                partial: 'project_custom_field_configuration/settings_tab', # or controller link
                label:   :label_project_custom_field_configuration
              }
            end
            tabs
          end
        end
      end
    end
  end
end
ProjectsHelper.include(RedmineDependingCustomFields::Patches::ProjectsHelperPatch)
```

Notes / compatibility:
- `project_settings_tabs` exists in Redmine **5.1 and 6.1**
  (`app/helpers/projects_helper.rb`). The `:action` key lets `render_tabs`
  re-check permission so the tab is hidden when not allowed (defense alongside
  the `allowed_to?` guard).
- **Rendering model — decision (independent-review fix #5):** Redmine renders a
  settings tab's `:partial` **inline** inside `projects/settings` (a content
  pane), and `ProjectsController#settings` does **not** set this feature's
  instance variables. Therefore:
  - **The tab partial `_settings_tab.html.erb` renders the OVERVIEW inline.** It
    must compute its data through a **helper** (e.g.
    `dcf_relevant_custom_fields(@project)`), since it cannot rely on dedicated
    controller ivars. Keep the overview cheap (no eager cross-project usage
    counts — see UI Spec §3 and review fix #13).
  - **All mutating forms POST/PATCH/DELETE to the dedicated
    `ProjectCustomFieldConfigurationController`**, which performs the operation
    and **redirects back** to
    `project_settings_path(@project, tab: 'custom_field_configuration')` with a
    flash. Returning to the tab keeps the "inside Project settings" feel.
  - **The richer screens** — single-field values editor (`show`), dependency
    matrix (`edit_dependencies`), and audit (`audit`) — are **full pages** served
    by the dedicated controller (they are too large for the settings content
    pane). They link back to the settings tab.
  - This supersedes the earlier "thin shell that links/redirects" vs "render
    overview directly" ambiguity: **overview inline via helper; actions on the
    dedicated controller; detail screens as full pages.**
- **Use `alias_method`, not `prepend`** (environment requirement; `prepend` has
  caused issues here for this kind of patch).

## 5. Controllers

`app/controllers/project_custom_field_configuration_controller.rb`:
- `< ApplicationController`.
- `before_action :find_project, :authorize` (Redmine helpers).
- `before_action :require_active_project, only: %i[add_value rename_value
  remove_value reorder_values update_dependencies]` → returns 403
  `error_project_archived` when `!@project.active?` (archived-project read/write
  boundary; see Permissions §9).
- `before_action :find_field` for field-scoped actions (relevance + supported-
  format check here; standard formats additionally gated by the
  `manage_standard_custom_fields` setting rule).
- HTML responses; **no `accept_api_auth`** in v1.
- Mutating actions redirect back to
  `project_settings_path(@project, tab: 'custom_field_configuration')` (overview
  is rendered inline in the settings tab); `show`/`edit_dependencies`/`audit` are
  full pages.
- Delegates mutations to service objects; never `safe_attributes=`.
- `helper :project_custom_field_configuration` for view helpers.

`app/controllers/dcf_config_audit_controller.rb` (**admin-only global audit**,
independent-review fix #6):
- `< ApplicationController`.
- `before_action :require_admin` (NOT the project permission).
- `index` lists **all** `dcf_config_audit_events`, paginated/filterable
  (read-only). This is the only cross-project audit surface; delegated users
  cannot reach it.

## 6. Helpers

`app/helpers/project_custom_field_configuration_helper.rb`:
- `dcf_relevant_custom_fields(project)` (used by the inline settings-tab partial,
  since `ProjectsController#settings` does not set this feature's ivars),
- scope badge rendering, usage-count formatting, visible-project-name filtering,
  icon helper with `respond_to?(:sprite_icon)` guard.

## 7. Services

`app/services/redmine_depending_custom_fields/`:
- `field_relevance.rb` — relevance + supported-format predicate + the
  `standard_enabled` setting read rule (single source of truth) + capability
  classes (value-only vs value+dependency) + `children_of(field)` helper for the
  parent-side cascade.
- `add_value_service.rb`, `rename_value_service.rb`, `remove_value_service.rb`,
  `reorder_values_service.rb`, `dependency_mapping_service.rb`,
  `usage_calculator.rb` (own-side **and** parent-side reference counts),
  `audit_recorder.rb`.
- Rename/Remove services run the **parent-side cascade** into depending children
  (Operations §B/§C) inside the same transaction.
- Reuse existing `MappingBuilder` / `Sanitizer` for dependency building.

## 8. Views

`app/views/project_custom_field_configuration/`:
- `index.html.erb` (overview), `show.html.erb` (values),
  `edit_dependencies.html.erb` (matrix), `audit.html.erb`,
  `_settings_tab.html.erb` (tab shell), plus small partials.
- Reuse existing matrix partial style; reuse Redmine `box`/`list` classes.
- The values screen (`show`) is shared by all four formats; it renders the
  dependency-screen link only when the field is a depending format with a parent.

`app/views/settings/`:
- `_dcf_project_config.html.erb` — the plugin settings partial holding the
  `manage_standard_custom_fields` checkbox (admin-only, rendered by Redmine's
  plugin settings page).

## 9. Model

`app/models/redmine_depending_custom_fields/config_audit_event.rb`
(`ActiveRecord::Base`, table `dcf_config_audit_events`, append-only, validations
per Audit Spec). This requires the plugin's **first migration**:
`db/migrate/NNN_create_dcf_config_audit_events.rb` (schema per Audit Spec) —
**to be written in the implementation phase, not now.**

## 10. I18n

Add keys (UI Spec §8) to `config/locales/en.yml`, then mirror into
`de.yml`/`fr.yml`/`nl.yml` (English fallback acceptable initially). Permission
label key required so Redmine's role screen shows a readable name.

## 11. Assets

- Reuse existing matrix JS/CSS. Add minimal CSS only if needed (scope badges) to
  the plugin's existing `assets/` and run `redmine:plugins:assets`.
- No new JS framework.

## 12. Audit model — see Data Model & Audit specs.

## 13. Compatibility — Redmine 5.1

- Rails 6.1; `require_relative` loading (matches plugin).
- `project_settings_tabs`, `format_store`, `CustomFieldEnumeration`,
  `AccessControl.map`, `authorize`, strong params, `protect_from_forgery` all
  present.
- `sprite_icon` **absent** → guard with `respond_to?`; fall back to `icon-*`.
- Migration uses plain `create_table` (no 6.x-only options).

## 14. Compatibility — Redmine 6.1

- Rails 7.x + Zeitwerk: keep `require_relative` (plugin already does); avoid
  relying on autoload of plugin lib files. Ensure new `app/` classes follow
  Redmine's plugin autoload (Redmine adds plugin `app/` paths) — name files to
  match class names.
- Verify `project_settings_tabs` signature/markup unchanged; the `alias_method`
  approach is version-agnostic.
- Verify icon/markup helpers; branch via `respond_to?`.
- `update_all` within a transaction behaves identically.
- Document any divergence; **never** break 5.1.

## 15. Validation checklist (pre-merge)

- `rake routes` shows the new project-scoped routes (HTML), existing routes
  intact.
- Role screen shows the new permission with a translated label.
- Tab visible to admin + permission holder; hidden otherwise.
- Existing admin API still `require_admin`.
- Plugin loads on both 5.1 and 6.1 without `Rails.configuration.to_prepare`.
