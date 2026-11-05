# Performance summary: main (0.0.15) versus branch

Generated 2026-11-05T18:23:59.020Z. Cells: median / p90 / min. Delta = branch median minus main median, ratio = branch median / main median (below 1 means the branch is faster or smaller).

## Redmine 5.1

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 300, 15.5 min, load average at start 0.78.

### Memory (puma worker, 1 thread)

| checkpoint | main RSS (MB) | branch RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|
| after_boot | 184 | 181 | - | - | - | - |
| after_warmup | 301 | 307 | 302 | 311 | 1,142,021 | 980,464 |
| after_rounds | 302 | 314 | 315 | 329 | 1,147,447 | 954,886 |
| after_mixed | 334 | 314 | 339 | 345 | 1,135,801 | 1,057,971 |
| mixed run totals (300 requests) | time 119 s, objects 125,812,492, SQL 14576 | time 95 s, objects 71,087,473, SQL 14162 | | | | |
| after_heavy | 233 (restarted) | 321 | 233 | 345 | 854,313 | 1,113,800 |

Update check (PATCH stores the new values, reset restores them): {"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 167 / 200 / 141 | 69 / 77 / 52 | -99 | 0.41 | 30/30 |  |
| admin_cf_part | - | 441 / 604 / 398 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 342 / 426 / 284 | 273 / 304 / 200 | -69 | 0.80 | 30/30 |  |
| bulk_edit_s2 | 774 / 834 / 723 | 779 / 869 / 728 | 5 | 1.01 | 8/8 |  |
| context_menu_s1 | 217 / 275 / 177 | 132 / 163 / 108 | -85 | 0.61 | 30/30 |  |
| context_menu_s2 | 956 / 1,029 / 761 | 183 / 228 / 160 | -773 | 0.19 | 30/30 |  |
| issue_edit_s1 | 238 / 300 / 200 | 150 / 204 / 118 | -88 | 0.63 | 30/30 |  |
| issue_edit_s2 | 808 / 912 / 614 | 735 / 846 / 610 | -73 | 0.91 | 30/30 |  |
| issue_edit_s2_admin | 671 / 978 / 582 | 658 / 902 / 603 | -12 | 0.98 | 8/8 |  |
| issue_list_s1 | 370 / 583 / 290 | 271 / 354 / 215 | -98 | 0.73 | 30/30 |  |
| issue_list_s2 | 952 / 1,109 / 757 | 801 / 903 / 576 | -151 | 0.84 | 30/30 |  |
| issue_new_baseline | 676 / 876 / 553 | 517 / 565 / 461 | -159 | 0.76 | 8/8 |  |
| issue_new_s1 | 223 / 272 / 192 | 127 / 163 / 105 | -96 | 0.57 | 30/30 |  |
| issue_new_s2 | 708 / 762 / 614 | 846 / 914 / 677 | 137 | 1.19 | 30/30 |  |
| issue_new_s2_admin | 644 / 859 / 597 | 685 / 864 / 601 | 41 | 1.06 | 8/8 |  |
| issue_show_s1 | 452 / 613 / 373 | 341 / 402 / 270 | -111 | 0.75 | 30/30 |  |
| issue_show_s2 | 841 / 1,008 / 779 | 877 / 963 / 768 | 36 | 1.04 | 30/30 |  |
| issue_show_s2_admin | 773 / 908 / 646 | 684 / 781 / 637 | -89 | 0.89 | 8/8 |  |
| issue_update_s1 | 101 / 115 / 82 | 96 / 126 / 79 | -5 | 0.95 | 30/30 |  |
| issue_update_s2 | 226 / 250 / 196 | 243 / 266 / 217 | 17 | 1.07 | 30/30 |  |
| project_deps_s1_city | 149 / 166 / 138 | 63 / 80 / 53 | -86 | 0.42 | 30/30 |  |
| project_deps_s2_part | - | 833 / 922 / 663 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 216 / 247 / 175 | 128 / 153 / 101 | -88 | 0.59 | 30/30 |  |
| project_settings_s2 | 335 / 555 / 311 | 268 / 312 / 250 | -67 | 0.80 | 8/8 |  |
| project_values_s1_city | 184 / 214 / 159 | 85 / 274 / 71 | -98 | 0.46 | 30/30 |  |
| project_values_s2_part | 19,136 / 19,601 / 19,053 | 459 / 624 / 378 | -18,677 | 0.02 | 3/15 | main: heavy (19 s first) |

#### Process CPU time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 143 / 158 / 130 | 53 / 59 / 42 | -90 | 0.37 | 30/30 |  |
| admin_cf_part | - | 397 / 557 / 376 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 288 / 331 / 255 | 222 / 240 / 172 | -66 | 0.77 | 30/30 |  |
| bulk_edit_s2 | 686 / 714 / 656 | 704 / 770 / 674 | 18 | 1.03 | 8/8 |  |
| context_menu_s1 | 177 / 218 / 152 | 108 / 123 / 89 | -70 | 0.61 | 30/30 |  |
| context_menu_s2 | 888 / 926 / 700 | 153 / 168 / 137 | -735 | 0.17 | 30/30 |  |
| issue_edit_s1 | 203 / 230 / 180 | 118 / 154 / 93 | -85 | 0.58 | 30/30 |  |
| issue_edit_s2 | 763 / 807 / 573 | 645 / 794 / 581 | -119 | 0.84 | 30/30 |  |
| issue_edit_s2_admin | 628 / 854 / 557 | 596 / 837 / 557 | -32 | 0.95 | 8/8 |  |
| issue_list_s1 | 296 / 484 / 246 | 206 / 242 / 172 | -90 | 0.70 | 30/30 |  |
| issue_list_s2 | 861 / 943 / 671 | 700 / 745 / 495 | -161 | 0.81 | 30/30 |  |
| issue_new_baseline | 617 / 764 / 513 | 460 / 475 / 423 | -157 | 0.75 | 8/8 |  |
| issue_new_s1 | 190 / 215 / 174 | 101 / 122 / 89 | -88 | 0.53 | 30/30 |  |
| issue_new_s2 | 620 / 649 / 579 | 784 / 802 / 603 | 165 | 1.27 | 30/30 |  |
| issue_new_s2_admin | 589 / 794 / 551 | 608 / 795 / 578 | 18 | 1.03 | 8/8 |  |
| issue_show_s1 | 353 / 513 / 307 | 255 / 291 / 219 | -97 | 0.72 | 30/30 |  |
| issue_show_s2 | 746 / 817 / 709 | 777 / 809 / 699 | 31 | 1.04 | 30/30 |  |
| issue_show_s2_admin | 672 / 820 / 609 | 636 / 670 / 595 | -36 | 0.95 | 8/8 |  |
| issue_update_s1 | 77 / 86 / 66 | 73 / 89 / 65 | -4 | 0.95 | 30/30 |  |
| issue_update_s2 | 191 / 209 / 177 | 211 / 224 / 191 | 21 | 1.11 | 30/30 |  |
| project_deps_s1_city | 133 / 141 / 127 | 49 / 61 / 43 | -83 | 0.37 | 30/30 |  |
| project_deps_s2_part | - | 812 / 872 / 645 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 179 / 196 / 153 | 95 / 112 / 80 | -84 | 0.53 | 30/30 |  |
| project_settings_s2 | 299 / 518 / 285 | 229 / 250 / 217 | -71 | 0.76 | 8/8 |  |
| project_values_s1_city | 163 / 176 / 151 | 70 / 256 / 61 | -93 | 0.43 | 30/30 |  |
| project_values_s2_part | 18,612 / 18,793 / 18,542 | 396 / 567 / 363 | -18,217 | 0.02 | 3/15 | main: heavy (19 s first) |

#### View time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 137 / 167 / 118 | 41 / 50 / 31 | -96 | 0.30 | 30/30 |  |
| admin_cf_part | - | 404 / 568 / 363 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 138 / 165 / 123 | 57 / 66 / 42 | -81 | 0.42 | 30/30 |  |
| bulk_edit_s2 | 554 / 608 / 541 | 569 / 654 / 527 | 16 | 1.03 | 8/8 |  |
| context_menu_s1 | 71 / 82 / 59 | 15 / 20 / 12 | -56 | 0.21 | 30/30 |  |
| context_menu_s2 | 662 / 703 / 468 | 13 / 14 / 10 | -650 | 0.02 | 30/30 |  |
| issue_edit_s1 | 161 / 216 / 140 | 75 / 107 / 59 | -85 | 0.47 | 30/30 |  |
| issue_edit_s2 | 725 / 817 / 537 | 620 / 727 / 528 | -105 | 0.86 | 30/30 |  |
| issue_edit_s2_admin | 595 / 886 / 506 | 559 / 785 / 525 | -36 | 0.94 | 8/8 |  |
| issue_list_s1 | 213 / 437 / 182 | 124 / 174 / 97 | -90 | 0.58 | 30/30 |  |
| issue_list_s2 | 747 / 827 / 547 | 571 / 653 / 357 | -176 | 0.76 | 30/30 |  |
| issue_new_baseline | 573 / 775 / 485 | 439 / 476 / 391 | -134 | 0.77 | 8/8 |  |
| issue_new_s1 | 166 / 189 / 146 | 70 / 87 / 61 | -95 | 0.43 | 30/30 |  |
| issue_new_s2 | 618 / 668 / 541 | 767 / 825 / 594 | 149 | 1.24 | 30/30 |  |
| issue_new_s2_admin | 580 / 794 / 531 | 602 / 795 / 539 | 21 | 1.04 | 8/8 |  |
| issue_show_s1 | 199 / 247 / 178 | 114 / 146 / 81 | -85 | 0.57 | 30/30 |  |
| issue_show_s2 | 613 / 751 / 565 | 640 / 688 / 552 | 27 | 1.04 | 30/30 |  |
| issue_show_s2_admin | 684 / 827 / 575 | 598 / 672 / 559 | -87 | 0.87 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 116 / 123 / 105 | 30 / 39 / 25 | -85 | 0.26 | 30/30 |  |
| project_deps_s2_part | - | 455 / 519 / 297 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 157 / 178 / 126 | 70 / 85 / 55 | -87 | 0.45 | 30/30 |  |
| project_settings_s2 | 276 / 489 / 259 | 209 / 229 / 191 | -67 | 0.76 | 8/8 |  |
| project_values_s1_city | 149 / 172 / 128 | 49 / 240 / 43 | -100 | 0.33 | 30/30 |  |
| project_values_s2_part | 18,383 / 18,790 / 18,261 | 45 / 52 / 41 | -18,338 | 0.00 | 3/15 | main: heavy (19 s first) |

#### ActiveRecord time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 13 / 16 / 10 | 15 / 19 / 10 | 2 | 1.12 | 30/30 |  |
| admin_cf_part | - | 17 / 23 / 15 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 50 / 59 / 37 | 52 / 61 / 38 | 2 | 1.05 | 30/30 |  |
| bulk_edit_s2 | 57 / 72 / 49 | 51 / 58 / 47 | -6 | 0.89 | 8/8 |  |
| context_menu_s1 | 36 / 42 / 28 | 28 / 35 / 22 | -8 | 0.78 | 30/30 |  |
| context_menu_s2 | 43 / 47 / 32 | 33 / 39 / 25 | -10 | 0.77 | 30/30 |  |
| issue_edit_s1 | 31 / 39 / 23 | 30 / 39 / 23 | -1 | 0.98 | 30/30 |  |
| issue_edit_s2 | 38 / 47 / 31 | 41 / 46 / 32 | 3 | 1.07 | 30/30 |  |
| issue_edit_s2_admin | 35 / 57 / 28 | 32 / 54 / 25 | -3 | 0.92 | 8/8 |  |
| issue_list_s1 | 65 / 75 / 47 | 59 / 76 / 48 | -5 | 0.92 | 30/30 |  |
| issue_list_s2 | 79 / 102 / 66 | 79 / 89 / 64 | 0 | 1.00 | 30/30 |  |
| issue_new_baseline | 33 / 39 / 28 | 32 / 47 / 28 | -1 | 0.96 | 8/8 |  |
| issue_new_s1 | 28 / 36 / 19 | 26 / 35 / 18 | -2 | 0.94 | 30/30 |  |
| issue_new_s2 | 38 / 44 / 27 | 35 / 41 / 28 | -3 | 0.92 | 30/30 |  |
| issue_new_s2_admin | 28 / 37 / 24 | 27 / 31 / 24 | -1 | 0.97 | 8/8 |  |
| issue_show_s1 | 77 / 98 / 58 | 76 / 93 / 58 | -1 | 0.98 | 30/30 |  |
| issue_show_s2 | 84 / 99 / 70 | 81 / 97 / 67 | -3 | 0.96 | 30/30 |  |
| issue_show_s2_admin | 39 / 59 / 32 | 39 / 51 / 32 | 0 | 1.00 | 8/8 |  |
| issue_update_s1 | 26 / 32 / 20 | 24 / 31 / 19 | -2 | 0.91 | 30/30 |  |
| issue_update_s2 | 31 / 36 / 22 | 30 / 36 / 23 | -2 | 0.94 | 30/30 |  |
| project_deps_s1_city | 12 / 16 / 10 | 13 / 17 / 10 | 1 | 1.04 | 30/30 |  |
| project_deps_s2_part | - | 23 / 32 / 19 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 33 / 40 / 26 | 33 / 40 / 25 | 0 | 0.99 | 30/30 |  |
| project_settings_s2 | 37 / 45 / 28 | 36 / 57 / 33 | -1 | 0.98 | 8/8 |  |
| project_values_s1_city | 14 / 16 / 10 | 13 / 16 / 10 | 0 | 0.97 | 30/30 |  |
| project_values_s2_part | 26 / 29 / 20 | 19 / 21 / 16 | -7 | 0.72 | 3/15 | main: heavy (19 s first) |

#### Allocations (Rails Completed line)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 246,129 / 246,217 / 246,098 | 22,530 / 22,644 / 22,530 | -223,599 | 0.09 | 30/30 |  |
| admin_cf_part | - | 399,035 / 399,040 / 399,035 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 292,287 / 292,525 / 292,050 | 81,610 / 81,613 / 81,605 | -210,677 | 0.28 | 30/30 |  |
| bulk_edit_s2 | 998,358 / 998,358 / 998,353 | 974,682 / 974,797 / 974,682 | -23,676 | 0.98 | 8/8 |  |
| context_menu_s1 | 155,940 / 156,831 / 155,937 | 39,375 / 40,260 / 39,370 | -116,565 | 0.25 | 30/30 |  |
| context_menu_s2 | 1,066,067 / 1,066,079 / 1,066,062 | 83,212 / 83,215 / 83,209 | -982,855 | 0.08 | 30/30 |  |
| issue_edit_s1 | 256,176 / 256,186 / 256,170 | 44,530 / 44,541 / 44,530 | -211,646 | 0.17 | 30/30 |  |
| issue_edit_s2 | 967,374 / 967,629 / 967,116 | 942,855 / 942,860 / 942,847 | -24,519 | 0.97 | 30/30 |  |
| issue_edit_s2_admin | 965,647 / 965,654 / 965,612 | 941,353 / 941,353 / 941,348 | -24,294 | 0.97 | 8/8 |  |
| issue_list_s1 | 306,261 / 306,266 / 306,256 | 91,429 / 91,434 / 91,424 | -214,832 | 0.30 | 30/30 |  |
| issue_list_s2 | 1,073,762 / 1,074,230 / 1,073,721 | 703,686 / 703,689 / 703,677 | -370,076 | 0.66 | 30/30 |  |
| issue_new_baseline | 897,048 / 897,051 / 896,540 | 682,430 / 682,430 / 682,425 | -214,617 | 0.76 | 8/8 |  |
| issue_new_s1 | 254,113 / 254,147 / 254,108 | 42,031 / 42,071 / 42,025 | -212,082 | 0.17 | 30/30 |  |
| issue_new_s2 | 965,534 / 965,540 / 965,505 | 941,132 / 941,137 / 941,127 | -24,402 | 0.97 | 30/30 |  |
| issue_new_s2_admin | 963,570 / 963,600 / 963,569 | 939,196 / 939,203 / 939,190 | -24,374 | 0.97 | 8/8 |  |
| issue_show_s1 | 332,861 / 333,326 / 332,846 | 121,188 / 121,193 / 121,182 | -211,673 | 0.36 | 30/30 |  |
| issue_show_s2 | 1,043,003 / 1,043,478 / 1,042,965 | 1,018,687 / 1,018,693 / 1,018,678 | -24,315 | 0.98 | 30/30 |  |
| issue_show_s2_admin | 974,475 / 974,945 / 974,464 | 950,175 / 950,175 / 950,170 | -24,300 | 0.98 | 8/8 |  |
| issue_update_s1 | 21,794 / 21,825 / 21,789 | 21,701 / 21,703 / 21,701 | -93 | 1.00 | 30/30 |  |
| issue_update_s2 | 123,618 / 123,624 / 123,149 | 123,260 / 123,266 / 123,210 | -358 | 1.00 | 30/30 |  |
| project_deps_s1_city | 243,835 / 243,842 / 243,800 | 21,514 / 21,514 / 21,514 | -222,321 | 0.09 | 30/30 |  |
| project_deps_s2_part | - | 1,191,893 / 1,191,893 / 1,191,888 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 251,080 / 251,081 / 251,044 | 36,701 / 36,706 / 36,698 | -214,379 | 0.15 | 30/30 |  |
| project_settings_s2 | 353,796 / 353,799 / 353,793 | 139,788 / 139,793 / 139,788 | -214,008 | 0.40 | 8/8 |  |
| project_values_s1_city | 257,424 / 258,288 / 257,383 | 44,932 / 45,827 / 44,932 | -212,492 | 0.17 | 30/30 |  |
| project_values_s2_part | 23,046,973 / 23,047,290 / 23,046,822 | 605,195 / 605,200 / 605,195 | -22,441,778 | 0.03 | 3/15 | main: heavy (19 s first) |

#### SQL queries (without SCHEMA and CACHE)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 16 / 17 / 16 | 17 / 18 / 17 | 1 | 1.06 | 30/30 |  |
| admin_cf_part | - | 17 / 17 / 17 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 73 / 73 / 73 | 73 / 73 / 73 | 0 | 1.00 | 30/30 |  |
| bulk_edit_s2 | 69 / 69 / 69 | 69 / 70 / 69 | 0 | 1.00 | 8/8 |  |
| context_menu_s1 | 44 / 47 / 44 | 38 / 41 / 38 | -6 | 0.86 | 30/30 |  |
| context_menu_s2 | 42 / 42 / 42 | 38 / 38 / 38 | -4 | 0.90 | 30/30 |  |
| issue_edit_s1 | 48 / 48 / 48 | 47 / 47 / 47 | -1 | 0.98 | 30/30 |  |
| issue_edit_s2 | 45 / 45 / 45 | 45 / 45 / 45 | 0 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 36 / 36 / 36 | 36 / 36 / 36 | 0 | 1.00 | 8/8 |  |
| issue_list_s1 | 63 / 63 / 63 | 61 / 61 / 61 | -2 | 0.97 | 30/30 |  |
| issue_list_s2 | 43 / 43 / 43 | 41 / 41 / 41 | -2 | 0.95 | 30/30 |  |
| issue_new_baseline | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 8/8 |  |
| issue_new_s1 | 41 / 41 / 41 | 40 / 40 / 40 | -1 | 0.98 | 30/30 |  |
| issue_new_s2 | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 31 / 31 / 31 | 31 / 31 / 31 | 0 | 1.00 | 8/8 |  |
| issue_show_s1 | 72 / 72 / 72 | 71 / 71 / 71 | -1 | 0.99 | 30/30 |  |
| issue_show_s2 | 65 / 65 / 65 | 65 / 65 / 65 | 0 | 1.00 | 30/30 |  |
| issue_show_s2_admin | 47 / 47 / 47 | 47 / 47 / 47 | 0 | 1.00 | 8/8 |  |
| issue_update_s1 | 52 / 52 / 52 | 49 / 49 / 49 | -3 | 0.94 | 30/30 |  |
| issue_update_s2 | 42 / 42 / 42 | 41 / 41 / 41 | -1 | 0.98 | 30/30 |  |
| project_deps_s1_city | 21 / 21 / 21 | 23 / 23 / 23 | 2 | 1.10 | 30/30 |  |
| project_deps_s2_part | - | 23 / 23 / 23 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 46 / 46 / 46 | 46 / 46 / 46 | 0 | 1.00 | 30/30 |  |
| project_settings_s2 | 46 / 46 / 46 | 45 / 45 / 45 | -1 | 0.98 | 8/8 |  |
| project_values_s1_city | 22 / 25 / 22 | 22 / 25 / 22 | 0 | 1.00 | 30/30 |  |
| project_values_s2_part | 22 / 23 / 22 | 22 / 22 / 22 | 0 | 1.00 | 3/15 | main: heavy (19 s first) |

#### Response bytes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 348,695 / 348,695 / 348,695 | 30,557 / 30,557 / 30,557 | -318,138 | 0.09 | 30/30 |  |
| admin_cf_part | - | 824,653 / 824,653 / 824,653 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 320,086 / 320,086 / 320,086 | 34,893 / 34,893 / 34,893 | -285,193 | 0.11 | 30/30 |  |
| bulk_edit_s2 | 1,402,808 / 1,402,808 / 1,402,808 | 1,665,613 / 1,665,613 / 1,665,613 | 262,805 | 1.19 | 8/8 |  |
| context_menu_s1 | 26,121 / 26,121 / 26,121 | 13,420 / 13,420 / 13,420 | -12,701 | 0.51 | 30/30 |  |
| context_menu_s2 | 1,105,754 / 1,105,754 / 1,105,754 | 11,308 / 11,308 / 11,308 | -1,094,446 | 0.01 | 30/30 |  |
| issue_edit_s1 | 321,933 / 321,933 / 321,933 | 36,939 / 36,939 / 36,939 | -284,994 | 0.11 | 30/30 |  |
| issue_edit_s2 | 1,404,076 / 1,404,076 / 1,404,076 | 1,667,057 / 1,667,057 / 1,667,057 | 262,981 | 1.19 | 30/30 |  |
| issue_edit_s2_admin | 1,403,248 / 1,403,248 / 1,403,248 | 1,666,229 / 1,666,229 / 1,666,229 | 262,981 | 1.19 | 8/8 |  |
| issue_list_s1 | 364,068 / 364,068 / 364,068 | 73,196 / 73,196 / 73,196 | -290,872 | 0.20 | 30/30 |  |
| issue_list_s2 | 943,634 / 943,634 / 943,634 | 652,762 / 652,762 / 652,762 | -290,872 | 0.69 | 30/30 |  |
| issue_new_baseline | 1,535,014 / 1,535,014 / 1,535,014 | 1,244,142 / 1,244,142 / 1,244,142 | -290,872 | 0.81 | 8/8 |  |
| issue_new_s1 | 320,575 / 320,575 / 320,575 | 34,856 / 34,856 / 34,856 | -285,719 | 0.11 | 30/30 |  |
| issue_new_s2 | 1,402,661 / 1,402,661 / 1,402,661 | 1,665,527 / 1,665,527 / 1,665,527 | 262,866 | 1.19 | 30/30 |  |
| issue_new_s2_admin | 1,401,873 / 1,401,873 / 1,401,873 | 1,664,739 / 1,664,739 / 1,664,739 | 262,866 | 1.19 | 8/8 |  |
| issue_show_s1 | 330,480 / 330,480 / 330,480 | 45,486 / 45,486 / 45,486 | -284,994 | 0.14 | 30/30 |  |
| issue_show_s2 | 1,412,124 / 1,412,124 / 1,412,124 | 1,675,105 / 1,675,105 / 1,675,105 | 262,981 | 1.19 | 30/30 |  |
| issue_show_s2_admin | 1,411,073 / 1,411,073 / 1,411,073 | 1,674,054 / 1,674,054 / 1,674,054 | 262,981 | 1.19 | 8/8 |  |
| issue_update_s1 | 96 / 96 / 96 | 96 / 96 / 96 | 0 | 1.00 | 30/30 |  |
| issue_update_s2 | 98 / 98 / 98 | 98 / 98 / 98 | 0 | 1.00 | 30/30 |  |
| project_deps_s1_city | 349,377 / 349,377 / 349,377 | 25,224 / 25,224 / 25,224 | -324,153 | 0.07 | 30/30 |  |
| project_deps_s2_part | - | 1,568,174 / 1,568,174 / 1,568,174 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 319,471 / 319,471 / 319,471 | 28,734 / 28,734 / 28,734 | -290,737 | 0.09 | 30/30 |  |
| project_settings_s2 | 315,600 / 315,600 / 315,600 | 24,863 / 24,863 / 24,863 | -290,737 | 0.08 | 8/8 |  |
| project_values_s1_city | 360,021 / 360,021 / 360,021 | 71,435 / 71,435 / 71,435 | -288,586 | 0.20 | 30/30 |  |
| project_values_s2_part | 47,752,635 / 47,752,635 / 47,752,635 | 59,308 / 59,308 / 59,308 | -47,693,327 | 0.00 | 3/15 | main: heavy (19 s first) |

#### Response bytes gzipped

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 66,220 / 66,225 / 66,209 | 7,800 / 7,806 / 7,793 | -58,420 | 0.12 | 30/30 |  |
| admin_cf_part | - | 135,091 / 135,096 / 135,080 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 65,836 / 65,840 / 65,820 | 6,814 / 6,819 / 6,810 | -59,022 | 0.10 | 30/30 |  |
| bulk_edit_s2 | 201,807 / 201,818 / 201,801 | 212,159 / 212,166 / 212,153 | 10,352 | 1.05 | 8/8 |  |
| context_menu_s1 | 2,787 / 2,790 / 2,780 | 1,228 / 1,228 / 1,228 | -1,559 | 0.44 | 30/30 |  |
| context_menu_s2 | 136,958 / 136,963 / 136,952 | 1,093 / 1,093 / 1,093 | -135,865 | 0.01 | 30/30 |  |
| issue_edit_s1 | 66,733 / 66,738 / 66,727 | 7,642 / 7,645 / 7,637 | -59,091 | 0.11 | 30/30 |  |
| issue_edit_s2 | 203,020 / 203,027 / 203,012 | 213,419 / 213,425 / 213,410 | 10,399 | 1.05 | 30/30 |  |
| issue_edit_s2_admin | 202,965 / 202,969 / 202,959 | 213,368 / 213,374 / 213,363 | 10,403 | 1.05 | 8/8 |  |
| issue_list_s1 | 69,934 / 69,937 / 69,924 | 9,974 / 9,977 / 9,968 | -59,960 | 0.14 | 30/30 |  |
| issue_list_s2 | 192,362 / 192,368 / 192,354 | 132,724 / 132,728 / 132,716 | -59,637 | 0.69 | 30/30 |  |
| issue_new_baseline | 196,377 / 196,387 / 196,368 | 137,017 / 137,019 / 137,012 | -59,359 | 0.70 | 8/8 |  |
| issue_new_s1 | 66,502 / 66,507 / 66,494 | 7,348 / 7,351 / 7,342 | -59,154 | 0.11 | 30/30 |  |
| issue_new_s2 | 202,604 / 202,609 / 202,594 | 212,924 / 212,929 / 212,914 | 10,320 | 1.05 | 30/30 |  |
| issue_new_s2_admin | 202,542 / 202,546 / 202,539 | 212,856 / 212,857 / 212,849 | 10,315 | 1.05 | 8/8 |  |
| issue_show_s1 | 68,713 / 68,717 / 68,702 | 9,547 / 9,552 / 9,538 | -59,166 | 0.14 | 30/30 |  |
| issue_show_s2 | 205,081 / 205,086 / 205,064 | 215,310 / 215,314 / 215,302 | 10,230 | 1.05 | 30/30 |  |
| issue_show_s2_admin | 204,949 / 204,955 / 204,940 | 215,166 / 215,174 / 215,159 | 10,217 | 1.05 | 8/8 |  |
| project_deps_s1_city | 64,460 / 64,463 / 64,451 | 6,585 / 6,588 / 6,575 | -57,875 | 0.10 | 30/30 |  |
| project_deps_s2_part | - | 149,061 / 149,068 / 149,051 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 65,593 / 65,597 / 65,582 | 5,929 / 5,933 / 5,918 | -59,664 | 0.09 | 30/30 |  |
| project_settings_s2 | 65,371 / 65,374 / 65,362 | 5,730 / 5,736 / 5,728 | -59,640 | 0.09 | 8/8 |  |
| project_values_s1_city | 69,019 / 69,031 / 68,986 | 9,710 / 9,723 / 9,682 | -59,308 | 0.14 | 30/30 |  |
| project_values_s2_part | - | 8,872 / 8,889 / 8,863 | - | - | 3/15 | main: heavy (19 s first) |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 4.7 min.

#### domContentLoaded (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,206 / 1,416 / 1,117 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 441 / 539 / 378 | 272 / 296 / 239 | -169 | 0.62 | 10/10 |  |
| context_menu_s2 | 457 / 482 / 427 | 346 / 383 / 314 | -111 | 0.76 | 5/5 |  |
| issue_edit_s2 | 1,770 / 2,045 / 1,430 | 1,745 / 1,942 / 1,586 | -25 | 0.99 | 10/10 |  |
| issue_new_s1 | 402 / 455 / 367 | 294 / 325 / 261 | -108 | 0.73 | 10/10 |  |
| issue_new_s2 | 1,761 / 1,963 / 1,454 | 1,821 / 1,891 / 1,627 | 61 | 1.03 | 10/10 |  |

#### load event (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,464 / 1,626 / 1,243 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 442 / 540 / 379 | 273 / 297 / 239 | -169 | 0.62 | 10/10 |  |
| context_menu_s2 | 458 / 483 / 428 | 347 / 384 / 315 | -111 | 0.76 | 5/5 |  |
| issue_edit_s2 | 1,958 / 2,226 / 1,732 | 1,931 / 2,133 / 1,764 | -27 | 0.99 | 10/10 |  |
| issue_new_s1 | 407 / 459 / 372 | 299 / 329 / 266 | -108 | 0.73 | 10/10 |  |
| issue_new_s2 | 2,003 / 2,167 / 1,723 | 2,027 / 2,097 / 1,831 | 24 | 1.01 | 10/10 |  |

#### time to first byte (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 448 / 595 / 383 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 255 / 388 / 221 | 135 / 157 / 116 | -120 | 0.53 | 10/10 |  |
| context_menu_s2 | 307 / 338 / 296 | 214 / 258 / 192 | -93 | 0.70 | 5/5 |  |
| issue_edit_s2 | 661 / 817 / 618 | 661 / 745 / 601 | -1 | 1.00 | 10/10 |  |
| issue_new_s1 | 225 / 248 / 197 | 120 / 150 / 101 | -105 | 0.53 | 10/10 |  |
| issue_new_s2 | 670 / 692 / 605 | 673 / 859 / 626 | 3 | 1.00 | 10/10 |  |

#### JSHeapUsedSize (MB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 5.2 / 6.4 / 5.1 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 3.9 / 3.9 / 3.9 | 3.3 / 3.3 / 3.3 | -0.6 | 0.84 | 10/10 |  |
| context_menu_s2 | 3.9 / 3.9 / 3.9 | 3.3 / 3.3 / 3.3 | -0.6 | 0.84 | 5/5 |  |
| issue_edit_s2 | 4.7 / 4.9 / 4.4 | 7 / 7.2 / 5.1 | 2.3 | 1.50 | 10/10 |  |
| issue_new_s1 | 4.1 / 4.1 / 4.1 | 3.5 / 3.5 / 3.5 | -0.5 | 0.87 | 10/10 |  |
| issue_new_s2 | 4.5 / 4.7 / 4.2 | 6.8 / 6.9 / 5.7 | 2.3 | 1.53 | 10/10 |  |

#### ScriptDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 230 / 252 / 201 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 94 / 110 / 71 | 82 / 86 / 73 | -12 | 0.87 | 10/10 |  |
| context_menu_s2 | 73 / 81 / 67 | 75 / 89 / 72 | 2 | 1.03 | 5/5 |  |
| issue_edit_s2 | 393 / 406 / 349 | 370 / 385 / 338 | -23 | 0.94 | 10/10 |  |
| issue_new_s1 | 85 / 94 / 80 | 94 / 102 / 81 | 8 | 1.10 | 10/10 |  |
| issue_new_s2 | 402 / 429 / 356 | 362 / 383 / 348 | -40 | 0.90 | 10/10 |  |

#### TaskDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,028 / 1,059 / 871 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 195 / 232 / 162 | 161 / 167 / 140 | -33 | 0.83 | 10/10 |  |
| context_menu_s2 | 167 / 193 / 150 | 152 / 168 / 146 | -15 | 0.91 | 5/5 |  |
| issue_edit_s2 | 1,442 / 1,540 / 1,228 | 1,407 / 1,571 / 1,306 | -35 | 0.98 | 10/10 |  |
| issue_new_s1 | 216 / 226 / 192 | 204 / 219 / 171 | -12 | 0.95 | 10/10 |  |
| issue_new_s2 | 1,479 / 1,596 / 1,204 | 1,418 / 1,524 / 1,332 | -61 | 0.96 | 10/10 |  |

#### LayoutDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 399 / 435 / 350 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 15 / 17 / 13 | 16 / 18 / 14 | 1 | 1.05 | 10/10 |  |
| context_menu_s2 | 14 / 18 / 12 | 15 / 16 / 14 | 0 | 1.02 | 5/5 |  |
| issue_edit_s2 | 257 / 277 / 182 | 246 / 272 / 219 | -11 | 0.96 | 10/10 |  |
| issue_new_s1 | 19 / 22 / 17 | 19 / 23 / 17 | 0 | 1.02 | 10/10 |  |
| issue_new_s2 | 262 / 284 / 189 | 246 / 277 / 236 | -16 | 0.94 | 10/10 |  |

#### RecalcStyleDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 73 / 82 / 68 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 12 / 15 / 10 | 11 / 12 / 10 | -1 | 0.92 | 10/10 |  |
| context_menu_s2 | 11 / 13 / 10 | 12 / 14 / 11 | 1 | 1.13 | 5/5 |  |
| issue_edit_s2 | 329 / 339 / 180 | 337 / 363 / 320 | 8 | 1.02 | 10/10 |  |
| issue_new_s1 | 22 / 26 / 17 | 22 / 26 / 17 | 0 | 1.00 | 10/10 |  |
| issue_new_s2 | 351 / 370 / 193 | 332 / 358 / 316 | -19 | 0.95 | 10/10 |  |

#### DOM nodes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 52,549 / 52,557 / 52,548 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 2,137 / 2,137 / 2,137 | 2,135 / 2,135 / 2,135 | -2 | 1.00 | 10/10 |  |
| context_menu_s2 | 2,025 / 2,025 / 2,025 | 2,023 / 2,023 / 2,023 | -2 | 1.00 | 5/5 |  |
| issue_edit_s2 | 179,749 / 179,810 / 179,618 | 179,744 / 179,744 / 179,744 | -5 | 1.00 | 10/10 |  |
| issue_new_s1 | 2,201 / 2,201 / 2,201 | 2,203 / 2,203 / 2,203 | 2 | 1.00 | 10/10 |  |
| issue_new_s2 | 179,402 / 179,604 / 179,402 | 179,606 / 179,606 / 179,401 | 204 | 1.00 | 10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 192 / 192 / 191 | - | - | 0/10 | main: timeout > 30 s |
| issue_new_s1 | 7 / 7 / 7 | 9 / 9 / 8 | 2 | 1.21 | 10/10 |  |
| issue_new_s2 | 249 / 260 / 237 | 205 / 213 / 197 | -44 | 0.82 | 10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 185.3 / 185.3 / 185.3 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| context_menu_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 5/5 |  |
| issue_edit_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| issue_new_s1 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| issue_new_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |

#### Plugin asset load time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 109 / 158 / 75 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 42 / 58 / 28 | 40 / 48 / 28 | -2 | 0.94 | 10/10 |  |
| context_menu_s2 | 31 / 41 / 23 | 49 / 66 / 37 | 18 | 1.58 | 5/5 |  |
| issue_edit_s2 | 55 / 66 / 40 | 49 / 68 / 32 | -6 | 0.89 | 10/10 |  |
| issue_new_s1 | 46 / 62 / 33 | 54 / 66 / 40 | 9 | 1.19 | 10/10 |  |
| issue_new_s2 | 54 / 73 / 33 | 55 / 62 / 33 | 1 | 1.01 | 10/10 |  |

#### Context menu shown (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 236 / 257 / 185 | 146 / 161 / 117 | -90 | 0.62 | 10/10 |  |
| context_menu_s2 | 1,013 / 1,096 / 865 | 204 / 230 / 160 | -810 | 0.20 | 5/5 |  |

#### Wizard opened (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 5 / 6 / 5 | 70 / 96 / 59 | 65 | 14.19 | 10/10 |  |
| context_menu_s2 | 554 / 603 / 535 | 1,562 / 1,603 / 1,434 | 1,008 | 2.82 | 5/5 |  |

#### Interaction: change handler returns (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 3 / 4 / 3 | 3 / 4 / 2 | 0 | 0.98 | 10/10 |  |
| interaction_s2_assembly | 132 / 148 / 116 | 91 / 100 / 76 | -42 | 0.69 | 10/10 |  |

#### Interaction: options shown and painted (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 11 / 18 / 8 | 11 / 19 / 7 | 1 | 1.06 | 10/10 |  |
| interaction_s2_assembly | 300 / 338 / 272 | 185 / 197 / 155 | -115 | 0.62 | 10/10 |  |

#### js_errors

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 0 / 0 / 0 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| context_menu_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 5/5 |  |
| issue_edit_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |

## Redmine 6.1

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 300, 13.6 min, load average at start 0.96.

### Memory (puma worker, 1 thread)

| checkpoint | main RSS (MB) | branch RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|
| after_boot | 231 | 225 | - | - | - | - |
| after_warmup | 358 | 347 | 358 | 347 | 1,054,208 | 938,197 |
| after_rounds | 374 | 372 | 374 | 372 | 963,440 | 939,693 |
| after_mixed | 394 | 389 | 394 | 403 | 1,052,119 | 1,027,081 |
| mixed run totals (300 requests) | time 92 s, objects 51,967,296, SQL 14675 | time 80 s, objects 35,661,757, SQL 14263 | | | | |
| after_heavy | 280 (restarted) | 392 | 280 | 403 | 788,716 | 912,479 |

Update check (PATCH stores the new values, reset restores them): {"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 94 / 109 / 75 | 68 / 87 / 58 | -26 | 0.72 | 30/30 |  |
| admin_cf_part | - | 407 / 436 / 386 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 288 / 337 / 246 | 278 / 328 / 226 | -10 | 0.97 | 30/30 |  |
| bulk_edit_s2 | 645 / 842 / 578 | 689 / 1,007 / 613 | 44 | 1.07 | 8/8 |  |
| context_menu_s1 | 209 / 241 / 187 | 145 / 211 / 109 | -64 | 0.69 | 30/30 |  |
| context_menu_s2 | 754 / 838 / 689 | 221 / 364 / 174 | -533 | 0.29 | 30/30 |  |
| issue_edit_s1 | 174 / 213 / 137 | 132 / 149 / 112 | -42 | 0.76 | 30/30 |  |
| issue_edit_s2 | 524 / 550 / 469 | 531 / 593 / 495 | 7 | 1.01 | 30/30 |  |
| issue_edit_s2_admin | 514 / 603 / 483 | 520 / 554 / 488 | 7 | 1.01 | 8/8 |  |
| issue_list_s1 | 313 / 361 / 271 | 278 / 327 / 220 | -34 | 0.89 | 30/30 |  |
| issue_list_s2 | 665 / 884 / 608 | 560 / 599 / 496 | -105 | 0.84 | 30/30 |  |
| issue_new_baseline | 446 / 620 / 402 | 414 / 452 / 392 | -32 | 0.93 | 8/8 |  |
| issue_new_s1 | 157 / 189 / 135 | 125 / 151 / 100 | -31 | 0.80 | 30/30 |  |
| issue_new_s2 | 521 / 565 / 476 | 510 / 546 / 461 | -11 | 0.98 | 30/30 |  |
| issue_new_s2_admin | 474 / 512 / 446 | 488 / 561 / 443 | 14 | 1.03 | 8/8 |  |
| issue_show_s1 | 393 / 430 / 335 | 360 / 410 / 311 | -33 | 0.92 | 30/30 |  |
| issue_show_s2 | 726 / 862 / 671 | 762 / 899 / 671 | 36 | 1.05 | 30/30 |  |
| issue_show_s2_admin | 524 / 595 / 487 | 540 / 649 / 503 | 16 | 1.03 | 8/8 |  |
| issue_update_s1 | 178 / 234 / 91 | 105 / 118 / 84 | -73 | 0.59 | 30/30 |  |
| issue_update_s2 | 266 / 303 / 242 | 269 / 297 / 238 | 3 | 1.01 | 30/30 |  |
| project_deps_s1_city | 91 / 121 / 74 | 69 / 81 / 57 | -22 | 0.75 | 30/30 |  |
| project_deps_s2_part | - | 445 / 489 / 416 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 181 / 214 / 146 | 147 / 179 / 124 | -34 | 0.81 | 30/30 |  |
| project_settings_s2 | 323 / 351 / 280 | 321 / 353 / 275 | -2 | 0.99 | 8/8 |  |
| project_values_s1_city | 108 / 129 / 91 | 98 / 123 / 76 | -10 | 0.90 | 30/30 |  |
| project_values_s2_part | 17,332 / 18,079 / 17,180 | 305 / 323 / 283 | -17,027 | 0.02 | 3/15 | main: heavy (18 s first) |

#### Process CPU time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 77 / 87 / 65 | 52 / 59 / 47 | -25 | 0.67 | 30/30 |  |
| admin_cf_part | - | 371 / 379 / 358 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 240 / 273 / 214 | 224 / 249 / 192 | -16 | 0.93 | 30/30 |  |
| bulk_edit_s2 | 562 / 759 / 523 | 589 / 829 / 547 | 26 | 1.05 | 8/8 |  |
| context_menu_s1 | 173 / 193 / 155 | 110 / 166 / 90 | -63 | 0.63 | 30/30 |  |
| context_menu_s2 | 683 / 746 / 629 | 173 / 313 / 149 | -510 | 0.25 | 30/30 |  |
| issue_edit_s1 | 141 / 159 / 119 | 107 / 116 / 93 | -35 | 0.76 | 30/30 |  |
| issue_edit_s2 | 464 / 485 / 437 | 480 / 504 / 457 | 15 | 1.03 | 30/30 |  |
| issue_edit_s2_admin | 464 / 504 / 443 | 461 / 485 / 449 | -3 | 0.99 | 8/8 |  |
| issue_list_s1 | 253 / 280 / 225 | 218 / 248 / 185 | -35 | 0.86 | 30/30 |  |
| issue_list_s2 | 565 / 738 / 533 | 454 / 473 / 424 | -112 | 0.80 | 30/30 |  |
| issue_new_baseline | 387 / 574 / 375 | 367 / 384 / 356 | -20 | 0.95 | 8/8 |  |
| issue_new_s1 | 126 / 149 / 112 | 103 / 115 / 84 | -23 | 0.82 | 30/30 |  |
| issue_new_s2 | 464 / 486 / 433 | 458 / 479 / 436 | -6 | 0.99 | 30/30 |  |
| issue_new_s2_admin | 431 / 460 / 419 | 451 / 488 / 422 | 21 | 1.05 | 8/8 |  |
| issue_show_s1 | 304 / 334 / 275 | 281 / 304 / 251 | -23 | 0.93 | 30/30 |  |
| issue_show_s2 | 629 / 700 / 598 | 648 / 707 / 608 | 19 | 1.03 | 30/30 |  |
| issue_show_s2_admin | 479 / 537 / 457 | 500 / 516 / 472 | 21 | 1.04 | 8/8 |  |
| issue_update_s1 | 150 / 182 / 74 | 82 / 88 / 69 | -68 | 0.55 | 30/30 |  |
| issue_update_s2 | 234 / 253 / 215 | 238 / 244 / 221 | 4 | 1.02 | 30/30 |  |
| project_deps_s1_city | 74 / 83 / 64 | 53 / 60 / 47 | -21 | 0.72 | 30/30 |  |
| project_deps_s2_part | - | 408 / 418 / 392 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 142 / 153 / 122 | 110 / 128 / 94 | -32 | 0.78 | 30/30 |  |
| project_settings_s2 | 276 / 294 / 251 | 266 / 288 / 247 | -10 | 0.96 | 8/8 |  |
| project_values_s1_city | 91 / 106 / 81 | 77 / 89 / 66 | -14 | 0.84 | 30/30 |  |
| project_values_s2_part | 16,926 / 17,389 / 16,774 | 277 / 284 / 269 | -16,648 | 0.02 | 3/15 | main: heavy (18 s first) |

#### View time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 65 / 75 / 51 | 39 / 51 / 33 | -26 | 0.60 | 30/30 |  |
| admin_cf_part | - | 370 / 393 / 348 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 73 / 90 / 63 | 56 / 68 / 43 | -16 | 0.77 | 30/30 |  |
| bulk_edit_s2 | 399 / 464 / 363 | 450 / 571 / 401 | 51 | 1.13 | 8/8 |  |
| context_menu_s1 | 67 / 77 / 57 | 17 / 61 / 13 | -50 | 0.25 | 30/30 |  |
| context_menu_s2 | 419 / 482 / 361 | 13 / 19 / 11 | -406 | 0.03 | 30/30 |  |
| issue_edit_s1 | 103 / 124 / 77 | 65 / 76 / 54 | -38 | 0.63 | 30/30 |  |
| issue_edit_s2 | 427 / 457 / 392 | 429 / 471 / 404 | 1 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 425 / 501 / 398 | 427 / 463 / 399 | 2 | 1.01 | 8/8 |  |
| issue_list_s1 | 157 / 180 / 138 | 133 / 154 / 108 | -23 | 0.85 | 30/30 |  |
| issue_list_s2 | 430 / 619 / 379 | 305 / 325 / 280 | -124 | 0.71 | 30/30 |  |
| issue_new_baseline | 363 / 539 / 333 | 333 / 365 / 317 | -30 | 0.92 | 8/8 |  |
| issue_new_s1 | 95 / 119 / 82 | 73 / 83 / 55 | -23 | 0.76 | 30/30 |  |
| issue_new_s2 | 437 / 478 / 398 | 432 / 465 / 396 | -5 | 0.99 | 30/30 |  |
| issue_new_s2_admin | 406 / 428 / 383 | 420 / 482 / 380 | 14 | 1.03 | 8/8 |  |
| issue_show_s1 | 141 / 170 / 110 | 113 / 136 / 94 | -28 | 0.80 | 30/30 |  |
| issue_show_s2 | 479 / 527 / 441 | 498 / 582 / 434 | 19 | 1.04 | 30/30 |  |
| issue_show_s2_admin | 445 / 511 / 415 | 461 / 568 / 429 | 16 | 1.04 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 55 / 75 / 44 | 31 / 38 / 26 | -24 | 0.56 | 30/30 |  |
| project_deps_s2_part | - | 125 / 139 / 112 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 108 / 135 / 90 | 83 / 104 / 65 | -24 | 0.77 | 30/30 |  |
| project_settings_s2 | 252 / 281 / 222 | 246 / 278 / 221 | -6 | 0.98 | 8/8 |  |
| project_values_s1_city | 69 / 84 / 60 | 56 / 73 / 45 | -13 | 0.81 | 30/30 |  |
| project_values_s2_part | 16,688 / 17,477 / 16,520 | 47 / 62 / 42 | -16,641 | 0.00 | 3/15 | main: heavy (18 s first) |

#### ActiveRecord time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 14 / 18 / 11 | 16 / 23 / 13 | 2 | 1.14 | 30/30 |  |
| admin_cf_part | - | 21 / 42 / 17 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 51 / 56 / 40 | 53 / 60 / 39 | 1 | 1.03 | 30/30 |  |
| bulk_edit_s2 | 54 / 69 / 50 | 56 / 81 / 46 | 2 | 1.04 | 8/8 |  |
| context_menu_s1 | 37 / 40 / 32 | 28 / 33 / 23 | -9 | 0.77 | 30/30 |  |
| context_menu_s2 | 42 / 47 / 35 | 36 / 41 / 27 | -7 | 0.84 | 30/30 |  |
| issue_edit_s1 | 29 / 35 / 22 | 27 / 31 / 24 | -2 | 0.94 | 30/30 |  |
| issue_edit_s2 | 39 / 47 / 29 | 41 / 51 / 33 | 2 | 1.05 | 30/30 |  |
| issue_edit_s2_admin | 36 / 49 / 30 | 37 / 42 / 27 | 1 | 1.03 | 8/8 |  |
| issue_list_s1 | 71 / 81 / 60 | 59 / 72 / 45 | -12 | 0.84 | 30/30 |  |
| issue_list_s2 | 80 / 93 / 70 | 78 / 93 / 64 | -2 | 0.98 | 30/30 |  |
| issue_new_baseline | 33 / 46 / 30 | 35 / 43 / 28 | 2 | 1.06 | 8/8 |  |
| issue_new_s1 | 28 / 34 / 23 | 25 / 30 / 21 | -2 | 0.91 | 30/30 |  |
| issue_new_s2 | 37 / 43 / 30 | 34 / 39 / 26 | -3 | 0.92 | 30/30 |  |
| issue_new_s2_admin | 28 / 33 / 24 | 27 / 34 / 25 | -1 | 0.96 | 8/8 |  |
| issue_show_s1 | 80 / 91 / 65 | 83 / 95 / 64 | 3 | 1.04 | 30/30 |  |
| issue_show_s2 | 84 / 104 / 70 | 87 / 95 / 71 | 3 | 1.03 | 30/30 |  |
| issue_show_s2_admin | 42 / 52 / 36 | 44 / 47 / 38 | 2 | 1.05 | 8/8 |  |
| issue_update_s1 | 32 / 37 / 22 | 25 / 31 / 20 | -6 | 0.80 | 30/30 |  |
| issue_update_s2 | 34 / 40 / 24 | 31 / 40 / 25 | -2 | 0.93 | 30/30 |  |
| project_deps_s1_city | 13 / 20 / 10 | 14 / 16 / 11 | 0 | 1.03 | 30/30 |  |
| project_deps_s2_part | - | 25 / 28 / 20 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 38 / 46 / 32 | 38 / 46 / 28 | 0 | 1.00 | 30/30 |  |
| project_settings_s2 | 39 / 48 / 36 | 43 / 50 / 34 | 4 | 1.10 | 8/8 |  |
| project_values_s1_city | 14 / 18 / 11 | 15 / 19 / 10 | 1 | 1.07 | 30/30 |  |
| project_values_s2_part | 24 / 25 / 19 | 20 / 31 / 17 | -4 | 0.82 | 3/15 | main: heavy (18 s first) |

#### Allocations (Rails Completed line)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 47,498 / 47,616 / 47,498 | 16,751 / 16,869 / 16,751 | -30,747 | 0.35 | 30/30 |  |
| admin_cf_part | - | 200,682 / 200,687 / 200,680 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 98,779 / 98,895 / 98,765 | 73,671 / 73,682 / 73,641 | -25,108 | 0.75 | 30/30 |  |
| bulk_edit_s2 | 423,658 / 424,392 / 423,619 | 401,566 / 401,818 / 401,317 | -22,092 | 0.95 | 8/8 |  |
| context_menu_s1 | 150,531 / 151,438 / 150,469 | 36,551 / 37,516 / 36,549 | -113,979 | 0.24 | 30/30 |  |
| context_menu_s2 | 681,345 / 682,120 / 681,340 | 80,947 / 80,956 / 80,942 | -600,398 | 0.12 | 30/30 |  |
| issue_edit_s1 | 62,176 / 62,181 / 62,167 | 35,737 / 35,737 / 35,699 | -26,439 | 0.57 | 30/30 |  |
| issue_edit_s2 | 393,172 / 393,540 / 393,167 | 370,721 / 370,726 / 370,211 | -22,451 | 0.94 | 30/30 |  |
| issue_edit_s2_admin | 391,961 / 392,700 / 391,924 | 369,225 / 369,480 / 368,969 | -22,735 | 0.94 | 8/8 |  |
| issue_list_s1 | 101,422 / 101,790 / 101,417 | 73,536 / 73,541 / 73,506 | -27,886 | 0.73 | 30/30 |  |
| issue_list_s2 | 473,288 / 473,675 / 473,283 | 290,237 / 290,680 / 290,175 | -183,051 | 0.61 | 30/30 |  |
| issue_new_baseline | 330,069 / 330,956 / 330,045 | 302,889 / 302,904 / 302,889 | -27,180 | 0.92 | 8/8 |  |
| issue_new_s1 | 59,618 / 59,654 / 59,618 | 33,020 / 33,034 / 32,990 | -26,598 | 0.55 | 30/30 |  |
| issue_new_s2 | 391,390 / 391,797 / 391,385 | 368,633 / 368,889 / 368,376 | -22,757 | 0.94 | 30/30 |  |
| issue_new_s2_admin | 389,551 / 390,289 / 389,512 | 366,762 / 367,017 / 366,510 | -22,788 | 0.94 | 8/8 |  |
| issue_show_s1 | 139,215 / 139,639 / 139,206 | 112,767 / 113,266 / 112,727 | -26,448 | 0.81 | 30/30 |  |
| issue_show_s2 | 469,696 / 470,095 / 469,691 | 446,722 / 447,226 / 446,717 | -22,974 | 0.95 | 30/30 |  |
| issue_show_s2_admin | 398,740 / 399,481 / 398,703 | 376,006 / 376,254 / 375,749 | -22,734 | 0.94 | 8/8 |  |
| issue_update_s1 | 20,831 / 20,862 / 20,831 | 20,643 / 20,647 / 20,606 | -188 | 0.99 | 30/30 |  |
| issue_update_s2 | 122,048 / 122,381 / 122,037 | 122,563 / 122,568 / 122,061 | 515 | 1.00 | 30/30 |  |
| project_deps_s1_city | 45,553 / 45,557 / 45,552 | 16,075 / 16,077 / 16,075 | -29,477 | 0.35 | 30/30 |  |
| project_deps_s2_part | - | 259,391 / 259,396 / 259,391 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 59,006 / 59,036 / 58,995 | 31,334 / 31,335 / 31,330 | -27,672 | 0.53 | 30/30 |  |
| project_settings_s2 | 162,088 / 162,466 / 162,054 | 134,986 / 135,236 / 134,735 | -27,102 | 0.83 | 8/8 |  |
| project_values_s1_city | 53,274 / 54,236 / 53,274 | 27,402 / 28,368 / 27,400 | -25,872 | 0.51 | 30/30 |  |
| project_values_s2_part | 10,572,531 / 10,572,649 / 10,572,196 | 229,727 / 229,732 / 229,727 | -10,342,804 | 0.02 | 3/15 | main: heavy (18 s first) |

#### SQL queries (without SCHEMA and CACHE)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 16 / 17 / 16 | 17 / 18 / 17 | 1 | 1.06 | 30/30 |  |
| admin_cf_part | - | 17 / 17 / 17 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 73 / 73 / 73 | 73 / 73 / 73 | 0 | 1.00 | 30/30 |  |
| bulk_edit_s2 | 69 / 69 / 69 | 69 / 69 / 69 | 0 | 1.00 | 8/8 |  |
| context_menu_s1 | 44 / 47 / 44 | 38 / 41 / 38 | -6 | 0.86 | 30/30 |  |
| context_menu_s2 | 42 / 42 / 42 | 38 / 38 / 38 | -4 | 0.90 | 30/30 |  |
| issue_edit_s1 | 49 / 49 / 49 | 48 / 48 / 48 | -1 | 0.98 | 30/30 |  |
| issue_edit_s2 | 46 / 46 / 46 | 46 / 46 / 46 | 0 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 37 / 37 / 37 | 37 / 37 / 37 | 0 | 1.00 | 8/8 |  |
| issue_list_s1 | 64 / 64 / 64 | 62 / 62 / 62 | -2 | 0.97 | 30/30 |  |
| issue_list_s2 | 44 / 44 / 44 | 42 / 42 / 42 | -2 | 0.95 | 30/30 |  |
| issue_new_baseline | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 8/8 |  |
| issue_new_s1 | 42 / 42 / 42 | 41 / 41 / 41 | -1 | 0.98 | 30/30 |  |
| issue_new_s2 | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 31 / 31 / 31 | 31 / 31 / 31 | 0 | 1.00 | 8/8 |  |
| issue_show_s1 | 74 / 74 / 74 | 73 / 73 / 73 | -1 | 0.99 | 30/30 |  |
| issue_show_s2 | 67 / 67 / 67 | 67 / 67 / 67 | 0 | 1.00 | 30/30 |  |
| issue_show_s2_admin | 47 / 47 / 47 | 47 / 47 / 47 | 0 | 1.00 | 8/8 |  |
| issue_update_s1 | 51 / 51 / 51 | 48 / 48 / 48 | -3 | 0.94 | 30/30 |  |
| issue_update_s2 | 41 / 41 / 41 | 40 / 40 / 40 | -1 | 0.98 | 30/30 |  |
| project_deps_s1_city | 21 / 21 / 21 | 23 / 23 / 23 | 2 | 1.10 | 30/30 |  |
| project_deps_s2_part | - | 23 / 23 / 23 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 46 / 46 / 46 | 46 / 46 / 46 | 0 | 1.00 | 30/30 |  |
| project_settings_s2 | 46 / 46 / 46 | 45 / 45 / 45 | -1 | 0.98 | 8/8 |  |
| project_values_s1_city | 22 / 25 / 22 | 22 / 25 / 22 | 0 | 1.00 | 30/30 |  |
| project_values_s2_part | 22 / 23 / 22 | 22 / 22 / 22 | 0 | 1.00 | 3/15 | main: heavy (18 s first) |

#### Response bytes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 353,873 / 353,873 / 353,873 | 35,856 / 35,856 / 35,856 | -318,017 | 0.10 | 30/30 |  |
| admin_cf_part | - | 829,952 / 829,952 / 829,952 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 322,913 / 322,913 / 322,913 | 37,720 / 37,720 / 37,720 | -285,193 | 0.12 | 30/30 |  |
| bulk_edit_s2 | 1,405,635 / 1,405,635 / 1,405,635 | 1,668,440 / 1,668,440 / 1,668,440 | 262,805 | 1.19 | 8/8 |  |
| context_menu_s1 | 27,744 / 27,744 / 27,744 | 15,355 / 15,355 / 15,355 | -12,389 | 0.55 | 30/30 |  |
| context_menu_s2 | 1,107,207 / 1,107,207 / 1,107,207 | 12,917 / 12,917 / 12,917 | -1,094,290 | 0.01 | 30/30 |  |
| issue_edit_s1 | 325,735 / 325,735 / 325,735 | 40,741 / 40,741 / 40,741 | -284,994 | 0.13 | 30/30 |  |
| issue_edit_s2 | 1,407,878 / 1,407,878 / 1,407,878 | 1,670,859 / 1,670,859 / 1,670,859 | 262,981 | 1.19 | 30/30 |  |
| issue_edit_s2_admin | 1,406,994 / 1,406,994 / 1,406,994 | 1,669,975 / 1,669,975 / 1,669,975 | 262,981 | 1.19 | 8/8 |  |
| issue_list_s1 | 373,346 / 373,346 / 373,346 | 82,474 / 82,474 / 82,474 | -290,872 | 0.22 | 30/30 |  |
| issue_list_s2 | 953,054 / 953,054 / 953,054 | 662,182 / 662,182 / 662,182 | -290,872 | 0.69 | 30/30 |  |
| issue_new_baseline | 1,538,555 / 1,538,555 / 1,538,555 | 1,247,683 / 1,247,683 / 1,247,683 | -290,872 | 0.81 | 8/8 |  |
| issue_new_s1 | 324,116 / 324,116 / 324,116 | 38,397 / 38,397 / 38,397 | -285,719 | 0.12 | 30/30 |  |
| issue_new_s2 | 1,406,202 / 1,406,202 / 1,406,202 | 1,669,068 / 1,669,068 / 1,669,068 | 262,866 | 1.19 | 30/30 |  |
| issue_new_s2_admin | 1,405,358 / 1,405,358 / 1,405,358 | 1,668,224 / 1,668,224 / 1,668,224 | 262,866 | 1.19 | 8/8 |  |
| issue_show_s1 | 337,744 / 337,744 / 337,744 | 52,750 / 52,750 / 52,750 | -284,994 | 0.16 | 30/30 |  |
| issue_show_s2 | 1,419,400 / 1,419,400 / 1,419,400 | 1,682,381 / 1,682,381 / 1,682,381 | 262,981 | 1.19 | 30/30 |  |
| issue_show_s2_admin | 1,418,293 / 1,418,293 / 1,418,293 | 1,681,274 / 1,681,274 / 1,681,274 | 262,981 | 1.19 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 352,105 / 352,105 / 352,105 | 28,176 / 28,176 / 28,176 | -323,929 | 0.08 | 30/30 |  |
| project_deps_s2_part | - | 1,571,016 / 1,571,016 / 1,571,016 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 323,855 / 323,855 / 323,855 | 33,111 / 33,111 / 33,111 | -290,744 | 0.10 | 30/30 |  |
| project_settings_s2 | 319,874 / 319,874 / 319,874 | 29,131 / 29,131 / 29,131 | -290,743 | 0.09 | 8/8 |  |
| project_values_s1_city | 364,679 / 364,679 / 364,679 | 76,241 / 76,241 / 76,241 | -288,438 | 0.21 | 30/30 |  |
| project_values_s2_part | 49,430,283 / 49,430,283 / 49,430,283 | 60,199 / 60,199 / 60,199 | -49,370,084 | 0.00 | 3/15 | main: heavy (18 s first) |

#### Response bytes gzipped

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 67,442 / 67,449 / 67,432 | 8,698 / 8,702 / 8,693 | -58,744 | 0.13 | 30/30 |  |
| admin_cf_part | - | 136,211 / 136,215 / 136,205 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 66,749 / 66,754 / 66,741 | 7,516 / 7,519 / 7,512 | -59,233 | 0.11 | 30/30 |  |
| bulk_edit_s2 | 202,844 / 202,847 / 202,838 | 212,951 / 212,959 / 212,948 | 10,107 | 1.05 | 8/8 |  |
| context_menu_s1 | 2,869 / 2,872 / 2,865 | 1,324 / 1,324 / 1,324 | -1,545 | 0.46 | 30/30 |  |
| context_menu_s2 | 137,059 / 137,062 / 137,052 | 1,185 / 1,185 / 1,185 | -135,873 | 0.01 | 30/30 |  |
| issue_edit_s1 | 67,784 / 67,789 / 67,775 | 8,518 / 8,521 / 8,508 | -59,266 | 0.13 | 30/30 |  |
| issue_edit_s2 | 204,309 / 204,315 / 204,301 | 214,391 / 214,395 / 214,380 | 10,082 | 1.05 | 30/30 |  |
| issue_edit_s2_admin | 204,243 / 204,247 / 204,238 | 214,348 / 214,350 / 214,344 | 10,105 | 1.05 | 8/8 |  |
| issue_list_s1 | 71,237 / 71,241 / 71,230 | 10,959 / 10,964 / 10,954 | -60,278 | 0.15 | 30/30 |  |
| issue_list_s2 | 193,802 / 193,809 / 193,793 | 133,893 / 133,897 / 133,884 | -59,909 | 0.69 | 30/30 |  |
| issue_new_baseline | 197,458 / 197,463 / 197,451 | 137,912 / 137,917 / 137,906 | -59,546 | 0.70 | 8/8 |  |
| issue_new_s1 | 67,504 / 67,508 / 67,493 | 8,096 / 8,101 / 8,089 | -59,407 | 0.12 | 30/30 |  |
| issue_new_s2 | 203,698 / 203,702 / 203,684 | 213,786 / 213,792 / 213,776 | 10,088 | 1.05 | 30/30 |  |
| issue_new_s2_admin | 203,615 / 203,633 / 203,611 | 213,719 / 213,725 / 213,716 | 10,104 | 1.05 | 8/8 |  |
| issue_show_s1 | 70,267 / 70,274 / 70,256 | 10,788 / 10,792 / 10,781 | -59,479 | 0.15 | 30/30 |  |
| issue_show_s2 | 206,653 / 206,658 / 206,642 | 216,747 / 216,751 / 216,732 | 10,094 | 1.05 | 30/30 |  |
| issue_show_s2_admin | 206,521 / 206,534 / 206,512 | 216,598 / 216,604 / 216,589 | 10,077 | 1.05 | 8/8 |  |
| project_deps_s1_city | 65,391 / 65,398 / 65,385 | 7,246 / 7,248 / 7,242 | -58,145 | 0.11 | 30/30 |  |
| project_deps_s2_part | - | 150,105 / 150,108 / 150,098 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 66,609 / 66,614 / 66,597 | 6,716 / 6,720 / 6,709 | -59,893 | 0.10 | 30/30 |  |
| project_settings_s2 | 66,377 / 66,380 / 66,367 | 6,509 / 6,510 / 6,505 | -59,867 | 0.10 | 8/8 |  |
| project_values_s1_city | 69,926 / 69,935 / 69,900 | 10,372 / 10,379 / 10,349 | -59,554 | 0.15 | 30/30 |  |
| project_values_s2_part | - | 9,574 / 9,585 / 9,556 | - | - | 3/15 | main: heavy (18 s first) |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 4.8 min.

#### domContentLoaded (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,389 / 1,473 / 1,270 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 363 / 385 / 330 | 308 / 313 / 293 | -55 | 0.85 | 10/10 |  |
| context_menu_s2 | 434 / 521 / 418 | 393 / 441 / 362 | -41 | 0.91 | 5/5 |  |
| issue_edit_s2 | 1,771 / 1,874 / 1,635 | 1,739 / 1,916 / 1,642 | -32 | 0.98 | 10/10 |  |
| issue_new_s1 | 386 / 509 / 361 | 346 / 377 / 327 | -40 | 0.90 | 10/10 |  |
| issue_new_s2 | 1,743 / 1,850 / 1,646 | 1,715 / 1,824 / 1,620 | -28 | 0.98 | 10/10 |  |

#### load event (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,451 / 1,535 / 1,329 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 371 / 393 / 336 | 315 / 319 / 299 | -56 | 0.85 | 10/10 |  |
| context_menu_s2 | 435 / 527 / 424 | 400 / 450 / 368 | -35 | 0.92 | 5/5 |  |
| issue_edit_s2 | 1,981 / 2,073 / 1,833 | 1,935 / 2,103 / 1,861 | -46 | 0.98 | 10/10 |  |
| issue_new_s1 | 394 / 514 / 370 | 353 / 384 / 334 | -41 | 0.90 | 10/10 |  |
| issue_new_s2 | 1,975 / 2,055 / 1,865 | 1,925 / 2,025 / 1,830 | -49 | 0.98 | 10/10 |  |

#### time to first byte (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 412 / 542 / 369 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 173 / 193 / 150 | 142 / 153 / 131 | -31 | 0.82 | 10/10 |  |
| context_menu_s2 | 259 / 350 / 244 | 227 / 261 / 222 | -32 | 0.88 | 5/5 |  |
| issue_edit_s2 | 537 / 579 / 504 | 521 / 710 / 483 | -16 | 0.97 | 10/10 |  |
| issue_new_s1 | 145 / 163 / 127 | 123 / 126 / 109 | -22 | 0.85 | 10/10 |  |
| issue_new_s2 | 499 / 528 / 482 | 502 / 526 / 464 | 3 | 1.01 | 10/10 |  |

#### JSHeapUsedSize (MB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 6.6 / 6.8 / 6.6 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 4.3 / 4.3 / 4.3 | 3.7 / 3.7 / 3.6 | -0.6 | 0.85 | 10/10 |  |
| context_menu_s2 | 4.3 / 4.3 / 4.3 | 3.6 / 3.7 / 3.6 | -0.6 | 0.85 | 5/5 |  |
| issue_edit_s2 | 4.7 / 4.8 / 4.5 | 8.8 / 9.6 / 6.3 | 4.1 | 1.86 | 10/10 |  |
| issue_new_s1 | 4.6 / 4.6 / 4.5 | 4 / 4 / 4 | -0.6 | 0.88 | 10/10 |  |
| issue_new_s2 | 4.6 / 5.8 / 4.4 | 8.9 / 9.4 / 8.3 | 4.3 | 1.94 | 10/10 |  |

#### ScriptDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 224 / 237 / 202 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 86 / 96 / 73 | 83 / 87 / 77 | -3 | 0.97 | 10/10 |  |
| context_menu_s2 | 79 / 110 / 75 | 80 / 96 / 75 | 1 | 1.01 | 5/5 |  |
| issue_edit_s2 | 420 / 432 / 405 | 404 / 437 / 374 | -16 | 0.96 | 10/10 |  |
| issue_new_s1 | 92 / 97 / 86 | 91 / 95 / 82 | -2 | 0.98 | 10/10 |  |
| issue_new_s2 | 438 / 455 / 423 | 417 / 432 / 396 | -21 | 0.95 | 10/10 |  |

#### TaskDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,053 / 1,085 / 968 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 223 / 234 / 207 | 191 / 202 / 186 | -32 | 0.86 | 10/10 |  |
| context_menu_s2 | 207 / 230 / 198 | 188 / 206 / 167 | -19 | 0.91 | 5/5 |  |
| issue_edit_s2 | 1,575 / 1,595 / 1,460 | 1,544 / 1,595 / 1,470 | -31 | 0.98 | 10/10 |  |
| issue_new_s1 | 280 / 298 / 261 | 258 / 291 / 234 | -22 | 0.92 | 10/10 |  |
| issue_new_s2 | 1,600 / 1,627 / 1,511 | 1,549 / 1,653 / 1,447 | -51 | 0.97 | 10/10 |  |

#### LayoutDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 404 / 417 / 367 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 23 / 26 / 17 | 21 / 24 / 18 | -2 | 0.92 | 10/10 |  |
| context_menu_s2 | 20 / 22 / 18 | 21 / 34 / 19 | 1 | 1.05 | 5/5 |  |
| issue_edit_s2 | 244 / 261 / 237 | 248 / 254 / 233 | 4 | 1.02 | 10/10 |  |
| issue_new_s1 | 23 / 30 / 19 | 26 / 37 / 20 | 3 | 1.13 | 10/10 |  |
| issue_new_s2 | 245 / 261 / 241 | 246 / 275 / 229 | 0 | 1.00 | 10/10 |  |

#### RecalcStyleDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 90 / 95 / 83 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 14 / 16 / 12 | 15 / 19 / 13 | 1 | 1.11 | 10/10 |  |
| context_menu_s2 | 13 / 17 / 12 | 13 / 15 / 11 | 0 | 1.00 | 5/5 |  |
| issue_edit_s2 | 336 / 348 / 318 | 348 / 359 / 329 | 12 | 1.04 | 10/10 |  |
| issue_new_s1 | 25 / 29 / 21 | 24 / 27 / 19 | -1 | 0.97 | 10/10 |  |
| issue_new_s2 | 356 / 361 / 330 | 338 / 361 / 326 | -18 | 0.95 | 10/10 |  |

#### DOM nodes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 53,950 / 53,963 / 53,941 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 3,542 / 3,542 / 3,542 | 3,540 / 3,540 / 3,540 | -2 | 1.00 | 10/10 |  |
| context_menu_s2 | 3,430 / 3,430 / 3,430 | 3,428 / 3,428 / 3,428 | -2 | 1.00 | 5/5 |  |
| issue_edit_s2 | 181,170 / 181,256 / 181,083 | 181,250 / 181,250 / 181,077 | 81 | 1.00 | 10/10 |  |
| issue_new_s1 | 3,615 / 3,615 / 3,615 | 3,617 / 3,617 / 3,617 | 2 | 1.00 | 10/10 |  |
| issue_new_s2 | 180,788 / 181,040 / 180,784 | 180,864 / 181,039 / 180,783 | 76 | 1.00 | 10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 179 / 183 / 175 | - | - | 0/10 | main: timeout > 30 s |
| issue_new_s1 | 7 / 7 / 7 | 10 / 11 / 10 | 3 | 1.48 | 10/10 |  |
| issue_new_s2 | 245 / 252 / 239 | 241 / 245 / 237 | -5 | 0.98 | 10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 185.3 / 185.3 / 185.3 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| context_menu_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 5/5 |  |
| issue_edit_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| issue_new_s1 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |
| issue_new_s2 | 30.4 / 30.4 / 30.4 | 65 / 65 / 65 | 34.6 | 2.14 | 10/10 |  |

#### Plugin asset load time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 110 / 187 / 80 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 79 / 102 / 53 | 83 / 93 / 39 | 3 | 1.04 | 10/10 |  |
| context_menu_s2 | 50 / 90 / 40 | 87 / 100 / 41 | 37 | 1.73 | 5/5 |  |
| issue_edit_s2 | 80 / 118 / 52 | 69 / 108 / 42 | -11 | 0.87 | 10/10 |  |
| issue_new_s1 | 88 / 119 / 56 | 90 / 114 / 57 | 2 | 1.02 | 10/10 |  |
| issue_new_s2 | 74 / 112 / 47 | 73 / 87 / 46 | -1 | 0.99 | 10/10 |  |

#### Context menu shown (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 226 / 335 / 207 | 137 / 159 / 121 | -89 | 0.61 | 10/10 |  |
| context_menu_s2 | 921 / 1,002 / 829 | 216 / 227 / 193 | -705 | 0.23 | 5/5 |  |

#### Wizard opened (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 5 / 6 / 5 | 71 / 76 / 62 | 66 | 13.06 | 10/10 |  |
| context_menu_s2 | 462 / 479 / 430 | 1,499 / 1,561 / 1,423 | 1,038 | 3.25 | 5/5 |  |

#### Interaction: change handler returns (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 3 / 3 / 3 | 3 / 3 / 3 | 0 | 0.97 | 10/10 |  |
| interaction_s2_assembly | 155 / 166 / 136 | 89 / 94 / 80 | -66 | 0.57 | 10/10 |  |

#### Interaction: options shown and painted (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 9 / 12 / 9 | 11 / 18 / 8 | 2 | 1.24 | 10/10 |  |
| interaction_s2_assembly | 333 / 363 / 313 | 177 / 190 / 158 | -156 | 0.53 | 10/10 |  |

#### js_errors

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 0 / 0 / 0 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| context_menu_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 5/5 |  |
| issue_edit_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |

