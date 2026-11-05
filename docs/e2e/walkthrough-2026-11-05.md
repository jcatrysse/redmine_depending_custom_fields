# Chromium walkthrough on Redmine 5.1 and 7.0 (2026-11-05)

## Scope and environment

A scripted walkthrough of the plugin in a real browser: Chromium driven by Playwright
against development servers of Redmine 5.1 and Redmine 7.0 (PostgreSQL, one database
per checkout). It covers the issue form (new and edit), the issue list and show page,
bulk edit, the context menu wizard, time entries, the hidden field rules for users who
may not see a field, the administration (dependency editor, CSV export and import),
the 25,000 value field, and the project configuration pages (values page,
dependency page, settings tab, audit page, permissions). The goal was to find product
defects, UX problems and privacy leaks that unit and request specs do not show.

Tested code: commit 51efb99 (the plugin tree of that commit, copied with `git archive`
into all four checkouts). The first walkthrough ran on 84d3d68; the results below are
the re-run after the fixes, from the packaged tooling in `.codex/e2e/`.

Seed (`.codex/e2e/seed.rb`, identical ids in all four databases):

- Projects Walk, Walk Sub and Other (private); trackers Bug and Feature.
- Users admin, manager, developer and reporter, with different roles (only the manager
  may configure fields per project; developer and reporter must never see the
  Secret Code and Clearance fields or their values).
- 22 custom fields: single and two level dependencies, a multiple select, a required
  child, a child that hides itself without options, depending enumerations, a
  role-restricted field and a visible child of a hidden parent, project only and shared
  scope fields, a field with 25,000 values over 500 parents, time entry fields and
  project fields.
- Issues with all value combinations, two legacy issues with a stored value that no
  longer matches its parent, time entries, audit rows.

Checkouts: b51 and b70 for the issue side scenarios, c51 and c70 for the scenarios that
change configuration data (re-seeded before each scenario). The REST API is enabled.
Screenshots are kept outside the repository.

## Scenarios and results after the fixes

| Scenario | Area | 5.1 | 7.0 |
|---|---|---|---|
| seed-check | seed in place, login, pages load | pass (5) | pass (5) |
| issue-new | new issue: filtering, chains, defaults, hints, validation | pass (17) | pass (17) |
| issue-edit | edit existing issue, legacy values, journal | pass (10) | pass (10) |
| issue-list | columns, filters, sort, group, show page, saved query | pass (8) | pass (8) |
| bulk-edit | bulk edit with untouched multi-select and parent change | pass (11) | pass (11) |
| context-wizard | context menu wizard (open, save, refusal, load error) | pass (14) | pass (14) |
| privacy | hidden Secret Code and Clearance as developer and reporter | pass (28) | pass (28) |
| time-entry | time entry parent and child fields | pass (15) | pass (15) |
| admin-editor | administration, dependency editor | pass (11) | pass (11) |
| csv | CSV export and import | pass (9) | pass (9) |
| large-list | 25,000 value field, timings | pass (10) | pass (10) |
| project-values | project values page (manager) | pass (13) | pass (13) |
| project-dependency | project dependency page | pass (12) | pass (12) |
| permissions | project page access by role, hidden field rule | pass (6) | pass (6) |

The number in brackets is the count of passed steps. Every step passed on both
versions; no 5xx response and no server log exception was caused by an unintended
request. The browser console reports only status codes of requests that the scenarios
make on purpose: 403 and 404 for pages a role may not open (permissions, seed-check),
422 for confirmation panels and refused saves (project-values, project-dependency,
privacy, context-wizard, see finding admin-3), and one 500 that the context-wizard
scenario forces itself to test the load error text.

The first run (before the fixes) had these results: issue-new, issue-edit, issue-list,
bulk-edit, time-entry, admin-editor, csv, large-list and project-dependency passed with
findings of the kinds listed below; privacy, project-values and permissions reported
the hidden field disclosure on the project pages (finding admin-1) as failed steps.

## Findings

All 22 findings of the walkthrough. Severity is the verified severity. Kinds: ux,
privacy, console.

### issue-1 (ux, minor; 5.1 and 7.0)

Problem: when the wizard save is refused for several issues, the browser alert
repeated each message once per issue and named no issue, whereas bulk edit lists
"City is invalid: #61, #62".
Verdict: real, caused by the plugin.
Resolution: fixed in 51efb99. One line per message with the issue numbers, no
duplicates, as bulk edit does.

### issue-2 (ux, nit; 7.0 and 5.1)

