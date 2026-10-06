# Phase 8 — Custom Field Operation Specification

Each operation is implemented by a **service object** (PORO under
`app/services/redmine_depending_custom_fields/`). All operations share a common
preamble and a common audit/transaction wrapper. Services never call
`safe_attributes=`; they mutate only the specific surface and persist via the
model's `save!` so the plugin's sanitizer/cache callbacks run.

### Supported formats & capability classes

```
SUPPORTED_VALUE_FORMATS      = %w[list enumeration depending_list depending_enumeration]
SUPPORTED_DEPENDENCY_FORMATS = %w[depending_list depending_enumeration]   # require parent_custom_field_id
STANDARD_FORMATS             = %w[list enumeration]                       # gated by Setting.plugin_*['manage_standard_custom_fields']
LIST_FAMILY                  = %w[list depending_list]                    # possible_values, string-keyed CustomValue
ENUM_FAMILY                  = %w[enumeration depending_enumeration]      # CustomFieldEnumeration, id-keyed CustomValue
```

A format in `STANDARD_FORMATS` is supported **only** when the admin setting
`manage_standard_custom_fields` is enabled. **Setting read rule (exact):** plugin
settings are strings, so read it as
```
raw = Setting.plugin_redmine_depending_custom_fields['manage_standard_custom_fields']
standard_enabled = raw.nil? ? true : ActiveModel::Type::Boolean.new.cast(raw)
```
(missing key ⇒ enabled; `'0'`/unchecked ⇒ disabled). All agents MUST use this
identical rule. The dependency operations (F, G) are valid **only** for
`SUPPORTED_DEPENDENCY_FORMATS`.

### Parent-side relationships (critical)

In this plugin a child field's `value_dependencies` / `default_value_dependencies`
are **keyed by the *parent* field's values**. Therefore a value of **any** field
in scope — including a standard `list`/`enumeration` — may be referenced as a
**parent key** in one or more depending child fields. Renaming or removing a
value that is used as a parent key **must cascade** into every such child, or the
child's mapping is silently orphaned.

```
children_of(field) =
  CustomField
    .where(field_format: SUPPORTED_DEPENDENCY_FORMATS)
    .select { |c| c.parent_custom_field_id.to_i == field.id }
```
Parent-key type follows the existing `MappingBuilder`/`Sanitizer` keying: for a
`list`/`depending_list` parent the key is the option **string**; for an
`enumeration`/`depending_enumeration` parent the key is the enumeration **id**
(string). Rename of an enumeration parent value is **id-stable** ⇒ no parent-key
cascade needed; remove of an enumeration parent value **does** require pruning
the id key from children.

## 0. Common preamble (every operation)

```
1. assert User.current.allowed_to?(:manage_project_custom_field_configuration, project)   # else forbidden (audit authorization_failed)
2. assert field relevant to project (Feasibility 2.3)                                       # else 404
3. assert field.field_format in SUPPORTED_VALUE_FORMATS                                      # else 422 error_format_unsupported
3a. if field.field_format in STANDARD_FORMATS: assert standard_enabled (setting rule above)  # else 422 error_format_unsupported
3b. for dependency ops (F,G): assert field.field_format in SUPPORTED_DEPENDENCY_FORMATS       # else 422 error_format_unsupported
4. assert project active for write ops (@project.active?)                                    # else 422 error_project_archived
5. optimistic check: submitted state-hash == current state-hash                             # else 422 error_stale_edit
```

Behaviour is driven by **family**, not by individual format:
- `LIST_FAMILY` → operate on `possible_values`; rename rewrites string-keyed
  `CustomValue` rows; only `depending_list` also rewrites/prunes its **own**
  dependency entries.
- `ENUM_FAMILY` → operate on `CustomFieldEnumeration`; id-stable; only
  `depending_enumeration` also prunes id references in its **own** dependencies.
- **Both families**, for rename/remove, additionally run the **parent-side
  cascade** into depending children that name this field as parent (see above).

This means the Add/Rename/Remove/Reorder/Enumeration service bodies are
**format-agnostic within a family** — standard and depending fields share the
same code path, with (a) the *own*-dependency-rewrite step guarded by
`field.field_format.in?(SUPPORTED_DEPENDENCY_FORMATS)` and (b) the parent-side
cascade applied for every format.

