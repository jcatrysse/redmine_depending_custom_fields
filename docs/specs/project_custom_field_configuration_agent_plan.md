# Phase 11 — Multi-Agent Implementation Plan

Each work package is sized for one coding agent and references the specs above.
No production code exists yet; these packages produce it.

## Conventions for all agents

- Branch: `claude/festive-mayer-tooku` (per task) or a feature branch off it.
- Honor HARD RULES: `alias_method` for the settings-tab patch (not `prepend`);
  no `Rails.configuration.to_prepare` in `init.rb`; keep the existing admin API
  admin-only; no field create/delete; no type/visibility/applicability edits.
- Reuse existing `MappingBuilder` / `Sanitizer` / matrix JS.
- Tests follow existing RSpec conventions; target green on Redmine 5.1.

---

## Agent 1 — Feasibility validation & final v1 scope (gatekeeper)

- **Scope:** Confirm Redmine 5.1/6.1 internals used by the spec against the
  pinned sources (`jcatrysse/redmine` 5.1-stable & 6.1-stable): `format_store`,
  `project_settings_tabs`, `CustomFieldEnumeration`, `all_issue_custom_fields`,
  `CustomValue.value` semantics, `AccessControl.map` options. Lock OQ-2/OQ-3
  defaults (OQ-1 is resolved: standard `list`/`enumeration` are in v1, value-only,
  admin-gated by `manage_standard_custom_fields`). Confirm `list`≡`depending_list`
  and `enumeration`≡`depending_enumeration` storage equivalence so the
  family-shared service bodies are safe. Confirm how `value_dependencies` parent
  keys are typed by reading `MappingBuilder`/`Sanitizer`.
- **Files:** updates to feasibility/operations specs only (docs).
- **Inputs:** Feasibility, Operations specs.
- **Outputs:** A short "scope-locked" note + any corrections; green light.
- **Dependencies:** none (runs first).
- **Acceptance:** every "assumption" either confirmed or corrected with source
  links; supported-format set finalized.
- **Tests:** none (analysis).
- **Risks:** dependency key typing differs from README → must correct Operations
  §F/§B before others build.
- **Handoff:** publish confirmed key-typing rules to Agents 4 & 7.

## Agent 2 — Permission registration & project settings tab

- **Scope:** Register `manage_project_custom_field_configuration` (module-
  independent, `require: :member`); add the `ProjectsHelper#project_settings_tabs`
  patch via `alias_method`; add the tab partial/link; register the plugin setting
  `manage_standard_custom_fields` (default true) + its settings partial; permission
  + setting I18n labels.
- **Files:** `init.rb` (additive — permission + `settings` block),
  `lib/.../patches/projects_helper_patch.rb`,
  `app/views/project_custom_field_configuration/_settings_tab.html.erb`,
  `app/views/settings/_dcf_project_config.html.erb`,
  `config/locales/en.yml` (permission + label + setting keys).
- **Inputs:** Permissions Spec, Integration Spec §1/§4.
- **Outputs:** Tab visible to admin + permission holder; hidden otherwise.
- **Dependencies:** Agent 1.
- **Acceptance:** T-AUTH-1/2/3, T-INT-2/3/4.
- **Tests:** helper/request specs for tab visibility; load check (no
  `to_prepare`; uses `alias_method`).
- **Risks:** tab partial coupling to core settings instance vars → prefer link
  into the dedicated controller.

## Agent 3 — Audit model & migration

