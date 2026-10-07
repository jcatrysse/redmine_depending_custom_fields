// Project > Settings with the "Custom field configuration" tab, next to the
// other GEOxyz plugins that add settings tabs (redmine_agile, redmine_contacts,
// redmine_itil_priority, redmine_mail_digest). Before the prepend fix the page
// answered HTTP 500 for everyone allowed to open it as soon as a plugin that
// prepends project_settings_tabs (redmine_agile) was installed.
//
//   admin     tab present, opens the overview with the seeded fields
//   manager   member with the permission: tab present, a field opens
//   editor    member with every permission but this one: settings open, no tab,
//             the configuration URL refused
//   outsider  no membership: settings and configuration refused
import { e2e } from '../../.codex/e2e/lib.mjs';

const P = 'e2e-project';
const TAB = '#tab-custom_field_configuration';
const t = await e2e(process.env.RMP_E2E_NAME || 'project-settings-tab');

async function tabNames() {
  return t.page.$$eval('#content .tabs ul li a[id^="tab-"]', as => as.map(a => a.id.replace(/^tab-/, '')));
}

async function expectTabs(who, { present }) {
  const names = await tabNames();
  console.log(`  ${who}: tabs ${names.join(', ')}`);
  if (!names.includes('info')) t.problems.push(`${who}: core tab "info" missing (${names})`);
  if (names.includes('custom_field_configuration') !== present) {
    t.problems.push(`${who}: custom field configuration tab ${present ? 'missing' : 'shown'} (${names})`);
  }
  return names;
}

for (const who of ['admin', 'manager']) {
  await t.login(who);
  await t.go(`/projects/${P}/settings`);
  await t.sudo();
  const names = await expectTabs(who, { present: true });
  await t.shot(`${who}-settings`, `Project settings as ${who}: tabs ${names.join(', ')}`);

  if (!names.includes('custom_field_configuration')) continue; // recorded by expectTabs
  await t.page.click(TAB);
  await t.settle();
  t.check(`${who} open tab`);
  for (const f of ['E2E colour', 'E2E size']) {
    if (!(await t.page.locator('table.dcf-config-fields', { hasText: f }).count())) {
      t.problems.push(`${who}: field ${f} not listed in the tab`);
    }
  }
  await t.shot(`${who}-tab`, `The custom field configuration tab as ${who}, with the seeded fields`);
}

// manager: a field opens from the tab
const field = t.page.locator('table.dcf-config-fields a:text("E2E colour")');
if (await field.count()) {
  await field.first().click();
  await t.settle();
  t.check('manager open field');
  if (!/custom_field_configuration\/fields\/\d+/.test(t.page.url())) t.problems.push(`manager: field did not open (${t.page.url()})`);
  await t.shot('manager-field', 'A list field opened from the tab, as manager');
} else {
  t.problems.push('manager: no E2E colour link to open');
}

await t.login('editor');
await t.go(`/projects/${P}/settings`);
const editorTabs = await expectTabs('editor', { present: false });
await t.shot('editor-settings', `Project settings as a member without the permission: tabs ${editorTabs.join(', ')}`);
await t.go(`/projects/${P}/custom_field_configuration`, { status: 403 });
await t.shot('editor-refused', 'The configuration URL is refused without the permission');

await t.login('outsider');
await t.go(`/projects/${P}/settings`, { status: 403 });
await t.shot('outsider-settings', 'Project settings refused to a non-member');
await t.go(`/projects/${P}/custom_field_configuration`, { status: 403 });
await t.shot('outsider-refused', 'The configuration URL refused to a non-member');

await t.done();