Common wrapper:
```
ActiveRecord::Base.transaction do
  before = snapshot(field)
  <operation body>            # uses field.save! (raises on invalid)
  cascade_into_children!      # rename/remove only; saves each affected child via save!
  after = snapshot(field)
  AuditEvent.record!(action:, status: 'success', before:, after:, counts:, request_meta:)
end
# on validation/auth/save failure: record failure event in its own transaction, re-raise/return errors
```

`snapshot(field)` captures a **compact delta**, not whole lists, to keep audit
rows small on large global fields (see Audit Spec): for add/rename/remove store
the specific value(s) changed; for reorder store a compact moved-item
representation (old/new index) or a truncated old/new order with a
`truncated: true` flag. `affected_child_field_ids` is recorded when the
parent-side cascade touched children.

State-hash = digest of `possible_values` (or enumeration ids+names+positions) +
own dependency store, used for optimistic concurrency.

## A. Add value

Params: `value` (string), `position` (int, optional).
1. Preamble.
2. `v = normalize(value)` (strip). Reject blank → `error_value_blank`.
3. **List:** reject if `v` already in `possible_values`
   (Redmine list comparison semantics) → `error_value_duplicate`.
   Append, or insert at `position` (clamped to range).
   **Enumeration:** reject if an active enumeration with `name == v` exists.
   Build `CustomFieldEnumeration(name: v, position: next, active: true)`.
4. `field.save!`.
5. Audit `add_value` (`affected_values_count = 0`). (Add never needs a
   parent-side cascade — a new value has no existing references.)

## B. Rename value

Params: `old_value`/`enumeration_id`, `new_value`, `confirm` (bool).
1. Preamble.
2. `nv = normalize(new_value)`. Reject blank → `error_value_blank`.
3. Reject if `nv` duplicates an existing value (other than the target) →
   `error_value_duplicate`.
4. Compute impact: `usage_here`, `usage_other`, `own_dep_refs`,
   `parent_key_refs` (occurrences of the value as a **parent key** across
   `children_of(field)`), `affected_child_field_ids`.
5. If (`usage_other > 0` or field Shared/Global or `own_dep_refs > 0` or
   `parent_key_refs > 0`) and not `confirm` → return needs-confirmation
   (re-render with impact panel listing affected child fields).
6. **LIST_FAMILY (`list`, `depending_list`) — string-keyed:**
   - replace in `possible_values` (preserve order/position),
   - if `field.default_value == old`: set `field.default_value = nv`,
   - `CustomValue.where(custom_field_id: f.id, value: old).update_all(value: nv)`
     **scoped within the transaction** (rewrites all projects' rows;
     `affected_values_count = rows updated`; see note on journals below),
   - **only if `depending_list`**: rewrite this field's own `value_dependencies`
     (child-array entries `old`→`nv`) and `default_value_dependencies`. Standard
     `list` has no own dependency store → skip.
   - `field.save!`.
   **ENUM_FAMILY (`enumeration`, `depending_enumeration`) — id-keyed:**
   - update `CustomFieldEnumeration#name`; **no** CustomValue / own-dep /
     parent-key rewrite (ids unchanged); `field.save!`.
