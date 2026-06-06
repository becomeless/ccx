import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { Store } from './config/types.js';
import { setLang, T } from './i18n/index.js';
import { currentTerminalLine } from './runtime-info.js';

const store: Store = {
  current: 'DeepSeek',
  providers: [{ name: 'DeepSeek', env: { ANTHROPIC_BASE_URL: 'https://api.deepseek.com/anthropic' } }],
};

// currentTerminalLine：空地址=官方态；命中配置（含尾斜杠/空格规范化）显示 host→名；否则未匹配。
test('currentTerminalLine reflects env vs profiles', () => {
  setLang('en');
  const matched = T('terminal.matched', 'api.deepseek.com', 'DeepSeek');
  const cases: Array<[string | undefined, string]> = [
    [undefined, T('terminal.current', T('terminal.official'))],
    ['https://api.deepseek.com/anthropic', T('terminal.current', matched)],
    ['https://api.deepseek.com/anthropic/', T('terminal.current', matched)],
    ['  https://api.deepseek.com/anthropic  ', T('terminal.current', matched)],
    ['https://unknown.example.com/x', T('terminal.current', T('terminal.unmatched', 'unknown.example.com'))],
  ];
  for (const [base, want] of cases) {
    if (base === undefined) delete process.env.ANTHROPIC_BASE_URL;
    else process.env.ANTHROPIC_BASE_URL = base;
    assert.equal(currentTerminalLine(store), want, `base=${String(base)}`);
  }
  delete process.env.ANTHROPIC_BASE_URL;
});
