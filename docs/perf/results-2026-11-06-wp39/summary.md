# Performance summary: main (0.0.15) versus branch

Generated 2026-11-06T00:33:13.084Z. Cells: median / p90 / min. Delta = branch median minus main median, ratio = branch median / main median (below 1 means the branch is faster or smaller).

## Redmine 5.1

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 300, 13.8 min, load average at start 0.79.

### Memory (puma worker, 1 thread)

| checkpoint | main RSS (MB) | branch RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|
| after_boot | 183 | 180 | - | - | - | - |
| after_warmup | 301 | 303 | 306 | 312 | 1,143,482 | 979,498 |
| after_rounds | 306 | 302 | 312 | 323 | 1,147,108 | 980,516 |
| after_mixed | 335 | 293 | 347 | 323 | 1,166,385 | 918,855 |
| mixed run totals (300 requests) | time 99 s, objects 125,809,823, SQL 14575 | time 78 s, objects 71,100,481, SQL 14162 | | | | |
| after_heavy | 233 (restarted) | 313 | 233 | 323 | 854,325 | 1,343,295 |

Update check (PATCH stores the new values, reset restores them): {"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 140 / 153 / 132 | 56 / 65 / 48 | -84 | 0.40 | 30/30 |  |
| admin_cf_part | - | 393 / 407 / 380 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 274 / 308 / 258 | 207 / 247 / 177 | -67 | 0.75 | 30/30 |  |
| bulk_edit_s2 | 671 / 737 / 650 | 672 / 748 / 648 | 1 | 1.00 | 8/8 |  |
| context_menu_s1 | 175 / 189 / 156 | 105 / 117 / 93 | -69 | 0.60 | 30/30 |  |
| context_menu_s2 | 872 / 923 / 694 | 157 / 174 / 141 | -715 | 0.18 | 30/30 |  |
| issue_edit_s1 | 186 / 216 / 175 | 108 / 123 / 90 | -78 | 0.58 | 30/30 |  |
| issue_edit_s2 | 729 / 814 / 559 | 626 / 663 / 584 | -103 | 0.86 | 30/30 |  |
| issue_edit_s2_admin | 660 / 785 / 580 | 617 / 634 / 579 | -43 | 0.93 | 8/8 |  |
| issue_list_s1 | 292 / 438 / 261 | 215 / 254 / 187 | -77 | 0.74 | 30/30 |  |
| issue_list_s2 | 874 / 936 / 707 | 729 / 791 / 608 | -146 | 0.83 | 30/30 |  |
| issue_new_baseline | 634 / 722 / 531 | 618 / 662 / 445 | -16 | 0.98 | 8/8 |  |
| issue_new_s1 | 184 / 204 / 165 | 103 / 117 / 86 | -80 | 0.56 | 30/30 |  |
| issue_new_s2 | 602 / 620 / 569 | 730 / 778 / 599 | 128 | 1.21 | 30/30 |  |
| issue_new_s2_admin | 585 / 787 / 546 | 763 / 785 / 753 | 178 | 1.30 | 8/8 |  |
| issue_show_s1 | 371 / 500 / 323 | 270 / 305 / 230 | -100 | 0.73 | 30/30 |  |
| issue_show_s2 | 761 / 884 / 717 | 787 / 848 / 745 | 26 | 1.03 | 30/30 |  |
| issue_show_s2_admin | 663 / 792 / 607 | 628 / 694 / 593 | -34 | 0.95 | 8/8 |  |
| issue_update_s1 | 80 / 97 / 69 | 81 / 91 / 68 | 1 | 1.02 | 30/30 |  |
| issue_update_s2 | 198 / 221 / 186 | 219 / 230 / 205 | 21 | 1.10 | 30/30 |  |
| project_deps_s1_city | 137 / 149 / 125 | 53 / 69 / 45 | -85 | 0.38 | 30/30 |  |
| project_deps_s2_part | - | 654 / 813 / 632 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 181 / 202 / 161 | 101 / 112 / 89 | -81 | 0.55 | 30/30 |  |
| project_settings_s2 | 322 / 465 / 300 | 245 / 268 / 219 | -77 | 0.76 | 8/8 |  |
| project_values_s1_city | 161 / 173 / 149 | 71 / 87 / 60 | -90 | 0.44 | 30/30 |  |
| project_values_s2_part | 18,216 / 18,216 / 17,948 | 382 / 534 / 365 | -17,833 | 0.02 | 3/15 | main: heavy (18 s first) |

#### Process CPU time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 131 / 139 / 123 | 47 / 52 / 38 | -84 | 0.36 | 30/30 |  |
| admin_cf_part | - | 375 / 383 / 365 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 247 / 269 / 233 | 179 / 201 / 155 | -68 | 0.72 | 30/30 |  |
| bulk_edit_s2 | 634 / 675 / 616 | 642 / 677 / 624 | 7 | 1.01 | 8/8 |  |
| context_menu_s1 | 152 / 164 / 140 | 86 / 94 / 79 | -66 | 0.57 | 30/30 |  |
| context_menu_s2 | 833 / 860 / 671 | 136 / 142 / 125 | -697 | 0.16 | 30/30 |  |
| issue_edit_s1 | 169 / 187 / 160 | 88 / 100 / 78 | -81 | 0.52 | 30/30 |  |
| issue_edit_s2 | 705 / 756 / 540 | 582 / 606 / 562 | -122 | 0.83 | 30/30 |  |
| issue_edit_s2_admin | 635 / 741 / 539 | 578 / 587 / 559 | -57 | 0.91 | 8/8 |  |
| issue_list_s1 | 249 / 392 / 228 | 170 / 188 / 154 | -79 | 0.68 | 30/30 |  |
| issue_list_s2 | 812 / 847 / 648 | 658 / 698 / 510 | -154 | 0.81 | 30/30 |  |
| issue_new_baseline | 597 / 683 / 508 | 587 / 616 / 416 | -9 | 0.98 | 8/8 |  |
| issue_new_s1 | 166 / 178 / 153 | 87 / 95 / 74 | -78 | 0.53 | 30/30 |  |
| issue_new_s2 | 569 / 581 / 548 | 706 / 737 / 572 | 137 | 1.24 | 30/30 |  |
| issue_new_s2_admin | 557 / 737 / 528 | 739 / 749 / 728 | 182 | 1.33 | 8/8 |  |
| issue_show_s1 | 311 / 442 / 282 | 218 / 231 / 191 | -92 | 0.70 | 30/30 |  |
| issue_show_s2 | 696 / 794 / 667 | 720 / 749 / 691 | 24 | 1.03 | 30/30 |  |
| issue_show_s2_admin | 618 / 758 / 580 | 596 / 637 / 573 | -22 | 0.96 | 8/8 |  |
| issue_update_s1 | 64 / 73 / 56 | 65 / 71 / 57 | 1 | 1.01 | 30/30 |  |
| issue_update_s2 | 178 / 195 / 170 | 197 / 203 / 190 | 19 | 1.10 | 30/30 |  |
| project_deps_s1_city | 124 / 131 / 118 | 43 / 48 / 38 | -82 | 0.34 | 30/30 |  |
| project_deps_s2_part | - | 627 / 779 / 609 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 160 / 171 / 144 | 80 / 88 / 72 | -80 | 0.50 | 30/30 |  |
| project_settings_s2 | 290 / 442 / 278 | 215 / 234 / 199 | -75 | 0.74 | 8/8 |  |
| project_values_s1_city | 151 / 158 / 140 | 61 / 70 / 53 | -90 | 0.40 | 30/30 |  |
| project_values_s2_part | 18,026 / 18,047 / 17,760 | 365 / 521 / 348 | -17,660 | 0.02 | 3/15 | main: heavy (18 s first) |

#### View time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 118 / 129 / 110 | 36 / 43 / 28 | -83 | 0.30 | 30/30 |  |
| admin_cf_part | - | 360 / 375 / 346 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 121 / 130 / 114 | 45 / 55 / 37 | -76 | 0.37 | 30/30 |  |
| bulk_edit_s2 | 514 / 524 / 502 | 520 / 594 / 503 | 6 | 1.01 | 8/8 |  |
| context_menu_s1 | 60 / 70 / 54 | 12 / 13 / 11 | -48 | 0.20 | 30/30 |  |
| context_menu_s2 | 602 / 650 / 440 | 11 / 12 / 10 | -591 | 0.02 | 30/30 |  |
| issue_edit_s1 | 132 / 151 / 125 | 53 / 61 / 45 | -80 | 0.40 | 30/30 |  |
| issue_edit_s2 | 661 / 743 / 493 | 549 / 583 / 511 | -112 | 0.83 | 30/30 |  |
| issue_edit_s2_admin | 545 / 719 / 503 | 541 / 557 / 510 | -4 | 0.99 | 8/8 |  |
| issue_list_s1 | 181 / 321 / 166 | 100 / 116 / 89 | -81 | 0.55 | 30/30 |  |
| issue_list_s2 | 693 / 749 / 518 | 537 / 596 / 423 | -155 | 0.78 | 30/30 |  |
| issue_new_baseline | 553 / 643 / 468 | 559 / 601 / 386 | 6 | 1.01 | 8/8 |  |
| issue_new_s1 | 140 / 151 / 126 | 59 / 67 / 49 | -81 | 0.42 | 30/30 |  |
| issue_new_s2 | 536 / 556 / 509 | 669 / 713 / 532 | 133 | 1.25 | 30/30 |  |
| issue_new_s2_admin | 523 / 729 / 496 | 704 / 728 / 694 | 182 | 1.35 | 8/8 |  |
| issue_show_s1 | 175 / 199 / 142 | 80 / 91 / 64 | -95 | 0.46 | 30/30 |  |
| issue_show_s2 | 566 / 685 / 533 | 575 / 624 / 548 | 9 | 1.02 | 30/30 |  |
| issue_show_s2_admin | 592 / 724 / 536 | 561 / 604 / 534 | -31 | 0.95 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 107 / 115 / 99 | 24 / 38 / 20 | -83 | 0.22 | 30/30 |  |
| project_deps_s2_part | - | 289 / 434 / 271 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 135 / 147 / 119 | 56 / 63 / 48 | -79 | 0.41 | 30/30 |  |
| project_settings_s2 | 268 / 413 / 251 | 191 / 210 / 176 | -77 | 0.71 | 8/8 |  |
| project_values_s1_city | 130 / 142 / 118 | 43 / 55 / 37 | -87 | 0.33 | 30/30 |  |
| project_values_s2_part | 17,421 / 17,448 / 17,153 | 42 / 141 / 40 | -17,379 | 0.00 | 3/15 | main: heavy (18 s first) |

#### ActiveRecord time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 11 / 14 / 9 | 12 / 14 / 10 | 1 | 1.10 | 30/30 |  |
| admin_cf_part | - | 16 / 19 / 15 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 36 / 47 / 31 | 36 / 42 / 29 | 0 | 0.99 | 30/30 |  |
| bulk_edit_s2 | 41 / 66 / 36 | 36 / 53 / 34 | -4 | 0.89 | 8/8 |  |
| context_menu_s1 | 29 / 32 / 24 | 22 / 26 / 18 | -7 | 0.76 | 30/30 |  |
| context_menu_s2 | 32 / 36 / 29 | 26 / 31 / 22 | -7 | 0.79 | 30/30 |  |
| issue_edit_s1 | 22 / 25 / 18 | 20 / 24 / 16 | -1 | 0.94 | 30/30 |  |
| issue_edit_s2 | 29 / 34 / 25 | 29 / 32 / 25 | -1 | 0.98 | 30/30 |  |
| issue_edit_s2_admin | 25 / 38 / 24 | 27 / 28 / 24 | 2 | 1.09 | 8/8 |  |
| issue_list_s1 | 46 / 55 / 42 | 45 / 55 / 38 | -1 | 0.98 | 30/30 |  |
| issue_list_s2 | 66 / 74 / 61 | 65 / 82 / 58 | -1 | 0.99 | 30/30 |  |
| issue_new_baseline | 30 / 33 / 25 | 24 / 28 / 22 | -6 | 0.80 | 8/8 |  |
| issue_new_s1 | 20 / 25 / 17 | 20 / 25 / 15 | 0 | 0.99 | 30/30 |  |
| issue_new_s2 | 26 / 30 / 22 | 26 / 30 / 23 | 0 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 22 / 26 / 20 | 21 / 26 / 20 | -2 | 0.92 | 8/8 |  |
| issue_show_s1 | 61 / 70 / 52 | 60 / 72 / 50 | -1 | 0.99 | 30/30 |  |
| issue_show_s2 | 67 / 82 / 59 | 66 / 75 / 59 | -1 | 0.98 | 30/30 |  |
| issue_show_s2_admin | 33 / 37 / 31 | 32 / 37 / 27 | -1 | 0.97 | 8/8 |  |
| issue_update_s1 | 20 / 24 / 16 | 19 / 23 / 15 | -1 | 0.95 | 30/30 |  |
| issue_update_s2 | 25 / 30 / 21 | 24 / 32 / 21 | -1 | 0.97 | 30/30 |  |
| project_deps_s1_city | 10 / 12 / 8 | 11 / 13 / 8 | 1 | 1.08 | 30/30 |  |
| project_deps_s2_part | - | 20 / 24 / 17 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 26 / 31 / 23 | 26 / 30 / 23 | 0 | 0.99 | 30/30 |  |
| project_settings_s2 | 29 / 36 / 27 | 30 / 37 / 26 | 1 | 1.05 | 8/8 |  |
| project_values_s1_city | 10 / 14 / 8 | 10 / 14 / 8 | 0 | 1.02 | 30/30 |  |
| project_values_s2_part | 20 / 22 / 16 | 18 / 23 / 16 | -2 | 0.90 | 3/15 | main: heavy (18 s first) |

#### Allocations (Rails Completed line)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 246,124 / 246,213 / 246,098 | 22,530 / 22,644 / 22,530 | -223,593 | 0.09 | 30/30 |  |
| admin_cf_part | - | 399,035 / 399,040 / 399,035 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 292,055 / 292,538 / 292,050 | 81,781 / 81,786 / 81,770 | -210,274 | 0.28 | 30/30 |  |
| bulk_edit_s2 | 998,358 / 998,358 / 998,353 | 974,723 / 974,723 / 974,718 | -23,635 | 0.98 | 8/8 |  |
| context_menu_s1 | 155,940 / 156,831 / 155,937 | 39,373 / 40,260 / 39,370 | -116,567 | 0.25 | 30/30 |  |
| context_menu_s2 | 1,066,067 / 1,066,068 / 1,066,061 | 83,211 / 83,215 / 83,209 | -982,856 | 0.08 | 30/30 |  |
| issue_edit_s1 | 256,176 / 256,296 / 256,175 | 44,703 / 44,733 / 44,697 | -211,473 | 0.17 | 30/30 |  |
| issue_edit_s2 | 967,601 / 967,637 / 967,111 | 942,897 / 942,902 / 942,889 | -24,704 | 0.97 | 30/30 |  |
| issue_edit_s2_admin | 965,651 / 965,727 / 965,617 | 941,390 / 941,395 / 941,390 | -24,260 | 0.97 | 8/8 |  |
| issue_list_s1 | 306,261 / 306,266 / 306,256 | 91,429 / 91,434 / 91,424 | -214,832 | 0.30 | 30/30 |  |
| issue_list_s2 | 1,074,203 / 1,074,238 / 1,073,721 | 703,682 / 703,682 / 703,677 | -370,520 | 0.66 | 30/30 |  |
| issue_new_baseline | 897,063 / 897,069 / 896,540 | 682,430 / 682,430 / 682,425 | -214,633 | 0.76 | 8/8 |  |
| issue_new_s1 | 254,112 / 254,135 / 254,108 | 42,198 / 42,233 / 42,192 | -211,913 | 0.17 | 30/30 |  |
| issue_new_s2 | 965,530 / 965,535 / 965,504 | 941,174 / 941,177 / 941,169 | -24,355 | 0.97 | 30/30 |  |
| issue_new_s2_admin | 963,582 / 963,603 / 963,569 | 939,237 / 939,240 / 939,232 | -24,344 | 0.97 | 8/8 |  |
| issue_show_s1 | 332,857 / 332,922 / 332,846 | 121,355 / 121,360 / 121,349 | -211,502 | 0.36 | 30/30 |  |
| issue_show_s2 | 1,042,976 / 1,043,485 / 1,042,960 | 1,018,733 / 1,018,735 / 1,018,720 | -24,243 | 0.98 | 30/30 |  |
| issue_show_s2_admin | 974,473 / 974,958 / 974,469 | 950,217 / 950,332 / 950,212 | -24,255 | 0.98 | 8/8 |  |
| issue_update_s1 | 21,789 / 21,820 / 21,789 | 21,701 / 21,703 / 21,701 | -88 | 1.00 | 30/30 |  |
| issue_update_s2 | 123,631 / 123,637 / 123,149 | 123,210 / 123,261 / 123,210 | -421 | 1.00 | 30/30 |  |
| project_deps_s1_city | 243,830 / 243,836 / 243,800 | 21,514 / 21,514 / 21,514 | -222,316 | 0.09 | 30/30 |  |
| project_deps_s2_part | - | 1,191,895 / 1,191,895 / 1,191,890 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 251,075 / 251,076 / 251,043 | 36,698 / 36,703 / 36,698 | -214,377 | 0.15 | 30/30 |  |
| project_settings_s2 | 353,797 / 353,830 / 353,793 | 139,788 / 139,793 / 139,788 | -214,008 | 0.40 | 8/8 |  |
| project_values_s1_city | 257,418 / 258,282 / 257,382 | 44,932 / 45,822 / 44,932 | -212,486 | 0.17 | 30/30 |  |
| project_values_s2_part | 23,046,560 / 23,046,754 / 23,046,506 | 605,195 / 605,200 / 605,195 | -22,441,365 | 0.03 | 3/15 | main: heavy (18 s first) |

#### SQL queries (without SCHEMA and CACHE)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 16 / 17 / 16 | 17 / 18 / 17 | 1 | 1.06 | 30/30 |  |
| admin_cf_part | - | 17 / 17 / 17 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 73 / 73 / 73 | 73 / 73 / 73 | 0 | 1.00 | 30/30 |  |
| bulk_edit_s2 | 69 / 69 / 69 | 69 / 69 / 69 | 0 | 1.00 | 8/8 |  |
| context_menu_s1 | 44 / 47 / 44 | 38 / 41 / 38 | -6 | 0.86 | 30/30 |  |
| context_menu_s2 | 42 / 42 / 42 | 38 / 38 / 38 | -4 | 0.90 | 30/30 |  |
| issue_edit_s1 | 48 / 48 / 48 | 47 / 47 / 47 | -1 | 0.98 | 30/30 |  |
| issue_edit_s2 | 45 / 45 / 45 | 45 / 45 / 45 | 0 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 36 / 37 / 36 | 36 / 36 / 36 | 0 | 1.00 | 8/8 |  |
| issue_list_s1 | 63 / 63 / 63 | 61 / 61 / 61 | -2 | 0.97 | 30/30 |  |
| issue_list_s2 | 43 / 43 / 43 | 41 / 41 / 41 | -2 | 0.95 | 30/30 |  |
| issue_new_baseline | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 8/8 |  |
| issue_new_s1 | 41 / 41 / 41 | 40 / 40 / 40 | -1 | 0.98 | 30/30 |  |
| issue_new_s2 | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 31 / 31 / 31 | 31 / 31 / 31 | 0 | 1.00 | 8/8 |  |
| issue_show_s1 | 72 / 72 / 72 | 71 / 71 / 71 | -1 | 0.99 | 30/30 |  |
| issue_show_s2 | 65 / 65 / 65 | 65 / 65 / 65 | 0 | 1.00 | 30/30 |  |
| issue_show_s2_admin | 47 / 47 / 47 | 47 / 48 / 47 | 0 | 1.00 | 8/8 |  |
| issue_update_s1 | 52 / 52 / 52 | 49 / 49 / 49 | -3 | 0.94 | 30/30 |  |
| issue_update_s2 | 42 / 42 / 42 | 41 / 41 / 41 | -1 | 0.98 | 30/30 |  |
| project_deps_s1_city | 21 / 21 / 21 | 23 / 23 / 23 | 2 | 1.10 | 30/30 |  |
| project_deps_s2_part | - | 23 / 23 / 23 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 46 / 46 / 46 | 46 / 46 / 46 | 0 | 1.00 | 30/30 |  |
| project_settings_s2 | 46 / 46 / 46 | 45 / 45 / 45 | -1 | 0.98 | 8/8 |  |
| project_values_s1_city | 22 / 25 / 22 | 22 / 25 / 22 | 0 | 1.00 | 30/30 |  |
| project_values_s2_part | 22 / 23 / 22 | 22 / 22 / 22 | 0 | 1.00 | 3/15 | main: heavy (18 s first) |

#### Response bytes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 348,695 / 348,695 / 348,695 | 30,557 / 30,557 / 30,557 | -318,138 | 0.09 | 30/30 |  |
| admin_cf_part | - | 824,653 / 824,653 / 824,653 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 320,086 / 320,086 / 320,086 | 33,989 / 33,989 / 33,989 | -286,097 | 0.11 | 30/30 |  |
| bulk_edit_s2 | 1,402,808 / 1,402,808 / 1,402,808 | 1,410,759 / 1,410,759 / 1,410,759 | 7,951 | 1.01 | 8/8 |  |
| context_menu_s1 | 26,121 / 26,121 / 26,121 | 13,420 / 13,420 / 13,420 | -12,701 | 0.51 | 30/30 |  |
| context_menu_s2 | 1,105,754 / 1,105,754 / 1,105,754 | 11,308 / 11,308 / 11,308 | -1,094,446 | 0.01 | 30/30 |  |
| issue_edit_s1 | 321,933 / 321,933 / 321,933 | 36,035 / 36,035 / 36,035 | -285,898 | 0.11 | 30/30 |  |
| issue_edit_s2 | 1,404,076 / 1,404,076 / 1,404,076 | 1,412,203 / 1,412,203 / 1,412,203 | 8,127 | 1.01 | 30/30 |  |
| issue_edit_s2_admin | 1,403,248 / 1,403,248 / 1,403,248 | 1,411,375 / 1,411,375 / 1,411,375 | 8,127 | 1.01 | 8/8 |  |
| issue_list_s1 | 364,068 / 364,068 / 364,068 | 73,196 / 73,196 / 73,196 | -290,872 | 0.20 | 30/30 |  |
| issue_list_s2 | 943,634 / 943,634 / 943,634 | 652,762 / 652,762 / 652,762 | -290,872 | 0.69 | 30/30 |  |
| issue_new_baseline | 1,535,014 / 1,535,014 / 1,535,014 | 1,244,142 / 1,244,142 / 1,244,142 | -290,872 | 0.81 | 8/8 |  |
| issue_new_s1 | 320,575 / 320,575 / 320,575 | 33,952 / 33,952 / 33,952 | -286,623 | 0.11 | 30/30 |  |
| issue_new_s2 | 1,402,661 / 1,402,661 / 1,402,661 | 1,410,673 / 1,410,673 / 1,410,673 | 8,012 | 1.01 | 30/30 |  |
| issue_new_s2_admin | 1,401,873 / 1,401,873 / 1,401,873 | 1,409,885 / 1,409,885 / 1,409,885 | 8,012 | 1.01 | 8/8 |  |
| issue_show_s1 | 330,480 / 330,480 / 330,480 | 44,582 / 44,582 / 44,582 | -285,898 | 0.13 | 30/30 |  |
| issue_show_s2 | 1,412,124 / 1,412,124 / 1,412,124 | 1,420,251 / 1,420,251 / 1,420,251 | 8,127 | 1.01 | 30/30 |  |
| issue_show_s2_admin | 1,411,073 / 1,411,073 / 1,411,073 | 1,419,200 / 1,419,200 / 1,419,200 | 8,127 | 1.01 | 8/8 |  |
| issue_update_s1 | 96 / 96 / 96 | 96 / 96 / 96 | 0 | 1.00 | 30/30 |  |
| issue_update_s2 | 98 / 98 / 98 | 98 / 98 / 98 | 0 | 1.00 | 30/30 |  |
| project_deps_s1_city | 349,377 / 349,377 / 349,377 | 25,224 / 25,224 / 25,224 | -324,153 | 0.07 | 30/30 |  |
| project_deps_s2_part | - | 1,568,174 / 1,568,174 / 1,568,174 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 319,471 / 319,471 / 319,471 | 28,734 / 28,734 / 28,734 | -290,737 | 0.09 | 30/30 |  |
| project_settings_s2 | 315,600 / 315,600 / 315,600 | 24,863 / 24,863 / 24,863 | -290,737 | 0.08 | 8/8 |  |
| project_values_s1_city | 360,021 / 360,021 / 360,021 | 71,435 / 71,435 / 71,435 | -288,586 | 0.20 | 30/30 |  |
| project_values_s2_part | 47,752,635 / 47,752,635 / 47,752,635 | 59,308 / 59,308 / 59,308 | -47,693,327 | 0.00 | 3/15 | main: heavy (18 s first) |

#### Response bytes gzipped

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 66,220 / 66,225 / 66,211 | 7,800 / 7,802 / 7,794 | -58,419 | 0.12 | 30/30 |  |
| admin_cf_part | - | 135,091 / 135,096 / 135,081 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 65,838 / 65,844 / 65,827 | 6,880 / 6,884 / 6,874 | -58,958 | 0.10 | 30/30 |  |
| bulk_edit_s2 | 201,805 / 201,808 / 201,794 | 202,096 / 202,103 / 202,090 | 291 | 1.00 | 8/8 |  |
| context_menu_s1 | 2,786 / 2,789 / 2,781 | 1,228 / 1,228 / 1,228 | -1,558 | 0.44 | 30/30 |  |
| context_menu_s2 | 136,959 / 136,962 / 136,955 | 1,093 / 1,093 / 1,093 | -135,866 | 0.01 | 30/30 |  |
| issue_edit_s1 | 66,732 / 66,740 / 66,725 | 7,725 / 7,729 / 7,720 | -59,006 | 0.12 | 30/30 |  |
| issue_edit_s2 | 203,021 / 203,025 / 203,014 | 203,434 / 203,439 / 203,426 | 414 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 202,960 / 202,972 / 202,955 | 203,374 / 203,384 / 203,370 | 414 | 1.00 | 8/8 |  |
| issue_list_s1 | 69,933 / 69,939 / 69,923 | 9,974 / 9,977 / 9,966 | -59,959 | 0.14 | 30/30 |  |
| issue_list_s2 | 192,364 / 192,370 / 192,355 | 132,724 / 132,728 / 132,717 | -59,640 | 0.69 | 30/30 |  |
| issue_new_baseline | 196,379 / 196,384 / 196,368 | 137,015 / 137,019 / 137,008 | -59,363 | 0.70 | 8/8 |  |
| issue_new_s1 | 66,501 / 66,507 / 66,492 | 7,438 / 7,440 / 7,432 | -59,063 | 0.11 | 30/30 |  |
| issue_new_s2 | 202,604 / 202,612 / 202,597 | 202,936 / 202,941 / 202,926 | 332 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 202,541 / 202,546 / 202,529 | 202,867 / 202,871 / 202,861 | 326 | 1.00 | 8/8 |  |
| issue_show_s1 | 68,713 / 68,720 / 68,699 | 9,629 / 9,632 / 9,622 | -59,084 | 0.14 | 30/30 |  |
| issue_show_s2 | 205,079 / 205,087 / 205,069 | 205,419 / 205,422 / 205,408 | 341 | 1.00 | 30/30 |  |
| issue_show_s2_admin | 204,943 / 204,953 / 204,938 | 205,285 / 205,292 / 205,278 | 343 | 1.00 | 8/8 |  |
| project_deps_s1_city | 64,460 / 64,465 / 64,450 | 6,584 / 6,588 / 6,581 | -57,876 | 0.10 | 30/30 |  |
| project_deps_s2_part | - | 149,066 / 149,068 / 149,056 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 65,592 / 65,598 / 65,585 | 5,930 / 5,933 / 5,925 | -59,662 | 0.09 | 30/30 |  |
| project_settings_s2 | 65,374 / 65,385 / 65,368 | 5,731 / 5,735 / 5,728 | -59,643 | 0.09 | 8/8 |  |
| project_values_s1_city | 69,023 / 69,034 / 68,999 | 9,708 / 9,722 / 9,686 | -59,315 | 0.14 | 30/30 |  |
| project_values_s2_part | - | 8,868 / 8,878 / 8,860 | - | - | 3/15 | main: heavy (18 s first) |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 4.4 min.

#### domContentLoaded (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,194 / 1,401 / 1,023 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 363 / 492 / 332 | 235 / 268 / 222 | -128 | 0.65 | 10/10 |  |
| context_menu_s2 | 422 / 436 / 409 | 331 / 342 / 305 | -91 | 0.78 | 5/5 |  |
| issue_edit_s2 | 1,661 / 1,763 / 1,591 | 1,819 / 1,887 / 1,598 | 159 | 1.10 | 10/10 |  |
| issue_new_s1 | 374 / 405 / 353 | 259 / 271 / 237 | -115 | 0.69 | 10/10 |  |
| issue_new_s2 | 1,637 / 1,708 / 1,552 | 1,592 / 1,655 / 1,556 | -45 | 0.97 | 10/10 |  |

#### load event (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,286 / 1,452 / 1,230 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 364 / 493 / 334 | 240 / 269 / 222 | -125 | 0.66 | 10/10 |  |
| context_menu_s2 | 424 / 437 / 410 | 331 / 343 / 305 | -92 | 0.78 | 5/5 |  |
| issue_edit_s2 | 1,864 / 1,940 / 1,777 | 2,035 / 2,104 / 1,805 | 171 | 1.09 | 10/10 |  |
| issue_new_s1 | 379 / 409 / 359 | 263 / 275 / 240 | -116 | 0.69 | 10/10 |  |
| issue_new_s2 | 1,850 / 1,896 / 1,768 | 1,792 / 1,872 / 1,750 | -57 | 0.97 | 10/10 |  |

#### time to first byte (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 393 / 562 / 375 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 220 / 349 / 194 | 119 / 129 / 113 | -101 | 0.54 | 10/10 |  |
| context_menu_s2 | 284 / 295 / 281 | 212 / 215 / 197 | -72 | 0.75 | 5/5 |  |
| issue_edit_s2 | 622 / 642 / 584 | 751 / 861 / 595 | 129 | 1.21 | 10/10 |  |
| issue_new_s1 | 200 / 223 / 186 | 110 / 127 / 96 | -90 | 0.55 | 10/10 |  |
| issue_new_s2 | 595 / 635 / 563 | 595 / 625 / 567 | 0 | 1.00 | 10/10 |  |

#### JSHeapUsedSize (MB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 6.4 / 6.4 / 5.1 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 3.9 / 3.9 / 3.9 | 3.3 / 3.3 / 3.3 | -0.6 | 0.84 | 10/10 |  |
| context_menu_s2 | 3.9 / 3.9 / 3.9 | 3.3 / 3.3 / 3.3 | -0.6 | 0.84 | 5/5 |  |
| issue_edit_s2 | 4.8 / 4.9 / 4.7 | 6.3 / 6.4 / 6.2 | 1.5 | 1.30 | 10/10 |  |
| issue_new_s1 | 4.1 / 4.1 / 4.1 | 3.5 / 3.6 / 3.5 | -0.5 | 0.87 | 10/10 |  |
| issue_new_s2 | 4.7 / 4.8 / 4.4 | 5.9 / 7.1 / 5.8 | 1.2 | 1.26 | 10/10 |  |

#### ScriptDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 205 / 214 / 195 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 71 / 76 / 69 | 73 / 79 / 66 | 2 | 1.02 | 10/10 |  |
| context_menu_s2 | 75 / 87 / 69 | 69 / 76 / 65 | -7 | 0.91 | 5/5 |  |
| issue_edit_s2 | 369 / 385 / 353 | 353 / 357 / 341 | -17 | 0.95 | 10/10 |  |
| issue_new_s1 | 79 / 84 / 76 | 80 / 85 / 75 | 1 | 1.01 | 10/10 |  |
| issue_new_s2 | 365 / 398 / 348 | 347 / 364 / 337 | -18 | 0.95 | 10/10 |  |

#### TaskDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 901 / 929 / 862 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 162 / 170 / 153 | 145 / 156 / 127 | -17 | 0.90 | 10/10 |  |
| context_menu_s2 | 169 / 180 / 151 | 143 / 151 / 131 | -27 | 0.84 | 5/5 |  |
| issue_edit_s2 | 1,370 / 1,442 / 1,322 | 1,372 / 1,486 / 1,318 | 2 | 1.00 | 10/10 |  |
| issue_new_s1 | 196 / 211 / 190 | 178 / 182 / 157 | -19 | 0.91 | 10/10 |  |
| issue_new_s2 | 1,373 / 1,415 / 1,343 | 1,328 / 1,380 / 1,294 | -44 | 0.97 | 10/10 |  |

#### LayoutDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 365 / 375 / 346 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 14 / 16 / 13 | 15 / 16 / 13 | 1 | 1.06 | 10/10 |  |
| context_menu_s2 | 13 / 16 / 13 | 14 / 21 / 12 | 0 | 1.01 | 5/5 |  |
| issue_edit_s2 | 248 / 255 / 242 | 258 / 276 / 242 | 10 | 1.04 | 10/10 |  |
| issue_new_s1 | 18 / 20 / 16 | 18 / 19 / 15 | -1 | 0.97 | 10/10 |  |
| issue_new_s2 | 246 / 255 / 240 | 246 / 259 / 233 | 0 | 1.00 | 10/10 |  |

#### RecalcStyleDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 70 / 75 / 67 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 11 / 12 / 10 | 10 / 11 / 9 | -1 | 0.94 | 10/10 |  |
| context_menu_s2 | 10 / 11 / 10 | 10 / 12 / 9 | 0 | 1.02 | 5/5 |  |
| issue_edit_s2 | 306 / 322 / 299 | 324 / 364 / 311 | 18 | 1.06 | 10/10 |  |
| issue_new_s1 | 20 / 23 / 19 | 18 / 20 / 17 | -2 | 0.88 | 10/10 |  |
| issue_new_s2 | 318 / 321 / 307 | 310 / 323 / 300 | -8 | 0.97 | 10/10 |  |

#### DOM nodes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 52,549 / 52,556 / 52,548 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 2,137 / 2,137 / 2,137 | 2,135 / 2,135 / 2,135 | -2 | 1.00 | 10/10 |  |
| context_menu_s2 | 2,025 / 2,025 / 2,025 | 2,023 / 2,023 / 2,023 | -2 | 1.00 | 5/5 |  |
| issue_edit_s2 | 179,618 / 179,750 / 179,618 | 179,614 / 179,623 / 179,614 | -4 | 1.00 | 10/10 |  |
| issue_new_s1 | 2,201 / 2,201 / 2,201 | 2,211 / 2,211 / 2,211 | 10 | 1.00 | 10/10 |  |
| issue_new_s2 | 179,402 / 179,606 / 179,402 | 179,403 / 179,607 / 179,403 | 1 | 1.00 | 10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 160 / 165 / 155 | - | - | 0/10 | main: timeout > 30 s |
| issue_new_s1 | 6 / 7 / 6 | 9 / 10 / 9 | 3 | 1.50 | 10/10 |  |
| issue_new_s2 | 207 / 211 / 203 | 179 / 184 / 173 | -28 | 0.86 | 10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 194.6 / 194.6 / 194.6 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| context_menu_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 5/5 |  |
| issue_edit_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| issue_new_s1 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| issue_new_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |

#### Plugin asset load time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 108 / 118 / 55 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 50 / 63 / 32 | 42 / 49 / 17 | -8 | 0.84 | 10/10 |  |
| context_menu_s2 | 31 / 53 / 25 | 26 / 59 / 25 | -5 | 0.84 | 5/5 |  |
| issue_edit_s2 | 42 / 48 / 33 | 49 / 68 / 36 | 6 | 1.15 | 10/10 |  |
| issue_new_s1 | 39 / 54 / 31 | 40 / 47 / 29 | 0 | 1.01 | 10/10 |  |
| issue_new_s2 | 45 / 58 / 33 | 49 / 77 / 39 | 4 | 1.10 | 10/10 |  |

#### Context menu shown (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 197 / 208 / 189 | 127 / 136 / 113 | -69 | 0.65 | 10/10 |  |
| context_menu_s2 | 1,009 / 1,028 / 842 | 172 / 187 / 157 | -837 | 0.17 | 5/5 |  |

#### Wizard opened (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 5 / 6 / 5 | 62 / 69 / 57 | 57 | 12.74 | 10/10 |  |
| context_menu_s2 | 501 / 509 / 482 | 1,479 / 1,507 / 1,413 | 978 | 2.95 | 5/5 |  |

#### Interaction: change handler returns (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 3 / 3 / 3 | 3 / 3 / 2 | 0 | 0.93 | 10/10 |  |
| interaction_s2_assembly | 117 / 124 / 111 | 84 / 88 / 77 | -33 | 0.72 | 10/10 |  |

#### Interaction: options shown and painted (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 14 / 17 / 8 | 17 / 18 / 7 | 3 | 1.19 | 10/10 |  |
| interaction_s2_assembly | 274 / 284 / 264 | 171 / 180 / 158 | -104 | 0.62 | 10/10 |  |

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

Server bench: 30 measured rounds, 5 warm-up rounds, mixed run 300, 11.8 min, load average at start 0.83.

### Memory (puma worker, 1 thread)

| checkpoint | main RSS (MB) | branch RSS (MB) | main peak RSS (MB) | branch peak RSS (MB) | main heap_live_slots | branch heap_live_slots |
|---|---|---|---|---|---|---|
| after_boot | 231 | 229 | - | - | - | - |
| after_warmup | 352 | 349 | 352 | 349 | 992,807 | 844,630 |
| after_rounds | 356 | 368 | 356 | 368 | 896,659 | 847,931 |
| after_mixed | 375 | 388 | 375 | 396 | 1,010,927 | 896,577 |
| mixed run totals (300 requests) | time 74 s, objects 51,947,578, SQL 14675 | time 62 s, objects 35,665,804, SQL 14262 | | | | |
| after_heavy | 277 (restarted) | 390 | 277 | 396 | 788,722 | 847,856 |

Update check (PATCH stores the new values, reset restores them): {"main":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}},"branch":{"issue_update_s1":{"patch_status":302,"changed":true,"reset_status":302,"restored":true},"issue_update_s2":{"patch_status":302,"changed":true,"reset_status":302,"restored":true}}}

