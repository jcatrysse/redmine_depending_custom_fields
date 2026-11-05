# Chromium walkthrough tooling

Playwright (Chromium) scenarios that drive the plugin in real Redmine 5.1 and 7.0
checkouts with a fixed seed. The report of the last run is in
`docs/e2e/walkthrough-2026-11-05.md`. Nothing here is part of the plugin at runtime
and nothing runs in CI.

## Prerequisites

- The test checkouts prepared by `.codex/redmine_clone.sh` and `.codex/test_setup.sh`
  for 5.1 and 7.0 (PostgreSQL, role `redmine` with password `redmine`, as in CI),
  under `$DCF_WORK_DIR/redmine-5.1` and `$DCF_WORK_DIR/redmine-7.0`.
- PostgreSQL running (`pg_ctlcluster 16 main start` if it is not).
- Node 22 with the `playwright` package and a Chromium browser installed so that
  `require('playwright')` resolves (for example through `NODE_PATH`).
- `DCF_WORK_DIR` set as for the other `.codex` scripts. `E2E_DIR` is the directory for
  the walkthrough checkouts and output; it defaults to `$DCF_WORK_DIR/e2e`.

```
export DCF_WORK_DIR=/path/to/work        # as for .codex/test_plugin.sh
export E2E_DIR="$DCF_WORK_DIR/e2e"       # default
export PATH=/opt/node22/bin:$PATH
```

## Set up the four checkouts

Each call copies the test checkout, points development and production at its own
database, creates and migrates it, loads the default data and syncs the plugin from
the given directory. Usage: `setup.sh <5.1|7.0> <name> <database> <plugin-dir>`.

| name | Redmine | port | database | used by |
|---|---|---|---|---|
| b51 | 5.1 | 3051 | dcf_e2e_b51 | issue side scenarios (`run.sh`) |
| b70 | 7.0 | 3070 | dcf_e2e_b70 | issue side scenarios (`run.sh`) |
| c51 | 5.1 | 3151 | dcf_e2e_c51 | admin and project scenarios (`run-admin.sh`) |
| c70 | 7.0 | 3170 | dcf_e2e_c70 | admin and project scenarios (`run-admin.sh`) |

```
cd /path/to/plugin/.codex/e2e
./setup.sh 5.1 b51 dcf_e2e_b51 /path/to/plugin
./setup.sh 7.0 b70 dcf_e2e_b70 /path/to/plugin
./setup.sh 5.1 c51 dcf_e2e_c51 /path/to/plugin
./setup.sh 7.0 c70 dcf_e2e_c70 /path/to/plugin
```

To test changed plugin code, stop the servers, replace
`$E2E_DIR/<name>/plugins/redmine_depending_custom_fields` with the new files (for
example `git archive HEAD | tar -x -C <that directory>`), re-seed and start again.

## Seed

`seed.rb` is idempotent (2 to 12 seconds) and writes the ids of everything it creates to
`$E2E_DIR/out/ids-<database>.json`, which the scenarios read.

```
./reseed.sh b51 5.1     # <name> <version>; likewise b70 7.0, c51 5.1, c70 7.0
```

Seed summary: projects Walk (`walk`), Walk Sub and Other (private); trackers Bug and
Feature; users `admin` (password `admin123!`), `manager`, `developer` and `reporter`
(password `Passw0rd!x` each; test data only); 22 custom fields (single and two level
dependencies, multiple select, required, hide when no options, enumeration, a
manager-only field with a visible child, project scope, shared scope, a 25,000 value
field, time entry and project fields); about 33 issues including two legacy mismatch
issues; the REST API is enabled.

## Run

```
./run.sh all                       # issue side scenarios on 5.1 and 7.0 (b51, b70)
./run.sh 7.0 issue-new privacy     # one version, selected scenarios
./run.sh 5.1 seed-check            # proof that the seed is in place
```

`run.sh` starts and stops the b51 and b70 servers itself. Note that without scenario
names it runs every file in `scenarios/`, but the admin and project scenarios
(admin-editor, csv, large-list, permissions, project-dependency, project-values) take a
base URL and an output directory instead of a version, so run them with
`run-admin.sh`, with the c51 and c70 servers started first:

```
./server.sh start c51 3151
./server.sh start c70 3170
./run-admin.sh                     # all six admin and project scenarios, re-seeding before each
./run-admin.sh permissions csv     # selected ones
./server.sh stop c51 3151
./server.sh stop c70 3170
```

Do not run two `run.sh` at the same time (same ports). Scenarios that change data
(admin side) re-seed first; the issue side scenarios add issues to b51 and b70, which a
re-seed does not remove.

## Results

Under `$E2E_DIR/out/<version>/`: one `<scenario>.json` per run (steps with expected and
observed values, pass or fail, console messages, 5xx responses) and screenshots in
`<scenario>/NN-name.png`. Screenshots are never committed. A step that fails records a
`FAIL-` screenshot. Each scenario exits non-zero when a step fails.

## Files

- `setup.sh`, `server.sh`, `reseed.sh`, `seed.rb`: environment.
- `run.sh`, `run-admin.sh`: runners.
- `lib.js` (browser, login, steps, privacy assertions), `lib-issue.js`, `lib-admin.js`.
- `scenarios/*.js`: one file per area.
