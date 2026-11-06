# Performance comparison: plugin 0.0.15 (main) versus the 0.1.0 branch

Date of the measurement: 2026-11-05. Branch `claude/festive-noether-2y8x7c`, measured at commit 4068728. The plugin code (app, lib, assets, config, db, init.rb) is identical at the current HEAD; later commits only touched `.codex` and `docs/reviews`.

In all text below "main, X / branch, Y" gives the median of main first and of the branch second.

## 1. The question

The owner of the plugin put it this way: "Ik wil echt vermijden dat mijn gebruikers een trage redmine krijgen door deze plugin." (I really want to avoid my users getting a slow Redmine because of this plugin.)

So the question is: does the rewritten plugin (the branch, 0.1.0 in the CHANGELOG, `init.rb` still says 0.0.16) make Redmine slower than the released plugin (origin/main, 0.0.15) without good reason, and where is it faster? The branch is acceptable when no page, interaction or memory figure that users or administrators feel gets worse, except where the new behaviour needs the extra work and the extra work is small.

## 2. Short answer

The branch is faster than main almost everywhere, and much faster where a lot of data is involved. It is not slower in any way that an end user would notice as a regression of the plugin itself. Four things are bigger or slower on the branch (R1, R3, R4, R5 in section 8). None of them is a reason to hold the release back; two have a cheap fix that is worth doing.

Across the 26 server pages measured per Redmine version, using the rule in section 3.5:

| | Redmine 5.1 | Redmine 6.1 |
|---|---|---|
| faster | 18 (2 of them pages where main never finished) | 13 (2 of them pages where main never finished) |
| equal within noise | 7 | 13 |
| slower | 1 (issue_new_s2, not shown to be caused by the plugin, R2) | 0 |

Headline figures (medians, Redmine 5.1 first, Redmine 6.1 second):

* Typical data (S1): server time of the new issue form main 223 ms / branch 127 ms (5.1) and main 157 / branch 125 ms (6.1); edit form 238 / 150 and 174 / 132 ms; issue list 370 / 271 and 313 / 278 ms. On 5.1 all six typical issue pages are 20 to 43 percent faster; on 6.1 four of six are 11 to 31 percent faster and two (issue page, bulk edit) are equal. The page of the new issue form is 313.1 KB on main and 34.0 KB on the branch (5.1), because main pasted the complete dependency mapping into the head of every page, including pages without a depending field.
* Mixed run of 300 requests, both versions served at the same time: 20 percent less wall time (119 s to 95 s) and 44 percent fewer allocated Ruby objects on 5.1; 14 percent less time (92 s to 80 s) and 31 percent fewer objects on 6.1.
* The right click on issues with the very large field (25,000 child values): main 956 ms / branch 183 ms (5.1), main 754 / branch 221 ms (6.1). Main rendered the whole wizard, 1,080 KB, inside every context menu.
* Pages where main did not finish within 45 seconds (and not within 240 seconds in a separate try on 5.1): the administration editor of the large field (branch 441 ms on 5.1, 407 ms on 6.1) and the project dependency page (branch 833 and 445 ms). The project values page of the large field: main 19.1 s and 46,633 KB, branch 0.46 s and 57.9 KB (5.1).
* Memory of the Puma worker: equal within about 4 percent (peak after the measured rounds main 315 MB / branch 329 MB on 5.1; after the mixed run main 394 MB / branch 403 MB on 6.1).

Where the branch costs more:

1. Pages that show the very large field (issue new, edit, show, bulk edit) are 19 percent larger (about 263 KB, 5 percent more gzipped) because the mapping is now inside an HTML attribute where every quote becomes `&quot;`. A cheap fix exists (R1).
2. The JavaScript heap on those pages is 2.3 MB (5.1) and 4.1 to 4.3 MB (6.1) higher (R3).
3. The plugin's scripts and stylesheet are 65.0 KB instead of 30.4 KB on every page (gzipped 7.5 KB on main, 18.8 KB on the branch), downloaded once and then cached (R4).
4. Opening the wizard from the context menu takes longer, because the wizard now loads when you open it: main 5 ms / branch 70 ms on typical data and main 554 ms / branch 1,562 ms with the large field (5.1). The right click itself is faster by the same amount or more, so both steps together are 25 ms faster on typical data and 198 ms (5.1) or 333 ms (6.1) slower with the large field (R5).

One more figure is flagged by the rule but is not shown to be caused by the plugin code: the new issue form with the large field on Redmine 5.1 (main 708 ms / branch 846 ms). The same data show main jumping to a comparable slow level on a sibling page (issue_edit_s2) for the same amount of work, and the page is equal on 6.1 (R2).

## 3. Environment and method

### 3.1 Environment

| item | value |
|---|---|
| Machine | 4 vCPU Intel Xeon 2.80 GHz virtual machine, 16 GB RAM, Linux 6.18.44 |
| Redmine 5.1 | 5.1.13 (Rails 6.1.7.10), Ruby 3.2.6 |
| Redmine 6.1 | 6.1.6 (Rails 7.2.4), Ruby 3.3.6 |
| Web server | Puma 8.0.2, production mode, one process, one thread (requests are sequential), static files served by Rails, no reverse proxy, so nothing is compressed on the wire |
| Database | PostgreSQL 16.15 on the same machine |
| Cache store | Rails default (file store in tmp/cache). Main used it for the mapping, the branch does not use the cache for the mapping |
| Browser | Chromium 153.0.8010.12 driven by Playwright, one browser, fresh tab per page load, warm HTTP cache |
| Variants | `main`: export of origin/main (0.0.15). `branch`: git archive of the branch HEAD (0.1.0). Same Redmine tree and Ruby per version, one Puma and one database per variant |
| Database upgrade | The seeded database of main was cloned for the branch and the branch plugin migration ran on it, which is the real upgrade path. A mapping check compared the stored data (identical) and the options shown on 36 form fields (no difference) on both versions |
| Probe | An identical small initializer (`zz_perf_probe.rb`) in both variants publishes the SQL count, view and database time, allocations and CPU time of each request as response headers. It costs the same in both variants |

### 3.2 Data sets

* S1, typical use: 3 projects with 300 issues. Country (6 values) with City (30 values depending on Country), District (60 depending on City) and Languages (multiple, 12 values depending on Country); Zone (4 key/value entries) with Site (20 entries depending on Zone). Plain fields Severity and Customer next to them.
* S2, very large lists: one project "Perf Large" with 2,000 issues. Assembly (500 values) and Part (depending list, 25,000 values, 50 per assembly, so 25,000 links). This is the stress case the large lists work of 0.1.0 is about.
* Baseline: one project with 50 issues and a plain core list field of 25,000 values (no plugin field at all), to show what Redmine itself costs for a list that size.

Two users: an administrator, and a project member with the Manager role that also holds the plugin permission for project custom field configuration.

### 3.3 Server and browser measurement

* Server: 5 warm-up rounds, then 30 measured rounds. In each round every page is requested once per variant, one variant right after the other (main first in even rounds, branch first in odd rounds), over one keep-alive connection with a logged-in session. Interleaving means that slow drifts of the machine hit both variants alike.
* Secondary pages (the administrator copies of the S2 pages, the baseline, S2 bulk edit and S2 project settings) have 8 rounds. Heavy pages (the administration editor and the two project pages of the 25,000 value field) are tried once with a timeout of 45 seconds. A variant that needs more than 8 seconds gets 3 rounds, a variant that does not finish within 45 seconds is recorded as a timeout, the other variant gets 15 rounds. The number of rounds is in the "n main/branch" column. In a separate single try with a timeout of 240 seconds on 5.1, main again did not finish on the administration editor and on the project dependency page of the large field.
* Mixed run: the same random sequence of 300 requests goes to both Puma processes at the same time. It feeds the memory checkpoints and the totals.
* Browser: each page is loaded 10 times per variant (5 times for the right click page on S2), interleaved the same way.
* Each block started only when the one minute load average of the machine was below 1.0. The load at the start was 0.78 (5.1) and 0.96 (6.1) for the server blocks and 0.89 (5.1) and 0.85 (6.1) for the browser blocks. The full run took 41 minutes.
* After the full run, and before this report was written, one request per variant to three pages was made on Redmine 5.1 only to split the response bytes (R1). That was a diagnostic without timing and both servers were stopped afterwards. No timing was measured again.

### 3.4 What each metric means

| metric | meaning |
|---|---|
| Time (wall) | Milliseconds from sending the request to receiving the last byte, as seen by the client. This is what users feel for the server part |
| CPU | CPU milliseconds that the Puma process used for the request |
| SQL queries | Queries sent to the database, without schema and cached queries |
| Allocations | Ruby objects allocated while handling the request (Rails "Completed" line). A good proxy for garbage collection pressure |
| Response KB | Size of the HTML in KB (1 KB = 1,024 bytes). Gzipped is the size with gzip level 6, a proxy for what a compressing proxy would send |
| RSS | Resident memory of the Puma process in MB. Peak is the high water mark of the process |
| First byte, DOM ready, load | Browser navigation timing for the page in milliseconds |
| Script, main thread tasks | Chromium counters for the time spent running JavaScript and in all main thread tasks during the load |
| JS heap | JavaScript memory in use in the page after loading, in MB |
| Plugin script (profile) | Time inside the plugin's script files, measured with the V8 CPU profiler in separate loads (the profiler slows everything, so these loads feed only this figure) |
| Interaction | After the parent select of a new issue form is changed, the time until the child select shows exactly the allowed options. "Handler returns" is the time until the change handlers finish, "painted" includes the next two animation frames |
| Context menu shown, wizard opened | Right click on a selected issue until the menu shows, and the click on the wizard entry until the wizard form is visible |

### 3.5 Verdict rule

For every time figure, the verdict compares the medians: the branch is **slower** when its median is more than 10 percent AND more than 5 ms above main, **faster** when it is more than 10 percent AND more than 5 ms below, otherwise **equal**. For sizes the absolute limit is 10 KB (response size), 1 MB (JavaScript heap) or 5 KB (plugin assets). A verdict marked "weak" means that p90 or the minimum is within 5 percent, so the difference is not consistent over the series. "n=8" or "n=3" marks a small series. A difference counts as real only when it is above noise: p90 and minimum agree and the other Redmine version agrees, or the cause is known.

How noisy are the series? Most pages have a p90 within 10 to 25 percent of the median. One effect deserves a warning: some series on Redmine 5.1 move between two levels about 150 to 250 ms apart for exactly the same work (same SQL, same allocations). Example: main on issue_edit_s2 has a median of 677 ms in the first 9 rounds and 855 ms in the other 21 (CPU 607 against 792 ms), and the branch on the same page does the opposite (841 ms, then 717 ms). The median of such a series depends on which level a process happened to be in. This is why one slower median on one version is checked against p90, minimum and the other version before it is called a regression.

## 4. Pages measured