### Server, per request

#### Wall time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 74 / 82 / 67 | 52 / 58 / 46 | -22 | 0.70 | 30/30 |  |
| admin_cf_part | - | 350 / 352 / 347 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 363 / 398 / 206 | 213 / 239 / 185 | -150 | 0.59 | 30/30 |  |
| bulk_edit_s2 | 608 / 730 / 515 | 538 / 716 / 487 | -69 | 0.89 | 8/8 |  |
| context_menu_s1 | 177 / 194 / 155 | 107 / 115 / 92 | -70 | 0.60 | 30/30 |  |
| context_menu_s2 | 667 / 701 / 639 | 179 / 274 / 156 | -489 | 0.27 | 30/30 |  |
| issue_edit_s1 | 130 / 154 / 116 | 109 / 126 / 95 | -21 | 0.84 | 30/30 |  |
| issue_edit_s2 | 490 / 528 / 457 | 472 / 516 / 447 | -18 | 0.96 | 30/30 |  |
| issue_edit_s2_admin | 473 / 511 / 450 | 469 / 675 / 450 | -4 | 0.99 | 8/8 |  |
| issue_list_s1 | 239 / 266 / 214 | 213 / 232 / 197 | -26 | 0.89 | 30/30 |  |
| issue_list_s2 | 605 / 640 / 574 | 457 / 485 / 429 | -148 | 0.76 | 30/30 |  |
| issue_new_baseline | 394 / 446 / 356 | 366 / 431 / 344 | -28 | 0.93 | 8/8 |  |
| issue_new_s1 | 129 / 147 / 116 | 101 / 119 / 91 | -28 | 0.78 | 30/30 |  |
| issue_new_s2 | 469 / 560 / 446 | 453 / 481 / 431 | -16 | 0.97 | 30/30 |  |
| issue_new_s2_admin | 469 / 522 / 431 | 447 / 460 / 426 | -21 | 0.95 | 8/8 |  |
| issue_show_s1 | 327 / 351 / 285 | 296 / 319 / 268 | -30 | 0.91 | 30/30 |  |
| issue_show_s2 | 668 / 734 / 620 | 656 / 724 / 619 | -13 | 0.98 | 30/30 |  |
| issue_show_s2_admin | 513 / 568 / 484 | 497 / 521 / 486 | -16 | 0.97 | 8/8 |  |
| issue_update_s1 | 83 / 93 / 66 | 88 / 153 / 67 | 5 | 1.06 | 30/30 |  |
| issue_update_s2 | 237 / 262 / 222 | 232 / 258 / 217 | -5 | 0.98 | 30/30 |  |
| project_deps_s1_city | 72 / 76 / 65 | 54 / 63 / 45 | -18 | 0.75 | 30/30 |  |
| project_deps_s2_part | - | 379 / 384 / 371 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 128 / 145 / 114 | 107 / 118 / 92 | -21 | 0.84 | 30/30 |  |
| project_settings_s2 | 281 / 312 / 274 | 266 / 292 / 246 | -15 | 0.95 | 8/8 |  |
| project_values_s1_city | 89 / 99 / 82 | 73 / 85 / 64 | -16 | 0.82 | 30/30 |  |
| project_values_s2_part | 15,856 / 16,032 / 15,635 | 263 / 267 / 260 | -15,594 | 0.02 | 3/15 | main: heavy (16 s first) |

