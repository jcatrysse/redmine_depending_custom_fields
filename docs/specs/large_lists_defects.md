# Large lists: defects found during research
> Status: plan (spec only, no production code). Spec set: large_lists (see large_lists_README.md).
> Points: 1 to 9 (fixed defects), none (tracked defects). Owner area: delivery (cross-area). Work packages: see per defect. Decisions: UD-03.

## Purpose

Research for this plan uncovered defects in 0.0.15. Some are fixed inside the work packages; others fall outside the nine points and are tracked separately, so they can be planned on their own. SD-01 is a security issue.

## Contents

1. Defects tracked separately (SD-01 to SD-14)
2. Defects fixed inside the plan

## 1. Defects tracked separately

| Id | Severity | Title |
|---|---|---|
| SD-01 | security (medium) | SECURITY: context-menu wizard save writes custom fields the user may not edit |
| SD-02 | major | Wizard save hardening: no journal, :edit_issues instead of core @can[:edit], 7.0 webhooks and updated_on |
| SD-03 | minor | Time-entry context menu leaks extended_user group headers and shows depending fields unfiltered |
| SD-04 | major | Workflow-required depending children with no options cannot be saved |
| SD-05 | minor | default_value_dependencies are not applied server-side (REST, CSV import, email) |
| SD-06 | minor | copy_from of a Key/Value list (depending) field keeps the source field's enumeration ids |
| SD-07 | minor | Editing parent values on the core admin page does not cascade into child mappings |
| SD-08 | minor | Deleting a parent field leaves dangling parent_custom_field_id in children |
| SD-09 | minor | Values containing a comma cannot be imported into multi-value depending fields |
| SD-10 | minor | query_filter_values is asymmetric between the two depending formats |
| SD-11 | minor | block_removal_when_used is not applied to replace-mode imports |
| SD-12 | minor | No report of stored invalid combinations and stored cycles |
| SD-13 | security (medium) | SECURITY: CSV import of extended_user fields bypasses the editable filter |
| SD-14 | security (low) | SECURITY: the wizard options action is reachable over non-JSON formats without visibility or edit checks |

### SD-01: SECURITY: context-menu wizard save writes custom fields the user may not edit

**Status.** Fixed in 0.0.16 (own commit, UD-03): the save assigns through `Issue#safe_attributes=`. An independent review approved it and added SD-13 (same class of defect in the import patch) and a UX item for WP-15 (the wizard still offers fields that are read-only for the user; their values are ignored).

**Severity.** security (medium)

**Evidence.** app/controllers/context_menu_wizard_controller.rb:31-32 assigns issue.custom_field_values = values directly; the check at :22-27 only asks safe_attribute?('custom_field_values'). Core filters assignments to editable_custom_field_values(user) only inside Issue#safe_attributes= (core-5.1 app/models/issue.rb:625-626, core-7.0 :647-648). A user with edit_issues can therefore write workflow read-only and role-invisible fields, without a journal. Confirmed independently by the server, frontend, limits and quality designs (SP-07).

**Recommendation.** Separate PR, outside the 9 points (D4). Minimal fix: keep only keys present in issue.editable_custom_field_values(User.current), or assign through issue.safe_attributes = { 'custom_field_values' => values }. Spec: posted read-only and role-hidden fields stay unchanged; login, visibility and editability still required. CHANGELOG 'Security' entry. Merge before tagging 0.0.16 (recommended, UD-03), no later than 0.1.0 (M2). WP-15 pins the current gates so the plan never widens the endpoint meanwhile.

**Verified during consolidation.** `ContextMenuWizardController#save` (`app/controllers/context_menu_wizard_controller.rb:19-35`) assigns `issue.custom_field_values = values` for every posted field id. Before that it only checks that the user may view and edit each issue (`check_edit_permission`, `:141-147`) and that `custom_field_values` is a safe attribute at all (`:23-28`). Core `Issue#safe_attributes=` instead filters custom field values through `editable_custom_field_values(user)`, which excludes fields that are read-only by workflow or not visible for the user's role. A user who may edit an issue can therefore write such fields by posting their ids to `/depending_custom_fields/save`. No journal entry is created, so the change leaves no history. Timing: own pull request, merged before 0.0.16 is tagged (UD-03); hard prerequisite for 0.1.0 (M2).

