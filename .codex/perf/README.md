# Performance harness: main against a branch on Redmine 5.1 and 6.1

Measures the plugin of `origin/main` (variant `main`) against the plugin of the checked out commit (variant `branch`) in production mode on Redmine 5.1 and 6.1: server time, SQL queries, allocations and response sizes per request, memory of the Puma worker, and in Chromium the load times, JavaScript heap, plugin asset size and the interactions of the depending fields. The report of the first run is `docs/perf/main-vs-branch-2026-11-05.md`.

## Requirements

* The Redmine test checkouts `$DCF_WORK_DIR/redmine-5.1` and `redmine-6.1` with installed gems (`.codex/redmine_clone.sh`, `.codex/test_setup.sh`). They are copied, never modified.
* PostgreSQL on localhost with the user `redmine` (password `redmine`, CREATEDB). The databases `dcf_perf_m51`, `dcf_perf_p51`, `dcf_perf_m61` and `dcf_perf_p61` are created and dropped by the scripts.
* Node 22 with the `playwright` package resolvable (Chromium is used as it is installed; nothing is downloaded). `NODE_BIN` (default `/opt/node22/bin`) is put on the PATH.
* 4 CPUs and about 3 GB of free memory. Run on an idle machine: each block waits for a one minute load average below 1.0 (`LOAD_MAX`).

## Directories

| variable | default | holds |
|---|---|---|
| `DCF_WORK_DIR` | `~/.cache/redmine_depending_custom_fields` | the Redmine checkouts `redmine-<ver>` (shared with the other `.codex` scripts) |
| `E2E_DIR` | `$DCF_WORK_DIR/e2e` | the perf checkouts `m51 p51 m61 p61` and the exported plugins `src-main`, `src-branch` |
| `PERF_DIR` | `$DCF_WORK_DIR/perf` | `data/ids-<ver>.json` (written by the seed), `logs/`, `run/` (pid files), `results/` |

The scripts of this directory only read from `$REPO` (the plugin repository); everything they write goes below `E2E_DIR` and `PERF_DIR` (and the databases).

## Running it

```bash
export DCF_WORK_DIR=/some/work/dir            # optional, E2E_DIR and PERF_DIR can be set instead
.codex/perf/refresh_src.sh                    # exports origin/main to src-main and HEAD to src-branch (MAIN_REF, BRANCH_REF to change)
.codex/perf/build.sh                          # creates m51 p51 m61 p61, seeds the main databases, clones them for the branch (about 5 minutes first time; --rebuild starts over)
.codex/perf/measure.sh --smoke                # 2 rounds, to check the harness (results in $PERF_DIR/results/smoke)
.codex/perf/measure.sh 30                     # the full run: 30 measured rounds, 10 browser repetitions, about 40 minutes
```

`measure.sh` copies `src-branch` into `p51` and `p61` when it differs (run `refresh_src.sh` first to measure a newer commit), runs for each version the mapping check, the server bench and the browser bench, and writes `$PERF_DIR/results/summary.json` and `summary.md`. An earlier `results/raw` is moved to `results/archive-<time>`. All servers are stopped when the script ends. Ports: 3051 (m51), 3052 (p51), 3061 (m61), 3062 (p61).

Environment of `measure.sh`: `HEAVY_TIMEOUT_S` (45), `HEAVY_ROUNDS` (3), `HEAVY_NORMAL_ROUNDS` (15), `SEC_ROUNDS` (8), `WARMUP` (5), `MIXED` (300), `BROWSER_REPS` (10), `PROFILE_REPS` (2), `BROWSER_TIMEOUT_S` (30), `LOAD_MAX` (1.0), `LOAD_WAIT_MAX` (900 s), `VERSIONS` ("51 61").

## Files

| file | purpose |
|---|---|
| `common.sh` | variables and helpers sourced by the shell scripts |
| `refresh_src.sh` | exports the two plugin versions from git |
| `build.sh` | builds the checkouts and databases |
| `seed_perf.rb` | deterministic data sets (see below), run inside a checkout with `rails runner`, writes `data/ids-<ver>.json` |
| `server.sh` | starts and stops one Puma process (production, 1 thread) |
| `measure.sh` | the full run |
| `verify_mapping.js` | checks that both variants show the same options on the migrated data |
| `server_bench.js`, `browser_bench.js` | the two benches (options in the file headers) |
| `heavy_once.js` | one request of a heavy page with a long timeout (what main really needs when the bench stops at 45 s) |
| `compose_diag.js` | diagnostic, no timing: splits the response bytes of three pages (head, select, mapping: the `data-dcf-map` attribute before WP-39, the JSON script the select names in `data-dcf-map-ref` from WP-39 on) per variant; writes HTML to `results/` |
| `summarize.js` | `results/raw` to `summary.json` and `summary.md` |
| `report_tables.js` | `summary.json` to the markdown tables of the report with the verdicts, so the report holds no hand typed numbers |
| `lib/zz_perf_probe.rb` | initializer installed in every checkout: SQL count, view and database time, allocations, CPU and GC heap per request as `X-Perf-*` headers and `log/perf.log` |
| `lib/pages.js`, `client.js`, `servers.js`, `paths.js`, `stats.js` | page catalogue, HTTP client with cookie jar, server control, directories, median and percentiles |

## Data sets (seed_perf.rb)

* S1: 3 projects, 300 issues; Country, City, District, Languages (depending list), Zone and Site (depending enumeration) and plain fields.
* S2: project `perf-large`, 2,000 issues; Assembly (500 values) and Part (depending list, 25,000 values, 25,000 links).
* Baseline: project `perf-baseline`, 50 issues with a plain core list of 25,000 values.
* Users `admin` and `perfmember` (Manager role plus the permission `manage_project_custom_field_configuration`).

The seed runs against the main plugin (data model 0.0.15); the branch databases are clones of the seeded main databases followed by `redmine:plugins:migrate`, so the upgrade path is part of the test.

## Method in short

Server bench: one Puma process per variant, one thread, one keep-alive connection, sequential requests; warm-up rounds, then measured rounds in which main and branch are requested alternately per page (the first variant alternates per round); a mixed run of 300 requests; memory checkpoints from `/proc`; heavy pages with a timeout. Browser bench: Chromium, fresh tab per load, warm HTTP cache, interleaved repetitions; CDP performance counters, resource timing of the plugin files, a CPU profile in separate loads, and timed interactions (parent select change, context menu, wizard).

Verdict rule of the report (`report_tables.js`): the branch is slower when its median is more than 10 percent and more than 5 ms above main, faster when it is more than 10 percent and more than 5 ms below, otherwise equal; response sizes use 10 KB, the JavaScript heap 1 MB and plugin assets 5 KB as absolute limits. A verdict is marked weak when p90 or the minimum is within 5 percent. Medians of series that switch between two levels (a process state effect seen on Redmine 5.1 with the large pages) need a check against p90, minimum and the other Redmine version before a difference is called a regression.

## Repeating one finding

* A longer series of one page: `node server_bench.js --version 51 --only '^issue_new_s2$' --rounds 100 --warmup 5 --mixed 0 --out "$PERF_DIR/results/raw-extra"` (starts and stops both servers itself).
* What main really needs for a heavy page: `node heavy_once.js --version 51 --variant main --page admin_cf_part --timeout 600`.
* Byte composition of a page: `node compose_diag.js 51`.