| page key | what it is |
|---|---|
| issue_new_s1, issue_new_s2 | New issue form in the S1 or S2 project (tracker with the depending fields) |
| issue_new_baseline | New issue form with the plain 25,000 value core list, no plugin field |
| issue_new_s2_admin, issue_edit_s2_admin, issue_show_s2_admin | The S2 pages as administrator |
| issue_edit_s1, issue_edit_s2 | Edit form of one issue |
| issue_show_s1, issue_show_s2 | Issue page |
| issue_list_s1, issue_list_s2 | Issue list, 25 rows, filter on City or on Part, with the depending columns |
| bulk_edit_s1, bulk_edit_s2 | Bulk edit form for 10 issues |
| context_menu_s1, context_menu_s2 | The context menu (right click) response for 10 selected issues |
| issue_update_s1, issue_update_s2 | Saving an issue (PATCH) in which the parent and the child change; a second untimed request restores the values. Both variants store the new values (checked) |
| project_settings_s1, project_settings_s2 | Project settings page |
| project_values_s1_city, project_values_s2_part | Project level "Custom field configuration" page with the values of one field |
| project_deps_s1_city, project_deps_s2_part | Project level page with the dependency mapping of one field |
| admin_cf_city, admin_cf_part | Administration edit page of the custom field (which holds the dependency mapping editor) |

## 5. Results

Medians in the tables unless the header says otherwise; "ratio" is branch divided by main (below 1 means the branch is faster or smaller). Every number is generated from `summary.json` by `.codex/perf/report_tables.js`.

### 5.1 Server, Redmine 5.1: time per request (ms)

| page | n main / branch | main median | main p90 | branch median | branch p90 | ratio median | ratio min | verdict |
|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 30/30 | 223 | 272 | 127 | 163 | 0.57 | 0.54 | faster |
| issue_new_s2 | 30/30 | 708 | 762 | 846 | 914 | 1.19 | 1.10 | slower |
| issue_new_baseline | 8/8 | 676 | 876 | 517 | 565 | 0.76 | 0.83 | faster (n=8) |
| issue_new_s2_admin | 8/8 | 644 | 859 | 685 | 864 | 1.06 | 1.01 | equal (n=8) |
| issue_edit_s1 | 30/30 | 238 | 300 | 150 | 204 | 0.63 | 0.59 | faster |
| issue_edit_s2 | 30/30 | 808 | 912 | 735 | 846 | 0.91 | 0.99 | equal |
| issue_edit_s2_admin | 8/8 | 671 | 978 | 658 | 902 | 0.98 | 1.04 | equal (n=8) |
| issue_show_s1 | 30/30 | 452 | 613 | 341 | 402 | 0.75 | 0.72 | faster |
| issue_show_s2 | 30/30 | 841 | 1,008 | 877 | 963 | 1.04 | 0.99 | equal |
| issue_show_s2_admin | 8/8 | 773 | 908 | 684 | 781 | 0.89 | 0.99 | faster (weak: p90 or min within 5 percent) (n=8) |
| issue_list_s1 | 30/30 | 370 | 583 | 271 | 354 | 0.73 | 0.74 | faster |
| issue_list_s2 | 30/30 | 952 | 1,109 | 801 | 903 | 0.84 | 0.76 | faster |
| bulk_edit_s1 | 30/30 | 342 | 426 | 273 | 304 | 0.80 | 0.71 | faster |
| bulk_edit_s2 | 8/8 | 774 | 834 | 779 | 869 | 1.01 | 1.01 | equal (n=8) |
| context_menu_s1 | 30/30 | 217 | 275 | 132 | 163 | 0.61 | 0.61 | faster |
| context_menu_s2 | 30/30 | 956 | 1,029 | 183 | 228 | 0.19 | 0.21 | faster |
| issue_update_s1 | 30/30 | 101 | 115 | 96 | 126 | 0.95 | 0.97 | equal |
| issue_update_s2 | 30/30 | 226 | 250 | 243 | 266 | 1.07 | 1.11 | equal |
| project_settings_s1 | 30/30 | 216 | 247 | 128 | 153 | 0.59 | 0.58 | faster |
| project_settings_s2 | 8/8 | 335 | 555 | 268 | 312 | 0.80 | 0.80 | faster (n=8) |
| project_values_s1_city | 30/30 | 184 | 214 | 85 | 274 | 0.46 | 0.45 | faster (weak: p90 or min within 5 percent) |
| project_values_s2_part | 3/15 | 19,136 | 19,601 | 459 | 624 | 0.02 | 0.02 | faster (n=3) |
| project_deps_s1_city | 30/30 | 149 | 166 | 63 | 80 | 0.42 | 0.38 | faster |
| project_deps_s2_part | 0/15 | timeout (> 45 s) | - | 833 | 922 | - | - | faster (main did not finish) |
| admin_cf_city | 30/30 | 167 | 200 | 69 | 77 | 0.41 | 0.37 | faster |
| admin_cf_part | 0/15 | timeout (> 45 s) | - | 441 | 604 | - | - | faster (main did not finish) |

Notes: issue_new_s2 is the slower page and is discussed in R2. issue_update_s2 is equal by the rule (main 226 / branch 243 ms, ratio 1.07; minimum and p90 are also 15 to 21 ms higher; CPU +20 ms with identical SQL and allocations); it is discussed in R6. The project_values_s2_part row of main has 3 rounds of about 19 s each.

### 5.2 Server, Redmine 5.1: work and size per request

| page | SQL queries main / branch | allocations main / branch (thousands) | CPU ms main / branch | response KB main / branch | gzipped KB main / branch | size verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 41 / 40 | 254.1 / 42.0 | 190 / 101 | 313.1 / 34.0 | 64.9 / 7.2 | faster |
| issue_new_s2 | 42 / 42 | 965.5 / 941.1 | 620 / 784 | 1,369.8 / 1,626.5 | 197.9 / 207.9 | slower |
| issue_new_baseline | 42 / 42 | 897.0 / 682.4 | 617 / 460 | 1,499.0 / 1,215.0 | 191.8 / 133.8 | faster |
| issue_new_s2_admin | 31 / 31 | 963.6 / 939.2 | 589 / 608 | 1,369.0 / 1,625.7 | 197.8 / 207.9 | slower |
| issue_edit_s1 | 48 / 47 | 256.2 / 44.5 | 203 / 118 | 314.4 / 36.1 | 65.2 / 7.5 | faster |
| issue_edit_s2 | 45 / 45 | 967.4 / 942.9 | 763 / 645 | 1,371.2 / 1,628.0 | 198.3 / 208.4 | slower |
| issue_edit_s2_admin | 36 / 36 | 965.6 / 941.4 | 628 / 596 | 1,370.4 / 1,627.2 | 198.2 / 208.4 | slower |
| issue_show_s1 | 72 / 71 | 332.9 / 121.2 | 353 / 255 | 322.7 / 44.4 | 67.1 / 9.3 | faster |
| issue_show_s2 | 65 / 65 | 1,043.0 / 1,018.7 | 746 / 777 | 1,379.0 / 1,635.8 | 200.3 / 210.3 | slower |
| issue_show_s2_admin | 47 / 47 | 974.5 / 950.2 | 672 / 636 | 1,378.0 / 1,634.8 | 200.1 / 210.1 | slower |
| issue_list_s1 | 63 / 61 | 306.3 / 91.4 | 296 / 206 | 355.5 / 71.5 | 68.3 / 9.7 | faster |
| issue_list_s2 | 43 / 41 | 1,073.8 / 703.7 | 861 / 700 | 921.5 / 637.5 | 187.9 / 129.6 | faster |
| bulk_edit_s1 | 73 / 73 | 292.3 / 81.6 | 288 / 222 | 312.6 / 34.1 | 64.3 / 6.7 | faster |
| bulk_edit_s2 | 69 / 69 | 998.4 / 974.7 | 686 / 704 | 1,369.9 / 1,626.6 | 197.1 / 207.2 | slower |
| context_menu_s1 | 44 / 38 | 155.9 / 39.4 | 177 / 108 | 25.5 / 13.1 | 2.7 / 1.2 | faster |
| context_menu_s2 | 42 / 38 | 1,066.1 / 83.2 | 888 / 153 | 1,079.8 / 11.0 | 133.7 / 1.1 | faster |
| issue_update_s1 | 52 / 49 | 21.8 / 21.7 | 77 / 73 | redirect, no body | redirect, no body | - |
| issue_update_s2 | 42 / 41 | 123.6 / 123.3 | 191 / 211 | redirect, no body | redirect, no body | - |
| project_settings_s1 | 46 / 46 | 251.1 / 36.7 | 179 / 95 | 312.0 / 28.1 | 64.1 / 5.8 | faster |
| project_settings_s2 | 46 / 45 | 353.8 / 139.8 | 299 / 229 | 308.2 / 24.3 | 63.8 / 5.6 | faster |
| project_values_s1_city | 22 / 22 | 257.4 / 44.9 | 163 / 70 | 351.6 / 69.8 | 67.4 / 9.5 | faster |
| project_values_s2_part | 22 / 22 | 23,047.0 / 605.2 | 18,612 / 396 | 46,633.4 / 57.9 | - / 8.7 | faster |
| project_deps_s1_city | 21 / 23 | 243.8 / 21.5 | 133 / 49 | 341.2 / 24.6 | 62.9 / 6.4 | faster |
| project_deps_s2_part | timeout (> 45 s) / 23 | timeout (> 45 s) / 1,191.9 | timeout (> 45 s) / 812 | timeout (> 45 s) / 1,531.4 | timeout (> 45 s) / 145.6 | - |
| admin_cf_city | 16 / 17 | 246.1 / 22.5 | 143 / 53 | 340.5 / 29.8 | 64.7 / 7.6 | faster |
| admin_cf_part | timeout (> 45 s) / 17 | timeout (> 45 s) / 399.0 | timeout (> 45 s) / 397 | timeout (> 45 s) / 805.3 | timeout (> 45 s) / 131.9 | - |

Notes: "redirect, no body" are the two save requests, which answer with an empty redirect. The gzipped size of project_values_s2_part on main is not available because the response (46,633 KB) is above the 8 MB limit up to which responses were compressed for the statistic. The three S2 form pages, the S2 issue page and S2 bulk edit are larger on the branch (R1); every other page is smaller, most of them by 80 to 91 percent.

### 5.3 Server, Redmine 6.1: time per request (ms)

