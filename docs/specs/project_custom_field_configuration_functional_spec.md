# Phase 3 — Functional Specification (v1)

Covers the recommended v1 scope from the Feasibility analysis. Operation-level
algorithms are in the Operations Spec (Phase 8); this document defines behaviour,
flows, edge cases and validation messaging.

## 1. Permission lifecycle

- Admin grants the role permission `manage_project_custom_field_configuration`
  (Administration → Roles and permissions). No per-project config needed.
- A user gains access in a project once they are a **member** of that project via
  a role carrying the permission. The permission is **module-independent**, so it
  is available regardless of enabled modules.
- Revocation (role change / membership removal / project archived) takes effect
  on the next request; in-flight sessions are not trusted (server re-checks).

## 2. Project settings tab behaviour

- Tab label: **Custom field configuration** (I18n `label_project_custom_field_configuration`).
- Shown in `Project → Settings` iff
  `User.current.allowed_to?(:manage_project_custom_field_configuration, @project)`
  is true (admins always true).
- Selecting the tab loads the **overview** (action `index`).

## 3. Administrator override

- Admins always see the tab and pass every `authorize` check (Redmine grants
  module-independent permissions to admins unconditionally).
- Admins additionally may access the **global audit view** (read-only). No extra
  configuration screen is added.

## 4. Field relevance selection (overview)

The overview lists custom fields where (see Feasibility §2.3):
- type ∈ {`IssueCustomField`, `ProjectCustomField`}, and
- relevant to the project (`all_issue_custom_fields` / project-scoped), and
- `field_format` ∈ supported set (v1: `list`, `enumeration`, `depending_list`,
  `depending_enumeration`; standard `list`/`enumeration` only when the admin
  setting `manage_standard_custom_fields` is enabled — default on).

Each row shows: name, format label, scope badge (Global / Project / Shared),
project-usage count, value count, shared-warning indicator, and a **Manage** link.

**Capability split by format:**
- `list` and `enumeration` (standard) → **value operations only** (add / rename /
  remove / reorder; enumeration values). No dependency matrix (they have no
  parent). Dependency entries/pruning steps below are **no-ops** for them.
- `depending_list` and `depending_enumeration` → value operations **plus** the
  dependency-mapping and default-dependency screens.

When the admin setting `manage_standard_custom_fields` is **off**, standard
`list`/`enumeration` fields are excluded from the overview and rejected on direct
access (`error_format_unsupported`).

## 5. Shared / global field identification

A field is **shared** (relative to project P) when it is usable by projects other
than P:
- `is_for_all == true` → **Global** (all projects).
- else `projects.count > 1` or `projects` includes any project ≠ P → **Shared**.
- else (`projects == [P]` and not for-all) → **Project-only**.

Shared/Global fields render a warning badge on the overview and a prominent
warning banner on the edit screens.

## 6. Impact warnings