#### Process CPU time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 65 / 72 / 60 | 44 / 47 / 39 | -22 | 0.67 | 30/30 |  |
| admin_cf_part | - | 339 / 342 / 337 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 336 / 369 / 186 | 184 / 207 / 165 | -152 | 0.55 | 30/30 |  |
| bulk_edit_s2 | 576 / 687 / 489 | 494 / 668 / 463 | -82 | 0.86 | 8/8 |  |
| context_menu_s1 | 154 / 165 / 134 | 90 / 98 / 78 | -64 | 0.59 | 30/30 |  |
| context_menu_s2 | 640 / 655 / 619 | 155 / 249 / 138 | -485 | 0.24 | 30/30 |  |
| issue_edit_s1 | 112 / 126 / 100 | 91 / 103 / 81 | -21 | 0.81 | 30/30 |  |
| issue_edit_s2 | 460 / 477 / 436 | 445 / 458 / 426 | -15 | 0.97 | 30/30 |  |
| issue_edit_s2_admin | 443 / 456 / 432 | 443 / 630 / 422 | 0 | 1.00 | 8/8 |  |
| issue_list_s1 | 203 / 214 / 186 | 179 / 197 / 167 | -24 | 0.88 | 30/30 |  |
| issue_list_s2 | 549 / 568 / 522 | 402 / 416 / 377 | -147 | 0.73 | 30/30 |  |
| issue_new_baseline | 365 / 425 / 337 | 344 / 379 / 326 | -21 | 0.94 | 8/8 |  |
| issue_new_s1 | 113 / 126 / 103 | 87 / 99 / 76 | -26 | 0.77 | 30/30 |  |
| issue_new_s2 | 438 / 537 / 425 | 428 / 444 / 411 | -9 | 0.98 | 30/30 |  |
| issue_new_s2_admin | 442 / 473 / 415 | 424 / 438 / 405 | -18 | 0.96 | 8/8 |  |
| issue_show_s1 | 271 / 285 / 242 | 246 / 256 / 221 | -25 | 0.91 | 30/30 |  |
| issue_show_s2 | 607 / 654 / 570 | 598 / 624 / 573 | -9 | 0.99 | 30/30 |  |
| issue_show_s2_admin | 479 / 511 / 461 | 465 / 476 / 450 | -14 | 0.97 | 8/8 |  |
| issue_update_s1 | 67 / 74 / 56 | 70 / 133 / 57 | 2 | 1.04 | 30/30 |  |
| issue_update_s2 | 216 / 229 / 206 | 213 / 224 / 203 | -4 | 0.98 | 30/30 |  |
| project_deps_s1_city | 63 / 66 / 58 | 45 / 48 / 38 | -18 | 0.71 | 30/30 |  |
| project_deps_s2_part | - | 363 / 370 / 358 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 108 / 117 / 98 | 88 / 99 / 76 | -20 | 0.81 | 30/30 |  |
| project_settings_s2 | 259 / 272 / 250 | 238 / 263 / 227 | -21 | 0.92 | 8/8 |  |
| project_values_s1_city | 80 / 85 / 75 | 64 / 68 / 57 | -16 | 0.79 | 30/30 |  |
| project_values_s2_part | 15,636 / 15,859 / 15,520 | 252 / 254 / 249 | -15,384 | 0.02 | 3/15 | main: heavy (16 s first) |

