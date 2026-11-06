# Performance summary: main (0.0.15) versus branch versus Redmine without the plugin (none)

Generated 2026-11-06T07:09:00.521Z. Cells: median / p90 / min. Delta = branch median minus main median, ratio = branch median / main median (below 1 means the branch is faster or smaller). Branch - none is the branch median minus the median of Redmine without the plugin (ms or the unit of the table, and percent of none).

## Redmine 5.1

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 0, 1.7 min, load average at start 0.45.

### Memory (puma worker, 1 thread)

| checkpoint | none RSS (MB) | main RSS (MB) | branch RSS (MB) | none peak RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | none heap_live_slots | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|---|---|---|
| after_boot | 180 | 183 | 181 | - | - | - | - | - | - |
| after_warmup | 198 | 243 | 205 | 198 | 243 | 205 | 655,872 | 859,895 | 667,891 |
| after_rounds | 198 | 254 | 208 | 198 | 254 | 208 | 646,388 | 858,977 | 664,945 |
| after_mixed | 198 | 254 | 208 | 198 | 254 | 208 | 646,388 | 858,977 | 664,945 |
| after_heavy | 198 | 254 | 208 | 198 | 254 | 208 | 646,388 | 858,977 | 664,945 |

Update check (PATCH stores the new values, reset restores them): {"none":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 115 / 185 / 105 | 159 / 193 / 145 | 115 / 133 / 108 | -44 | 0.72 | 0 | 0.2 | 30/30/30 |  |
| context_menu_s1 | 67 / 87 / 60 | 100 / 110 / 94 | 63 / 123 / 56 | -37 | 0.63 | -4 | -6 | 30/30/30 |  |
| issue_edit_s1 | 58 / 64 / 53 | 111 / 118 / 103 | 62 / 68 / 54 | -49 | 0.56 | 3 | 5.7 | 30/30/30 |  |
| issue_list_s1 | 114 / 126 / 103 | 168 / 193 / 154 | 117 / 125 / 105 | -51 | 0.70 | 3 | 2.8 | 30/30/30 |  |
| issue_new_s1 | 57 / 67 / 51 | 111 / 116 / 99 | 63 / 133 / 54 | -48 | 0.57 | 6 | 10.1 | 30/30/30 |  |
| issue_show_s1 | 101 / 120 / 89 | 157 / 180 / 148 | 106 / 123 / 99 | -51 | 0.67 | 5 | 5.1 | 30/30/30 |  |
| issue_update_s1 | 44 / 91 / 38 | 44 / 55 / 40 | 44 / 56 / 38 | 1 | 1.02 | 0 | -0.5 | 30/30/30 |  |
| project_settings_s1 | 48 / 51 / 43 | 111 / 117 / 99 | 60 / 77 / 53 | -51 | 0.54 | 12 | 24.3 | 30/30/30 |  |

#### Process CPU time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 99 / 171 / 90 | 145 / 175 / 132 | 100 / 113 / 96 | -45 | 0.69 | 1 | 1.1 | 30/30/30 |  |
| context_menu_s1 | 57 / 66 / 51 | 88 / 96 / 84 | 53 / 109 / 47 | -35 | 0.60 | -4 | -7.5 | 30/30/30 |  |
| issue_edit_s1 | 49 / 54 / 45 | 101 / 105 / 94 | 53 / 58 / 46 | -48 | 0.52 | 3 | 6.3 | 30/30/30 |  |
| issue_list_s1 | 93 / 97 / 82 | 142 / 171 / 133 | 94 / 100 / 85 | -48 | 0.66 | 1 | 1 | 30/30/30 |  |
| issue_new_s1 | 48 / 53 / 41 | 100 / 104 / 91 | 53 / 124 / 46 | -47 | 0.53 | 5 | 10 | 30/30/30 |  |
| issue_show_s1 | 80 / 86 / 70 | 133 / 147 / 126 | 84 / 93 / 79 | -49 | 0.63 | 5 | 5.7 | 30/30/30 |  |
| issue_update_s1 | 36 / 83 / 31 | 36 / 39 / 33 | 36 / 44 / 32 | 1 | 1.02 | 0 | -0.3 | 30/30/30 |  |
| project_settings_s1 | 39 / 42 / 35 | 98 / 102 / 88 | 48 / 65 / 43 | -50 | 0.49 | 9 | 22.4 | 30/30/30 |  |

#### View time (ms), Rails Completed line

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 21 / 93 / 19 | 73 / 84 / 67 | 26 / 30 / 23 | -48 | 0.35 | 4 | 19.3 | 30/30/30 |  |
| context_menu_s1 | 14 / 16 / 11 | 37 / 39 / 33 | 8 / 30 / 6 | -29 | 0.21 | -6 | -44.6 | 30/30/30 |  |
| issue_edit_s1 | 29 / 33 / 26 | 79 / 88 / 73 | 32 / 35 / 28 | -48 | 0.40 | 3 | 9.2 | 30/30/30 |  |
| issue_list_s1 | 55 / 59 / 46 | 107 / 135 / 95 | 56 / 61 / 50 | -51 | 0.52 | 2 | 2.8 | 30/30/30 |  |
| issue_new_s1 | 32 / 35 / 27 | 83 / 86 / 75 | 34 / 90 / 31 | -49 | 0.41 | 2 | 6.3 | 30/30/30 |  |
| issue_show_s1 | 44 / 47 / 37 | 96 / 117 / 91 | 47 / 52 / 43 | -48 | 0.49 | 4 | 8.2 | 30/30/30 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 30/30/30 |  |
| project_settings_s1 | 26 / 29 / 23 | 84 / 91 / 75 | 33 / 49 / 29 | -50 | 0.40 | 8 | 29 | 30/30/30 |  |

#### ActiveRecord time (ms), Rails Completed line

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 20 / 22 / 18 | 20 / 27 / 17 | 20 / 24 / 17 | 0 | 1.02 | 0 | 1 | 30/30/30 |  |
| context_menu_s1 | 12 / 14 / 10 | 15 / 19 / 13 | 13 / 17 / 11 | -2 | 0.84 | 0 | 1.2 | 30/30/30 |  |
| issue_edit_s1 | 11 / 12 / 10 | 12 / 12 / 10 | 11 / 14 / 10 | 0 | 0.98 | 0 | 2.3 | 30/30/30 |  |
| issue_list_s1 | 26 / 28 / 24 | 26 / 31 / 25 | 27 / 31 / 24 | 0 | 1.01 | 1 | 2.7 | 30/30/30 |  |
| issue_new_s1 | 12 / 15 / 10 | 12 / 13 / 10 | 12 / 15 / 11 | 0 | 1.01 | 0 | 0 | 30/30/30 |  |
| issue_show_s1 | 26 / 28 / 24 | 27 / 31 / 24 | 27 / 32 / 25 | 0 | 1.01 | 1 | 3.8 | 30/30/30 |  |
| issue_update_s1 | 10 / 13 / 9 | 10 / 12 / 9 | 10 / 15 / 8 | -1 | 0.95 | 0 | -4 | 30/30/30 |  |
| project_settings_s1 | 12 / 13 / 10 | 14 / 16 / 13 | 15 / 19 / 13 | 1 | 1.03 | 3 | 26.2 | 30/30/30 |  |

#### Allocations (Rails Completed line)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 75,513 / 75,519 / 75,508 | 291,283 / 291,667 / 291,200 | 80,906 / 80,906 / 80,895 | -210,377 | 0.28 | 5,393 | 7.1 | 30/30/30 |  |
| context_menu_s1 | 58,856 / 58,856 / 58,851 | 156,171 / 156,935 / 155,961 | 39,396 / 39,396 / 39,391 | -116,774 | 0.25 | -19,460 | -33.1 | 30/30/30 |  |
| issue_edit_s1 | 39,244 / 39,255 / 39,240 | 255,391 / 255,671 / 255,305 | 43,814 / 43,822 / 43,808 | -211,577 | 0.17 | 4,570 | 11.6 | 30/30/30 |  |
| issue_list_s1 | 87,675 / 87,683 / 87,670 | 305,450 / 305,836 / 305,354 | 90,520 / 90,524 / 90,507 | -214,930 | 0.30 | 2,845 | 3.2 | 30/30/30 |  |
| issue_new_s1 | 38,034 / 38,037 / 38,031 | 254,229 / 254,610 / 254,131 | 42,218 / 42,219 / 42,213 | -212,010 | 0.17 | 4,185 | 11 | 30/30/30 |  |
| issue_show_s1 | 61,261 / 61,269 / 61,250 | 278,408 / 278,773 / 278,316 | 66,731 / 66,733 / 66,722 | -211,676 | 0.24 | 5,470 | 8.9 | 30/30/30 |  |
| issue_update_s1 | 19,192 / 19,197 / 19,192 | 20,920 / 20,920 / 20,920 | 20,834 / 20,837 / 20,832 | -86 | 1.00 | 1,642 | 8.6 | 30/30/30 |  |
| project_settings_s1 | 28,972 / 28,977 / 28,972 | 250,225 / 250,398 / 250,173 | 35,829 / 35,834 / 35,829 | -214,396 | 0.14 | 6,857 | 23.7 | 30/30/30 |  |

#### SQL queries (without SCHEMA and CACHE)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 70 / 70 / 70 | 70 / 70 / 70 | 70 / 70 / 70 | 0 | 1.00 | 0 | 0 | 30/30/30 |  |
| context_menu_s1 | 38 / 38 / 38 | 44 / 44 / 44 | 38 / 38 / 38 | -6 | 0.86 | 0 | 0 | 30/30/30 |  |
| issue_edit_s1 | 44 / 44 / 44 | 45 / 45 / 45 | 44 / 44 / 44 | -1 | 0.98 | 0 | 0 | 30/30/30 |  |
| issue_list_s1 | 58 / 58 / 58 | 60 / 60 / 60 | 58 / 58 / 58 | -2 | 0.97 | 0 | 0 | 30/30/30 |  |
| issue_new_s1 | 40 / 40 / 40 | 41 / 41 / 41 | 40 / 40 / 40 | -1 | 0.98 | 0 | 0 | 30/30/30 |  |
| issue_show_s1 | 67 / 67 / 67 | 68 / 68 / 68 | 67 / 67 / 67 | -1 | 0.99 | 0 | 0 | 30/30/30 |  |
| issue_update_s1 | 46 / 46 / 46 | 49 / 49 / 49 | 46 / 46 / 46 | -3 | 0.94 | 0 | 0 | 30/30/30 |  |
| project_settings_s1 | 37 / 37 / 37 | 43 / 43 / 43 | 43 / 43 / 43 | 0 | 1.00 | 6 | 16.2 | 30/30/30 |  |

#### Response bytes

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 27,295 / 27,295 / 27,295 | 320,086 / 320,086 / 320,086 | 33,989 / 33,989 / 33,989 | -286,097 | 0.11 | 6,694 | 24.5 | 30/30/30 |  |
| context_menu_s1 | 55,868 / 55,868 / 55,868 | 26,121 / 26,121 / 26,121 | 13,420 / 13,420 / 13,420 | -12,701 | 0.51 | -42,448 | -76 | 30/30/30 |  |
| issue_edit_s1 | 28,572 / 28,572 / 28,572 | 321,933 / 321,933 / 321,933 | 36,035 / 36,035 / 36,035 | -285,898 | 0.11 | 7,463 | 26.1 | 30/30/30 |  |
| issue_list_s1 | 69,712 / 69,712 / 69,712 | 364,068 / 364,068 / 364,068 | 73,196 / 73,196 / 73,196 | -290,872 | 0.20 | 3,484 | 5 | 30/30/30 |  |
| issue_new_s1 | 27,024 / 27,024 / 27,024 | 320,575 / 320,575 / 320,575 | 33,952 / 33,952 / 33,952 | -286,623 | 0.11 | 6,928 | 25.6 | 30/30/30 |  |
| issue_show_s1 | 38,514 / 38,514 / 38,514 | 331,915 / 331,915 / 331,915 | 46,017 / 46,017 / 46,017 | -285,898 | 0.14 | 7,503 | 19.5 | 30/30/30 |  |
| issue_update_s1 | 96 / 96 / 96 | 96 / 96 / 96 | 96 / 96 / 96 | 0 | 1.00 | 0 | 0 | 30/30/30 |  |
| project_settings_s1 | 20,966 / 20,966 / 20,966 | 319,471 / 319,471 / 319,471 | 28,734 / 28,734 / 28,734 | -290,737 | 0.09 | 7,768 | 37.1 | 30/30/30 |  |

#### Response bytes gzipped

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 5,557 / 5,560 / 5,554 | 65,830 / 65,834 / 65,820 | 6,874 / 6,879 / 6,866 | -58,956 | 0.10 | 1,317 | 23.7 | 30/30/30 |  |
| context_menu_s1 | 2,255 / 2,255 / 2,255 | 2,786 / 2,790 / 2,782 | 1,228 / 1,228 / 1,228 | -1,558 | 0.44 | -1,027 | -45.5 | 30/30/30 |  |
| issue_edit_s1 | 6,310 / 6,313 / 6,306 | 66,727 / 66,732 / 66,719 | 7,723 / 7,727 / 7,717 | -59,004 | 0.12 | 1,413 | 22.4 | 30/30/30 |  |
| issue_list_s1 | 9,306 / 9,309 / 9,298 | 69,929 / 69,935 / 69,917 | 9,970 / 9,974 / 9,964 | -59,959 | 0.14 | 664 | 7.1 | 30/30/30 |  |
| issue_new_s1 | 6,084 / 6,087 / 6,077 | 66,502 / 66,507 / 66,493 | 7,436 / 7,440 / 7,432 | -59,066 | 0.11 | 1,352 | 22.2 | 30/30/30 |  |
| issue_show_s1 | 8,513 / 8,517 / 8,506 | 69,031 / 69,037 / 69,022 | 9,932 / 9,936 / 9,923 | -59,099 | 0.14 | 1,419 | 16.7 | 30/30/30 |  |
| project_settings_s1 | 4,922 / 4,926 / 4,916 | 65,588 / 65,592 / 65,577 | 5,927 / 5,930 / 5,922 | -59,661 | 0.09 | 1,005 | 20.4 | 30/30/30 |  |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 0.7 min.

#### domContentLoaded (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 135 / 147 / 110 | 199 / 213 / 185 | 135 / 144 / 132 | -63 | 0.68 | 0 | 0 | 10/10/10 |  |
| issue_new_s1 | 135 / 146 / 105 | 199 / 216 / 188 | 153 / 159 / 140 | -46 | 0.77 | 18 | 13.3 | 10/10/10 |  |

#### load event (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 138 / 148 / 123 | 202 / 214 / 185 | 136 / 144 / 132 | -67 | 0.67 | -3 | -1.9 | 10/10/10 |  |
| issue_new_s1 | 137 / 147 / 128 | 202 / 219 / 190 | 156 / 161 / 143 | -46 | 0.77 | 18 | 13.4 | 10/10/10 |  |

#### time to first byte (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 67 / 76 / 62 | 116 / 124 / 109 | 68 / 69 / 65 | -48 | 0.59 | 0 | 0.6 | 10/10/10 |  |
| issue_new_s1 | 57 / 61 / 54 | 106 / 114 / 104 | 62 / 70 / 58 | -44 | 0.59 | 5 | 8.7 | 10/10/10 |  |

#### JSHeapUsedSize (MB)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 3.2 / 3.2 / 3.2 | 3.9 / 3.9 / 3.9 | 3.3 / 3.3 / 3.3 | -0.6 | 0.84 | 0.1 | 2.2 | 10/10/10 |  |
| issue_new_s1 | 3.4 / 3.4 / 3.3 | 4.1 / 4.1 / 4.1 | 3.5 / 3.5 / 3.5 | -0.5 | 0.87 | 0.2 | 5.5 | 10/10/10 |  |

#### ScriptDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 45 / 49 / 39 | 46 / 50 / 42 | 43 / 48 / 41 | -3 | 0.93 | -2 | -4.3 | 10/10/10 |  |
| issue_new_s1 | 44 / 48 / 41 | 48 / 50 / 45 | 50 / 52 / 46 | 2 | 1.05 | 7 | 15.4 | 10/10/10 |  |

#### TaskDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 82 / 93 / 70 | 97 / 105 / 90 | 82 / 87 / 78 | -14 | 0.85 | 0 | -0.3 | 10/10/10 |  |
| issue_new_s1 | 92 / 96 / 86 | 113 / 119 / 101 | 105 / 111 / 98 | -8 | 0.93 | 13 | 14.2 | 10/10/10 |  |

#### LayoutDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 8 / 10 / 7 | 8 / 9 / 7 | 8 / 8 / 7 | 0 | 1.01 | 0 | -4.2 | 10/10/10 |  |
| issue_new_s1 | 8 / 9 / 7 | 9 / 13 / 8 | 10 / 11 / 9 | 0 | 1.04 | 1 | 15.7 | 10/10/10 |  |

#### RecalcStyleDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 6 / 7 / 6 | 6 / 8 / 6 | 6 / 7 / 6 | 0 | 0.97 | 0 | -4.7 | 10/10/10 |  |
| issue_new_s1 | 10 / 11 / 9 | 11 / 11 / 10 | 10 / 12 / 10 | -1 | 0.94 | 0 | 1.1 | 10/10/10 |  |

#### DOM nodes

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 2,130 / 2,131 / 2,130 | 2,137 / 2,137 / 2,137 | 2,135 / 2,135 / 2,135 | -2 | 1.00 | 5 | 0.2 | 10/10/10 |  |
| issue_new_s1 | 2,175 / 2,175 / 2,175 | 2,201 / 2,201 / 2,201 | 2,211 / 2,211 / 2,211 | 10 | 1.00 | 36 | 1.7 | 10/10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 0 / 0 / 0 | 3 / 4 / 3 | 5 / 5 / 4 | 1 | 1.38 | 5 | - | 10/10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 74.4 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 74.4 | - | 10/10/10 |  |

#### Plugin asset load time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 16 / 25 / 13 | 17 / 20 / 14 | 1 | 1.08 | 17 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 20 / 27 / 15 | 21 / 28 / 16 | 1 | 1.04 | 21 | - | 10/10/10 |  |

#### Context menu shown (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 78 / 88 / 72 | 110 / 120 / 105 | 73 / 77 / 70 | -36 | 0.67 | -5 | -6.3 | 10/10/10 |  |

#### Wizard opened (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | - | 3 / 3 / 3 | 36 / 38 / 31 | 33 | 11.75 | - | - | 10/10/10 |  |

#### Interaction: change handler returns (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| interaction_s1_country | 0 / 0 / 0 | 2 / 2 / 1 | 2 / 2 / 1 | 0 | 0.94 | 1 | 275 | 10/10/10 |  |

#### Interaction: options shown and painted (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| interaction_s1_country | 5 / 10 / 3 | 10 / 17 / 5 | 7 / 11 / 4 | -3 | 0.68 | 1 | 22 | 10/10/10 |  |

#### js_errors

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 10/10/10 |  |

## Redmine 6.1

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 0, 1.6 min, load average at start 0.83.

### Memory (puma worker, 1 thread)

| checkpoint | none RSS (MB) | main RSS (MB) | branch RSS (MB) | none peak RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | none heap_live_slots | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|---|---|---|
| after_boot | 224 | 230 | 229 | - | - | - | - | - | - |
| after_warmup | 243 | 301 | 275 | 243 | 301 | 275 | 647,301 | 824,922 | 798,260 |
| after_rounds | 244 | 319 | 287 | 244 | 319 | 287 | 648,973 | 894,355 | 814,109 |
| after_mixed | 244 | 319 | 287 | 244 | 319 | 287 | 648,973 | 894,355 | 814,109 |
| after_heavy | 244 | 319 | 287 | 244 | 319 | 287 | 648,973 | 894,355 | 814,109 |

Update check (PATCH stores the new values, reset restores them): {"none":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 114 / 213 / 106 | 130 / 141 / 116 | 117 / 129 / 103 | -12 | 0.90 | 3 | 2.4 | 30/30/30 |  |
| context_menu_s1 | 69 / 75 / 64 | 106 / 115 / 93 | 65 / 72 / 55 | -40 | 0.62 | -4 | -5.4 | 30/30/30 |  |
| issue_edit_s1 | 60 / 71 / 55 | 76 / 85 / 64 | 64 / 70 / 56 | -13 | 0.83 | 3 | 5.3 | 30/30/30 |  |
| issue_list_s1 | 119 / 131 / 109 | 132 / 151 / 119 | 118 / 131 / 111 | -14 | 0.89 | -2 | -1.4 | 30/30/30 |  |
| issue_new_s1 | 60 / 67 / 51 | 70 / 78 / 65 | 60 / 67 / 51 | -10 | 0.86 | 0 | -0.2 | 30/30/30 |  |
| issue_show_s1 | 107 / 115 / 94 | 117 / 127 / 104 | 109 / 126 / 100 | -8 | 0.93 | 2 | 1.7 | 30/30/30 |  |
| issue_update_s1 | 42 / 52 / 39 | 46 / 54 / 41 | 45 / 56 / 40 | -1 | 0.98 | 3 | 6.7 | 30/30/30 |  |
| project_settings_s1 | 52 / 65 / 46 | 74 / 80 / 66 | 61 / 68 / 55 | -13 | 0.82 | 9 | 18 | 30/30/30 |  |

#### Process CPU time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 101 / 185 / 95 | 114 / 120 / 104 | 104 / 111 / 91 | -10 | 0.91 | 3 | 2.9 | 30/30/30 |  |
| context_menu_s1 | 60 / 63 / 56 | 93 / 99 / 82 | 55 / 58 / 47 | -39 | 0.58 | -5 | -8.4 | 30/30/30 |  |
| issue_edit_s1 | 52 / 57 / 48 | 66 / 73 / 56 | 53 / 58 / 48 | -13 | 0.81 | 2 | 3.5 | 30/30/30 |  |
| issue_list_s1 | 99 / 105 / 92 | 109 / 125 / 99 | 99 / 105 / 88 | -10 | 0.91 | 0 | -0.1 | 30/30/30 |  |
| issue_new_s1 | 50 / 53 / 43 | 61 / 66 / 56 | 50 / 55 / 43 | -11 | 0.83 | 1 | 1.2 | 30/30/30 |  |
| issue_show_s1 | 86 / 92 / 76 | 95 / 102 / 86 | 87 / 96 / 80 | -8 | 0.92 | 2 | 1.8 | 30/30/30 |  |
| issue_update_s1 | 35 / 41 / 31 | 37 / 43 / 34 | 37 / 43 / 33 | 0 | 1.00 | 2 | 6 | 30/30/30 |  |
| project_settings_s1 | 43 / 48 / 38 | 63 / 67 / 56 | 50 / 54 / 45 | -13 | 0.79 | 7 | 16.5 | 30/30/30 |  |

#### View time (ms), Rails Completed line

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 22 / 24 / 20 | 34 / 39 / 29 | 25 / 30 / 21 | -9 | 0.74 | 3 | 16 | 30/30/30 |  |
| context_menu_s1 | 15 / 17 / 13 | 38 / 46 / 33 | 8 / 9 / 7 | -30 | 0.21 | -7 | -45.1 | 30/30/30 |  |
| issue_edit_s1 | 30 / 34 / 27 | 43 / 46 / 36 | 32 / 35 / 28 | -10 | 0.76 | 3 | 8.4 | 30/30/30 |  |
| issue_list_s1 | 59 / 69 / 54 | 68 / 81 / 60 | 59 / 63 / 51 | -9 | 0.87 | 0 | -0.8 | 30/30/30 |  |
| issue_new_s1 | 32 / 36 / 28 | 43 / 47 / 39 | 33 / 36 / 29 | -9 | 0.78 | 1 | 3.1 | 30/30/30 |  |
| issue_show_s1 | 48 / 52 / 41 | 58 / 61 / 50 | 48 / 56 / 43 | -9 | 0.84 | 0 | 0.6 | 30/30/30 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 30/30/30 |  |
| project_settings_s1 | 29 / 35 / 25 | 47 / 51 / 41 | 34 / 38 / 31 | -12 | 0.74 | 5 | 17.6 | 30/30/30 |  |

#### ActiveRecord time (ms), Rails Completed line

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 18 / 23 / 16 | 19 / 26 / 17 | 19 / 23 / 17 | 0 | 1.00 | 1 | 6.6 | 30/30/30 |  |
| context_menu_s1 | 11 / 14 / 10 | 15 / 19 / 13 | 12 / 16 / 11 | -3 | 0.82 | 1 | 8.4 | 30/30/30 |  |
| issue_edit_s1 | 11 / 14 / 10 | 12 / 16 / 10 | 11 / 15 / 10 | 0 | 0.98 | 0 | 3.2 | 30/30/30 |  |
| issue_list_s1 | 25 / 28 / 22 | 25 / 31 / 22 | 25 / 31 / 22 | 0 | 0.99 | 0 | 1.8 | 30/30/30 |  |
| issue_new_s1 | 12 / 16 / 10 | 12 / 16 / 11 | 12 / 13 / 10 | 0 | 0.99 | -1 | -5.3 | 30/30/30 |  |
| issue_show_s1 | 26 / 28 / 23 | 26 / 32 / 23 | 26 / 34 / 23 | 0 | 1.00 | 1 | 2.9 | 30/30/30 |  |
| issue_update_s1 | 10 / 14 / 8 | 10 / 14 / 9 | 10 / 14 / 8 | 0 | 0.97 | 0 | 1 | 30/30/30 |  |
| project_settings_s1 | 12 / 15 / 10 | 14 / 18 / 12 | 15 / 19 / 13 | 0 | 1.02 | 3 | 24.2 | 30/30/30 |  |

#### Allocations (Rails Completed line)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 69,478 / 69,483 / 69,477 | 97,815 / 97,817 / 97,809 | 72,762 / 72,764 / 72,758 | -25,053 | 0.74 | 3,285 | 4.7 | 30/30/30 |  |
| context_menu_s1 | 53,393 / 53,395 / 53,391 | 150,490 / 150,492 / 150,485 | 36,566 / 36,571 / 36,564 | -113,924 | 0.24 | -16,827 | -31.5 | 30/30/30 |  |
| issue_edit_s1 | 32,563 / 32,567 / 32,558 | 61,202 / 61,218 / 61,199 | 34,814 / 34,827 / 34,810 | -26,388 | 0.57 | 2,251 | 6.9 | 30/30/30 |  |
| issue_list_s1 | 70,461 / 70,472 / 70,460 | 100,412 / 100,425 / 100,406 | 72,509 / 72,520 / 72,504 | -27,902 | 0.72 | 2,048 | 2.9 | 30/30/30 |  |
| issue_new_s1 | 30,972 / 30,978 / 30,971 | 59,629 / 59,635 / 59,623 | 33,072 / 33,082 / 33,069 | -26,557 | 0.55 | 2,100 | 6.8 | 30/30/30 |  |
| issue_show_s1 | 54,393 / 54,411 / 54,382 | 83,935 / 83,949 / 83,931 | 57,480 / 57,491 / 57,471 | -26,455 | 0.68 | 3,087 | 5.7 | 30/30/30 |  |
| issue_update_s1 | 18,007 / 18,010 / 18,003 | 19,879 / 19,882 / 19,878 | 19,657 / 19,660 / 19,655 | -223 | 0.99 | 1,650 | 9.2 | 30/30/30 |  |
| project_settings_s1 | 24,384 / 24,384 / 24,383 | 58,052 / 58,057 / 58,051 | 30,354 / 30,358 / 30,352 | -27,698 | 0.52 | 5,970 | 24.5 | 30/30/30 |  |

#### SQL queries (without SCHEMA and CACHE)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 70 / 70 / 70 | 70 / 70 / 70 | 70 / 70 / 70 | 0 | 1.00 | 0 | 0 | 30/30/30 |  |
| context_menu_s1 | 38 / 38 / 38 | 44 / 44 / 44 | 38 / 38 / 38 | -6 | 0.86 | 0 | 0 | 30/30/30 |  |
| issue_edit_s1 | 45 / 45 / 45 | 46 / 46 / 46 | 45 / 45 / 45 | -1 | 0.98 | 0 | 0 | 30/30/30 |  |
| issue_list_s1 | 59 / 59 / 59 | 61 / 61 / 61 | 59 / 59 / 59 | -2 | 0.97 | 0 | 0 | 30/30/30 |  |
| issue_new_s1 | 41 / 41 / 41 | 42 / 42 / 42 | 41 / 41 / 41 | -1 | 0.98 | 0 | 0 | 30/30/30 |  |
| issue_show_s1 | 69 / 69 / 69 | 70 / 70 / 70 | 69 / 69 / 69 | -1 | 0.99 | 0 | 0 | 30/30/30 |  |
| issue_update_s1 | 45 / 45 / 45 | 48 / 48 / 48 | 45 / 45 / 45 | -3 | 0.94 | 0 | 0 | 30/30/30 |  |
| project_settings_s1 | 37 / 37 / 37 | 43 / 43 / 43 | 43 / 43 / 43 | 0 | 1.00 | 6 | 16.2 | 30/30/30 |  |

#### Response bytes

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 30,143 / 30,143 / 30,143 | 322,913 / 322,913 / 322,913 | 36,816 / 36,816 / 36,816 | -286,097 | 0.11 | 6,673 | 22.1 | 30/30/30 |  |
| context_menu_s1 | 58,300 / 58,300 / 58,300 | 27,744 / 27,744 / 27,744 | 15,355 / 15,355 / 15,355 | -12,389 | 0.55 | -42,945 | -73.7 | 30/30/30 |  |
| issue_edit_s1 | 32,395 / 32,395 / 32,395 | 325,735 / 325,735 / 325,735 | 39,837 / 39,837 / 39,837 | -285,898 | 0.12 | 7,442 | 23 | 30/30/30 |  |
| issue_list_s1 | 79,011 / 79,011 / 79,011 | 373,346 / 373,346 / 373,346 | 82,474 / 82,474 / 82,474 | -290,872 | 0.22 | 3,463 | 4.4 | 30/30/30 |  |
| issue_new_s1 | 30,586 / 30,586 / 30,586 | 324,116 / 324,116 / 324,116 | 37,493 / 37,493 / 37,493 | -286,623 | 0.12 | 6,907 | 22.6 | 30/30/30 |  |
| issue_show_s1 | 45,799 / 45,799 / 45,799 | 339,179 / 339,179 / 339,179 | 53,281 / 53,281 / 53,281 | -285,898 | 0.16 | 7,482 | 16.3 | 30/30/30 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 30/30/30 |  |
| project_settings_s1 | 25,371 / 25,371 / 25,371 | 323,855 / 323,855 / 323,855 | 33,111 / 33,111 / 33,111 | -290,744 | 0.10 | 7,740 | 30.5 | 30/30/30 |  |

#### Response bytes gzipped

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| bulk_edit_s1 | 6,230 / 6,232 / 6,224 | 66,745 / 66,748 / 66,738 | 7,560 / 7,563 / 7,555 | -59,184 | 0.11 | 1,330 | 21.3 | 30/30/30 |  |
| context_menu_s1 | 2,366 / 2,366 / 2,366 | 2,868 / 2,872 / 2,865 | 1,324 / 1,324 / 1,324 | -1,544 | 0.46 | -1,042 | -44 | 30/30/30 |  |
| issue_edit_s1 | 7,103 / 7,106 / 7,097 | 67,781 / 67,786 / 67,771 | 8,515 / 8,518 / 8,508 | -59,266 | 0.13 | 1,412 | 19.9 | 30/30/30 |  |
| issue_list_s1 | 10,287 / 10,292 / 10,277 | 71,237 / 71,244 / 71,231 | 10,958 / 10,961 / 10,949 | -60,279 | 0.15 | 671 | 6.5 | 30/30/30 |  |
| issue_new_s1 | 6,834 / 6,836 / 6,829 | 67,502 / 67,506 / 67,493 | 8,182 / 8,185 / 8,175 | -59,319 | 0.12 | 1,348 | 19.7 | 30/30/30 |  |
| issue_show_s1 | 9,759 / 9,761 / 9,750 | 70,584 / 70,588 / 70,577 | 11,172 / 11,176 / 11,166 | -59,411 | 0.16 | 1,414 | 14.5 | 30/30/30 |  |
| project_settings_s1 | 5,698 / 5,700 / 5,692 | 66,603 / 66,607 / 66,595 | 6,712 / 6,717 / 6,704 | -59,891 | 0.10 | 1,014 | 17.8 | 30/30/30 |  |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 0.8 min.

#### domContentLoaded (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 158 / 166 / 143 | 172 / 183 / 165 | 153 / 168 / 142 | -19 | 0.89 | -6 | -3.6 | 10/10/10 |  |
| issue_new_s1 | 175 / 192 / 141 | 194 / 220 / 183 | 188 / 197 / 171 | -6 | 0.97 | 13 | 7.4 | 10/10/10 |  |

#### load event (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 160 / 167 / 147 | 175 / 188 / 169 | 157 / 173 / 151 | -18 | 0.90 | -4 | -2.3 | 10/10/10 |  |
| issue_new_s1 | 180 / 194 / 166 | 197 / 225 / 187 | 191 / 200 / 174 | -6 | 0.97 | 11 | 6.1 | 10/10/10 |  |

#### time to first byte (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 68 / 72 / 65 | 79 / 85 / 74 | 68 / 79 / 61 | -11 | 0.86 | 0 | -0.7 | 10/10/10 |  |
| issue_new_s1 | 61 / 69 / 58 | 72 / 80 / 66 | 61 / 73 / 57 | -11 | 0.85 | -1 | -1.1 | 10/10/10 |  |

#### JSHeapUsedSize (MB)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 3.6 / 3.6 / 3.6 | 4.3 / 4.3 / 4.3 | 3.7 / 3.7 / 3.6 | -0.6 | 0.85 | 0.1 | 1.7 | 10/10/10 |  |
| issue_new_s1 | 3.8 / 3.8 / 3.8 | 4.6 / 4.6 / 4.5 | 4 / 4 / 4 | -0.5 | 0.88 | 0.2 | 5.8 | 10/10/10 |  |

#### ScriptDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 45 / 48 / 43 | 47 / 49 / 44 | 48 / 51 / 43 | 1 | 1.02 | 2 | 4.8 | 10/10/10 |  |
| issue_new_s1 | 48 / 49 / 46 | 51 / 55 / 44 | 51 / 55 / 47 | 0 | 1.01 | 3 | 5.8 | 10/10/10 |  |

#### TaskDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 99 / 107 / 94 | 110 / 123 / 100 | 105 / 116 / 94 | -5 | 0.95 | 6 | 5.8 | 10/10/10 |  |
| issue_new_s1 | 133 / 142 / 123 | 148 / 163 / 135 | 141 / 149 / 126 | -7 | 0.95 | 8 | 6.3 | 10/10/10 |  |

#### LayoutDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 10 / 11 / 7 | 11 / 14 / 9 | 11 / 15 / 8 | 0 | 1.00 | 1 | 10.8 | 10/10/10 |  |
| issue_new_s1 | 13 / 15 / 10 | 12 / 14 / 10 | 14 / 16 / 10 | 2 | 1.16 | 1 | 9.1 | 10/10/10 |  |

#### RecalcStyleDuration (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 7 / 9 / 7 | 7 / 10 / 6 | 7 / 11 / 6 | 0 | 1.02 | 0 | -3.1 | 10/10/10 |  |
| issue_new_s1 | 12 / 13 / 9 | 12 / 16 / 11 | 12 / 13 / 10 | -1 | 0.93 | 0 | 0.6 | 10/10/10 |  |

#### DOM nodes

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 3,645 / 3,665 / 3,535 | 3,542 / 3,542 / 3,542 | 3,650 / 3,714 / 3,540 | 108 | 1.03 | 5 | 0.1 | 10/10/10 |  |
| issue_new_s1 | 3,610 / 3,632 / 3,589 | 3,615 / 3,615 / 3,615 | 3,667 / 3,667 / 3,625 | 52 | 1.01 | 57 | 1.6 | 10/10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| issue_new_s1 | 0 / 0 / 0 | 3 / 3 / 3 | 5 / 5 / 4 | 1 | 1.44 | 5 | - | 10/10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 74.4 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 74.4 | - | 10/10/10 |  |

#### Plugin asset load time (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 30 / 34 / 21 | 29 / 40 / 19 | -1 | 0.96 | 29 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 26 / 53 / 21 | 34 / 43 / 27 | 7 | 1.28 | 34 | - | 10/10/10 |  |

#### Context menu shown (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 83 / 89 / 77 | 113 / 127 / 106 | 75 / 82 / 69 | -38 | 0.66 | -8 | -9.6 | 10/10/10 |  |

#### Wizard opened (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | - | 3 / 4 / 3 | 35 / 39 / 34 | 32 | 10.74 | - | - | 10/10/10 |  |

#### Interaction: change handler returns (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| interaction_s1_country | 0 / 0 / 0 | 2 / 2 / 1 | 2 / 2 / 1 | 0 | 1.00 | 1 | 433.3 | 10/10/10 |  |

#### Interaction: options shown and painted (ms)

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| interaction_s1_country | 10 / 16 / 2 | 10 / 15 / 5 | 9 / 15 / 4 | -1 | 0.92 | -1 | -12 | 10/10/10 |  |

#### js_errors

| page | none (med / p90 / min) | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | branch - none | branch - none (%) | n none/main/branch | note |
|---|---|---|---|---|---|---|---|---|---|
| context_menu_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 10/10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 0 | - | 10/10/10 |  |

