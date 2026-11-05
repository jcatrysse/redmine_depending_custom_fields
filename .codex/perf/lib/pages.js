'use strict';
// Page catalogue of the server bench. Everything is derived from data/ids-<ver>.json (written by seed_perf.rb).
const q = (s) => encodeURIComponent(s);
const idsq = (a) => a.map((i) => `ids[]=${i}`).join('&');

function pages(ids) {
  const F = ids.fields; const I = ids.issues; const V = ids.values;
  const cfid = (n) => F[n].id;
  const colsS1 = ['project', 'tracker', 'status', 'subject'].concat(['Country', 'City', 'District', 'Languages', 'Zone', 'Site'].map((n) => `cf_${cfid(n)}`));
  const colsS2 = ['project', 'tracker', 'status', 'subject', `cf_${cfid('Assembly')}`, `cf_${cfid('Part')}`];
  const cols = (a) => a.map((c) => `&c[]=${c}`).join('');
  const cityFilter = `&f[]=cf_${cfid('City')}&op[cf_${cfid('City')}]==` +
    ['Belgium', 'Netherlands', 'France'].flatMap((c) => V.cities[c]).map((c) => `&v[cf_${cfid('City')}][]=${q(c)}`).join('');
  const partFilter = `&f[]=cf_${cfid('Part')}&op[cf_${cfid('Part')}]=*`;
  const base = '&set_filter=1&sort=id&per_page=25&f[]=status_id&op[status_id]=o';

  // PATCH bodies: the parent and the child change, reset restores the stored values (same work every round).
  const s1 = (v) => [[`issue[custom_field_values][${cfid('Country')}]`, v.country],
    [`issue[custom_field_values][${cfid('City')}]`, v.city], [`issue[custom_field_values][${cfid('District')}]`, v.district],
    [`issue[custom_field_values][${cfid('Languages')}][]`, ''], ...v.langs.map((l) => [`issue[custom_field_values][${cfid('Languages')}][]`, l])];
  const s2 = (a, p) => [[`issue[custom_field_values][${cfid('Assembly')}]`, a], [`issue[custom_field_values][${cfid('Part')}]`, p]];
  const s1Orig = V.s1_update;
  const s1New = { country: 'Netherlands', city: V.cities.Netherlands[1], district: V.districts[V.cities.Netherlands[1]][0], langs: [V.langs.Netherlands[0]] };
  const s2Orig = V.s2_update;

  return [
    // issue forms and pages (non-admin member)
    { key: 'issue_new_s1', mix: 3, user: 'member', path: `/projects/perf-a/issues/new?issue[tracker_id]=1`, marker: `issue_custom_field_values_${cfid('City')}` },
    { key: 'issue_new_s2', user: 'member', path: `/projects/perf-large/issues/new?issue[tracker_id]=2`, marker: `issue_custom_field_values_${cfid('Part')}` },
    { key: 'issue_new_baseline', secondary: true, user: 'member', path: `/projects/perf-baseline/issues/new?issue[tracker_id]=2`, marker: `issue_custom_field_values_${cfid('Plain25k')}` },
    { key: 'issue_edit_s1', mix: 3, user: 'member', path: `/issues/${I.s1_show}/edit`, marker: `issue_custom_field_values_${cfid('City')}` },
    { key: 'issue_edit_s2', user: 'member', path: `/issues/${I.s2_show}/edit`, marker: `issue_custom_field_values_${cfid('Part')}` },
    { key: 'issue_show_s1', mix: 3, user: 'member', path: `/issues/${I.s1_show}`, marker: 'Belgium City 1' },
    { key: 'issue_show_s2', user: 'member', path: `/issues/${I.s2_show}`, marker: 'A010-P05' },
    { key: 'issue_list_s1', mix: 3, user: 'member', path: `/projects/perf-a/issues?x=1${base}${cityFilter}${cols(colsS1)}`, rows: 25 },
    { key: 'issue_list_s2', user: 'member', path: `/projects/perf-large/issues?x=1${base}${partFilter}${cols(colsS2)}`, rows: 25 },
    { key: 'bulk_edit_s1', mix: 3, user: 'member', path: `/issues/bulk_edit?${idsq(I.s1_ctx_ids)}`, marker: `issue_custom_field_values_${cfid('City')}` },
    { key: 'bulk_edit_s2', secondary: true, user: 'member', path: `/issues/bulk_edit?${idsq(I.s2_ctx_ids)}`, marker: `issue_custom_field_values_${cfid('Part')}` },
    { key: 'context_menu_s1', mix: 3, user: 'member', path: `/issues/context_menu?${idsq(I.s1_ctx_ids)}` },
    { key: 'context_menu_s2', user: 'member', path: `/issues/context_menu?${idsq(I.s2_ctx_ids)}` },
    { key: 'issue_update_s1', user: 'member', method: 'PATCH', path: `/issues/${I.s1_update}`, csrfFrom: `/issues/${I.s1_update}/edit`,
      form: s1(s1New), reset: s1(s1Orig), expect: 302 },
    { key: 'issue_update_s2', user: 'member', method: 'PATCH', path: `/issues/${I.s2_update}`, csrfFrom: `/issues/${I.s2_update}/edit`,
      form: s2(V.s2_new_assembly, V.s2_new_part), reset: s2(s2Orig.assembly, s2Orig.part), expect: 302 },
    // project settings and the project level configuration pages (member with the Manager role)
    { key: 'project_settings_s1', user: 'member', path: '/projects/perf-a/settings' },
    { key: 'project_settings_s2', secondary: true, user: 'member', path: '/projects/perf-large/settings' },
    { key: 'project_values_s1_city', user: 'member', path: `/projects/perf-a/custom_field_configuration/fields/${cfid('City')}` },
    { key: 'project_values_s2_part', user: 'member', path: `/projects/perf-large/custom_field_configuration/fields/${cfid('Part')}`, heavy: true },
    { key: 'project_deps_s1_city', user: 'member', path: `/projects/perf-a/custom_field_configuration/fields/${cfid('City')}/dependencies` },
    { key: 'project_deps_s2_part', user: 'member', path: `/projects/perf-large/custom_field_configuration/fields/${cfid('Part')}/dependencies`, heavy: true },
    // administration
    { key: 'admin_cf_city', user: 'admin', path: `/custom_fields/${cfid('City')}/edit` },
    { key: 'admin_cf_part', user: 'admin', path: `/custom_fields/${cfid('Part')}/edit`, heavy: true },
    // the S2 issue pages as administrator
    { key: 'issue_new_s2_admin', secondary: true, user: 'admin', path: `/projects/perf-large/issues/new?issue[tracker_id]=2`, marker: `issue_custom_field_values_${cfid('Part')}` },
    { key: 'issue_edit_s2_admin', secondary: true, user: 'admin', path: `/issues/${I.s2_show}/edit`, marker: `issue_custom_field_values_${cfid('Part')}` },
    { key: 'issue_show_s2_admin', secondary: true, user: 'admin', path: `/issues/${I.s2_show}`, marker: 'A010-P05' }
  ];
}

module.exports = { pages };