| page | n main / branch | main median | main p90 | branch median | branch p90 | ratio median | ratio min | verdict |
|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 30/30 | 157 | 189 | 125 | 151 | 0.80 | 0.74 | faster |
| issue_new_s2 | 30/30 | 521 | 565 | 510 | 546 | 0.98 | 0.97 | equal |
| issue_new_baseline | 8/8 | 446 | 620 | 414 | 452 | 0.93 | 0.98 | equal (n=8) |
| issue_new_s2_admin | 8/8 | 474 | 512 | 488 | 561 | 1.03 | 0.99 | equal (n=8) |
| issue_edit_s1 | 30/30 | 174 | 213 | 132 | 149 | 0.76 | 0.82 | faster |
| issue_edit_s2 | 30/30 | 524 | 550 | 531 | 593 | 1.01 | 1.05 | equal |
| issue_edit_s2_admin | 8/8 | 514 | 603 | 520 | 554 | 1.01 | 1.01 | equal (n=8) |
| issue_show_s1 | 30/30 | 393 | 430 | 360 | 410 | 0.92 | 0.93 | equal |
| issue_show_s2 | 30/30 | 726 | 862 | 762 | 899 | 1.05 | 1.00 | equal |
| issue_show_s2_admin | 8/8 | 524 | 595 | 540 | 649 | 1.03 | 1.03 | equal (n=8) |
| issue_list_s1 | 30/30 | 313 | 361 | 278 | 327 | 0.89 | 0.81 | faster |
| issue_list_s2 | 30/30 | 665 | 884 | 560 | 599 | 0.84 | 0.81 | faster |
| bulk_edit_s1 | 30/30 | 288 | 337 | 278 | 328 | 0.97 | 0.92 | equal |
| bulk_edit_s2 | 8/8 | 645 | 842 | 689 | 1,007 | 1.07 | 1.06 | equal (n=8) |
| context_menu_s1 | 30/30 | 209 | 241 | 145 | 211 | 0.69 | 0.59 | faster |
| context_menu_s2 | 30/30 | 754 | 838 | 221 | 364 | 0.29 | 0.25 | faster |
| issue_update_s1 | 30/30 | 178 | 234 | 105 | 118 | 0.59 | 0.92 | faster |
| issue_update_s2 | 30/30 | 266 | 303 | 269 | 297 | 1.01 | 0.98 | equal |
| project_settings_s1 | 30/30 | 181 | 214 | 147 | 179 | 0.81 | 0.85 | faster |
| project_settings_s2 | 8/8 | 323 | 351 | 321 | 353 | 0.99 | 0.98 | equal (n=8) |
| project_values_s1_city | 30/30 | 108 | 129 | 98 | 123 | 0.90 | 0.83 | equal |
| project_values_s2_part | 3/15 | 17,332 | 18,079 | 305 | 323 | 0.02 | 0.02 | faster (n=3) |
| project_deps_s1_city | 30/30 | 91 | 121 | 69 | 81 | 0.75 | 0.77 | faster |
| project_deps_s2_part | 0/15 | timeout (> 45 s) | - | 445 | 489 | - | - | faster (main did not finish) |
| admin_cf_city | 30/30 | 94 | 109 | 68 | 87 | 0.72 | 0.77 | faster |
| admin_cf_part | 0/15 | timeout (> 45 s) | - | 407 | 436 | - | - | faster (main did not finish) |

Notes: nothing is slower. issue_update_s1 on main has a long tail (p90 234 ms, minimum 91 ms) against a branch median of 105 ms; the minimum shows the real difference to be small.

### 5.4 Server, Redmine 6.1: work and size per request

| page | SQL queries main / branch | allocations main / branch (thousands) | CPU ms main / branch | response KB main / branch | gzipped KB main / branch | size verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 42 / 41 | 59.6 / 33.0 | 126 / 103 | 316.5 / 37.5 | 65.9 / 7.9 | faster |
| issue_new_s2 | 42 / 42 | 391.4 / 368.6 | 464 / 458 | 1,373.2 / 1,629.9 | 198.9 / 208.8 | slower |
| issue_new_baseline | 42 / 42 | 330.1 / 302.9 | 387 / 367 | 1,502.5 / 1,218.4 | 192.8 / 134.7 | faster |
| issue_new_s2_admin | 31 / 31 | 389.6 / 366.8 | 431 / 451 | 1,372.4 / 1,629.1 | 198.8 / 208.7 | slower |
| issue_edit_s1 | 49 / 48 | 62.2 / 35.7 | 141 / 107 | 318.1 / 39.8 | 66.2 / 8.3 | faster |
| issue_edit_s2 | 46 / 46 | 393.2 / 370.7 | 464 / 480 | 1,374.9 / 1,631.7 | 199.5 / 209.4 | slower |
| issue_edit_s2_admin | 37 / 37 | 392.0 / 369.2 | 464 / 461 | 1,374.0 / 1,630.8 | 199.5 / 209.3 | slower |
| issue_show_s1 | 74 / 73 | 139.2 / 112.8 | 304 / 281 | 329.8 / 51.5 | 68.6 / 10.5 | faster |
| issue_show_s2 | 67 / 67 | 469.7 / 446.7 | 629 / 648 | 1,386.1 / 1,643.0 | 201.8 / 211.7 | slower |
| issue_show_s2_admin | 47 / 47 | 398.7 / 376.0 | 479 / 500 | 1,385.1 / 1,641.9 | 201.7 / 211.5 | slower |
| issue_list_s1 | 64 / 62 | 101.4 / 73.5 | 253 / 218 | 364.6 / 80.5 | 69.6 / 10.7 | faster |
| issue_list_s2 | 44 / 42 | 473.3 / 290.2 | 565 / 454 | 930.7 / 646.7 | 189.3 / 130.8 | faster |
| bulk_edit_s1 | 73 / 73 | 98.8 / 73.7 | 240 / 224 | 315.3 / 36.8 | 65.2 / 7.3 | faster |
| bulk_edit_s2 | 69 / 69 | 423.7 / 401.6 | 562 / 589 | 1,372.7 / 1,629.3 | 198.1 / 208.0 | slower |
| context_menu_s1 | 44 / 38 | 150.5 / 36.6 | 173 / 110 | 27.1 / 15.0 | 2.8 / 1.3 | faster |
| context_menu_s2 | 42 / 38 | 681.3 / 80.9 | 683 / 173 | 1,081.3 / 12.6 | 133.8 / 1.2 | faster |
| issue_update_s1 | 51 / 48 | 20.8 / 20.6 | 150 / 82 | redirect, no body | redirect, no body | - |
| issue_update_s2 | 41 / 40 | 122.0 / 122.6 | 234 / 238 | redirect, no body | redirect, no body | - |
| project_settings_s1 | 46 / 46 | 59.0 / 31.3 | 142 / 110 | 316.3 / 32.3 | 65.0 / 6.6 | faster |
| project_settings_s2 | 46 / 45 | 162.1 / 135.0 | 276 / 266 | 312.4 / 28.4 | 64.8 / 6.4 | faster |
| project_values_s1_city | 22 / 22 | 53.3 / 27.4 | 91 / 77 | 356.1 / 74.5 | 68.3 / 10.1 | faster |
| project_values_s2_part | 22 / 22 | 10,572.5 / 229.7 | 16,926 / 277 | 48,271.8 / 58.8 | - / 9.3 | faster |
| project_deps_s1_city | 21 / 23 | 45.6 / 16.1 | 74 / 53 | 343.9 / 27.5 | 63.9 / 7.1 | faster |
| project_deps_s2_part | timeout (> 45 s) / 23 | timeout (> 45 s) / 259.4 | timeout (> 45 s) / 408 | timeout (> 45 s) / 1,534.2 | timeout (> 45 s) / 146.6 | - |
| admin_cf_city | 16 / 17 | 47.5 / 16.8 | 77 / 52 | 345.6 / 35.0 | 65.9 / 8.5 | faster |
| admin_cf_part | timeout (> 45 s) / 17 | timeout (> 45 s) / 200.7 | timeout (> 45 s) / 371 | timeout (> 45 s) / 810.5 | timeout (> 45 s) / 133.0 | - |

### 5.5 Memory of the Puma worker

Redmine 5.1:

| checkpoint | main RSS MB | branch RSS MB | main peak RSS MB | branch peak RSS MB |
|---|---|---|---|---|
| after_boot | 184 | 181 | - | - |
| after_warmup | 301 | 307 | 302 | 311 |
| after_rounds | 302 | 314 | 315 | 329 |
| after_mixed | 334 | 314 | 339 | 345 |
| mixed run of 300 requests: wall seconds, objects allocated (millions), SQL queries | 119 s, 125.8 M, 14,576 | 95 s, 71.1 M, 14,162 | | |
| after_heavy | 233 (server restarted) | 321 | 233 | 345 |

Redmine 6.1:

| checkpoint | main RSS MB | branch RSS MB | main peak RSS MB | branch peak RSS MB |
|---|---|---|---|---|
| after_boot | 231 | 225 | - | - |
| after_warmup | 358 | 347 | 358 | 347 |
| after_rounds | 374 | 372 | 374 | 372 |
| after_mixed | 394 | 389 | 394 | 403 |
| mixed run of 300 requests: wall seconds, objects allocated (millions), SQL queries | 92 s, 52.0 M, 14,675 | 80 s, 35.7 M, 14,263 | | |
| after_heavy | 280 (server restarted) | 392 | 280 | 403 |

After the boot the branch is 3 to 6 MB lower. After the measured rounds and the mixed run the two are within about 4 percent of each other: on 5.1 the peak after the rounds is 14 MB higher on the branch and the median RSS after the mixed run is 20 MB lower; on 6.1 the median RSS is equal and the peak after the mixed run is 9 MB higher. I read this as equal. The "after_heavy" rows are not comparable, because main was restarted after its timeouts. For the record, during the separate 240 second try on 5.1 the main process had reached 838 MB (administration editor of the large field) and 1,356 MB (project dependency page) of RSS without finishing, while the branch worker was at 321 MB after serving the same pages in the full run.

### 5.6 Browser, Redmine 5.1

Load times (milliseconds):

| page | first byte main / branch | verdict | DOM ready main / branch | verdict | load main / branch | verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 225 / 120 | faster | 402 / 294 | faster | 407 / 299 | faster |
| issue_new_s2 | 670 / 673 | equal | 1,761 / 1,821 | equal | 2,003 / 2,027 | equal |
| issue_edit_s2 | 661 / 661 | equal | 1,770 / 1,745 | equal | 1,958 / 1,931 | equal |
| context_menu_s1 | 255 / 135 | faster | 441 / 272 | faster | 442 / 273 | faster |
| context_menu_s2 | 307 / 214 | faster | 457 / 346 | faster | 458 / 347 | faster |
| admin_part_editor | timeout (> 30 s) / 448 | faster (main did not finish) | timeout (> 30 s) / 1,206 | faster (main did not finish) | timeout (> 30 s) / 1,464 | faster (main did not finish) |

Script, main thread and JavaScript memory:

