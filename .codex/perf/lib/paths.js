'use strict';
// Directories of the perf harness. H = the scripts (this directory), WORK = DCF_WORK_DIR, P = PERF_DIR (data, logs, run, results),
// E = E2E_DIR (the Redmine checkouts m51 p51 m61 p61 and src-main, src-branch). Same defaults as common.sh.
const os = require('os');
const path = require('path');
const H = path.resolve(__dirname, '..');
const WORK = process.env.DCF_WORK_DIR || path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'redmine_depending_custom_fields');
const P = process.env.PERF_DIR || path.join(WORK, 'perf');
const E = process.env.E2E_DIR || path.join(WORK, 'e2e');
module.exports = { H, WORK, P, E, ids: (ver) => require(path.join(P, 'data', `ids-${ver}.json`)) };