### SD-02: Wizard save hardening: no journal, :edit_issues instead of core @can[:edit], 7.0 webhooks and updated_on

**Correction (review of SD-01).** Wizard saves without a journal do change `updated_on` and `lock_version`: core's `save_custom_field_values` touches the record when only custom values changed (core-5.1 `lib/plugins/acts_as_customizable/lib/acts_as_customizable.rb:149`, probed on 5.1 and 7.0). The effect on 7.0 webhooks still needs checking.

**Severity.** major

**Evidence.** Wizard saves custom values without init_journal (context_menu_wizard_controller.rb:31-35). On 7.0, acts_as_webhookable uses after_update_commit (core-7.0 app/models/issue.rb:63, lib/redmine/acts/webhookable.rb:35-39) and updated_on changes only when changed? or a journal has details (core-7.0 app/models/issue.rb:2039-2041), so wizard saves likely fire no webhook or notification (critic C4, inference). The wizard gate is :edit_issues on every issue, not core's @can[:edit].

**Recommendation.** Track after SD-01. Decide whether wizard saves should behave like bulk_update (init_journal, notifications, bulk hook, webhooks); spec on 7.0 for webhook and updated_on.

### SD-03: Time-entry context menu leaks extended_user group headers and shows depending fields unfiltered

**Severity.** minor

**Evidence.** The plugin's ContextMenusControllerPatch only acts on the issue menu (lib/redmine_depending_custom_fields/patches/context_menus_controller_patch.rb:9,26-29). Core time-entry menu: core-7.0 app/controllers/context_menus/time_entries_controller.rb:31-40 and app/views/context_menus/time_entries.html.erb:30-31 render __group_* rows as clickable values and depending fields with all values (critic C3).

**Recommendation.** Separate WP after 0.1.0 (M2) reusing SelectionGraph and the __group_* filter for TimeEntry selections; out of the 9 points per D4.

### SD-04: Workflow-required depending children with no options cannot be saved

**Severity.** major

**Evidence.** The CustomFieldPatch required bypass covers is_required? only; workflow-required fields are checked by Issue#validate_required_fields (core-7.0 app/models/issue.rb:842, core-5.1 :820), which still reports 'cannot be blank' when the parent value allows no child (server design section 8).

**Recommendation.** Separate defect: extend the no-options bypass to workflow-required fields (patch or validate_required_fields filter) with specs on 5.1 and 7.0.

### SD-05: default_value_dependencies are not applied server-side (REST, CSV import, email)

**Severity.** minor

**Evidence.** Per-parent defaults are applied only by the browser runtime (admin mapping); REST API, IssueImport and MailHandler create issues without them (critic C12).

**Recommendation.** Separate feature decision: optionally apply defaults in a before_validation for new records when the child is blank and the parent is set, with an opt-in setting.

### SD-06: copy_from of a Key/Value list (depending) field keeps the source field's enumeration ids

**Severity.** minor

**Evidence.** CustomField copy duplicates format_store, but the copy gets new CustomFieldEnumeration ids, so value_dependencies keys and values still point at the source field (D6 explicitly out of scope; editor design section 3.4).

**Recommendation.** Separate WP: remap enumeration ids by position/name on copy_from. Until then the 0.1.0 (M3) editor shows them as orphans and removes them on the first editor save (documented).

### SD-07: Editing parent values on the core admin page does not cascade into child mappings

**Severity.** minor

**Evidence.** Renaming or removing a value in the parent's possible_values textarea leaves the child mapping keys unchanged; only project-level rename/remove services cascade (app/services/redmine_depending_custom_fields/base_service.rb:236-261; critic C6).

**Recommendation.** Separate feature: optional cascade on admin saves of a parent (rename detection is ambiguous). The 0.1.0 (M3) editor reports such orphans and removes them at the next editor save.

### SD-08: Deleting a parent field leaves dangling parent_custom_field_id in children

**Severity.** minor

**Evidence.** No destroy hook in the plugin or core; children keep the id until their next save, when before_custom_field_save sets it to nil (critic C5; lib/redmine_depending_custom_fields/depending_list_format.rb:20-24 before WP-06).

**Recommendation.** Separate defect: after_destroy hook (in CustomFieldValidationPatch) clearing parent_custom_field_id of children, or a report_sizes column flagging dangling parents. The plan tolerates dangling parents everywhere (unmanaged fields).

### SD-09: Values containing a comma cannot be imported into multi-value depending fields

