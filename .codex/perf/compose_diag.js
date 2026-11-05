// Diagnostic, not a timing run: byte composition of one issue_new_s2 response per variant.
const { Client } = require('./lib/client');
const { pages } = require('./lib/pages');
const S = require('./lib/servers');
const fs = require('fs');
const path = require('path');
const VER = process.argv[2] || '51';
const ids = S.paths.ids(VER);
(async () => {
  for (const [variant, name] of [['main', 'm' + VER], ['branch', 'p' + VER]]) {
    S.start(name);
    try {
      const c = await new Client(S.PORTS[name]).login(ids.users.member.login, ids.users.member.password);
      const out = {};
      for (const key of ['issue_new_s2', 'issue_new_s1', 'context_menu_s2']) {
        const page = pages(ids).find((p) => p.key === key);
        const r = await c.get(page.path);
        const b = r.body.toString('utf8');
        const head = b.slice(0, b.indexOf('</head>'));
        const sel = new RegExp(`<select[^>]*id="issue_custom_field_values_${ids.fields.Part.id}"[\\s\\S]*?</select>`).exec(b);
        const tag = sel ? /^<select[^>]*>/.exec(sel[0])[0] : '';
        const dm = /data-dcf-map="([^"]*)"/.exec(tag);
        out[key] = { total: r.bytes, head_bytes: head.length, select_bytes: sel ? sel[0].length : 0, select_tag_bytes: tag.length,
          dcf_map_attr_bytes: dm ? dm[1].length : 0, dcf_map_quot_count: dm ? (dm[1].match(/&quot;/g) || []).length : 0,
          main_mapping_in_head: /window\.DependingCustomFieldData = /.test(head) ? head.length - head.indexOf('window.DependingCustomFieldData') : 0,
          option_count: sel ? (sel[0].match(/<option/g) || []).length : 0,
          hidden_options: sel ? (sel[0].match(/<option[^>]*hidden/g) || []).length : 0 };
        if (key === 'issue_new_s2') fs.writeFileSync(path.join(S.P, 'results', `${variant}_${VER}_issue_new_s2.html`), b);
      }
      console.log(variant, JSON.stringify(out, null, 1));
    } finally { S.stop(name); }
  }
})().catch((e) => { console.error(e); process.exit(1); });