#### View time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 52 / 58 / 48 | 31 / 33 / 27 | -21 | 0.60 | 30/30 |  |
| admin_cf_part | - | 322 / 325 / 320 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 165 / 189 / 55 | 45 / 51 / 39 | -120 | 0.27 | 30/30 |  |
| bulk_edit_s2 | 378 / 405 / 361 | 367 / 377 / 337 | -11 | 0.97 | 8/8 |  |
| context_menu_s1 | 62 / 65 / 51 | 13 / 14 / 11 | -49 | 0.21 | 30/30 |  |
| context_menu_s2 | 374 / 405 / 346 | 13 / 31 / 11 | -361 | 0.03 | 30/30 |  |
| issue_edit_s1 | 74 / 88 / 65 | 53 / 59 / 45 | -21 | 0.72 | 30/30 |  |
| issue_edit_s2 | 403 / 441 / 388 | 390 / 435 / 374 | -12 | 0.97 | 30/30 |  |
| issue_edit_s2_admin | 402 / 429 / 384 | 390 / 595 / 371 | -12 | 0.97 | 8/8 |  |
| issue_list_s1 | 124 / 132 / 114 | 103 / 112 / 94 | -21 | 0.83 | 30/30 |  |
| issue_list_s2 | 403 / 428 / 379 | 254 / 267 / 239 | -149 | 0.63 | 30/30 |  |
| issue_new_baseline | 322 / 353 / 293 | 304 / 360 / 289 | -18 | 0.95 | 8/8 |  |
| issue_new_s1 | 84 / 95 / 72 | 60 / 68 / 50 | -24 | 0.71 | 30/30 |  |
| issue_new_s2 | 404 / 496 / 387 | 391 / 412 / 372 | -13 | 0.97 | 30/30 |  |
| issue_new_s2_admin | 412 / 461 / 379 | 384 / 402 / 376 | -28 | 0.93 | 8/8 |  |
| issue_show_s1 | 116 / 124 / 95 | 91 / 98 / 77 | -25 | 0.78 | 30/30 |  |
| issue_show_s2 | 452 / 468 / 425 | 438 / 494 / 420 | -14 | 0.97 | 30/30 |  |
| issue_show_s2_admin | 433 / 483 / 416 | 428 / 448 / 411 | -5 | 0.99 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 43 / 45 / 39 | 25 / 29 / 20 | -18 | 0.57 | 30/30 |  |
| project_deps_s2_part | - | 101 / 103 / 98 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 79 / 92 / 72 | 61 / 68 / 52 | -18 | 0.77 | 30/30 |  |
| project_settings_s2 | 230 / 244 / 224 | 210 / 228 / 201 | -19 | 0.92 | 8/8 |  |
| project_values_s1_city | 60 / 63 / 56 | 44 / 51 / 39 | -16 | 0.74 | 30/30 |  |
| project_values_s2_part | 15,283 / 15,466 / 15,061 | 38 / 39 / 37 | -15,244 | 0.00 | 3/15 | main: heavy (16 s first) |