- **Scope:** `ConfigAuditEvent` model + first plugin migration
  (`dcf_config_audit_events`, incl. `affected_child_field_ids` and **compact
  delta** before/after — fixes #1/#10), append-only semantics, validations,
  `AuditRecorder` service with transactional + failure-status helpers. Also the
  **admin-only `DcfConfigAuditController#index`** global view + route
  (`require_admin`, fix #6).
- **Files:** `db/migrate/NNN_create_dcf_config_audit_events.rb`,
  `app/models/redmine_depending_custom_fields/config_audit_event.rb`,
  `app/services/redmine_depending_custom_fields/audit_recorder.rb`,
  `app/controllers/dcf_config_audit_controller.rb`,
  `app/views/dcf_config_audit/index.html.erb`.
- **Inputs:** Data Model & Audit specs.
- **Outputs:** Usable audit API for services; admin global audit page.
- **Dependencies:** Agent 1.
- **Acceptance:** model tests (validations, append-only), T-AUD-7, T-SEC-9.
- **Risks:** table-name collision (use `dcf_` prefix); 5.1/6.1 migration syntax;
  delta serialization must stay small on large global lists.

## Agent 4 — Custom field operation services

- **Scope:** `FieldRelevance` (supported-format set + `manage_standard_custom_fields`
  gating + capability classes), `UsageCalculator`, and services A–E
  (add/rename/remove/reorder/enumeration) with the common preamble + transaction
  + audit wrapper; CustomValue rewrite on list-family rename; dependency pruning
  guarded to the two depending formats. **Services are format-agnostic within a
  family** (`list`≡`depending_list`, `enumeration`≡`depending_enumeration`); the
  only branch is the dependency-rewrite step (depending formats only).
- **Files:** `app/services/redmine_depending_custom_fields/*` (per Integration §7).
- **Inputs:** Operations (incl. SUPPORTED_*/families), Functional, Feasibility §6,
  Audit specs.
- **Dependencies:** Agents 1, 3.
- **Scope addendum:** implement the **parent-side cascade** (rename/remove rewrite
  or prune the value as a *parent key* across `children_of(field)` — fix #1),
  **own-side + parent-side ref counts** in `UsageCalculator` (fix #2),
  **`default_value` integrity** on rename/remove (fix #3), and **enum
  deactivate-when-used** vs destroy-when-unused (fix #9). Centralize the
  `standard_enabled` setting read rule (fix #8) in `FieldRelevance`.
- **Acceptance:** T-ADD/REN/RM/ORD/USE across all four formats; T-REL-7/8/9;
  T-SET-*; T-CAS-1..5; T-DEF-1/2; T-ENU-1/2; T-USE-4; T-AUD-1/2/3/4; T-SEC-8/10.
- **Risks:** depending-list rename desync of dependencies; **forgetting the
  parent-side cascade for standard lists used as parents**; cross-project
  `update_all` scope on global standard lists; cache invalidation (must save the
  field AND each affected child via model `save!`); accidentally running
  *own*-dependency-pruning on a standard `list` (it has none).

## Agent 5 — Project settings controller & routes

- **Scope:** `ProjectCustomFieldConfigurationController` with `find_project`,
  `authorize`, **`require_active_project` guard on write actions** (archived →
  403, fix #4), `find_field` (relevance + supported-format + standard-setting
  gate), strong params per operation, service delegation, flash, **redirect back
  to the settings tab** for mutations (fix #5); routes (project-scoped, HTML, no
  `accept_api_auth`; global audit route owned by Agent 3).
- **Files:** `app/controllers/project_custom_field_configuration_controller.rb`,
  `config/routes.rb` (additive), helper file.
- **Inputs:** Integration §3/§5/§6, Security, Permissions specs.
- **Dependencies:** Agents 2, 3, 4.
- **Acceptance:** T-AUTH-4..9, T-REL-*, T-SEC-1..10, T-INT-1, T-SET-2.
- **Risks:** param leakage (no `custom_field` blob); 403 vs 404 discipline;
  ensuring `read: true` + controller guard (not the flag) gates archived writes.

## Agent 6 — Project settings UI views

- **Scope:** **inline overview** rendered in the settings-tab partial via the
  `dcf_relevant_custom_fields(@project)` helper (fix #5, no controller ivars);
  `show` (values, full page) and `audit` (full page) views + partials; Redmine
  markup; scope badges (project CF always Global, fix #7); impact panel showing
  **affected child fields** (fix #1/#2); no-JS reorder; confirmations; Format
  column label derived from the field-format registry (fix #14); N+1-safe
  overview (fix #13); I18n wiring.
- **Files:** `app/views/project_custom_field_configuration/*` (incl.
  `_settings_tab.html.erb`), helper additions, locale keys, minimal CSS in
  `assets/`.
- **Inputs:** UI Spec, Integration §4/§6.
- **Dependencies:** Agent 5.
- **Acceptance:** T-UI-1/2/3/5/6/7, T-USE-6, T-CMP-3.
- **Risks:** icon helper 5.1/6.1 divergence (guard `sprite_icon`); keeping the
  inline overview cheap; core label-key drift across versions.

## Agent 7 — Dependency mapping UI & service integration

- **Scope:** services F/G (dependency + default mappings) using existing
  `MappingBuilder`/`Sanitizer`; `edit_dependencies` view reusing the matrix
  partial style + existing JS; validation + audit.
- **Files:** `app/services/.../dependency_mapping_service.rb`,
  `app/views/project_custom_field_configuration/edit_dependencies.html.erb`,
  controller actions `edit_dependencies`/`update_dependencies` (coordinate w/ A5).
- **Inputs:** Operations §F/§G, UI §5.
- **Dependencies:** Agents 1, 4, 5.
- **Acceptance:** T-DEP-1..6, T-UI-4.
- **Risks:** parent-key typing (list vs enum); reuse existing helpers exactly.

## Agent 8 — Security & bypass tests

- **Scope:** dedicated security suite implementing all Security Model §20
  answers; mass-assignment, cross-project, API isolation, audit-on-failure,
  403/404 discipline.
- **Files:** `spec/requests/*`, `spec/services/*` security specs.
- **Inputs:** Security Model, Test Plan §6/§7.
- **Dependencies:** Agents 2–7.
- **Acceptance:** all T-SEC-*, T-AUD-2/3/8.
- **Risks:** false sense of security — assert behaviour, not just status codes.

## Agent 9 — Documentation & final integration

- **Scope:** README section for the feature (project-level configuration,
  permission, audit); CHANGELOG; verify `rake routes`, locale completeness
  (de/fr/nl), 5.1 suite green; document any 6.1 divergences.
- **Files:** `README.md`, `CHANGELOG.md`, locale files, docs updates.
- **Inputs:** all specs.
- **Dependencies:** Agents 1–8.
- **Acceptance:** quality gates G1–G9; T-CMP-1 green.
- **Risks:** locale drift; doc/behaviour mismatch.

---

## Integration order

1. **Agent 1** (scope lock) →
2. **Agent 3** (audit) and **Agent 2** (permission/tab) in parallel →
3. **Agent 4** (operation services) →
4. **Agent 5** (controller/routes) →
5. **Agent 7** (dependency UI/service) and **Agent 6** (overview/values UI) in
   parallel →
6. **Agent 8** (security tests) →
7. **Agent 9** (docs/final).

Critical path: 1 → 3 → 4 → 5 → 7 → 8 → 9. Agents 2 and 6 run alongside without
blocking the critical path beyond their stated dependencies.