| page | script ms main / branch | verdict | main thread tasks ms main / branch | verdict | JS heap MB main / branch | verdict | plugin script ms (profile) main / branch | verdict |
|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 85 / 94 | equal | 216 / 204 | equal | 4.1 / 3.5 | equal | 7 / 9 | equal |
| issue_new_s2 | 402 / 362 | equal | 1,479 / 1,418 | equal | 4.5 / 6.8 | slower | 249 / 205 | faster |
| issue_edit_s2 | 393 / 370 | equal | 1,442 / 1,407 | equal | 4.7 / 7.0 | slower | - | - |
| context_menu_s1 | 94 / 82 | faster | 195 / 161 | faster | 3.9 / 3.3 | equal | - | - |
| context_menu_s2 | 73 / 75 | equal | 167 / 152 | equal | 3.9 / 3.3 | equal | - | - |
| admin_part_editor | timeout (> 30 s) / 230 | faster (main did not finish) | timeout (> 30 s) / 1,028 | faster (main did not finish) | timeout (> 30 s) / 5.2 | main did not finish | timeout (> 30 s) / 192 | faster (main did not finish) |

Plugin assets and page size:

| page | plugin asset KB main / branch | verdict | plugin asset load ms main / branch | verdict | DOM nodes main / branch | verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 30.4 / 65.0 | slower | 46 / 54 | slower | 2,201 / 2,203 | equal |
| issue_new_s2 | 30.4 / 65.0 | slower | 54 / 55 | equal | 179,402 / 179,606 | equal |
| issue_edit_s2 | 30.4 / 65.0 | slower | 55 / 49 | faster | 179,749 / 179,744 | equal |
| context_menu_s1 | 30.4 / 65.0 | slower | 42 / 40 | equal | 2,137 / 2,135 | equal |
| context_menu_s2 | 30.4 / 65.0 | slower | 31 / 49 | slower | 2,025 / 2,023 | equal |
| admin_part_editor | timeout (> 30 s) / 185.3 | main did not finish | timeout (> 30 s) / 109 | faster (main did not finish) | timeout (> 30 s) / 52,549 | main did not finish |

Interaction: change the parent select on the new issue form and wait for the child options:

| interaction | change handler returns (ms) main / branch | verdict | options shown and painted (ms) main / branch | verdict |
|---|---|---|---|---|
| interaction_s1_country | 3 / 3 | equal | 11 / 11 | equal |
| interaction_s2_assembly | 132 / 91 | faster | 300 / 185 | faster |

Context menu on the issue list with 10 selected issues:

| page | context menu shown (ms) main / branch | verdict | wizard opened (ms) main / branch | verdict | sum of the two medians (ms) main / branch |
|---|---|---|---|---|---|
| context_menu_s1 | 236 / 146 | faster | 5 / 70 | slower | 241 / 216 |
| context_menu_s2 | 1,013 / 204 | faster | 554 / 1,562 | slower | 1,568 / 1,766 |

### 5.7 Browser, Redmine 6.1

| page | first byte main / branch | verdict | DOM ready main / branch | verdict | load main / branch | verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 145 / 123 | faster | 386 / 346 | faster | 394 / 353 | faster |
| issue_new_s2 | 499 / 502 | equal | 1,743 / 1,715 | equal | 1,975 / 1,925 | equal |
| issue_edit_s2 | 537 / 521 | equal | 1,771 / 1,739 | equal | 1,981 / 1,935 | equal |
| context_menu_s1 | 173 / 142 | faster | 363 / 308 | faster | 371 / 315 | faster |
| context_menu_s2 | 259 / 227 | faster | 434 / 393 | equal | 435 / 400 | equal |
| admin_part_editor | timeout (> 30 s) / 412 | faster (main did not finish) | timeout (> 30 s) / 1,389 | faster (main did not finish) | timeout (> 30 s) / 1,451 | faster (main did not finish) |

| page | script ms main / branch | verdict | main thread tasks ms main / branch | verdict | JS heap MB main / branch | verdict | plugin script ms (profile) main / branch | verdict |
|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 92 / 91 | equal | 280 / 258 | equal | 4.6 / 4.0 | equal | 7 / 10 | equal |
| issue_new_s2 | 438 / 417 | equal | 1,600 / 1,549 | equal | 4.6 / 8.9 | slower | 245 / 241 | equal |
| issue_edit_s2 | 420 / 404 | equal | 1,575 / 1,544 | equal | 4.7 / 8.8 | slower | - | - |
| context_menu_s1 | 86 / 83 | equal | 223 / 191 | faster | 4.3 / 3.7 | equal | - | - |
| context_menu_s2 | 79 / 80 | equal | 207 / 188 | equal | 4.3 / 3.6 | equal | - | - |
| admin_part_editor | timeout (> 30 s) / 224 | faster (main did not finish) | timeout (> 30 s) / 1,053 | faster (main did not finish) | timeout (> 30 s) / 6.6 | main did not finish | timeout (> 30 s) / 179 | faster (main did not finish) |

| page | plugin asset KB main / branch | verdict | plugin asset load ms main / branch | verdict | DOM nodes main / branch | verdict |
|---|---|---|---|---|---|---|
| issue_new_s1 | 30.4 / 65.0 | slower | 88 / 90 | equal | 3,615 / 3,617 | equal |
| issue_new_s2 | 30.4 / 65.0 | slower | 74 / 73 | equal | 180,788 / 180,864 | equal |
| issue_edit_s2 | 30.4 / 65.0 | slower | 80 / 69 | faster | 181,170 / 181,250 | equal |
| context_menu_s1 | 30.4 / 65.0 | slower | 79 / 83 | equal | 3,542 / 3,540 | equal |
| context_menu_s2 | 30.4 / 65.0 | slower | 50 / 87 | slower | 3,430 / 3,428 | equal |
| admin_part_editor | timeout (> 30 s) / 185.3 | main did not finish | timeout (> 30 s) / 110 | faster (main did not finish) | timeout (> 30 s) / 53,950 | main did not finish |

| interaction | change handler returns (ms) main / branch | verdict | options shown and painted (ms) main / branch | verdict |
|---|---|---|---|---|
| interaction_s1_country | 3 / 3 | equal | 9 / 11 | equal |
| interaction_s2_assembly | 155 / 89 | faster | 333 / 177 | faster |

| page | context menu shown (ms) main / branch | verdict | wizard opened (ms) main / branch | verdict | sum of the two medians (ms) main / branch |
|---|---|---|---|---|---|
| context_menu_s1 | 226 / 137 | faster | 5 / 71 | slower | 232 / 209 |
| context_menu_s2 | 921 / 216 | faster | 462 / 1,499 | slower | 1,382 / 1,715 |

Notes for both browser sections: on the S2 pages the DOM holds about 180,000 nodes in both variants (25,000 options in several selects of the form and of the quick edit form on the issue page), so loading takes 1.7 to 2.0 s in both and the time is dominated by Redmine's own markup. No JavaScript errors occurred in any run. The extra plugin asset load time on context_menu_s2 (5 repetitions, +18 ms on 5.1 and +37 ms on 6.1) does not appear on the other four pages and is within the spread of a series of 5; I treat it as noise. The administration editor page of the large field loads on the branch with DOM ready after 1.2 s (5.1) and 1.4 s (6.1) with 52,549 and 53,950 nodes; main never finished within 30 s.

## 6. Verdict per area, in plain words

| area | verdict | basis |
|---|---|---|
| New, edit, show, list and bulk edit pages with typical data (S1) | faster on 5.1; faster or equal on 6.1 | 5.1: 20 to 43 percent less server time, 80 to 91 percent smaller pages, browser load 27 percent faster on the new form. 6.1: up to 24 percent faster, show and bulk edit equal, browser load 10 percent faster on the new form |
| Issue pages with the very large field (S2) | equal in time on both versions (one exception on 5.1, R2); pages 19 percent larger | medians within +/- 10 percent; page +263 KB; JavaScript heap higher |
| Issue list with the large field | faster, 16 percent on both versions | the list no longer carries the mapping |
| Context menu (right click) | much faster: 39 percent (typical data) and 81 percent (large field) less on 5.1; 31 and 71 percent on 6.1 | the menu no longer contains the wizard |
| Wizard open step | slower, because it now loads when opened | R5 |
| Saving an issue (PATCH) | equal | 5.1: main 101 / branch 96 ms (typical), main 226 / branch 243 ms (large). 6.1: main 178 / branch 105 ms and main 266 / branch 269 ms |
| Parent change on the issue form | equal on typical data, faster with the large field | options painted: main 300 / branch 185 ms (5.1), main 333 / branch 177 ms (6.1) |
| Project settings page | faster or equal | ratio 0.59 and 0.80 on 5.1, 0.81 and 0.99 on 6.1 |
| Project values page | faster; with the large field from 19 s to 0.46 s | search, pagination and sort |
| Project dependency page and administration editor | main did not finish with the large field, the branch needs 0.4 to 0.8 s | new editor |
| Administration edit page with typical data | faster (main 167 / branch 69 ms on 5.1, main 94 / branch 68 ms on 6.1) | no matrix of checkboxes |
| Memory | equal | section 5.5 |
| Downloaded plugin files | larger (65.0 KB against 30.4 KB, cached after the first page) | R4 |

## 7. Behaviour side by side

This table describes what happens, from the CHANGELOG ("Unreleased (0.1.0)") and from what the measurements and the request inspections show. It explains the numbers; it is not a full list of changes.

| workflow | main (0.0.15) | branch (0.1.0) | what the numbers show |
|---|---|---|---|
| Every page of Redmine | The head hook reads the mapping of all depending fields from `Rails.cache` (building it when missing) and pastes it as `window.DependingCustomFieldData` into the head of every page, also the login page | The head carries only a small `dcf-i18n` meta tag, the plugin scripts and the stylesheet (head of about 4.8 KB). No cache, no database access | Typical pages are about 280 KB smaller; server time is 69 to 111 ms lower on 5.1 and 10 to 64 ms lower on 6.1 on the typical pages, even on the baseline page without a plugin field (main 676 / branch 517 ms on 5.1 and main 446 / branch 414 ms on 6.1) |
| New and edit issue form | The browser script filters the child options with the global mapping | Each depending field carries its own `data-dcf-*` attributes (parent, mapping, defaults); disallowed options are hidden and disabled; the last pick per parent value is remembered; hints are announced | Typical data: 43 percent less server time on 5.1. Large field: page 19 percent larger, same server time, faster interaction |
| Bulk edit | Child fields filtered with the global mapping | Own bulk attributes; "(No change)" stays available, defaults are preselected with a hint | S1 20 percent faster on 5.1, equal on 6.1; S2 equal |
| Context menu | Renders the whole wizard (every field, all options) inside every context menu response | The menu holds only the wizard entry; the wizard body is fetched when the entry is opened (a new request, with a loading text) | Menu 3 to 5 times faster with the large field. The wizard step is slower (R5) |
| Issue show and list | Mapping in the head, as on every page | No mapping unless the field is rendered | List pages 11 to 27 percent faster |
| Saving an issue | Core validation plus the format check | Stored values that no longer fit are accepted until the parent changes; a parent change is refused when a dependent field you cannot edit holds a value the new parent value does not allow | Equal in time and queries (main 42 / branch 41 and main 52 / branch 49 on 5.1) |
| Administration: dependency mapping of a field | Matrix of checkboxes, parents times children | Dependency editor with sections per parent value, search, filters, CSV import and export, conflict detection | Large field: main did not finish in 45 s (nor in 240 s on 5.1); branch 441 ms on 5.1 and 407 ms on 6.1 with an 805 KB page |
| Project settings: values of a field | One page with all values, no search, no paging | Search (more than 25 values), pagination (more than 500 values), sort A-Z and Z-A, page-scoped save | Large field: 46,633 KB and 19 s on main, 57.9 KB and 0.46 s on the branch (5.1) |
| Project settings: dependency page | Matrix, as in the administration | The same editor as in the administration, with the confirmation rule for shared fields | Large field: main did not finish, branch 833 ms (5.1) and 445 ms (6.1) with a 1.5 MB page |
| Cache | `Rails.cache` key `depending_custom_fields/mapping`, deleted on every field save | None. The key is no longer used | Nothing to invalidate; on a persistent cache store the key is deleted once before a downgrade (CHANGELOG upgrade notes) |
| REST API, imports, email | Validation as in 0.0.15 | Same JSON shape; new 422 reasons (circular parent, MySQL oversize, a parent change blocked by a field you cannot edit) | Not measured |