#### ActiveRecord time (ms), Rails Completed line

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 11 / 13 / 9 | 12 / 14 / 10 | 1 | 1.10 | 30/30 |  |
| admin_cf_part | - | 14 / 14 / 13 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 38 / 43 / 30 | 35 / 41 / 29 | -3 | 0.92 | 30/30 |  |
| bulk_edit_s2 | 43 / 55 / 34 | 41 / 51 / 33 | -2 | 0.96 | 8/8 |  |
| context_menu_s1 | 27 / 32 / 22 | 22 / 24 / 18 | -6 | 0.79 | 30/30 |  |
| context_menu_s2 | 31 / 37 / 28 | 27 / 33 / 22 | -4 | 0.87 | 30/30 |  |
| issue_edit_s1 | 21 / 26 / 18 | 21 / 26 / 17 | 0 | 0.99 | 30/30 |  |
| issue_edit_s2 | 32 / 37 / 27 | 33 / 40 / 25 | 1 | 1.04 | 30/30 |  |
| issue_edit_s2_admin | 27 / 34 / 23 | 28 / 36 / 24 | 2 | 1.07 | 8/8 |  |
| issue_list_s1 | 45 / 50 / 39 | 47 / 56 / 40 | 2 | 1.04 | 30/30 |  |
| issue_list_s2 | 65 / 67 / 59 | 63 / 73 / 56 | -2 | 0.97 | 30/30 |  |
| issue_new_baseline | 26 / 38 / 24 | 25 / 35 / 22 | -1 | 0.96 | 8/8 |  |
| issue_new_s1 | 20 / 23 / 17 | 18 / 24 / 16 | -1 | 0.94 | 30/30 |  |
| issue_new_s2 | 27 / 33 / 25 | 26 / 30 / 22 | -1 | 0.97 | 30/30 |  |
| issue_new_s2_admin | 22 / 34 / 19 | 23 / 33 / 19 | 2 | 1.09 | 8/8 |  |
| issue_show_s1 | 68 / 77 / 59 | 61 / 69 / 53 | -7 | 0.90 | 30/30 |  |
| issue_show_s2 | 68 / 78 / 60 | 68 / 77 / 58 | 0 | 0.99 | 30/30 |  |
| issue_show_s2_admin | 45 / 51 / 37 | 40 / 48 / 33 | -6 | 0.88 | 8/8 |  |
| issue_update_s1 | 19 / 23 / 14 | 21 / 28 / 15 | 2 | 1.10 | 30/30 |  |
| issue_update_s2 | 24 / 28 / 21 | 24 / 32 / 20 | 0 | 0.98 | 30/30 |  |
| project_deps_s1_city | 10 / 11 / 8 | 10 / 12 / 8 | 0 | 1.05 | 30/30 |  |
| project_deps_s2_part | - | 16 / 17 / 16 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 26 / 30 / 22 | 26 / 30 / 22 | 0 | 0.99 | 30/30 |  |
| project_settings_s2 | 30 / 37 / 28 | 30 / 62 / 27 | 0 | 1.01 | 8/8 |  |
| project_values_s1_city | 10 / 13 / 9 | 11 / 13 / 8 | 0 | 1.03 | 30/30 |  |
| project_values_s2_part | 17 / 18 / 15 | 15 / 17 / 14 | -2 | 0.90 | 3/15 | main: heavy (16 s first) |

