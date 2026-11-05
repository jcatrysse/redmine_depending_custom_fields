'use strict';
// Minimal HTTP client with a cookie jar and keep-alive, one connection, hrtime timing. No redirects followed.
const http = require('http');

class Client {
  constructor(port) {
    this.port = port;
    this.agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
    this.cookies = {};
    this.csrf = null;
  }

  cookieHeader() {
    return Object.entries(this.cookies).map(([k, v]) => `${k}=${v}`).join('; ');
  }

  request(method, path, { form, headers = {}, timeoutMs = 0 } = {}) {
    return new Promise((resolve, reject) => {
      const body = form ? new URLSearchParams(form).toString() : null; // form: object or array of [key, value] pairs
      const h = { Cookie: this.cookieHeader(), Accept: 'text/html,application/xhtml+xml', 'Accept-Encoding': 'identity', ...headers };
      if (body !== null) { h['Content-Type'] = 'application/x-www-form-urlencoded'; h['Content-Length'] = Buffer.byteLength(body); }
      const t0 = process.hrtime.bigint();
      const req = http.request({ host: '127.0.0.1', port: this.port, method, path, headers: h, agent: this.agent }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const t1 = process.hrtime.bigint();
          const buf = Buffer.concat(chunks);
          for (const c of res.headers['set-cookie'] || []) {
            const [pair] = c.split(';');
            const i = pair.indexOf('=');
            this.cookies[pair.slice(0, i)] = pair.slice(i + 1);
          }
          resolve({ status: res.statusCode, headers: res.headers, body: buf, bytes: buf.length, ms: Number(t1 - t0) / 1e6 });
        });
      });
      const timer = timeoutMs ? setTimeout(() => req.destroy(new Error('timeout')), timeoutMs) : null;
      req.on('close', () => { if (timer) clearTimeout(timer); });
      req.on('error', (e) => { if (e.message === 'timeout') { resolve({ timeout: true, ms: Number(process.hrtime.bigint() - t0) / 1e6, status: 0, bytes: 0, headers: {}, body: Buffer.alloc(0) }); } else { reject(e); } });
      if (body !== null) req.write(body);
      req.end();
    });
  }

  get(path, opts) { return this.request('GET', path, opts); }

  static token(html) {
    const m = /name="csrf-token" content="([^"]+)"/.exec(html) || /name="authenticity_token" value="([^"]+)"/.exec(html);
    return m ? m[1] : null;
  }

  async login(user, password) {
    const page = await this.get('/login');
    const token = Client.token(page.body.toString());
    const res = await this.request('POST', '/login', { form: { authenticity_token: token, username: user, password } });
    if (res.status !== 302) throw new Error(`login failed for ${user}: HTTP ${res.status}`);
    const home = await this.get('/my/page');
    if (home.status !== 200) throw new Error(`login check failed for ${user}: HTTP ${home.status}`);
    this.csrf = Client.token(home.body.toString());
    return this;
  }

  close() { this.agent.destroy(); }
}

module.exports = { Client };