**Severity.** minor

**Evidence.** value_from_keyword splits multi values on /[;,]/ (lib/redmine_depending_custom_fields/depending_list_format.rb:118); characterized and preserved by WP-06.

**Recommendation.** Separate decision: align with core's own multi-value import separator handling or document; not part of the 9 points.

### SD-10: query_filter_values is asymmetric between the two depending formats

**Severity.** minor

**Evidence.** DependingEnumerationFormat#query_filter_values restricts filter values by the query project's parent value (lib/redmine_depending_custom_fields/depending_enumeration_format.rb:69-75) while DependingListFormat returns all values; a nil query raises today (server S23 keeps the asymmetry, only tolerating nil).

**Recommendation.** Separate decision on unified filter semantics; characterized in WP-04 so a later change is a listed flip.

### SD-11: block_removal_when_used is not applied to replace-mode imports

**Severity.** minor

**Evidence.** The setting is enforced only by RemoveValueService (app/services/redmine_depending_custom_fields/remove_value_service.rb:81, base_service.rb:172-173); a replace import can drop links still used by issues (critic C11).

**Recommendation.** Separate decision: whether link removal should honour the setting (links are not values; removing links destroys no stored data). Could warn in the import preview with usage counts.

### SD-12: No report of stored invalid combinations and stored cycles

**Severity.** minor

**Evidence.** D1 leniency (WP-09) and cycle-member leniency (WP-10) let legacy invalid data persist by design; the only visibility is the admin cycle warning and per-issue errors when the parent changes.

**Recommendation.** Follow-up rake task (read-only) listing issues with combinations outside the mapping and fields in cycles, built on DependencyRules and FieldIndex.

### SD-13: SECURITY: CSV import of extended_user fields bypasses the editable filter

**Severity.** security (medium)

**Evidence.** Found by the independent review of SD-01. Core `IssueImport#build_object` filters the custom field values of an import through `issue.send :safe_attributes=, attributes, user` (core-5.1 `app/models/issue_import.rb:136`, core-7.0 `:136`), which keeps only `editable_custom_field_values(user)`. The plugin's `IssueImportPatch#build_object` (`lib/redmine_depending_custom_fields/patches/issue_import_patch.rb:8,24` before the fix) then looped over every `issue.custom_field_values` and set `cfv.value` directly for `extended_user` fields. Import mappings accept any `cf_<id>` key (core `ImportsController#update_from_params` merges `params[:import_settings].to_unsafe_hash`), so a user with `:import_issues` could set extended_user fields that are hidden for their role or read-only by workflow; those values are not validated either, because core validates editable values only.

**Status.** Fixed in 0.0.16 (own commit, same treatment as SD-01 per UD-03): the patch loops over `issue.editable_custom_field_values(user)` with the import's user and fails closed when that method is missing. DB-backed spec `spec/patches/issue_import_patch_editable_spec.rb` (editable field written; role-hidden field without any workflow rule and workflow read-only field not written) fails on the old code and passes with the fix.

### SD-14: SECURITY: the wizard options action is reachable over non-JSON formats without visibility or edit checks

**Severity.** security (low)

**Evidence.** Found by the WP-04 characterization (`spec/characterization/wizard_routes_spec.rb`). The API routes `depending_custom_fields/:id` carry `format: 'json'`, which acts as a requirement, so `GET /depending_custom_fields/options.html` (or `.js`, `.xml`) falls through to `context_menu_wizard#options` (`config/routes.rb:2-8`). That action only requires a login (`app/controllers/context_menu_wizard_controller.rb:3-5`): no issue visibility check and no edit permission. Any logged-in user can pass issue ids of a private project and gets the parent and child field names and option values available on those issues, which reveals that the issues exist, their tracker field configuration, and for chained parents the values allowed by the issue's stored grandparent value. No client uses the action: the wizard script posts only to `save`. For list parents the values are also wrong (`map(&:last)` on a String gives its last character).

**Recommendation.** Same treatment as SD-01 and SD-13 (UD-03): its own small commit now, not waiting for WP-15. Remove the `options` route, the action and its private helpers (`parent_options`, `child_options`), so every format gives 404. WP-15 still deletes `intersect_allowed_values` and `ParentMenuBuilder`. Flip the SD-14 rows of `spec/characterization/wizard_routes_spec.rb` in that commit. CHANGELOG Security entry.