#### Allocations (Rails Completed line)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 47,498 / 47,616 / 47,498 | 16,751 / 16,869 / 16,751 | -30,747 | 0.35 | 30/30 |  |
| admin_cf_part | - | 201,682 / 201,687 / 201,682 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 99,276 / 99,312 / 98,770 | 73,718 / 73,725 / 73,711 | -25,558 | 0.74 | 30/30 |  |
| bulk_edit_s2 | 423,661 / 424,128 / 423,620 | 401,336 / 401,844 / 401,328 | -22,325 | 0.95 | 8/8 |  |
| context_menu_s1 | 150,479 / 151,437 / 150,479 | 36,551 / 37,521 / 36,551 | -113,928 | 0.24 | 30/30 |  |
| context_menu_s2 | 682,253 / 682,346 / 681,343 | 80,944 / 80,949 / 80,942 | -601,308 | 0.12 | 30/30 |  |
| issue_edit_s1 | 62,168 / 62,175 / 62,168 | 35,779 / 35,779 / 35,765 | -26,389 | 0.58 | 30/30 |  |
| issue_edit_s2 | 393,179 / 393,179 / 393,164 | 370,740 / 370,744 / 370,230 | -22,439 | 0.94 | 30/30 |  |
| issue_edit_s2_admin | 391,946 / 391,963 / 391,928 | 369,304 / 369,499 / 368,994 | -22,641 | 0.94 | 8/8 |  |
| issue_list_s1 | 101,409 / 101,450 / 101,409 | 73,511 / 73,522 / 73,506 | -27,898 | 0.72 | 30/30 |  |
| issue_list_s2 | 473,288 / 473,320 / 473,283 | 290,675 / 290,678 / 290,171 | -182,613 | 0.61 | 30/30 |  |
| issue_new_baseline | 330,070 / 330,593 / 330,057 | 302,887 / 302,899 / 302,887 | -27,182 | 0.92 | 8/8 |  |
| issue_new_s1 | 59,621 / 59,628 / 59,621 | 33,064 / 33,102 / 33,063 | -26,557 | 0.55 | 30/30 |  |
| issue_new_s2 | 391,397 / 391,420 / 391,397 | 368,415 / 368,919 / 368,403 | -22,982 | 0.94 | 30/30 |  |
| issue_new_s2_admin | 389,542 / 389,635 / 389,512 | 366,535 / 367,036 / 366,532 | -23,007 | 0.94 | 8/8 |  |
| issue_show_s1 | 139,215 / 139,220 / 139,211 | 113,296 / 113,302 / 112,796 | -25,919 | 0.81 | 30/30 |  |
| issue_show_s2 | 469,698 / 469,741 / 469,693 | 447,236 / 447,241 / 446,735 | -22,462 | 0.95 | 30/30 |  |
| issue_show_s2_admin | 398,727 / 398,744 / 398,714 | 375,868 / 376,272 / 375,771 | -22,859 | 0.94 | 8/8 |  |
| issue_update_s1 | 20,831 / 20,836 / 20,831 | 20,606 / 20,616 / 20,606 | -225 | 0.99 | 30/30 |  |
| issue_update_s2 | 122,045 / 122,050 / 122,045 | 122,563 / 122,617 / 122,059 | 518 | 1.00 | 30/30 |  |
| project_deps_s1_city | 45,552 / 45,557 / 45,552 | 16,075 / 16,080 / 16,075 | -29,477 | 0.35 | 30/30 |  |
| project_deps_s2_part | - | 260,391 / 260,396 / 259,891 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 58,995 / 59,031 / 58,995 | 31,304 / 31,309 / 31,298 | -27,691 | 0.53 | 30/30 |  |
| project_settings_s2 | 162,080 / 162,103 / 162,062 | 134,739 / 135,240 / 134,728 | -27,341 | 0.83 | 8/8 |  |
| project_values_s1_city | 53,274 / 54,237 / 53,274 | 27,402 / 28,368 / 27,400 | -25,872 | 0.51 | 30/30 |  |
| project_values_s2_part | 10,572,526 / 10,572,531 / 10,572,523 | 230,227 / 230,232 / 230,227 | -10,342,299 | 0.02 | 3/15 | main: heavy (16 s first) |

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
| issue_edit_s2_admin | 37 / 37 / 37 | 37 / 38 / 37 | 0 | 1.00 | 8/8 |  |
| issue_list_s1 | 64 / 64 / 64 | 62 / 62 / 62 | -2 | 0.97 | 30/30 |  |
| issue_list_s2 | 44 / 44 / 44 | 42 / 42 / 42 | -2 | 0.95 | 30/30 |  |
| issue_new_baseline | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 8/8 |  |
| issue_new_s1 | 42 / 42 / 42 | 41 / 41 / 41 | -1 | 0.98 | 30/30 |  |
| issue_new_s2 | 42 / 42 / 42 | 42 / 42 / 42 | 0 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 31 / 32 / 31 | 31 / 31 / 31 | 0 | 1.00 | 8/8 |  |
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
| project_values_s2_part | 22 / 22 / 22 | 22 / 22 / 22 | 0 | 1.00 | 3/15 | main: heavy (16 s first) |

