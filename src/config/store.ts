/**
 * 配置存取层：读写 ~/.cc-mini/providers.json，生成默认配置，构造 env map。
 *
 * 铁律：这里写的是工具自己的数据文件（providers.json），**绝不**碰 ~/.claude/*。
 * 格式与现版 PowerShell 完全兼容；写入 UTF-8 无 BOM、2 空格缩进。
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import { KNOWN_KEYS, type Lang, type Provider, type Store } from './types.js';

export { KNOWN_KEYS } from './types.js';
export type { Lang, ManagedKey, Provider, Store } from './types.js';

export interface StorePaths {
  dir: string;
  file: string;
}

/** 解析存储路径。`storeDir` 来自 --store-dir（测试用），默认 ~/.cc-mini。 */
export function resolveStorePaths(storeDir?: string): StorePaths {
  const dir = storeDir && storeDir.trim() ? storeDir : join(homedir(), '.cc-mini');
  return { dir, file: join(dir, 'providers.json') };
}

const nonEmpty = (v: unknown): v is string => typeof v === 'string' && v.trim() !== '';

/**
 * 默认配置：官方 + DeepSeek + 智谱GLM + 小米MiMo（密钥空）。
 * 官方档带 `builtin: 'official'`（评审①），其它供应商是专有名词、不翻译。
 */
export function defaultStore(): Store {
  return {
    current: '官方',
    lang: 'zh',
    providers: [
      { name: '官方', note: '', builtin: 'official', env: {} },
      {
        name: 'DeepSeek',
        note: '',
        env: {
          ANTHROPIC_BASE_URL: 'https://api.deepseek.com/anthropic',
          ANTHROPIC_DEFAULT_OPUS_MODEL: 'deepseek-v4-pro',
          ANTHROPIC_DEFAULT_SONNET_MODEL: 'deepseek-v4-pro',
          ANTHROPIC_DEFAULT_HAIKU_MODEL: 'deepseek-v4-flash',
          CLAUDE_CODE_EFFORT_LEVEL: 'max',
        },
      },
      {
        name: '智谱GLM',
        note: '',
        env: {
          ANTHROPIC_BASE_URL: 'https://open.bigmodel.cn/api/anthropic',
          ANTHROPIC_DEFAULT_OPUS_MODEL: 'GLM-4.7',
          ANTHROPIC_DEFAULT_SONNET_MODEL: 'GLM-4.7',
          ANTHROPIC_DEFAULT_HAIKU_MODEL: 'glm-4.5-air',
        },
      },
      {
        name: '小米MiMo',
        note: '',
        env: {
          ANTHROPIC_BASE_URL: 'https://api.xiaomimimo.com/anthropic',
          ANTHROPIC_DEFAULT_OPUS_MODEL: 'mimo-v2.5-pro',
          ANTHROPIC_DEFAULT_SONNET_MODEL: 'mimo-v2.5-pro',
          ANTHROPIC_DEFAULT_HAIKU_MODEL: 'mimo-v2.5-pro',
        },
      },
    ],
  };
}

/** 把任意解析结果规整为合法 Store（容错旧文件：缺 lang / 缺 builtin / env 非对象都不报错）。 */
function normalizeStore(raw: unknown): Store {
  const obj = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const providersRaw = Array.isArray(obj.providers) ? obj.providers : [];
  const providers: Provider[] = providersRaw.map((p) => normalizeProvider(p));
  const lang: Lang | undefined = obj.lang === 'en' ? 'en' : obj.lang === 'zh' ? 'zh' : undefined;
  const current = typeof obj.current === 'string' ? obj.current : (providers[0]?.name ?? '');
  return { current, ...(lang ? { lang } : {}), providers };
}

function normalizeProvider(raw: unknown): Provider {
  const p = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const name = typeof p.name === 'string' ? p.name : '';
  const note = typeof p.note === 'string' ? p.note : '';
  const builtin = typeof p.builtin === 'string' ? p.builtin : undefined;
  const env: Record<string, string> = {};
  if (p.env && typeof p.env === 'object') {
    for (const [k, v] of Object.entries(p.env as Record<string, unknown>)) {
      if (typeof v === 'string') env[k] = v;
    }
  }
  return { name, note, ...(builtin ? { builtin } : {}), env };
}

/** 读配置；文件不存在则生成默认并落盘后返回。 */
export function loadStore(paths: StorePaths): Store {
  if (existsSync(paths.file)) {
    const text = readFileSync(paths.file, 'utf-8');
    return normalizeStore(JSON.parse(text));
  }
  const store = defaultStore();
  saveStore(paths, store);
  return store;
}