## 8. Regressions, with cause and proposed fix

Seven findings. R1, R3, R4 and R5 are real but small. R5 follows from a design decision. R2 and R6 are not shown to be caused by the plugin. R7 is below the threshold. Effort is for one developer including specs and JavaScript tests: small is a few hours, medium is one to two days.

### R1. Pages with the very large field are 19 percent larger

* Where: issue new, edit, show and bulk edit pages with a field of 25,000 child values, on 5.1 and 6.1, administrator and member alike.
* Numbers: response main 1,369.8 KB / branch 1,626.5 KB (issue_new_s2, 5.1; 6.1: 1,373.2 and 1,629.9 KB), a difference of 262,866 bytes. Gzipped main 197.9 KB / branch 207.9 KB (+5 percent). Server time is not affected measurably (R2 explains why the one slower median is not shown to come from this).
* Cause: `ClientData.add_parent_data` puts the mapping of the field into the select as `data-dcf-map` (`lib/redmine_depending_custom_fields/client_data.rb:129`). Rails writes the JSON in an attribute, so each of the two quotes around every value becomes `&quot;`. In a diagnostic request on 5.1 the attribute is 534,501 bytes, of which 255,000 bytes are the 51,000 `&quot;` entities; as plain JSON the same mapping is 279,501 bytes, less than the 293,746 bytes that main put in the head (for all fields). The attribute is written by `DependingFormatMethods#edit_tag` and `#bulk_edit_tag` (`lib/redmine_depending_custom_fields/depending_format_methods.rb:141-156`) and read by `config` in `assets/javascripts/depending_custom_fields.js:451-482`.
* Fix: emit the mapping as `<script type="application/json">` next to the select (escaping `<` as `<`) and read it with `textContent`. The page is then within about 8 KB of main (1,665,527 minus 255,000 is 1,410,527 bytes against 1,402,661) instead of 263 KB larger. Specs of the markup and the JavaScript tests that read `data-dcf-map` have to change.
* Effort: medium (1 day).

### R2. issue_new_s2 on Redmine 5.1 is 137 ms slower (not shown to be caused by the plugin)

* Numbers: main 708 ms / branch 846 ms (ratio 1.19; p90 762 against 914; minimum 614 against 677); view time main 618 / branch 767 ms; CPU main 620 / branch 784 ms. On Redmine 6.1 the same page is equal (main 521 / branch 510 ms, ratio 0.98).
* What the data show: SQL queries are equal (42 and 42), database time is equal (main 38 / branch 35 ms), allocations are 2.5 percent lower on the branch and constant over the series (942,000 objects in every request of the branch). The extra CPU does not come from more work. In the branch series the median CPU is 649 ms in the first 9 rounds (wall 719 ms, against main 724 ms) and 793 ms in the other 21 rounds (wall 864 ms, against main 686 ms): a step at round 10 that lasts until the end. The same effect hits main on the sibling page issue_edit_s2 on 5.1 (wall median 677 ms in the first 9 rounds, 855 ms in the other 21), where the branch is the one that was fast first (841 ms, then 717 ms). On 6.1 the effect is not visible on these pages.
* Likely cause: a process state effect on Redmine 5.1 (Ruby 3.2.6), where a request builds and sends a page of 1.4 to 1.7 MB with 25,000 options (garbage collector or allocator state), hitting either variant. One run cannot show whether the branch is more likely to end up in the slow state. By the rule the page is slower; by the cause it is not shown to be a plugin regression.
* Fix: no code change proposed yet. Repeat issue_new_s2 on 5.1 with 100 requests per variant and a fresh process per variant, three times, and add the garbage collector time (`GC.stat(:time)`) to the probe. If the branch is still slower, R1 is the first suspect (less string churn per request) and should be applied before anything else.
* Effort: small (half a day, mostly waiting for the run).

### R3. Higher JavaScript heap on pages with the very large field

* Numbers: JS heap main 4.5 MB / branch 6.8 MB (issue_new_s2, 5.1, +2.3 MB; p90 4.7 against 6.9) and main 4.6 / branch 8.9 MB on 6.1 (+4.3 MB). The edit form shows the same (+2.3 MB and +4.1 MB). On typical pages the heap is lower on the branch (main 4.1 / branch 3.5 MB on 5.1, main 4.6 / branch 4.0 MB on 6.1). Script time and load time are equal or lower.
* Cause: the runtime reads the attribute, parses it and converts it into a `Map` of `Set`s of strings for all 500 parent values (`assets/javascripts/depending_custom_fields.js:60-69`, called from `:470`), keeps the raw attribute strings of every control to compare them on later evaluations (`:452` and `:479`), and on every evaluation builds a snapshot array of the 25,001 options, an array of their values and a `Set` of the values (`:528-531` and `:821-823`). Main parsed one JSON object and no more.
* Fix: build the `Set` of a parent value when it is first used instead of for all parents, drop the raw strings from the cache (compare a length and a hash), and skip the `optionValues` set when the field is not in a state that needs it. The gain is about 2 MB. The cost is real but small next to the 180,000 DOM nodes of these pages. I recommend accepting it for 0.1.0 and putting the lazy `Set` on the list for 0.1.x.
* Effort: medium (1 to 2 days, mostly JavaScript tests).

### R4. Plugin scripts and stylesheet are twice as large on every page

* Numbers: main 30.4 KB (three files: 23,837 + 4,455 + 2,860 bytes) / branch 65.0 KB (50,613 + 13,406 + 2,587 bytes); gzipped 7.5 KB against 18.8 KB (file sizes of the exported sources, gzip level 6, not part of the results files). On pages with the dependency editor (administration, project dependency page) 185.3 KB are loaded on the branch, because the editor model, script and style come on top. The measured load time of the plugin files is equal on 4 of 5 pages (issue_new_s2 main 54 / branch 55 ms, issue_new_s1 main 46 / branch 54 ms); context_menu_s2 is the 5 repetition outlier discussed in section 5.7.
* Cause: the runtime grew from 23.8 KB to 50.6 KB (the rules, hints, memory of picks, live announcements and cycle handling) and the wizard script from 4.5 KB to 13.4 KB (it now fetches the form). The head hook loads them on every page (`lib/redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook.rb:20-22`), also on pages that have no depending field and no context menu.
* Fix: (a) load `context_menu_wizard.js` only on pages that can show a context menu (issue and time entry lists, the issue page); that is 13.4 KB raw and 4.3 KB gzipped less on all other pages; (b) serve the files through a compressing proxy, which brings the first download to 18.8 KB (administrator action, no code change); (c) minify at release time (not a standard step of Redmine plugins, so a release step would have to be added). The browser caches the files after the first page, so the cost is one download per plugin version.
* Effort: (a) small to medium (0.5 to 1 day: the hook must know the page kind, plus specs), (b) none, (c) small.

### R5. The wizard step of the context menu is slower

* Numbers (browser, medians): wizard opened main 5 ms / branch 70 ms on typical data (5.1; main 5 / branch 71 ms on 6.1); with the large field main 554 ms / branch 1,562 ms (5.1) and main 462 / branch 1,499 ms (6.1). The context menu itself is faster in the same measurement: main 236 / branch 146 ms and main 1,013 / branch 204 ms (5.1). The sum of both medians is main 241 / branch 216 ms (typical data) and main 1,568 / branch 1,766 ms (large field) on 5.1, and main 232 / branch 209 ms and main 1,382 / branch 1,715 ms on 6.1.
* Cause: by design (WP-36) the wizard body is fetched when the entry is opened: `openWizard` shows a loading text and calls `fetch` (`assets/javascripts/context_menu_wizard.js:89-132`), and the server renders it in `ContextMenuWizardController#show` (`app/controllers/context_menu_wizard_controller.rb:29-58`) with the same bulk tag as bulk edit for every field (`app/views/depending_custom_fields/_context_menu_wizard_form.html.erb:19-24`). With the large field that is the same work as the S2 bulk edit page (branch 779 ms on 5.1, a 1.6 MB response) plus parsing and initialising 25,000 options in the browser. Main paid the server part on every right click, also when nobody opened the wizard (956 ms and 1.08 MB on S2); the branch pays it only when the wizard is opened. The server bench has no row for this request, so the server part is inferred from bulk_edit_s2.
* Fix: (a) start the fetch on `mouseenter` of the wizard entry instead of on click, so that most of the server time overlaps with the mouse movement; (b) R1 reduces the payload of this request by the same 255 KB. A cache of the body is not advised, because the body depends on the user and the selected issues.
* Effort: small to medium (a: half a day).

### R6. Saving an issue with the large field on 5.1 costs about 17 ms more (below the threshold)

* Numbers: issue_update_s2 on 5.1: main 226 ms / branch 243 ms (ratio 1.07, so equal by the rule); p90 250 against 266; minimum 196 against 217; CPU 191 against 211 ms. SQL queries 42 against 41, database time 31 against 30 ms, allocations 123.6 against 123.3 thousand. On 6.1: main 266 / branch 269 ms. On S1: main 101 / branch 96 ms (5.1) and main 178 / branch 105 ms (6.1).
* Cause: not found. The work counted by the probe is equal, and the code that runs on a save (`DependingFormatMethods#validate_custom_value`, `lib/redmine_depending_custom_fields/depending_format_methods.rb:94-109`, with `DependencyRules.allowed_for` and `dependency_check`, `lib/redmine_depending_custom_fields/dependency_rules.rb:256-279`) builds sets of 50 values, nothing that explains 20 ms. The shift is consistent over the series (minimum, median and p90 all +15 to +21 ms) on 5.1 only, so it may be the same process state effect as R2, or a small cost that a profile would show.
* Fix: none proposed. Profile one PATCH of the S2 issue on 5.1 with stackprof (100 requests per variant) and decide then.
* Effort: small (half a day).

