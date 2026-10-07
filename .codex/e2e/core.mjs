// Core flows with this plugin installed, run by e2e.sh after smoke.mjs: a plugin
// that patches issues, forms or menus most often breaks one of these, and the
// plugin's own tests rarely notice. Create an issue through the form, add a
// note, open the context menu, and the refusals for a user who is not a member.
import { e2e } from './lib.mjs';

const P = 'e2e-project';
const t = await e2e('core');

await t.login('manager');
await t.go(`/projects/${P}/issues/new`);
await t.page.fill('#issue_subject', `E2E created through the form ${Date.now()}`);
await t.shot('new-issue-form', 'New issue form as a member with every permission');
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('create issue');
if (!/\/issues\/\d+/.test(t.page.url())) t.problems.push(`create issue: still on ${t.page.url()} (validation error?)`);
await t.shot('issue-created', 'The issue is created and shown');

const issuePath = new URL(t.page.url()).pathname;
await t.go(`${issuePath}/edit`);
await t.page.fill('#issue_notes', 'A note added through the edit form.');
await t.page.click('#issue-form input[name=commit]');
await t.settle();
t.check('add note');
if (!(await t.page.locator('.journal .wiki', { hasText: 'A note added through the edit form.' }).count())) {
  t.problems.push('add note: the note is not shown on the issue');
}
await t.shot('note-added', 'The note is saved and shown in the history');

await t.go(`/projects/${P}/issues`);
// a right-click on a link opens the browser's own menu, so use a plain cell
await t.page.click('table.issues tr.issue td.status >> nth=0', { button: 'right' });
await t.page.waitForSelector('#context-menu ul', { timeout: 10000 }).catch(() => t.problems.push('context menu did not open'));
t.check('context menu');
await t.shot('context-menu', 'The context menu on the issue list', { full: false });

await t.login('reporter');
await t.go('/issues/1');
await t.shot('issue-as-reporter', 'An issue seen by a member without the plugin\'s permissions');

await t.login('outsider');
await t.go('/projects/e2e-private', { status: 403 });
await t.shot('private-refused', 'A private project is refused to a non-member');

await t.done();
