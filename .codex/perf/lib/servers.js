'use strict';
// Start, stop and inspect the perf puma servers (perf/server.sh), RSS and the per-request probe log.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const { H, P, E } = require('./paths');
const PORTS = { m51: 3051, p51: 3052, m61: 3061, p61: 3062, n51: 3053, n61: 3063 };

function start(name) {
  const out = execFileSync(`${H}/server.sh`, ['start', name, String(PORTS[name])], { encoding: 'utf8', timeout: 240000 });
  return out.trim();
}
function stop(name) {
  try { execFileSync(`${H}/server.sh`, ['stop', name], { encoding: 'utf8', timeout: 60000 }); } catch (e) { /* ignore */ }
}
function pid(name) {
  try { return parseInt(fs.readFileSync(`${P}/run/${name}.pid`, 'utf8'), 10); } catch (e) { return null; }
}
function rssKb(name) {
  const p = pid(name);
  if (!p) return null;
  try {
    const m = /VmRSS:\s+(\d+) kB/.exec(fs.readFileSync(`/proc/${p}/status`, 'utf8'));
    return m ? parseInt(m[1], 10) : null;
  } catch (e) { return null; }
}
// Last lines of the probe log of a checkout (JSON lines written by zz_perf_probe.rb).
function probeTail(name, n = 5) {
  try {
    const lines = fs.readFileSync(`${E}/${name}/log/perf.log`, 'utf8').trim().split('\n').slice(-n);
    return lines.map((l) => JSON.parse(l));
  } catch (e) { return []; }
}
function loadavg1() { return parseFloat(fs.readFileSync('/proc/loadavg', 'utf8').split(' ')[0]); }

const PGENV = { ...process.env, PGPASSWORD: 'redmine' };
function psql(db, sql) {
  return execFileSync('psql', ['-q', '-t', '-A', '-h', 'localhost', '-U', 'redmine', '-d', db, '-c', sql], { env: PGENV, encoding: 'utf8' }).trim();
}

module.exports = { paths: require('./paths'), H, PORTS, start, stop, pid, rssKb, probeTail, loadavg1, psql, P, E };
