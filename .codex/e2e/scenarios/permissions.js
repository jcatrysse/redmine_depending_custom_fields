const { L, start, check, finish, exp, rails } = require('../lib-admin');
(async () => {
  const run = await start('permissions');
  const p = () => run.page;
  const base = '/projects/walk/custom_field_configuration';
  const urls = ['/projects/walk/settings/custom_field_configuration', base, base + '/audit', base + '/fields/2', base + '/fields/2/dependencies', base + '/fields/18', base + '/fields/16'];
  const status = async (u) => (await L.goto(run, u)).status();
  const FORBID = ['Secret Code', 'Zulu-7731', 'Zulu-7732', 'Yankee-4410', 'Xray-9981', 'Whiskey-2208', 'Clearance', 'Alpha-Level', 'Bravo-Level'];
  const mut = async (method, u, body) => p().evaluate(async ([m, u, b]) => {
    const tok = (document.querySelector('meta[name=csrf-token]') || {}).content;
    const r = await fetch(u, { method: m, credentials: 'same-origin', headers: { 'X-CSRF-Token': tok, 'Content-Type': 'application/x-www-form-urlencoded' }, body: b });
    return r.status;
  }, [method, u, body]);
  const noAccess = async (user) => {
    await L.login(run, user);
    await L.goto(run, '/projects/walk');
    const res = {};
    for (const u of urls) res[u] = await status(u);
    await L.goto(run, '/projects/walk/settings');
    const tab = await p().locator('a#tab-custom_field_configuration, a:has-text("Custom field configuration")').count();
    // the plain Settings page (any tab name) renders for members with other settings permissions; it must not hold the plugin tab
    await L.goto(run, '/projects/walk/settings/custom_field_configuration');
    if ((await p().locator('table.dcf-config-fields').count()) || (await p().locator('#tab-custom_field_configuration').count())) throw new Error('plugin tab rendered for ' + user);
    const bad = Object.entries(res).filter(([u, s]) => s === 200 && !/settings\/custom_field_configuration$/.test(u));
    if (bad.length) throw new Error('reachable: ' + JSON.stringify(bad));
    await L.goto(run, '/projects/walk');
    const writes = {};
    writes.add = await mut('POST', base + '/fields/16/values', 'value=Hack');
    writes.sort = await mut('PATCH', base + '/fields/16/values/sort', 'direction=asc&confirm=1');
    writes.deps = await mut('PATCH', base + '/fields/2/dependencies', 'dependencies_json={}&confirm=1');
    for (const [k, s] of Object.entries(writes)) if (s === 200 || s === 302) throw new Error(`write ${k} -> ${s}`);
    const stored = rails(run, "puts CustomField.find(16).possible_values.inspect");
    if (/Hack/.test(stored)) throw new Error('value stored: ' + stored);
    return `GET ${JSON.stringify(res)}; settings tab links: ${tab}; writes ${JSON.stringify(writes)}`;
  };
  await check(run, 'developer-no-access', 'developer: every project configuration page and write answers 403 (no tab, nothing stored)', () => noAccess('developer'));
  await check(run, 'reporter-no-access', 'reporter: same', () => noAccess('reporter'));
  await check(run, 'anonymous-redirect', 'anonymous: redirected to login (302) or 403, never 200', async () => {
    const ctx = await run.browser.newContext(); const pg = await ctx.newPage();
    const out = {};
    for (const u of [base, base + '/fields/2', base + '/fields/2/dependencies']) { const r = await pg.goto(run.base + u); out[u] = r.status() + ' ' + pg.url().replace(run.base, ''); if (r.status() === 200 && !/\/login/.test(pg.url())) throw new Error('anonymous reached ' + u); }
    await ctx.close(); return JSON.stringify(out);
  });
  await check(run, 'manager-access', 'manager: all project pages 200, tab visible in Settings; admin-only pages (custom fields admin, global audit) denied', async () => {
    await L.login(run, 'manager');
    const res = {}; for (const u of urls) res[u] = await status(u);
    const bad = Object.entries(res).filter(([, s]) => s !== 200); if (bad.length) throw new Error('not 200: ' + JSON.stringify(bad));
    await L.goto(run, '/projects/walk/settings');
    const tab = await p().locator('a:has-text("Custom field configuration")').count();
    if (!tab) throw new Error('tab link missing');
    await L.screenshot(run, 'settings-tab');
    const adm = {}; for (const u of ['/custom_fields', '/custom_fields/2/edit', '/dcf_config_audit']) adm[u] = await status(u);
    if (Object.values(adm).some((s) => s === 200)) throw new Error('manager reached admin: ' + JSON.stringify(adm));
    const other = await status('/projects/other/custom_field_configuration');
    return `project pages ${JSON.stringify(res)}; admin-only ${JSON.stringify(adm)}; other project (manager there too) ${other}`;
  });
  await check(run, 'manager-other-project-scope', 'manager sees Walk Local fields only in Walk, not in Other; Shared fields in both', async () => {
    await L.goto(run, '/projects/other/custom_field_configuration');
    const names = (await p().locator('table.dcf-config-fields tbody td:first-child').allInnerTexts());
    if (names.includes('Walk Local Parent')) throw new Error('Walk-only field listed in Other');
    if (!names.includes('Shared Parent')) throw new Error('shared field missing in Other');
    const r = await L.goto(run, '/projects/other/custom_field_configuration/fields/12');
    return `Other lists ${names.join(', ')}; Walk-only field 12 under Other -> ${r.status()}`;
  });
  await check(run, 'hard-rule-permission-holder-without-visibility', 'Developer role temporarily given the permission: project pages never name Secret Code / Clearance or their values; hidden field URLs refused', async () => {
    rails(run, "Role.find_by(name: 'Developer').add_permission!(:manage_project_custom_field_configuration)");
    const leaks = [];
    try {
      await L.login(run, 'developer');
      const out = {};
      const pages = ['/projects/walk/settings/custom_field_configuration', base, base + '/audit', base + '/fields/1', base + '/fields/2', base + '/fields/2/dependencies', base + '/fields/11', base + '/fields/11/dependencies', base + '/fields/4/dependencies', base + '/fields/9', base + '/fields/9/dependencies', base + '/fields/10', base + '/fields/10/dependencies'];
      for (const u of pages) {
        const r = await L.goto(run, u); out[u] = r.status();
        const h = await p().content(); const hit = FORBID.filter((f) => h.includes(f));
        if (hit.length) { leaks.push(`${u} (HTTP ${r.status()}) contains ${JSON.stringify(hit)}`); await L.screenshot(run, 'leak-' + u.split('/').slice(-2).join('-')); }
      }
      await L.goto(run, base + '/fields/1');
      const row = p().locator("table.dcf-values tbody tr[data-dcf-value='Belgium']");
      await row.locator('input[name=new_value]').fill('Belgique');
      await Promise.all([p().waitForLoadState('load'), row.locator('form.dcf-inline-form input[type=submit]').click()]);
      const panel = (await p().locator('.dcf-confirm-panel').count()) ? (await p().locator('.dcf-confirm-panel').innerText()).replace(/\s+/g, ' ') : 'no panel';
      const h2 = await p().content(); const hit2 = FORBID.filter((f) => h2.includes(f)); if (hit2.length) leaks.push('rename panel page contains ' + JSON.stringify(hit2));
      const ep = await p().evaluate(async () => { const o = []; for (const u of ['/dcf_dependency_editor/values?parent_custom_field_id=10']) { const r = await fetch(u, { credentials: 'same-origin' }); o.push([u, r.status]); } return o; });
      run.leakInfo = { out, panel, ep };
      if (leaks.length) throw new Error('HARD RULE: ' + leaks.join(' ; ') + ' | statuses ' + JSON.stringify(out) + ' | Country rename panel "' + panel + '" | endpoints ' + JSON.stringify(ep));
      return 'no leaks ' + JSON.stringify(out);
    } finally {
      rails(run, "Role.find_by(name: 'Developer').remove_permission!(:manage_project_custom_field_configuration)");
    }
  });
  await finish(run);
})();
