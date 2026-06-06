/**
 * i18n 运行时：T() 翻译、当前语言、语言解析、供应商显示名。
 *
 * 语言来源优先级（plan §5）：
 *   --lang 参数 > providers.json 的 lang 字段 > 环境 LC_ALL/LANG/LANGUAGE > 默认 zh。
 */
import { isOfficial, type Lang, type Provider } from '../config/store.js';
import { messages } from './messages.js';

export type { Lang } from '../config/store.js';

let current: Lang = 'zh';

/** 设置本次进程的界面语言（启动时按 resolveLang 的结果调用一次）。 */
export function setLang(lang: Lang): void {
  current = lang;
}

export function getLang(): Lang {
  return current;
}

/**
 * 翻译：查目录取当前语言文案，按序替换 `{0}` `{1}` …。
 * 缺 key 时返回 key 本身（便于一眼发现漏翻），缺当前语言时回退 zh。
 */
export function T(key: string, ...args: Array<string | number>): string {
  const m = messages[key];
  if (!m) return key;
  let s = m[current] || m.zh || key;
  args.forEach((a, i) => {
    s = s.split(`{${i}}`).join(String(a));
  });
  return s;
}

/**
 * 解析本次界面语言。`explicit` 来自 --lang，`storeLang` 来自 providers.json。
 * 环境变量：含 `zh` → 中文；以 `en` 开头（如 en_US）→ 英文；其余默认 zh。
 */
export function resolveLang(explicit?: Lang, storeLang?: Lang): Lang {
  if (explicit) return explicit;
  if (storeLang) return storeLang;
  const env = (process.env.LC_ALL || process.env.LANG || process.env.LANGUAGE || '').toLowerCase();
  if (env.includes('zh')) return 'zh';
  if (env.startsWith('en')) return 'en';
  return 'zh';
}

/**
 * 配置的显示名：官方档显示翻译后的「官方/Official」（评审①：显示名与数据主键 `name` 解耦）；
 * 其余是专有名词，原样显示 `name`。
 */
export function providerDisplayName(p: Provider): string {
  if (isOfficial(p)) return T('provider.official');
  if (p.name === 'DeepSeek') return T('provider.deepseek');
  if (p.name === '智谱GLM') return T('provider.zhipu');
  if (p.name === '小米MiMo') return T('provider.mimo');
  return p.name;
}
