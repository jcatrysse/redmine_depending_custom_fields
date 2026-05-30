# Project-Level Custom Field Configuration — Specification Set

Feature: allow **administrators** and **non-admin project users holding a new
project permission** to manage relevant custom field *configuration* (possible
values, enumeration values, and dependency mappings) from a **Project →
Settings → Custom field configuration** tab inside the existing plugin
`redmine_depending_custom_fields`.

> This is configuration of custom fields, **not** editing custom field *values*
> on issues. Tracker and workflow management are **explicitly out of scope**.

## Status

Spec-first. **No production code, migrations, models, controllers, views or
tests are created by this task.** These documents are implementation-ready and
designed to be split across multiple coding agents.

## Reading order

| # | File | Phase | Purpose |
|---|------|-------|---------|
| 1 | [`project_custom_field_configuration_product_spec.md`](project_custom_field_configuration_product_spec.md) | 1 | Problem, personas, user stories, acceptance criteria |
| 2 | [`project_custom_field_configuration_feasibility.md`](project_custom_field_configuration_feasibility.md) | 2 | Redmine internals analysis, operation classification, v1 scope |
| 3 | [`project_custom_field_configuration_functional_spec.md`](project_custom_field_configuration_functional_spec.md) | 3 | Detailed flows, edge cases, error handling |
| 4 | [`project_custom_field_configuration_security_model.md`](project_custom_field_configuration_security_model.md) | 4 | Threat model, deny-by-default, bypass answers |
| 5 | [`project_custom_field_configuration_permissions_spec.md`](project_custom_field_configuration_permissions_spec.md) | 5 | Permission registration & authorization |
| 6 | [`project_custom_field_configuration_data_model.md`](project_custom_field_configuration_data_model.md) | 6 | Data model & storage analysis |
| 7 | [`project_custom_field_configuration_audit_spec.md`](project_custom_field_configuration_audit_spec.md) | 6 | Audit table & audit visibility |
| 8 | [`project_custom_field_configuration_ui_spec.md`](project_custom_field_configuration_ui_spec.md) | 7 | Redmine-consistent UI/UX |
| 9 | [`project_custom_field_configuration_operations_spec.md`](project_custom_field_configuration_operations_spec.md) | 8 | Per-operation algorithms |
| 10 | [`project_custom_field_configuration_redmine_integration_spec.md`](project_custom_field_configuration_redmine_integration_spec.md) | 9 | Plugin wiring, patching, compatibility |
| 11 | [`project_custom_field_configuration_test_plan.md`](project_custom_field_configuration_test_plan.md) | 10 | Test plan |
| 12 | [`project_custom_field_configuration_agent_plan.md`](project_custom_field_configuration_agent_plan.md) | 11 | Multi-agent work packages & order |
| 13 | [`project_custom_field_configuration_review_log.md`](project_custom_field_configuration_review_log.md) | 12 | Four review passes & resulting changes |

## One-paragraph summary of design decisions

A new **project-scoped controller** (`ProjectCustomFieldConfigurationController`)
under `/projects/:project_id/custom_field_configuration` exposes a small,
operation-specific set of actions. Access is gated by a new **module-independent
project permission** `manage_project_custom_field_configuration`; administrators
pass automatically. The feature manages **values** of four formats — standard
`list`, standard `enumeration`, and the plugin's `depending_list` /
`depending_enumeration` — and **dependency mappings** for the two depending
formats only; standard-format delegation is on by default and can be disabled by
an admin via the `manage_standard_custom_fields` plugin setting. A new
**Project → Settings tab** is added by patching
`ProjectsHelper#project_settings_tabs` with **`alias_method`** (never `prepend`,
never `Rails.configuration.to_prepare`). The existing admin-only
`DependingCustomFieldsApiController` is left **untouched and admin-only**. Every
successful and rejected change is written to a new
`dcf_config_audit_events` table inside the same DB transaction as the change, so
an audit failure rolls the change back. The feature targets Redmine **5.1**
(mandatory) and **6.1** (supported where it does not break 5.1).