## 2. Defects fixed inside the plan

| Defect | Evidence | Fixed by |
|---|---|---|
| Every save of a depending field fails on MemCacheStore: `Rails.cache.delete_matched('dcf/*')` raises `NotImplementedError` inside `after_save`, which rolls back the save (HTTP 500). Also NoMethodError on namespaced MemoryStore/FileStore. | `lib/redmine_depending_custom_fields/depending_list_format.rb:77-80`, `depending_enumeration_format.rb:87-90`, `patches/custom_field_patch.rb:9,39-43`; ActiveSupport 6.1, 7.2, 8.1 | WP-03 (hotfix), WP-18 (cache removed) |
| Bulk edit clears untouched multi-value dependent fields on every selected issue: the JS checks `#bulk-edit-form` while core uses `#bulk_edit_form`, falls back to regular mode and posts `name[]=''`. | `assets/javascripts/depending_custom_fields.js:201`; core-7.0 `app/views/issues/bulk_edit.html.erb:26`, `app/controllers/application_controller.rb:450-457` | WP-03 (hotfix), WP-17 |
| Admin matrix: unticking every box keeps the old mapping (no parameter is posted). | `app/views/custom_fields/formats/_dependencies_matrix.html.erb:29` (no hidden fallback) | WP-22, WP-25 |
| Parent values containing `[` or `]` are parsed into wrong keys; colliding rows give HTTP 400. | Rack nested parameter parsing; `_dependencies_matrix.html.erb:29`, `_default_dependencies.html.erb:30`, project `edit_dependencies.html.erb:35` | WP-21, WP-22, WP-27 |
| Forms with more than 4,096 parameters fail (admin matrix, project matrix, list reorder, enumeration batch): HTTP 400 on POST, 404 on PUT/PATCH (the method override is lost), HTTP 500 on Redmine 5.1. | Rack 2.2.14+, 3.0.16+, 3.1.14+ `params_limit`; research critic A1 | WP-22, WP-25, WP-27, WP-29, WP-30 |
| Every admin save drops links of inactive enumerations (the matrix renders only active values). | core `EnumerationFormat#possible_values_records` = `enumerations.active`; `_dependencies_matrix.html.erb:2-7,29` | WP-22, WP-25 |
| Missing translation for the admin "Default value" header (`label_default_value` exists in no locale). | `app/views/custom_fields/formats/_default_dependencies.html.erb:17` | WP-02 |
| Key/Value list (depending): duplicate option in the edit form and a double error for a disallowed value. | core RecordList `options.map(&:last)` on the plugin's 3-tuples, core-7.0 `lib/redmine/field_format.rb:789-806` | WP-08 |
| A circular parent configuration causes unbounded synchronous change-event recursion in the browser; cycles can be created through the admin form and the API. | `depending_custom_fields.js:416-431` always dispatches `change`; `_depending_list.html.erb:10-16` excludes only the field itself | WP-10, WP-17 |
| GET `/depending_custom_fields/options` is shadowed by the API's `:id` route for JSON; no client calls the wizard `options` action. It is still reachable over `.html`, `.js` and `.xml` (security: SD-14). | `config/routes.rb:2-8` | SD-14, WP-15 |
| The "combos" memory restores the value captured at the last parent change, not the user's latest pick. | `depending_custom_fields.js:356-412` | WP-17 |
| The context-menu MutationObserver is never attached (script runs in head, body is null). | `depending_custom_fields.js:544-558` | WP-17 |
| Project copy silently skips issues with a legacy combination; unchanged legacy combinations block REST and email updates. | core-7.0 `app/models/project.rb:1185,1227`; `depending_list_format.rb:102-106` | WP-09 |
| A stored disallowed value is silently dropped when the issue form loads, so a notes-only save clears it. | `depending_custom_fields.js:324-334` | WP-17 |
| On MySQL/MariaDB, value lists or mappings above 64 KB raise HTTP 500 (strict mode) or are silently truncated (non-strict mode). | core `custom_fields.possible_values`/`format_store` are TEXT in 5.1 to 7.0; research_limits | WP-11, WP-12, WP-13, WP-31 |
| QueryCustomFieldColumnPatch has no effect on any supported Redmine version. | core-5.1 `app/models/query.rb:128-135`, core-7.0 `:136-143` | WP-06 (removed) |