Before any destructive change (rename/remove value, or removing a value used in
mappings) the UI presents an **impact panel**:
- value usage count in current project,
- value usage count in other projects (count; names only if visible),
- number of dependency entries referencing the value,
- whether the field is Global/Shared,
and requires a checkbox confirmation ("I understand this affects other
projects / existing data") when cross-project or in-use impact is non-zero.

## 7. Value usage counts

- Computed lazily on the value-edit screen (not eagerly on overview).
- Current-project and other-projects counts computed via `custom_values`
  joined to the customized object's project (Feasibility §5).
- Cached per request; capped; a "usage unavailable (too large)" fallback is shown
  if a configurable threshold is exceeded, rather than timing out.

## 8. Dependency usage display

The reference count for a value is computed on **both sides** (a value can be
referenced as a child *and* as a parent key in other fields):

1. **Own-side (child) refs** — occurrences in *this* field's own
   `value_dependencies` / `default_value_dependencies` (only for the two
   depending formats; standard fields have none).
2. **Parent-side refs** — occurrences of the value as a **parent key** in the
   `value_dependencies` / `default_value_dependencies` of every depending child
   that names this field as its parent (`children_of(field)`; applies to **all**
   supported formats, including standard `list`/`enumeration`, because standard
   lists are commonly used as parents).

The impact panel shows the total and **names the affected child fields** so the
manager understands the cross-field blast radius before renaming/removing.
On the matrix screen, invalid/orphan references are flagged.

## 9. Add value flow

1. User enters a value (and optional position).
2. Normalize (strip; collapse only if existing convention does).
3. Reject blank → error `error_value_blank`.
4. Reject duplicate (case-sensitivity follows Redmine list semantics) →
   `error_value_duplicate`.
5. Append (or insert at position) into `possible_values` (list) or create
   `CustomFieldEnumeration` (enumeration).
6. Save via model; audit; flash `notice_value_added`.

## 10. Rename value flow

1. Select existing value; enter new value.
2. Reject blank/duplicate.
3. Compute impact (current + other project usage, own-side dependency refs,
   **parent-side refs across child fields**, affected child fields).
4. If cross-project, in-use, or parent/child impact > 0 → require confirmation
   checkbox.
5. **List family (`list`, `depending_list`):** in one transaction — update
   `possible_values`; if the value equals the field's `default_value`, rewrite it;
   rewrite every `CustomValue.value == old` to `new`; for `depending_list` also
   rewrite this field's own `value_dependencies`/`default_value_dependencies`
   child entries; **then cascade the parent-key rename into every depending child
   that names this field as parent** (rewrite their parent keys old→new); save
   the field and each affected child.
   **Enumeration family:** update `CustomFieldEnumeration.name` only (id-stable;
   no CustomValue / own-dep / parent-key rewrite needed).
6. Audit (before/after delta, affected child field ids); flash
   `notice_value_renamed`.

See Operations Spec §B for the exact algorithm and the journal/cache note.

## 11. Remove value flow

1. Select value.
2. Compute usage + own-side refs + parent-side refs + affected child fields.
3. If `block_removal_when_used` setting is true and usage > 0 → block with
   `error_value_in_use`.
4. Else require confirmation when usage > 0, field shared, or parent/child
   references exist.
5. **List / standard list:** remove from `possible_values`; if it equals
   `default_value`, clear it; for `depending_list` also prune this field's own
   dependency entries; standard `list` has none. Do **not** delete `CustomValue`
   rows (they become "orphaned", flagged in UI/audit). **Enumeration / standard
   enumeration:** **deactivate (`active = false`) when in use** (so historical
   ids still resolve to a name), hard-destroy only when unused; for
   `depending_enumeration` also prune its own id references.
6. **Parent-side cascade (all formats):** prune the removed value/id as a parent
   key from every depending child that names this field as parent; save each.
7. Save; audit (affected counts + child field ids); flash `notice_value_removed`.

## 12. Reorder values flow

1. UI submits the full ordered list of value identifiers.
2. Validate the submitted set is exactly a permutation of the current set
   (no missing, no extra, no duplicates) → else `error_reorder_mismatch`.
3. **List:** reorder `possible_values`. **Enumeration:** update `position`.
4. Save; audit; flash `notice_values_reordered`.

## 13. Enumeration value management flow

- Add: create `CustomFieldEnumeration(name, position, active: true)`.
- Rename: update `name` (safe).
- Remove: destroy or deactivate (mirror plugin's existing API semantics, which
  supports `_destroy: true`); prune id references in dependencies.
- Reorder: update `position`.
- Always operate through `CustomFieldEnumeration` records, never as string array.

## 14. Dependency mapping flow

1. Field must have a `parent_custom_field_id`; both fields relevant to project.
2. Matrix: rows = parent values, columns = child values; checkbox = allowed.
3. On save, build `value_dependencies` via the existing `MappingBuilder`/
   `Sanitizer` (do not reimplement).
4. Validate: every parent key exists in parent's values; every child exists in
   this field's values; reject unknown/orphan.
5. Save model; audit; flash `notice_dependencies_saved`.

## 15. Default value dependency flow

- Per parent value, optionally choose a default child (must be among allowed
  children for that parent). Stored in `default_value_dependencies`. For
  **single-value** child fields the selector is a single-select and stores one
  value per parent; for **`multiple`** child fields the selector is a
  multi-select and stores an array per parent (mirroring the admin form).
- Validate referenced values exist and are allowed; reject otherwise.
- Save with the mapping update (same screen/transaction); audit.

### 15a. Plain default value (non-child fields)

- A managed field **without** a parent (standard `list`/`enumeration` and
  parent depending fields) exposes its plain `default_value` on the values
  screen. Redmine stores `default_value` as a single column, so this default is
  single-valued even for `multiple` fields, matching core's admin form.
- The submitted value must be blank (clears the default) or one of the field's
  current values (list value string / enumeration id); reject otherwise with
  `error_invalid_default_value`.
- Child depending fields derive their default per parent value (§15) and reject
  the plain-default operation with `error_format_unsupported`.
- Save through the model; audit (`set_default_value`).

## 16. Audit logging flow

- Every successful operation writes one `dcf_config_audit_events` row **inside
  the same DB transaction** as the change. If the audit insert fails, the
  transaction rolls back and the user sees an error.
- Authorization failures and validation failures are audited per Audit Spec
  (auth failures: on by default; validation failures: on by default, status
  `validation_failed`).

## 17. Permission checks (defense in depth)

1. `before_action :find_project, :authorize` (controller).
2. Service re-checks `User.current.allowed_to?(perm, project)`.
3. Service asserts the target field is **relevant** to the project and in a
   **supported format** before any mutation.
4. Only operation-specific params are read; no blanket `safe_attributes=`.

## 18. Error handling

- Validation errors render the same screen with `error_messages_for`-style
  output and field-level messages; no partial writes (transactions).
- 403 for authorization failures; 404 when a field is not relevant to the
  project (do not reveal existence/details of unrelated fields).
- 409/422 on stale concurrent edits (optimistic value-set hash check).

## 19. Empty states
See Product Spec §11.

## 20. Behaviour: access revoked
Next request returns 403; no cached authorization.

## 21. Behaviour: project archived
- Archived projects are read-only in Redmine. The tab is **read-only**:
  overview and audit viewable (if the user retains access), all write actions
  return 403 with `error_project_archived`. (Admins: also read-only via this tab;
  they can still use Administration as before.)

## 22. Behaviour: custom field deleted (mid-flow)
- If a field is deleted between overview and edit, edit actions 404 gracefully
  with `error_field_not_found`.

## 23. Behaviour: custom field format changed
- If a field's format changed to an unsupported one (e.g. by an admin), it
  disappears from the overview; direct edit → 422 `error_format_unsupported`.

## 24. Behaviour: dependencies invalid
- On load, orphan/invalid dependency entries are flagged (not auto-deleted);
  saving the matrix re-sanitizes them. A "clean up invalid mappings" action may
  be offered (audited).

## 25. Behaviour: existing CustomValue records reference a value being
       renamed/removed
- **Rename (list):** `CustomValue` rows rewritten to the new string in the same
  transaction → no data loss.
- **Remove (list):** `CustomValue` rows are **not** deleted; they become orphaned
  and are reported (count in audit + UI warning). Admin/manager may later
  re-map. (Matches Redmine core behaviour where removing a list option leaves
  historical values.)
- **Enumeration rename/remove:** id-based; rename safe; remove deactivates the
  enumeration so historical references still resolve to a (possibly inactive)
  name.

## 26. Edge cases matrix

| Edge case | Behaviour |
|---|---|
| Permission in project A, not B | A: allowed; B: 403 |
| Admin any project | Allowed everywhere |
| Project has no relevant fields | Empty state |
| Field used by many projects | Shared badge + counts + confirm gate |
| Field is global (`is_for_all`) | Global badge + strongest warning |
| Field used by trackers not in this project | Still listed if in `all_issue_custom_fields`; note shown |
| Value used by issues in current project | Count shown; confirm required to rename/remove |
| Value used by issues in other projects | Count (names if visible) shown; confirm required |
| Value referenced by dependency mappings | Count shown; rename rewrites, remove prunes |
| Value referenced by default deps | Same as above |
| Direct URL access (no perm) | 403 |
| Hidden/disallowed params submitted | Ignored by strong params; attempt auditable |
| Attempt to change field type | Not in params; impossible; if forged → ignored + audit |
| Attempt to change visibility | Same |
| Attempt to change tracker/project applicability | Same |
| Attempt create/delete field | No such route/action; impossible |
| Add blank value | 422 |
| Add duplicate value | 422 |
| Rename to duplicate | 422 |
| Reorder missing value | 422 |
| Reorder extra value | 422 |
| Audit write fails | Transaction rollback; error flash |