7. **Parent-side cascade (LIST_FAMILY only — string keys change):** for each
   child in `children_of(field)`, rewrite the parent key `old`→`nv` in its
   `value_dependencies` **and** `default_value_dependencies`, then `child.save!`
   (runs the child's sanitizer + cache refresh). ENUM_FAMILY rename skips this
   (id-stable).
8. Audit `rename_value` with before/after delta + `affected_values_count`,
   `affected_projects_count`, `affected_child_field_ids`.

> Decision D-RENAME-LIST: list renames **do** update existing `CustomValue`
> rows (chosen over leaving them stale). **Note (D-NO-JOURNAL):** the bulk
> `update_all` deliberately does **not** write issue journals — issue history
> keeps the historical string, which is the correct immutable-history behaviour.
> After the bulk rewrite, no `acts_as_customizable` per-record callback fires;
> the plugin's own dependency cache is refreshed via the `save!` of the field and
> affected children. The implementing agent must confirm no other per-value cache
> needs busting.

## C. Remove value

Params: `value`/`enumeration_id`, `confirm` (bool).
1. Preamble.
2. Compute `usage_here`, `usage_other`, `own_dep_refs`, `parent_key_refs`,
   `affected_child_field_ids` (as in B.4).
3. If setting `block_removal_when_used` and `(usage_here+usage_other) > 0` →
   `error_value_in_use` (blocked).
4. Else if `(usage > 0 or own_dep_refs > 0 or parent_key_refs > 0 or
   Shared/Global)` and not `confirm` → needs-confirmation (impact panel lists
   affected child fields).
5. **LIST_FAMILY:** remove from `possible_values`; if `field.default_value ==
   value` clear it; **only if `depending_list`** prune the value from this
   field's own `value_dependencies` (child arrays) and
   `default_value_dependencies` (standard `list` → skip); **do not** delete
   `CustomValue` rows (they become orphaned; `affected_values_count = usage`);
   `field.save!`.
   **ENUM_FAMILY:** **deactivate (`active = false`) when `usage > 0`** so existing
   `CustomValue` ids still resolve to a (now inactive) name; **hard-`destroy`
   only when `usage == 0`** (decision D-ENUM-DEACTIVATE). **only if
   `depending_enumeration`** prune id refs in its own deps; `field.save!`.
6. **Parent-side cascade (all families):** for each child in
   `children_of(field)`, prune the parent key `value`/`enumeration_id` from its
   `value_dependencies` **and** `default_value_dependencies`, then `child.save!`.
   (Enumeration deactivate still requires this prune so disabled parent options
   stop driving child filters.)
7. Audit `remove_value` with counts (orphaned-value count) +
   `affected_child_field_ids`.

## D. Reorder values

Params: `ordered_values` (array of existing value identifiers).
1. Preamble.
2. Validate `Set(submitted) == Set(current)` and no duplicates and same length →
   else `error_reorder_mismatch`.
3. **List:** set `possible_values` to the submitted order.
   **Enumeration:** assign `position` by index.
4. `field.save!`.
5. Audit `reorder_values` (compact moved-item delta). No parent-side cascade or
   `CustomValue` rewrite — reorder changes display order only, not value
   identity, so no key/string references change.

## E. Update enumerations (batch — ENUM_FAMILY only)

Params: `enumerations` => `{ "<id>" => { name:, position:, active: } }`.

This is the **only** write path for enumeration names, positions and active
flags from the project screen, and it mirrors core's
`CustomFieldEnumerations#update_each`: one form for the whole table, one Save,
everything applied together in one transaction and one audit event.

> **Why batch and not per row.** Core has two reorder/submit models and this
> screen uses one of each, per family. `custom_field_enumerations#index` — the
> screen we are copying — stages everything in a single form: its sortable's
> `update` handler only rewrites the hidden `position` inputs and submits
> nothing. Core's *other* model (`reorder_handle` + `positionedItems`, used by
> trackers / issue statuses / roles / enumerations) persists each drop
> immediately by AJAX; that is the one the list family follows (§D). Amendment
> A2 originally applied the second model to both families — see the review log.

1. Preamble.
2. Reject `LIST_FAMILY` → `error_format_unsupported`: `possible_values` are plain
   strings with no id, position or active flag; lists keep §A–§D.
3. The submitted id set must equal the field's enumeration id set exactly →
   else `error_reorder_mismatch`. A partial or tampered payload is refused
   whole rather than applied in part; a concurrent add/delete is already caught
   by the state hash, so this never fires on a legitimate save.
4. `normalize` each name; any blank → `error_value_blank`.
5. Duplicate check on the **resulting** state: no two rows that end up `active`
   may share a name → `error_value_duplicate`. This catches both a rename onto
   a sibling's name and a reactivation onto a name meanwhile taken. Core has no
   such validation, but §A and §B enforce it, so this path must not be a way
   around them. A name duplicating an **inactive** value stays allowed.
   Only a collision the save **creates** is refused, i.e. one involving a row
   that is renamed or reactivated. Core's own enumeration editor allows two
   active values with the same name, so such a duplicate can already be in the
   data; it must not block reorders or unrelated renames, nor the rename or
   deactivation that resolves it. A name is "renamed" only when it differs from
   the **normalized** stored name, so stray whitespace in a stored name is
   neither a rename nor rewritten.
6. Order rows by submitted `position` (ties → current position, then input
   order) and assign contiguous positions `1..N`.
7. Apply name / position / active per changed row via `enum.update!`. Model
   validation failures (e.g. name over 60 chars) roll the **whole** save back.
8. If any row went active → inactive and `field.default_value` is that id, clear
   it (`field.save!`). The format only offers `enumerations.active`, so a default
   pointing at a deactivated value is unreachable *and* invisible on the values
   screen — the picker there lists active values only. Recorded in the audit
   summary as `default value cleared`.