Problem: the wizard panel had almost no vertical spacing between a hint and the next
field label, so a label ran into the hint above it.
Verdict: real, cosmetic.
Resolution: fixed in 51efb99. More space between fields and under hints; field names
are bold; the title attribute (and core's dotted underline) appears only when the field
has a description.

### issue-3 (ux, nit; 5.1 and 7.0)

Problem: after a refused save the form shows a forced invalid dependent value as blank,
and error messages use Redmine's humanized names ("Postal zone").
Verdict: not a defect. Humanized names are core Redmine, and not keeping a forced
invalid value on re-render is intended; the error names the field.
Resolution: not a defect: stock Redmine naming and intended re-render behaviour.

### admin-1 (privacy, major; 5.1 and 7.0)

Problem: a permission holder who may not see a role-restricted field still had the
field named and its values disclosed on the project configuration pages: the overview
and the Settings tab linked it, the values and dependency pages rendered every value
and mapping, and the audit page listed it. This broke the rule that a hidden field is
never named and its value never disclosed.
Verdict: real, plugin caused, the most important finding.
Resolution: fixed in 51efb99. A shared check (administrator, or the field is used in
the project and visible for the role) is applied to the Settings tab, to every page and
update action of a field (404 for a hidden or unknown field), to the service
preamble and to the project audit page (rows of hidden or deleted fields are left
out for non-administrators). The hidden parent of a visible child was already fixed by
the full review commit; it shows the generic text and no parent values.

### admin-2 (ux, nit; 5.1 and 7.0)

Problem: the refusal "The values of field would take N bytes, but at most M bytes can
be stored" showed the field's current size as the limit and never mentioned the
configured project storage ceiling, so an administrator could not tell what to change.
Verdict: real, wording.
Resolution: fixed in 51efb99. A refusal by the project storage ceiling has its own
texts that name the configured size in KiB and say that a field that is already larger
may keep its size but not grow. Column-limit refusals keep their text. en, de, fr, nl.

### admin-3 (console, minor; 5.1 and 7.0)

Problem: confirmation panels and conflict pages answer HTTP 422 (409 for a stale
dependency save), so the browser console logs "Failed to load resource" on expected
flows.
Verdict: real observation, by design.
Resolution: not a defect: the status is deliberate, so that an unsaved form is never
reported as a success to non-JavaScript clients and API callers. The console line is
the browser's normal report of that status.

### admin-4 (ux, nit; 5.1 and 7.0)

Problem: the values page heading had nested parentheses, the table header "Value" was
centred, and the drag note said drag and drop is unavailable although the table had no
handle column.
Verdict: real, cosmetic.
Resolution: fixed in 51efb99. No parentheses in the subtitles, the drag handle column
is rendered only when drag and drop is offered, the Value column is left aligned.

### ux-1 (ux, minor; 7.0)

Problem: on Redmine 7.0 the plugin's context menu entries showed no submenu arrow,
while every core entry with a flyout does.
Verdict: real, 7.0 only.
Resolution: fixed in 51efb99. From Redmine 6.0 the wizard entry gets core's
`span.icon-only` with the angle-right sprite after `a.submenu`; 5.1 is unchanged.

### ux-2 (ux, minor; 5.1 and 7.0)

Problem: duplicate of issue-1 (wizard refusal repeats every message per issue, names no
issue).
Verdict: real, duplicate of issue-1.
Resolution: fixed in 51efb99 together with issue-1.

### ux-3 (ux, minor; 5.1 and 7.0)

Problem: the audit pages showed internal keys to managers: raw action and status keys
(validation_failed, sort_values, ...) and the untranslated key of a refusal as summary.
Verdict: real.
Resolution: fixed in 51efb99. Action and status keys are translated when the page is
rendered; a refusal shows the translated text of its error key; a storage refusal shows
the size texts with sizes read from the stored summary and no field name. Unknown keys
and raw messages are shown as stored; stored rows are unchanged.

### ux-4 (ux, minor; 5.1 and 7.0)

Problem: in the dependency editor of a large child field a parent section opened in the
"All child values" view, the first 200 unrelated values, so a parent with 50 linked
values looked as if nothing was linked.
Verdict: real.
Resolution: fixed in 51efb99. A section opens in the Linked view when the parent has
links and the child field has more than 200 values. The check and uncheck buttons are
grouped so that they wrap together.

### ux-5 (ux, nit; 5.1 and 7.0)

Problem: large numbers were formatted inconsistently (25,000 in the editor, 25000 in
the Settings tab, the values page filter line and the pager).
Verdict: real for the plugin's own texts.
Resolution: fixed in 51efb99 for the Settings tab counts and the filter line. Not
fixed: the pager text "(1-25/25000)" is core's markup (it prints the raw item count,
as on core's own lists), so it cannot change without overriding core.

### ux-6 (ux, nit; 5.1 and 7.0)

Problem: subtitles with nested or needless parentheses, "(List (depending))" and
"(Edit dependencies)".
Verdict: real, cosmetic.
Resolution: fixed in 51efb99 together with admin-4.

### ux-7 (ux, nit; 5.1 and 7.0)

Problem: a dependent field is indented by 20px on the control only, so its hint line
started 20px left of the control it explains.
Verdict: real, cosmetic.
Resolution: fixed in 51efb99. The runtime marks the hint of a dependent control with a
class that has the same start margin as the control (issue form, bulk edit, wizard).

### ux-8 (ux, minor; 5.1 and 7.0)

Problem: a refusal after a parent change says only "City is invalid" and does not say
that the stored child value is not allowed for the new parent value. The report also
claimed that the Germany case with a required child cannot be saved.
Verdict: partly real (generic wording); the Germany claim is wrong, as the walkthrough
saved issues with a blank required Postal Zone under Germany on both versions.
Resolution: not fixed: the owner decision keeps core's "is invalid" for a kept
disallowed value; a dedicated message is an owner option.

### ux-9 (ux, nit; 5.1 and 7.0)

Problem: the privacy-safe refusal tells what is wrong but gives no next step.
Verdict: real, wording.
Resolution: fixed in 51efb99. Both privacy-safe refusal texts end with a next step
("Keep the current value(s), or ask someone who can see all fields to make this
change"), in en, de, fr and nl; they still name no field.

### ux-10 (ux, minor; 5.1 and 7.0)

Problem: for a required child with no allowed value for the chosen parent the form
looked normal, with the hint "No values are available for the selected ...", which
does not say that this blocks saving.
Verdict: real.
Resolution: fixed in 51efb99. A field whose label carries core's required marker gets
a dedicated hint text; optional fields keep the old text. The behaviour that such an
issue can still be saved with a blank value (owner decision) was checked first.

### ux-11 (ux, nit; 5.1 and 7.0)

Problem: after a refused save the banner said "Postal zone cannot be blank" while the
re-rendered form already showed a default value in the field, which the user had not
chosen.
Verdict: real.
Resolution: fixed in 51efb99. On a form that contains core's error explanation the
first runtime pass does not apply per-parent defaults to a new record, so a posted
blank stays. Fresh forms and later parent changes still apply defaults.

### ux-12 (ux, nit; 5.1 and 7.0)

Problem: the wizard load error did not say that clicking the entry again retries.
Verdict: real, wording.
Resolution: fixed in 51efb99. The text adds "Click the entry again to try again." in
en, de, fr, nl and in both JavaScript fallbacks.

### ux-13 (ux, nit; 5.1 and 7.0)

Problem: the wizard panel layout is unbalanced (one column per level of the field
hierarchy) and hints run into the next label.
Verdict: real, cosmetic.
Resolution: fixed in 51efb99 for spacing and labels. Not fixed: balancing the columns,
because they are one per level of the field hierarchy and balancing would mix levels;
that is not a small CSS change.

### ux-14 (ux, nit; 5.1 and 7.0)

Problem: the confirmation panel for cross-project changes showed the warning icon alone
on a row above the heading, and on 7.0 the whole text was dark red on yellow, which
reads as an error.
Verdict: real, cosmetic.
Resolution: fixed in 51efb99. The heading is the first line of the flash box next to
the icon, with no empty row, and the box uses the page text color. Checked on 5.1 and
7.0.

### ux-15 (ux, nit; 5.1 and 7.0)

Problem: the values page note about drag and drop was phrased as availability for a
field where it is not available, and was shown when the filter matched nothing; the two
sort buttons were not grouped.
Verdict: real, wording.
Resolution: fixed in 51efb99. The note says that drag and drop is not available for
fields with more than the limit of values, it is not shown when the filter matches
nothing, and the sort buttons form a labelled group.

## How to re-run

See `.codex/e2e/README.md`: set up the four checkouts, seed with `reseed.sh`, run the
issue side scenarios with `run.sh` and the admin and project scenarios with
`run-admin.sh`. Results (JSON per scenario and screenshots) go to
`$E2E_DIR/out/<version>/` and are not committed.