/**
 * 只读探测 lang，**不生成文件**（用于 --help/--version 在 parse 前定语言，避免副作用）。
 * 文件不存在/解析失败都返回 undefined。
 */
export function peekStoreLang(paths: StorePaths): Lang | undefined {
  try {
    if (!existsSync(paths.file)) return undefined;
    const raw = JSON.parse(readFileSync(paths.file, 'utf-8')) as { lang?: unknown };
    return raw.lang === 'en' ? 'en' : raw.lang === 'zh' ? 'zh' : undefined;
  } catch {
    return undefined;
  }
}

/** 写配置：UTF-8 无 BOM、2 空格缩进（Node 默认 utf-8 不带 BOM，与现版一致）。 */
export function saveStore(paths: StorePaths, store: Store): void {
  if (!existsSync(paths.dir)) mkdirSync(paths.dir, { recursive: true });
  writeFileSync(paths.file, `${JSON.stringify(store, null, 2)}\n`, 'utf-8');
}

/**
 * 是否官方档。优先认稳定标识 `builtin === 'official'`（评审①）；
 * 老文件没有 builtin 时退回认中文名 `'官方'`，与现版 PowerShell 行为一致。
 */
export function isOfficial(p: Provider): boolean {
  if (p.builtin) return p.builtin === 'official';
  return p.name === '官方';
}

/**
 * [P1] 编辑保存后修正身份：官方档（builtin='official' = 登录态、空 env）一旦被配成真实第三方
 * （env 非空，有了 base/key 等），就清掉 builtin —— 否则会继续被当登录态、跳过缺密钥警告。
 */
export function reconcileBuiltin(p: Provider): void {
  if (p.builtin === 'official' && Object.keys(p.env).length > 0) {
    delete p.builtin;
  }
}

/** 取配置的 env map（即 provider.env，保证非空对象）。 */
export function getProviderEnvMap(p: Provider): Record<string, string> {
  return p.env ?? {};
}

/**
 * 由一组字段构造 provider.env：按 KNOWN_KEYS 顺序、丢弃空白值。
 * 对齐现版 Build-ProviderEnv。`[1m]` 等后缀属于自由文本，原样保留（见 plan §3.1.1）。
 */
export function buildProviderEnv(fields: Record<string, string | undefined>): Record<string, string> {
  const env: Record<string, string> = {};
  for (const key of KNOWN_KEYS) {
    const v = fields[key];
    if (nonEmpty(v)) env[key] = v.trim();
  }
  return env;
}

/** 配置的密钥状态（语义枚举，不含界面文案；翻译交给 i18n 层，评审①）。 */
export type KeyState = 'official' | 'noKey' | 'apiKey' | 'hasToken';

export interface ProviderState {
  key: KeyState;
  effort?: string;
}

export function getProviderState(p: Provider): ProviderState {
  const map = getProviderEnvMap(p);
  const effort = nonEmpty(map.CLAUDE_CODE_EFFORT_LEVEL) ? map.CLAUDE_CODE_EFFORT_LEVEL : undefined;
  if (isOfficial(p)) return { key: 'official', ...(effort ? { effort } : {}) };
  const hasTok = nonEmpty(map.ANTHROPIC_AUTH_TOKEN);
  const hasKey = nonEmpty(map.ANTHROPIC_API_KEY);
  const key: KeyState = !hasTok && !hasKey ? 'noKey' : hasKey ? 'apiKey' : 'hasToken';
  return { key, ...(effort ? { effort } : {}) };
}

/** 按 name 找配置。 */
export function findProvider(store: Store, name: string): Provider | undefined {
  return store.providers.find((p) => p.name === name);
}

/**
 * 名称去重：同名被【其它】配置占用时追加 “ 2/3/…”。`exclude` 是正在编辑的本条（排除自身）。
 * 对齐现版 Resolve-UniqueName。
 */
export function resolveUniqueName(store: Store, name: string, exclude?: Provider): string {
  const existing = store.providers.filter((p) => p !== exclude).map((p) => p.name);
  if (!existing.includes(name)) return name;
  let i = 2;
  while (existing.includes(`${name} ${i}`)) i += 1;
  return `${name} ${i}`;
}

/** 语言：providers.json 的 lang 字段，缺省视为 zh。 */
export function getLang(store: Store): Lang {
  return store.lang === 'en' ? 'en' : 'zh';
}

export function setLang(store: Store, lang: Lang): void {
  store.lang = lang;
}