### R7. Peak memory is a few MB higher on the branch (below the threshold)

* Numbers: peak RSS after the measured rounds main 315 MB / branch 329 MB on 5.1 (+4 percent); after the mixed run main 339 / branch 345 MB (5.1) and main 394 / branch 403 MB (6.1). The median RSS at the same checkpoints is equal or lower on the branch (main 334 / branch 314 MB after the mixed run on 5.1).
* Cause: the larger pages and objects of R1 and R3 are held by the worker for a moment. Nothing to fix by itself; R1 will lower it.

## 9. What was not measured

* Concurrency. One Puma thread and sequential requests, so the figures are the cost of one request, not a capacity test. Less CPU and fewer allocations per request mean more capacity, but no throughput figure exists.
* MySQL/MariaDB (the branch adds size checks for these databases), SQLite, Redmine 6.0 and 7.0, other browsers, a reverse proxy with compression or a CDN, real network latency.
* Write paths other than saving an issue: project settings changes (rename, remove, reorder, sort, dependency save), the administration save of a field, bulk update, the wizard save, CSV import of links, REST API, issue import and email.
* The wizard body request on the server (only measured as part of the browser interaction).
* Boot time of Redmine (only the RSS after boot was measured: main 184 / branch 181 MB on 5.1, main 231 / branch 225 MB on 6.1).
* Long running behaviour such as memory growth over days. The mixed run has 300 requests.

## 10. Conclusion

For the question that matters to the owner, a slow Redmine: the plugin does not make Redmine slower. On typical data (tens of values per field) the pages that main slowed down by pasting its mapping into every page are now faster on the server (up to 43 percent on 5.1) and about 90 percent smaller, the right click menu is 31 to 39 percent faster, and the work per request (allocations) drops by a third to two thirds. With the very large lists the branch is the difference between a page that does not open at all (the administration editor, the project dependency page, the 46,633 KB values page) and a page that opens in less than a second.

The price is paid in four places that are all small: a few more downloaded KB of scripts (cached after the first page), a larger page and 2 to 4 MB more JavaScript memory when a form shows a list of tens of thousands of linked values, and a wizard that loads when it is opened instead of with every right click. The simplest improvement that removes the largest part of this is R1 (mapping in a script block instead of an attribute): about one day, it makes those pages as small as main again and shortens the wizard request. R5(a), prefetching on hover, makes the wizard feel at least as fast as before. Neither blocks the release.

One figure needs a second look before the release notes make a claim about Redmine 5.1: the new issue form with the large field (R2) was 19 percent slower on the median in this run, but the data show the same two level behaviour in main on a sibling page, and it is absent on 6.1. A repeat with 100 requests per variant will settle it.

## 11. How to repeat the measurement

The harness is in `.codex/perf/` (README there). The summary of this run is in `docs/perf/results-2026-11-05/summary.md` and `summary.json`; the raw per-request data (about 100 files per Redmine version) is not committed.

## 12. Re-measurement after WP-39 (2026-11-06)

The owner chose R1 and R5(a); WP-39 implemented both (the mapping is now a JSON script element next to the field, and the wizard body is fetched when the pointer or keyboard focus rests 150 ms on the entry). The full harness ran again on the WP-39 head (`adcda3b`, same data, same method, 30 rounds, `measure.sh 30`, 36 minutes); the summary is in `docs/perf/results-2026-11-06-wp39/`. Main was measured again in the same run, so each row compares numbers of one run; the "before" column is the branch of section 5.

Pages with the 25,000 value field (server median, response size, gzipped size):

| Page | Version | main | branch before WP-39 | branch after WP-39 |
|---|---|---|---|---|
| issue_new_s2 | 5.1 | 602 ms, 1,369.8 KB, 197.9 KB | 846 ms, 1,626.5 KB, 207.9 KB | 730 ms, 1,377.6 KB, 198.2 KB |
| issue_edit_s2 | 5.1 | 729 ms, 1,371.2 KB | 735 ms, 1,628.0 KB | 626 ms, 1,379.1 KB |
| issue_show_s2 | 5.1 | 761 ms, 1,379.0 KB | 877 ms, 1,635.8 KB | 787 ms, 1,387.0 KB |
| bulk_edit_s2 | 5.1 | 671 ms, 1,369.9 KB | 779 ms, 1,626.6 KB | 672 ms, 1,377.7 KB |
| issue_update_s2 | 5.1 | 198 ms | 243 ms | 219 ms |
| issue_new_s2 | 6.1 | 469 ms, 1,373.2 KB, 198.9 KB | 510 ms, 1,629.9 KB, 208.8 KB | 453 ms, 1,381.1 KB, 199.0 KB |
| issue_edit_s2 | 6.1 | 490 ms | 531 ms | 472 ms |
| issue_show_s2 | 6.1 | 668 ms | 762 ms | 656 ms |
| bulk_edit_s2 | 6.1 | 608 ms | 689 ms | 538 ms |
| issue_update_s2 | 6.1 | 237 ms | 269 ms | 232 ms |

Typical data (S1) stays faster than main: issue_new_s1 5.1 main 184 / branch 103 ms, 6.1 129 / 101 ms; issue_edit_s1 5.1 186 / 108 ms, 6.1 130 / 109 ms; pages 33 to 39 KB against 313 to 318 KB.

Browser, new issue form with the large field (load event, median): 5.1 main 1,850 / before 2,027 / after 1,792 ms; 6.1 main 1,811 / before 1,925 / after 1,764 ms. Parent change to child options painted, large field: 5.1 main 274 / after 171 ms, 6.1 main 310 / after 156 ms. The JavaScript heap of that page did not change with WP-39 (5.1 5.9 MB, 6.1 9.6 MB, main 4.7 to 4.8 MB; R3 was not part of WP-39).

Wizard. The harness clicks the entry without resting on it, so its wizard_ms (click to form shown) measures the path without prefetch: S2 5.1 main 501 / after 1,479 ms, 6.1 main 409 / after 1,241 ms. A separate run with the pointer resting 400 ms on the entry before the click (`browser_bench.js` with a hover step, 5 repetitions, context menu pages only, not committed) gives the realistic case:

| Context menu, 10 issues | Version | main: menu + wizard | branch: menu + wizard |
|---|---|---|---|
| S1 typical data | 5.1 | 171 + 5 = 176 ms | 107 + 10 = 117 ms |
| S1 typical data | 6.1 | 178 + 5 = 183 ms | 109 + 10 = 119 ms |
| S2 25,000 values | 5.1 | 783 + 462 = 1,245 ms | 170 + 1,032 = 1,202 ms |
| S2 25,000 values | 6.1 | 908 + 381 = 1,289 ms | 164 + 950 = 1,114 ms |

Conclusion of the re-measurement: R1 did what it promised. The pages with the large field are within 8 KB of main again (gzipped within 0.3 KB), and their server time dropped by 10 to 20 percent against the branch before WP-39. On 6.1 no server page is slower than main by the rule of section 3.5 (the largest difference is saving an issue with typical data, 88 against 83 ms, within noise). With prefetch the right click plus wizard is faster than main on typical data and equal or faster with the large field. On 5.1 three rows with the large field stay slower by that rule: the new issue form (730 against 602 ms; as administrator 763 against 585 ms; 846 against 708 ms in the first run) and saving such an issue (219 against 198 ms, 11 percent). The edit form of the same field on 5.1 is faster than main (626 against 729 ms) and 6.1 shows no such difference, so the cause is still open (R2 and R6); it only concerns fields with tens of thousands of values on Redmine 5.1.

## 13. Redmine without the plugin (2026-11-06)

The owner asked for the difference in general performance without the plugin and with the plugin, for normal amounts of fields and values. Sections 5 to 12 compare the plugin with its predecessor. This section compares it with plain Redmine, so it shows what the plugin costs on top of Redmine itself.

Method, in short:

* A third variant, `none`: a copy of the production checkout without `plugins/redmine_depending_custom_fields` (same production configuration and probe), on a database cloned from the branch database. In that clone the depending list fields became core `list` fields, the depending enumeration fields core `enumeration` fields (no extended user field exists in the S1 data), with the same possible values; issues, values and projects are unchanged and the plugin tables and settings are removed. Redmine boots, the S1 pages show all fields and saving an issue stores and restores the values (checked by the bench on all three variants). `none` shows the same fields but no filtering by a parent, no project level configuration pages and no wizard in the context menu.
* Typical data (S1: 3 projects, 300 issues, Country, City, District, Languages, Zone, Site and plain fields), the eight S1 server pages and the two S1 browser pages of the earlier runs. Main and the branch are the same builds as in section 12 (the plugin code of the branch is identical at `adcda3b` and at `8606acb`, where the run was made).
* The three variants are interleaved per page, their order rotates per round: 30 measured rounds after 5 warm-up rounds, one Puma worker with one thread per variant, Redmine 5.1 and 6.1, each block started with a one minute load average below 1.0. Browser: 10 repetitions in Chromium, same method as before. Medians; the summary is in `docs/perf/results-2026-11-06-noplugin/` (`summary.json`, `summary.md` with p90 and minimum), and the tables below were made from it by `.codex/perf/report_noplugin.js`. The pages of the plugin only features (project configuration, administration editor) have no counterpart in plain Redmine and are not part of this run.

### 13.a Redmine 5.1: server, per request (medians of 30 rounds)