#### Response bytes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 353,873 / 353,873 / 353,873 | 35,856 / 35,856 / 35,856 | -318,017 | 0.10 | 30/30 |  |
| admin_cf_part | - | 829,952 / 829,952 / 829,952 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 322,913 / 322,913 / 322,913 | 36,816 / 36,816 / 36,816 | -286,097 | 0.11 | 30/30 |  |
| bulk_edit_s2 | 1,405,635 / 1,405,635 / 1,405,635 | 1,413,586 / 1,413,586 / 1,413,586 | 7,951 | 1.01 | 8/8 |  |
| context_menu_s1 | 27,744 / 27,744 / 27,744 | 15,355 / 15,355 / 15,355 | -12,389 | 0.55 | 30/30 |  |
| context_menu_s2 | 1,107,207 / 1,107,207 / 1,107,207 | 12,917 / 12,917 / 12,917 | -1,094,290 | 0.01 | 30/30 |  |
| issue_edit_s1 | 325,735 / 325,735 / 325,735 | 39,837 / 39,837 / 39,837 | -285,898 | 0.12 | 30/30 |  |
| issue_edit_s2 | 1,407,878 / 1,407,878 / 1,407,878 | 1,416,005 / 1,416,005 / 1,416,005 | 8,127 | 1.01 | 30/30 |  |
| issue_edit_s2_admin | 1,406,994 / 1,406,994 / 1,406,994 | 1,415,121 / 1,415,121 / 1,415,121 | 8,127 | 1.01 | 8/8 |  |
| issue_list_s1 | 373,346 / 373,346 / 373,346 | 82,474 / 82,474 / 82,474 | -290,872 | 0.22 | 30/30 |  |
| issue_list_s2 | 953,054 / 953,054 / 953,054 | 662,182 / 662,182 / 662,182 | -290,872 | 0.69 | 30/30 |  |
| issue_new_baseline | 1,538,555 / 1,538,555 / 1,538,555 | 1,247,683 / 1,247,683 / 1,247,683 | -290,872 | 0.81 | 8/8 |  |
| issue_new_s1 | 324,116 / 324,116 / 324,116 | 37,493 / 37,493 / 37,493 | -286,623 | 0.12 | 30/30 |  |
| issue_new_s2 | 1,406,202 / 1,406,202 / 1,406,202 | 1,414,214 / 1,414,214 / 1,414,214 | 8,012 | 1.01 | 30/30 |  |
| issue_new_s2_admin | 1,405,358 / 1,405,358 / 1,405,358 | 1,413,370 / 1,413,370 / 1,413,370 | 8,012 | 1.01 | 8/8 |  |
| issue_show_s1 | 337,744 / 337,744 / 337,744 | 51,846 / 51,846 / 51,846 | -285,898 | 0.15 | 30/30 |  |
| issue_show_s2 | 1,419,400 / 1,419,400 / 1,419,400 | 1,427,527 / 1,427,527 / 1,427,527 | 8,127 | 1.01 | 30/30 |  |
| issue_show_s2_admin | 1,418,293 / 1,418,293 / 1,418,293 | 1,426,420 / 1,426,420 / 1,426,420 | 8,127 | 1.01 | 8/8 |  |
| issue_update_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| issue_update_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 30/30 |  |
| project_deps_s1_city | 352,105 / 352,105 / 352,105 | 28,176 / 28,176 / 28,176 | -323,929 | 0.08 | 30/30 |  |
| project_deps_s2_part | - | 1,571,016 / 1,571,016 / 1,571,016 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 323,855 / 323,855 / 323,855 | 33,111 / 33,111 / 33,111 | -290,744 | 0.10 | 30/30 |  |
| project_settings_s2 | 319,874 / 319,874 / 319,874 | 29,131 / 29,131 / 29,131 | -290,743 | 0.09 | 8/8 |  |
| project_values_s1_city | 364,679 / 364,679 / 364,679 | 76,241 / 76,241 / 76,241 | -288,438 | 0.21 | 30/30 |  |
| project_values_s2_part | 49,430,283 / 49,430,283 / 49,430,283 | 60,199 / 60,199 / 60,199 | -49,370,084 | 0.00 | 3/15 | main: heavy (16 s first) |

#### Response bytes gzipped

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_cf_city | 67,442 / 67,448 / 67,432 | 8,701 / 8,703 / 8,695 | -58,741 | 0.13 | 30/30 |  |
| admin_cf_part | - | 136,210 / 136,213 / 136,200 | - | - | 0/15 | main: timeout > 45 s |
| bulk_edit_s1 | 66,749 / 66,752 / 66,740 | 7,563 / 7,567 / 7,560 | -59,186 | 0.11 | 30/30 |  |
| bulk_edit_s2 | 202,842 / 202,845 / 202,837 | 202,949 / 202,955 / 202,943 | 107 | 1.00 | 8/8 |  |
| context_menu_s1 | 2,868 / 2,872 / 2,864 | 1,324 / 1,324 / 1,324 | -1,544 | 0.46 | 30/30 |  |
| context_menu_s2 | 137,058 / 137,061 / 137,050 | 1,185 / 1,185 / 1,185 | -135,873 | 0.01 | 30/30 |  |
| issue_edit_s1 | 67,784 / 67,789 / 67,775 | 8,518 / 8,519 / 8,506 | -59,266 | 0.13 | 30/30 |  |
| issue_edit_s2 | 204,311 / 204,318 / 204,303 | 204,341 / 204,345 / 204,335 | 31 | 1.00 | 30/30 |  |
| issue_edit_s2_admin | 204,237 / 204,247 / 204,235 | 204,286 / 204,290 / 204,278 | 49 | 1.00 | 8/8 |  |
| issue_list_s1 | 71,239 / 71,245 / 71,229 | 10,960 / 10,964 / 10,955 | -60,279 | 0.15 | 30/30 |  |
| issue_list_s2 | 193,801 / 193,807 / 193,791 | 133,894 / 133,897 / 133,882 | -59,907 | 0.69 | 30/30 |  |
| issue_new_baseline | 197,450 / 197,460 / 197,445 | 137,911 / 137,921 / 137,907 | -59,538 | 0.70 | 8/8 |  |
| issue_new_s1 | 67,503 / 67,508 / 67,492 | 8,183 / 8,187 / 8,174 | -59,320 | 0.12 | 30/30 |  |
| issue_new_s2 | 203,697 / 203,703 / 203,685 | 203,737 / 203,743 / 203,731 | 40 | 1.00 | 30/30 |  |
| issue_new_s2_admin | 203,620 / 203,626 / 203,611 | 203,674 / 203,680 / 203,665 | 55 | 1.00 | 8/8 |  |
| issue_show_s1 | 70,266 / 70,271 / 70,259 | 10,872 / 10,875 / 10,864 | -59,394 | 0.15 | 30/30 |  |
| issue_show_s2 | 206,652 / 206,657 / 206,643 | 206,858 / 206,863 / 206,849 | 206 | 1.00 | 30/30 |  |
| issue_show_s2_admin | 206,522 / 206,526 / 206,511 | 206,697 / 206,699 / 206,688 | 175 | 1.00 | 8/8 |  |
| project_deps_s1_city | 65,392 / 65,400 / 65,384 | 7,247 / 7,252 / 7,241 | -58,145 | 0.11 | 30/30 |  |
| project_deps_s2_part | - | 150,101 / 150,109 / 150,091 | - | - | 0/15 | main: timeout > 45 s |
| project_settings_s1 | 66,608 / 66,614 / 66,593 | 6,714 / 6,719 / 6,707 | -59,893 | 0.10 | 30/30 |  |
| project_settings_s2 | 66,377 / 66,383 / 66,372 | 6,507 / 6,511 / 6,505 | -59,870 | 0.10 | 8/8 |  |
| project_values_s1_city | 69,928 / 69,939 / 69,899 | 10,372 / 10,383 / 10,353 | -59,555 | 0.15 | 30/30 |  |
| project_values_s2_part | - | 9,577 / 9,590 / 9,559 | - | - | 3/15 | main: heavy (16 s first) |

### Browser (Chromium 153.0.8010.12)

10 measured repetitions per page and variant, 4.3 min.

