import assert from 'node:assert/strict';
import { test } from 'node:test';

import { authHeaders, checkProfile, classifyHttp } from './check.js';
import { setLang, T } from './i18n/index.js';

// classifyHttp：状态码 -> 结果分层（ok 标志 + 文案 key）。
test('classifyHttp maps status to layered result', () => {
  setLang('en');
  const cases: Array<[number, boolean, string]> = [
    [200, true, 'check.ok'],
    [204, true, 'check.ok'],
    [401, false, 'check.auth'],
    [403, false, 'check.auth'],
    [404, false, 'check.notFound'],
    [429, false, 'check.http'],
    [500, false, 'check.http'],
  ];
  for (const [status, ok, key] of cases) {
    const r = classifyHttp(status);
    assert.equal(r.ok, ok, `status ${status} ok`);
    assert.equal(r.message, T(key, String(status)), `status ${status} message`);
  }
});

// authHeaders：API_KEY 优先于 AUTH_TOKEN；空白忽略；都缺返回 undefined。
test('authHeaders prefers API key and ignores blanks', () => {
  assert.deepEqual(authHeaders({ ANTHROPIC_API_KEY: 'k' }), { 'x-api-key': 'k' });
  assert.deepEqual(authHeaders({ ANTHROPIC_AUTH_TOKEN: 't' }), { Authorization: 'Bearer t' });
  assert.equal(authHeaders({}), undefined);
  assert.deepEqual(authHeaders({ ANTHROPIC_API_KEY: 'k', ANTHROPIC_AUTH_TOKEN: 't' }), { 'x-api-key': 'k' });
  assert.deepEqual(authHeaders({ ANTHROPIC_API_KEY: '  ', ANTHROPIC_AUTH_TOKEN: 't' }), { Authorization: 'Bearer t' });
});

// checkProfile 的无网络早返回：缺地址 / 缺密钥。
test('checkProfile early-returns without network', async () => {
  setLang('en');

  const noUrl = await checkProfile({ name: 'X', env: {} });
  assert.equal(noUrl.ok, false);
  assert.equal(noUrl.message, T('check.noUrl'));

  const noKey = await checkProfile({ name: 'X', env: { ANTHROPIC_BASE_URL: 'https://x.example.com' } });
  assert.equal(noKey.ok, false);
  assert.equal(noKey.message, T('check.noKey'));
});