Time (ms):

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | wall | 57.4 | 111.2 | 63.2 | +5.8 | +10.1 |
| issue_new_s1 | CPU | 48.0 | 99.9 | 52.8 | +4.8 | +10.0 |
| issue_new_s1 | view | 32.0 | 83.3 | 34.0 | +2.0 | +6.3 |
| issue_new_s1 | ActiveRecord | 11.8 | 11.7 | 11.8 | 0.0 | 0.0 |
| issue_edit_s1 | wall | 58.4 | 111.0 | 61.7 | +3.3 | +5.7 |
| issue_edit_s1 | CPU | 49.5 | 100.5 | 52.5 | +3.1 | +6.3 |
| issue_edit_s1 | view | 28.9 | 79.3 | 31.5 | +2.6 | +9.2 |
| issue_edit_s1 | ActiveRecord | 11.1 | 11.6 | 11.4 | +0.3 | +2.3 |
| issue_show_s1 | wall | 101.1 | 157.4 | 106.3 | +5.2 | +5.1 |
| issue_show_s1 | CPU | 79.5 | 133.3 | 84.1 | +4.5 | +5.7 |
| issue_show_s1 | view | 43.8 | 95.8 | 47.4 | +3.6 | +8.2 |
| issue_show_s1 | ActiveRecord | 26.4 | 27.2 | 27.4 | +1.0 | +3.8 |
| issue_list_s1 | wall | 114.0 | 168.1 | 117.1 | +3.1 | +2.8 |
| issue_list_s1 | CPU | 93.4 | 142.3 | 94.3 | +0.9 | +1.0 |
| issue_list_s1 | view | 54.5 | 106.8 | 56.0 | +1.5 | +2.8 |
| issue_list_s1 | ActiveRecord | 25.8 | 26.4 | 26.5 | +0.7 | +2.7 |
| bulk_edit_s1 | wall | 114.7 | 158.8 | 114.9 | +0.2 | +0.2 |
| bulk_edit_s1 | CPU | 98.9 | 144.8 | 99.9 | +1.0 | +1.1 |
| bulk_edit_s1 | view | 21.4 | 73.2 | 25.6 | +4.2 | +19.3 |
| bulk_edit_s1 | ActiveRecord | 19.6 | 19.6 | 19.9 | +0.2 | +1.0 |
| context_menu_s1 | wall | 67.3 | 99.8 | 63.2 | -4.0 | -6.0 |
| context_menu_s1 | CPU | 57.4 | 88.3 | 53.1 | -4.3 | -7.5 |
| context_menu_s1 | view | 14.0 | 37.0 | 7.8 | -6.3 | -44.6 |
| context_menu_s1 | ActiveRecord | 12.4 | 15.1 | 12.6 | +0.2 | +1.2 |
| issue_update_s1 | wall | 44.5 | 43.6 | 44.3 | -0.2 | -0.5 |
| issue_update_s1 | CPU | 36.4 | 35.6 | 36.3 | -0.1 | -0.3 |
| issue_update_s1 | view | 0.0 | 0.0 | 0.0 | 0.0 | - |
| issue_update_s1 | ActiveRecord | 9.9 | 10.1 | 9.5 | -0.4 | -4.0 |
| project_settings_s1 | wall | 48.4 | 110.7 | 60.2 | +11.8 | +24.3 |
| project_settings_s1 | CPU | 39.0 | 97.9 | 47.8 | +8.8 | +22.4 |
| project_settings_s1 | view | 25.9 | 83.8 | 33.4 | +7.5 | +29.0 |
| project_settings_s1 | ActiveRecord | 11.9 | 14.4 | 14.9 | +3.1 | +26.2 |

Work and size per request:

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | SQL queries | 40 | 41 | 40 | 0 | 0.0 |
| issue_new_s1 | allocations (objects) | 38,034 | 254,229 | 42,218 | +4,185 | +11.0 |
| issue_new_s1 | response (KB) | 26.4 | 313.1 | 33.2 | +6.8 | +25.6 |
| issue_new_s1 | gzipped (KB) | 5.9 | 64.9 | 7.3 | +1.3 | +22.2 |
| issue_edit_s1 | SQL queries | 44 | 45 | 44 | 0 | 0.0 |
| issue_edit_s1 | allocations (objects) | 39,244 | 255,391 | 43,814 | +4,570 | +11.6 |
| issue_edit_s1 | response (KB) | 27.9 | 314.4 | 35.2 | +7.3 | +26.1 |
| issue_edit_s1 | gzipped (KB) | 6.2 | 65.2 | 7.5 | +1.4 | +22.4 |
| issue_show_s1 | SQL queries | 67 | 68 | 67 | 0 | 0.0 |
| issue_show_s1 | allocations (objects) | 61,261 | 278,408 | 66,731 | +5,470 | +8.9 |
| issue_show_s1 | response (KB) | 37.6 | 324.1 | 44.9 | +7.3 | +19.5 |
| issue_show_s1 | gzipped (KB) | 8.3 | 67.4 | 9.7 | +1.4 | +16.7 |
| issue_list_s1 | SQL queries | 58 | 60 | 58 | 0 | 0.0 |
| issue_list_s1 | allocations (objects) | 87,675 | 305,450 | 90,520 | +2,845 | +3.2 |
| issue_list_s1 | response (KB) | 68.1 | 355.5 | 71.5 | +3.4 | +5.0 |
| issue_list_s1 | gzipped (KB) | 9.1 | 68.3 | 9.7 | +0.6 | +7.1 |
| bulk_edit_s1 | SQL queries | 70 | 70 | 70 | 0 | 0.0 |
| bulk_edit_s1 | allocations (objects) | 75,513 | 291,283 | 80,906 | +5,393 | +7.1 |
| bulk_edit_s1 | response (KB) | 26.7 | 312.6 | 33.2 | +6.5 | +24.5 |
| bulk_edit_s1 | gzipped (KB) | 5.4 | 64.3 | 6.7 | +1.3 | +23.7 |
| context_menu_s1 | SQL queries | 38 | 44 | 38 | 0 | 0.0 |
| context_menu_s1 | allocations (objects) | 58,856 | 156,171 | 39,396 | -19,460 | -33.1 |
| context_menu_s1 | response (KB) | 54.6 | 25.5 | 13.1 | -41.5 | -76.0 |
| context_menu_s1 | gzipped (KB) | 2.2 | 2.7 | 1.2 | -1.0 | -45.5 |
| issue_update_s1 | SQL queries | 46 | 49 | 46 | 0 | 0.0 |
| issue_update_s1 | allocations (objects) | 19,192 | 20,920 | 20,834 | +1,642 | +8.6 |
| issue_update_s1 | response (KB) | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 |
| project_settings_s1 | SQL queries | 37 | 43 | 43 | +6 | +16.2 |
| project_settings_s1 | allocations (objects) | 28,972 | 250,225 | 35,829 | +6,857 | +23.7 |
| project_settings_s1 | response (KB) | 20.5 | 312.0 | 28.1 | +7.6 | +37.1 |
| project_settings_s1 | gzipped (KB) | 4.8 | 64.1 | 5.8 | +1.0 | +20.4 |

Memory of the Puma worker, Redmine 5.1 (RSS in MB):

| checkpoint | none | main | branch | branch - none (MB) | branch - none (%) |
|---|---|---|---|---|---|
| after_boot | 180 | 183 | 181 | +1 | +0.6 |
| after_warmup | 198 | 243 | 205 | +7 | +3.7 |
| after_rounds | 198 | 254 | 208 | +9 | +4.6 |

Ruby heap_live_slots after the rounds: none 646,388, main 858,977, branch 664,945.

Browser, Redmine 5.1 (Chromium 153.0.8010.12, 10 repetitions, medians):

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | load event (ms) | 137 | 202 | 156 | +18 | +13.4 |
| issue_new_s1 | domContentLoaded (ms) | 135 | 199 | 153 | +18 | +13.3 |
| issue_new_s1 | JS heap (MB) | 3.35 | 4.08 | 3.54 | +0.18 | +5.5 |
| issue_new_s1 | script duration (ms) | 43.7 | 48.2 | 50.4 | +6.7 | +15.4 |
| issue_new_s1 | plugin script CPU profile (ms) | 0.0 | 3.5 | 4.8 | +4.8 | - |
| issue_new_s1 | plugin asset bytes (KB) | 0.0 | 30.4 | 74.4 | +74.4 | - |
| interaction_s1_country | parent change to options painted (ms) | 5.4 | 9.8 | 6.6 | +1.2 | +22.0 |
| interaction_s1_country | parent change handler (ms) | 0.4 | 1.6 | 1.5 | +1.1 | +275.0 |
| context_menu_s1 | load event (ms) | 138 | 202 | 136 | -3 | -1.9 |
| context_menu_s1 | domContentLoaded (ms) | 135 | 199 | 135 | -0 | -0.0 |
| context_menu_s1 | JS heap (MB) | 3.21 | 3.91 | 3.28 | +0.07 | +2.2 |
| context_menu_s1 | script duration (ms) | 44.6 | 46.0 | 42.7 | -1.9 | -4.3 |
| context_menu_s1 | plugin asset bytes (KB) | 0.0 | 30.4 | 74.4 | +74.4 | - |
| context_menu_s1 | right click to menu shown (ms) | 78.3 | 109.8 | 73.4 | -5.0 | -6.3 |
| context_menu_s1 | wizard opened (ms, no hover) | - | 3.0 | 35.8 | - | - |

### 13.b Redmine 6.1: server, per request (medians of 30 rounds)

Time (ms):

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | wall | 60.1 | 70.0 | 60.0 | -0.1 | -0.2 |
| issue_new_s1 | CPU | 49.7 | 61.0 | 50.3 | +0.6 | +1.2 |
| issue_new_s1 | view | 32.3 | 42.8 | 33.3 | +1.0 | +3.1 |
| issue_new_s1 | ActiveRecord | 12.3 | 11.7 | 11.6 | -0.7 | -5.3 |
| issue_edit_s1 | wall | 60.3 | 76.3 | 63.5 | +3.2 | +5.3 |
| issue_edit_s1 | CPU | 51.6 | 66.2 | 53.4 | +1.8 | +3.5 |
| issue_edit_s1 | view | 29.9 | 42.7 | 32.4 | +2.5 | +8.4 |
| issue_edit_s1 | ActiveRecord | 11.1 | 11.6 | 11.4 | +0.3 | +3.2 |
| issue_show_s1 | wall | 106.9 | 116.8 | 108.7 | +1.8 | +1.7 |
| issue_show_s1 | CPU | 85.6 | 94.8 | 87.2 | +1.6 | +1.8 |
| issue_show_s1 | view | 48.0 | 57.5 | 48.3 | +0.3 | +0.6 |
| issue_show_s1 | ActiveRecord | 25.6 | 26.3 | 26.4 | +0.8 | +2.9 |
| issue_list_s1 | wall | 119.4 | 132.1 | 117.7 | -1.7 | -1.4 |
| issue_list_s1 | CPU | 98.7 | 108.5 | 98.5 | -0.1 | -0.1 |
| issue_list_s1 | view | 59.1 | 67.7 | 58.7 | -0.5 | -0.8 |
| issue_list_s1 | ActiveRecord | 24.5 | 25.2 | 24.9 | +0.4 | +1.8 |
| bulk_edit_s1 | wall | 114.3 | 129.5 | 117.1 | +2.8 | +2.4 |
| bulk_edit_s1 | CPU | 100.6 | 113.8 | 103.5 | +2.9 | +2.9 |
| bulk_edit_s1 | view | 21.6 | 33.8 | 25.1 | +3.4 | +16.0 |
| bulk_edit_s1 | ActiveRecord | 18.1 | 19.4 | 19.3 | +1.2 | +6.6 |
| context_menu_s1 | wall | 68.9 | 105.5 | 65.2 | -3.7 | -5.4 |
| context_menu_s1 | CPU | 59.6 | 93.5 | 54.6 | -5.0 | -8.4 |
| context_menu_s1 | view | 14.8 | 38.3 | 8.1 | -6.7 | -45.1 |
| context_menu_s1 | ActiveRecord | 11.3 | 14.9 | 12.2 | +0.9 | +8.4 |
| issue_update_s1 | wall | 42.3 | 46.0 | 45.1 | +2.8 | +6.7 |
| issue_update_s1 | CPU | 35.1 | 37.4 | 37.2 | +2.1 | +6.0 |
| issue_update_s1 | view | 0.0 | 0.0 | 0.0 | 0.0 | - |
| issue_update_s1 | ActiveRecord | 9.6 | 9.9 | 9.6 | +0.1 | +1.0 |
| project_settings_s1 | wall | 51.9 | 74.4 | 61.3 | +9.3 | +18.0 |
| project_settings_s1 | CPU | 42.5 | 62.5 | 49.5 | +7.0 | +16.5 |
| project_settings_s1 | view | 29.3 | 46.6 | 34.5 | +5.2 | +17.6 |
| project_settings_s1 | ActiveRecord | 11.8 | 14.3 | 14.6 | +2.8 | +24.2 |