#### domContentLoaded (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,182 / 1,250 / 1,137 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 305 / 326 / 289 | 248 / 266 / 238 | -57 | 0.81 | 10/10 |  |
| context_menu_s2 | 363 / 368 / 341 | 340 / 411 / 323 | -23 | 0.94 | 5/5 |  |
| issue_edit_s2 | 1,518 / 1,542 / 1,503 | 1,492 / 1,585 / 1,460 | -26 | 0.98 | 10/10 |  |
| issue_new_s1 | 336 / 369 / 294 | 284 / 300 / 259 | -52 | 0.84 | 10/10 |  |
| issue_new_s2 | 1,593 / 1,685 / 1,493 | 1,561 / 1,693 / 1,459 | -32 | 0.98 | 10/10 |  |

#### load event (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 1,232 / 1,304 / 1,187 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 310 / 327 / 295 | 254 / 272 / 243 | -56 | 0.82 | 10/10 |  |
| context_menu_s2 | 369 / 374 / 346 | 345 / 416 / 330 | -23 | 0.94 | 5/5 |  |
| issue_edit_s2 | 1,710 / 1,734 / 1,700 | 1,692 / 1,785 / 1,655 | -19 | 0.99 | 10/10 |  |
| issue_new_s1 | 343 / 375 / 301 | 290 / 307 / 265 | -53 | 0.85 | 10/10 |  |
| issue_new_s2 | 1,811 / 1,894 / 1,699 | 1,764 / 1,896 / 1,656 | -47 | 0.97 | 10/10 |  |

#### time to first byte (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 375 / 392 / 356 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 146 / 154 / 136 | 110 / 114 / 104 | -36 | 0.75 | 10/10 |  |
| context_menu_s2 | 208 / 211 / 202 | 200 / 287 / 190 | -7 | 0.96 | 5/5 |  |
| issue_edit_s2 | 463 / 473 / 444 | 462 / 476 / 452 | -1 | 1.00 | 10/10 |  |
| issue_new_s1 | 120 / 134 / 113 | 93 / 96 / 85 | -27 | 0.77 | 10/10 |  |
| issue_new_s2 | 447 / 585 / 436 | 470 / 612 / 445 | 22 | 1.05 | 10/10 |  |

#### JSHeapUsedSize (MB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 6.6 / 6.8 / 6.6 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 4.3 / 4.3 / 4.3 | 3.7 / 3.7 / 3.6 | -0.6 | 0.85 | 10/10 |  |
| context_menu_s2 | 4.3 / 4.3 / 4.3 | 3.7 / 3.7 / 3.6 | -0.6 | 0.85 | 5/5 |  |
| issue_edit_s2 | 5 / 5.1 / 4.6 | 9.8 / 9.8 / 6.4 | 4.8 | 1.96 | 10/10 |  |
| issue_new_s1 | 4.6 / 4.6 / 4.5 | 4 / 4 / 4 | -0.6 | 0.88 | 10/10 |  |
| issue_new_s2 | 4.8 / 4.9 / 4.6 | 9.6 / 9.6 / 9.5 | 4.8 | 1.99 | 10/10 |  |

#### ScriptDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 193 / 210 / 187 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 74 / 77 / 70 | 73 / 80 / 65 | 0 | 1.00 | 10/10 |  |
| context_menu_s2 | 73 / 78 / 66 | 71 / 74 / 67 | -2 | 0.98 | 5/5 |  |
| issue_edit_s2 | 388 / 399 / 375 | 380 / 391 / 352 | -8 | 0.98 | 10/10 |  |
| issue_new_s1 | 76 / 78 / 71 | 78 / 79 / 74 | 2 | 1.02 | 10/10 |  |
| issue_new_s2 | 406 / 422 / 380 | 387 / 412 / 381 | -19 | 0.95 | 10/10 |  |

#### TaskDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 879 / 952 / 842 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 183 / 194 / 172 | 166 / 173 / 144 | -17 | 0.91 | 10/10 |  |
| context_menu_s2 | 177 / 193 / 158 | 161 / 177 / 155 | -16 | 0.91 | 5/5 |  |
| issue_edit_s2 | 1,378 / 1,412 / 1,363 | 1,372 / 1,453 / 1,323 | -6 | 1.00 | 10/10 |  |
| issue_new_s1 | 234 / 241 / 208 | 213 / 224 / 200 | -21 | 0.91 | 10/10 |  |
| issue_new_s2 | 1,441 / 1,504 / 1,395 | 1,405 / 1,445 / 1,350 | -36 | 0.97 | 10/10 |  |

#### LayoutDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 343 / 376 / 335 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 18 / 21 / 16 | 19 / 21 / 16 | 1 | 1.05 | 10/10 |  |
| context_menu_s2 | 19 / 22 / 15 | 21 / 22 / 15 | 1 | 1.06 | 5/5 |  |
| issue_edit_s2 | 236 / 242 / 232 | 233 / 253 / 225 | -2 | 0.99 | 10/10 |  |
| issue_new_s1 | 22 / 25 / 16 | 20 / 23 / 16 | -2 | 0.89 | 10/10 |  |
| issue_new_s2 | 235 / 243 / 227 | 238 / 241 / 228 | 2 | 1.01 | 10/10 |  |

#### RecalcStyleDuration (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 77 / 79 / 76 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 13 / 13 / 10 | 11 / 12 / 11 | -1 | 0.88 | 10/10 |  |
| context_menu_s2 | 12 / 14 / 11 | 10 / 12 / 10 | -2 | 0.85 | 5/5 |  |
| issue_edit_s2 | 302 / 308 / 295 | 311 / 324 / 305 | 9 | 1.03 | 10/10 |  |
| issue_new_s1 | 20 / 25 / 17 | 21 / 24 / 17 | 1 | 1.04 | 10/10 |  |
| issue_new_s2 | 318 / 333 / 311 | 311 / 319 / 300 | -6 | 0.98 | 10/10 |  |

#### DOM nodes

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 53,955 / 53,967 / 53,941 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 3,542 / 3,542 / 3,542 | 3,540 / 3,540 / 3,540 | -2 | 1.00 | 10/10 |  |
| context_menu_s2 | 3,430 / 3,430 / 3,430 | 3,428 / 3,428 / 3,428 | -2 | 1.00 | 5/5 |  |
| issue_edit_s2 | 181,083 / 181,083 / 181,083 | 181,079 / 181,079 / 181,079 | -4 | 1.00 | 10/10 |  |
| issue_new_s1 | 3,615 / 3,615 / 3,615 | 3,625 / 3,625 / 3,625 | 10 | 1.00 | 10/10 |  |
| issue_new_s2 | 180,784 / 180,788 / 180,784 | 180,785 / 180,785 / 180,785 | 1 | 1.00 | 10/10 |  |

#### Plugin script time, CPU profile, inclusive (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 143 / 145 / 141 | - | - | 0/10 | main: timeout > 30 s |
| issue_new_s1 | 6 / 6 / 6 | 7 / 7 / 6 | 1 | 1.16 | 10/10 |  |
| issue_new_s2 | 199 / 209 / 189 | 174 / 174 / 173 | -25 | 0.87 | 10/10 |  |

#### Plugin asset bytes loaded (KB)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 194.6 / 194.6 / 194.6 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| context_menu_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 5/5 |  |
| issue_edit_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| issue_new_s1 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |
| issue_new_s2 | 30.4 / 30.4 / 30.4 | 74.4 / 74.4 / 74.4 | 43.9 | 2.44 | 10/10 |  |

#### Plugin asset load time (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 134 / 157 / 99 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 71 / 87 / 42 | 66 / 92 / 43 | -5 | 0.93 | 10/10 |  |
| context_menu_s2 | 55 / 91 / 50 | 49 / 85 / 43 | -6 | 0.89 | 5/5 |  |
| issue_edit_s2 | 63 / 90 / 48 | 63 / 73 / 46 | 1 | 1.01 | 10/10 |  |
| issue_new_s1 | 59 / 91 / 45 | 56 / 99 / 46 | -3 | 0.94 | 10/10 |  |
| issue_new_s2 | 65 / 72 / 47 | 55 / 77 / 42 | -10 | 0.85 | 10/10 |  |

#### Context menu shown (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 262 / 343 / 189 | 114 / 125 / 109 | -148 | 0.43 | 10/10 |  |
| context_menu_s2 | 778 / 925 / 750 | 306 / 316 / 230 | -471 | 0.39 | 5/5 |  |

#### Wizard opened (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| context_menu_s1 | 5 / 6 / 5 | 58 / 61 / 54 | 53 | 11.21 | 10/10 |  |
| context_menu_s2 | 409 / 417 / 392 | 1,241 / 1,274 / 1,208 | 832 | 3.04 | 5/5 |  |

#### Interaction: change handler returns (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 3 / 3 / 2 | 2 / 3 / 2 | 0 | 0.92 | 10/10 |  |
| interaction_s2_assembly | 136 / 141 / 123 | 73 / 78 / 64 | -63 | 0.54 | 10/10 |  |

#### Interaction: options shown and painted (ms)

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| interaction_s1_country | 8 / 17 / 8 | 10 / 16 / 7 | 3 | 1.35 | 10/10 |  |
| interaction_s2_assembly | 310 / 321 / 292 | 156 / 162 / 145 | -153 | 0.50 | 10/10 |  |

#### js_errors

| page | main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | n main/branch | note |
|---|---|---|---|---|---|---|
| admin_part_editor | - | 0 / 0 / 0 | - | - | 0/10 | main: timeout > 30 s |
| context_menu_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| context_menu_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 5/5 |  |
| issue_edit_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |
| issue_new_s2 | 0 / 0 / 0 | 0 / 0 / 0 | 0 | - | 10/10 |  |