9. Audit `update_enumerations` once, with a compact delta (renamed / activated /
   deactivated names, capped at 20 with a `(+N more)` tail, plus a `reordered`
   flag) and `affected_values_count` = summed `UsageCalculator.usage_total` of
   the deactivated ids — the stored values now pointing at an inactive option.

**No parent-side cascade and no own-dependency prune.** Enumeration renames are
id-stable (§B), and deactivation is a reversible visibility flag: existing
`CustomValue` ids still resolve to the (inactive) name, and keeping the
dependency entries is what lets a record already on a deactivated **parent**
value keep its allowed child options. Pruning would leave such a record with no
selectable child. `default_value_dependencies` are likewise left intact: the
project-level matrix lists **all** enumerations (`value_options`), so an entry
pointing at a deactivated value stays visible and editable there — unlike the
plain default of step 8, which would silently disappear from its picker.

For the same reason — reversible, destroys nothing — this operation needs **no
confirmation panel** on shared/global fields; the scope badge and warning banner
on the screen already state the blast radius. Delete (§C) keeps its panel: it is
the operation that prunes and destroys.

> Asymmetry to know about: Remove (§C) deactivates an in-use enumeration *and*
> prunes it as a parent key from depending children. Reactivating such a value
> here restores the value but **not** the pruned mappings — the two are not
> inverses, by design.
>
> Enumeration-backed fields are **not** treated like string arrays: they use ids
> and positions via `CustomFieldEnumeration`.

The single-value endpoints §B (`rename_value`) and §D (`reorder_values`) still
accept enumeration params — the list family shares them — but the project screen
no longer routes enumeration edits through them.

## F. Dependency mapping

Params: `value_dependencies` (hash).
1. Preamble (on the **child** field) + assert `field.field_format` ∈
   `SUPPORTED_DEPENDENCY_FORMATS` (rejects standard `list`/`enumeration` →
   `error_format_unsupported`) + assert it has `parent_custom_field_id`
   and the parent field is also relevant to the project. (The parent field may
   itself be a standard `list`/`enumeration` — that is allowed; only the *child*
   must be a depending format.)
2. Build/sanitize via existing `RedmineDependingCustomFields::MappingBuilder`
   and `Sanitizer` (do not reimplement key typing).
3. Validate: each parent key exists among the parent's value keys; each child
   value exists among this field's values; drop/reject orphans
   (`error_invalid_dependency`).
4. Assign `field.value_dependencies = sanitized`; `field.save!`
   (runs the plugin's `validate_dependencies` + `after_save` cache refresh).
5. Audit `update_dependencies`.

## G. Default value dependency mapping

Params: `default_value_dependencies` (hash).
1. Preamble + parent assertions (as F).
2. For each parent key, the chosen default child must be among the **allowed**
   children for that parent (per current `value_dependencies`) and must exist →
   else `error_invalid_dependency`.
3. Assign `field.default_value_dependencies = sanitized`; `field.save!`.
4. Audit `update_default_dependencies`.

(F and G may be saved together from the same matrix screen in one transaction.)

## Normalization & comparison rules

- `normalize` = `value.to_s.strip`. Do not alter case (Redmine list values are
  case-sensitive). Reject empty after strip.
- Duplicate detection mirrors Redmine list semantics (exact string match for
  lists; active-name match for enumerations).
- All counts computed via the queries in Feasibility §5, capped per the UI lazy
  rules.

## Error → HTTP mapping

| Condition | HTTP | Key |
|---|---|---|
| Not permitted | 403 | (forbidden) |
| Field not relevant / not found | 404 | error_field_not_found |
| Unsupported format | 422 | error_format_unsupported |
| Archived project (write) | 422/403 | error_project_archived |
| Blank value | 422 | error_value_blank |
| Duplicate value | 422 | error_value_duplicate |
| Reorder mismatch | 422 | error_reorder_mismatch |
| Batch save: name taken by another active value | 422 | error_value_duplicate |
| Batch save: submitted ids do not cover the value set | 422 | error_reorder_mismatch |
| Invalid dependency | 422 | error_invalid_dependency |
| In-use (when blocking enabled) | 422 | error_value_in_use |
| Stale edit | 409/422 | error_stale_edit |
| Needs confirmation | 422 (re-render) | text_confirm_cross_project_change |