Work and size per request:

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | SQL queries | 41 | 42 | 41 | 0 | 0.0 |
| issue_new_s1 | allocations (objects) | 30,972 | 59,629 | 33,072 | +2,100 | +6.8 |
| issue_new_s1 | response (KB) | 29.9 | 316.5 | 36.6 | +6.7 | +22.6 |
| issue_new_s1 | gzipped (KB) | 6.7 | 65.9 | 8.0 | +1.3 | +19.7 |
| issue_edit_s1 | SQL queries | 45 | 46 | 45 | 0 | 0.0 |
| issue_edit_s1 | allocations (objects) | 32,563 | 61,202 | 34,814 | +2,251 | +6.9 |
| issue_edit_s1 | response (KB) | 31.6 | 318.1 | 38.9 | +7.3 | +23.0 |
| issue_edit_s1 | gzipped (KB) | 6.9 | 66.2 | 8.3 | +1.4 | +19.9 |
| issue_show_s1 | SQL queries | 69 | 70 | 69 | 0 | 0.0 |
| issue_show_s1 | allocations (objects) | 54,393 | 83,935 | 57,480 | +3,087 | +5.7 |
| issue_show_s1 | response (KB) | 44.7 | 331.2 | 52.0 | +7.3 | +16.3 |
| issue_show_s1 | gzipped (KB) | 9.5 | 68.9 | 10.9 | +1.4 | +14.5 |
| issue_list_s1 | SQL queries | 59 | 61 | 59 | 0 | 0.0 |
| issue_list_s1 | allocations (objects) | 70,461 | 100,412 | 72,509 | +2,048 | +2.9 |
| issue_list_s1 | response (KB) | 77.2 | 364.6 | 80.5 | +3.4 | +4.4 |
| issue_list_s1 | gzipped (KB) | 10.0 | 69.6 | 10.7 | +0.7 | +6.5 |
| bulk_edit_s1 | SQL queries | 70 | 70 | 70 | 0 | 0.0 |
| bulk_edit_s1 | allocations (objects) | 69,478 | 97,815 | 72,762 | +3,285 | +4.7 |
| bulk_edit_s1 | response (KB) | 29.4 | 315.3 | 36.0 | +6.5 | +22.1 |
| bulk_edit_s1 | gzipped (KB) | 6.1 | 65.2 | 7.4 | +1.3 | +21.3 |
| context_menu_s1 | SQL queries | 38 | 44 | 38 | 0 | 0.0 |
| context_menu_s1 | allocations (objects) | 53,393 | 150,490 | 36,566 | -16,827 | -31.5 |
| context_menu_s1 | response (KB) | 56.9 | 27.1 | 15.0 | -41.9 | -73.7 |
| context_menu_s1 | gzipped (KB) | 2.3 | 2.8 | 1.3 | -1.0 | -44.0 |
| issue_update_s1 | SQL queries | 45 | 48 | 45 | 0 | 0.0 |
| issue_update_s1 | allocations (objects) | 18,007 | 19,879 | 19,657 | +1,650 | +9.2 |
| issue_update_s1 | response (KB) | 0.0 | 0.0 | 0.0 | 0.0 | - |
| project_settings_s1 | SQL queries | 37 | 43 | 43 | +6 | +16.2 |
| project_settings_s1 | allocations (objects) | 24,384 | 58,052 | 30,354 | +5,970 | +24.5 |
| project_settings_s1 | response (KB) | 24.8 | 316.3 | 32.3 | +7.6 | +30.5 |
| project_settings_s1 | gzipped (KB) | 5.6 | 65.0 | 6.6 | +1.0 | +17.8 |

Memory of the Puma worker, Redmine 6.1 (RSS in MB):

| checkpoint | none | main | branch | branch - none (MB) | branch - none (%) |
|---|---|---|---|---|---|
| after_boot | 224 | 230 | 229 | +5 | +2.0 |
| after_warmup | 243 | 301 | 275 | +32 | +13.0 |
| after_rounds | 244 | 319 | 287 | +43 | +17.4 |

Ruby heap_live_slots after the rounds: none 648,973, main 894,355, branch 814,109.

Browser, Redmine 6.1 (Chromium 153.0.8010.12, 10 repetitions, medians):

| page | metric | none | main | branch | branch - none | branch - none (%) |
|---|---|---|---|---|---|---|
| issue_new_s1 | load event (ms) | 180 | 197 | 191 | +11 | +6.1 |
| issue_new_s1 | domContentLoaded (ms) | 175 | 194 | 188 | +13 | +7.4 |
| issue_new_s1 | JS heap (MB) | 3.78 | 4.55 | 4.00 | +0.22 | +5.8 |
| issue_new_s1 | script duration (ms) | 48.3 | 50.9 | 51.2 | +2.8 | +5.8 |
| issue_new_s1 | plugin script CPU profile (ms) | 0.0 | 3.2 | 4.6 | +4.6 | - |
| issue_new_s1 | plugin asset bytes (KB) | 0.0 | 30.4 | 74.4 | +74.4 | - |
| interaction_s1_country | parent change to options painted (ms) | 10.0 | 9.5 | 8.8 | -1.2 | -12.0 |
| interaction_s1_country | parent change handler (ms) | 0.3 | 1.6 | 1.6 | +1.3 | +433.3 |
| context_menu_s1 | load event (ms) | 160 | 175 | 157 | -4 | -2.3 |
| context_menu_s1 | domContentLoaded (ms) | 158 | 172 | 153 | -6 | -3.6 |
| context_menu_s1 | JS heap (MB) | 3.59 | 4.30 | 3.65 | +0.06 | +1.7 |
| context_menu_s1 | script duration (ms) | 45.4 | 46.8 | 47.5 | +2.2 | +4.8 |
| context_menu_s1 | plugin asset bytes (KB) | 0.0 | 30.4 | 74.4 | +74.4 | - |
| context_menu_s1 | right click to menu shown (ms) | 82.6 | 113.1 | 74.7 | -7.9 | -9.6 |
| context_menu_s1 | wizard opened (ms, no hover) | - | 3.3 | 35.5 | - | - |

### 13.c Conclusion for the owner

On normal data (a few hundred issues, a handful of depending fields) the plugin adds very little to plain Redmine:

* Showing and editing issues (new issue form, edit form, issue page, issue list, bulk edit): the plugin adds 0.2 to 5.8 ms per request on Redmine 5.1 (0.2 to 10.1 percent, on pages of 57 to 115 ms) and between minus 1.7 and plus 3.2 ms on Redmine 6.1 (minus 1.4 to plus 5.3 percent). Only the new issue form on 5.1 touches the 10 percent line of section 3.5 (5.8 ms, 10.1 percent), and its p90 shows large outliers in that series, so it does not stand out from noise. For comparison, the released plugin (main) added 44 to 56 ms on these five pages on 5.1 and 10 to 16 ms on 6.1.
* Saving an issue costs nothing noticeable: 44.3 against 44.5 ms on 5.1 and 45.1 against 42.3 ms on 6.1 (2.8 ms). The number of SQL queries is identical to plain Redmine on these pages and on the context menu (main used 1 to 6 more); only the project settings page has more (below).
* The project settings page costs more: 11.8 ms (24 percent) on 5.1 and 9.3 ms (18 percent) on 6.1, against 48 and 52 ms. That page now carries the plugin's own part (the configuration tab, 6 more SQL queries, 7.6 KB more HTML), so the difference is the price of the feature, and it is a page that is rarely opened.
* The right click context menu is faster with the plugin than in plain Redmine (63.2 against 67.3 ms on 5.1, 65.2 against 68.9 ms on 6.1; the response is 13.1 against 54.6 KB on 5.1), and its response is much smaller: without the plugin Redmine puts a submenu with all values of each list field into the menu (the `none` response holds 131 `custom_field_values` links; a check of the `none` page on 5.1, not part of the measured series), the plugin replaces these entries for its fields by one wizard entry.
* Size on the wire: the issue forms, issue page and bulk edit are 6.5 to 7.3 KB larger (gzipped 1.3 to 1.4 KB) on top of 26 to 45 KB, the list 3.4 KB. The plugin's scripts and stylesheet are 74.4 KB that plain Redmine does not load; the browser fetches them once and then caches them.
* In the browser the new issue form loads 18 ms slower on 5.1 (156 against 137 ms) and 11 ms slower on 6.1 (191 against 180 ms); the page with the context menu loads as fast or faster (136 against 138 ms and 157 against 160 ms). The plugin's own scripts need 4.6 to 4.8 ms of CPU per page load, the JavaScript heap is 0.2 MB higher, and a change of a parent field is handled and painted in 6.6 ms (5.1) and 8.8 ms (6.1) including the filtering of the child options.
* Memory of the Puma worker: right after boot the plugin adds 1 MB (5.1) and 5 MB (6.1); after the rounds 9 MB (4.6 percent, 208 against 198 MB) on 5.1 and 43 MB (17.4 percent, 287 against 244 MB) on 6.1. The released plugin needed 254 and 319 MB there, so the branch uses less than main, but on 6.1 it is a visible step above plain Redmine. It is one measurement of one worker per variant, which is how the memory of the earlier sections was measured too; the size of the step on 6.1 has not been traced to a cause.

In plain words: on normal data the plugin is almost free for the people who work with issues, a few milliseconds per page on a page that takes 60 to 120 ms, with the same number of database queries as Redmine, and it makes the context menu faster. What it costs is a little more data per page, 74 KB of scripts downloaded once, and more memory per Puma worker (about 10 MB on 5.1, about 40 MB on 6.1). The one page that clearly takes longer is the project settings page, because it has the plugin's configuration on it.

What was not measured here: the data sets with the very large field (S2 and the baseline), where the plugin has the most to do and section 12 holds the comparison with main; the plugin only pages; Redmine 7.0; several workers or users at the same time; a mixed run of many requests; cold start of the first request. `none` renders the child fields as plain lists, so the differences above contain the cost of the mapping and the dependency behaviour together with the cost of loading the plugin, which is what an administrator sees when installing it.

To repeat: `.codex/perf/build_none.sh`, then `measure.sh 30` with `BENCH_VARIANTS=none,main,branch` (README of `.codex/perf`, section "Redmine without the plugin"). The run took 5 minutes (about 1.7 minutes of server bench and 0.8 minutes of browser bench per Redmine version).
